# doment architecture

This is the living record of doment's architecture: which processes exist and what each owns, how they talk, which
projects exist and what they may reference, the platform seams, how doment builds against darkraise-framework, and
how third-party components are kept out. It was first written from the architecture-decisions spec of 2026-11-24
(`docs/dforge/specs/2026-11-24-architecture-decisions-design.md`), which stays as that day's decision log; this file
is the one kept current. Requirement numbers (R1, R176, ...) refer to the product spec,
`docs/dforge/specs/2026-11-24-doment-design.md`.

## Process model

| Role | Executable | First appears | Runs as | Owns |
|---|---|---|---|---|
| Host service | Linux: `doment-agent`. Windows: `doment-service.exe` | Linux M1 (its systemd unit in M4); Windows M7 | Linux: decided in M4 under the rules below. Windows: SYSTEM | The device key and the paired-device list; the handshake; the one policy decision point (R18); every network socket; the transport and the reliable control channel; the session inventory; the wake helper and relay-node roles; keyboard modifier state; the handles of system-wide virtual devices; supervision of the session agent |
| Session agent | Windows: `doment-session.exe`. Linux and macOS desktop hosts: later | Windows M7; Linux and macOS desktop hosts M16 | SYSTEM in the console session | Everything that needs the interactive session: capture, encode, audio capture, input injection, cursor, display topology, clipboard access, on-host prompts and the session indicator. No keys, no network sockets |
| Terminal host | Linux: a mode of the `doment-agent` binary, so R45's single binary holds. Windows: a mode of `doment-session.exe`, started with the user's token | Linux M4; Windows M7 | The user whose shells it runs; one instance per user and privilege level | Pseudo-terminals, the terminal state and scrollback used for snapshots, session identifiers, each session's process tree. No keys, no network sockets |
| Client | `doment` command-line client; `Doment.exe` Win32UI desktop app | Command line M1; desktop app M8 | The user | The client device key, the client side of the connection ladder, decode, presentation, audio playback, input capture, terminal rendering |
| Self-hosted server | `doment-server` | M3 | An unprivileged account | Directory, connection brokering, relay, wake helper; never a device private key or plaintext (R33) |
| Shared portable core | Libraries (see Module map) | M1 | - | Everything two or more roles share |

Rules:

- **One network endpoint per host.** Only the host service opens network sockets. One authenticated connection per
  client carries every channel (control, terminal, video, audio, input, clipboard, files, power), as R118 and R53
  need. That connection stays up while the session agent restarts or the console session changes (R83, R84, R87).
- **Policy in one place.** Only the host service holds the device key and authorises (R18). Workers (the session
  agent and the terminal host) accept a link only from the host service, checked by the operating system (socket
  peer credentials, pipe access control), and trust what it sends. The host service reaches them only through the
  worker link (next section).
- **Terminals outlive the service.** A restart, crash, update or rollback of the host service leaves the terminal
  host and its shells running. When the service starts, it finds the running terminal hosts and lists their sessions
  again (R52, R145). Three rules follow:
  - *Outside the service's kill scope.* On Linux the terminal host runs in a systemd unit of its own, outside the
    service's control group (systemd's default kills every process of a restarted unit), as the configured user. The
    service finds it through a socket at a fixed per-user path. The "Host terminal service" epic chooses between a
    per-user unit with lingering and a template system unit, and how the service may start it; that choice also
    fixes the Linux service account. Its acceptance restarts the service unit and finds the shell alive. On Windows
    the host service launches the terminal host with the user's token, outside any job that closes with the service.
  - *Never killed by the service.* When a terminal host stops answering, its sessions are listed as unavailable,
    with a log line naming its process and its last heartbeat. A session agent that stops answering, by contrast, is
    killed and restarted (R83).
  - *Versions differ for days.* A terminal host keeps running the binary it was started from until its last session
    ends, then starts again from the installed one. The worker link therefore opens with a version exchange, and the
    service talks to a terminal host up to one minor version older or newer (an update, or a rollback under R148).
    Outside that range the service lists the sessions as "restart needed on the host", logs both versions and leaves
    the shells running.
- **Workers at lower privilege are untrusted input.** The terminal host runs as the user while the service runs as
  SYSTEM or a service account, so whatever the terminal host sends is parsed like network input: by safe code, with
  every length and offset copied out before it is validated. The framing and parsers of the socket and pipe form of
  the worker link live in `Doment.Protocol`, so the compiler enforces this rule. The terminal channel uses the socket
  or pipe only; shared memory is used only with the session agent, which runs at the service's own privilege.
- **User data under the user's identity.** Shells, received files and clipboard content are read and written under
  the identity of the signed-in user, never as SYSTEM or root, because a SYSTEM write into a user-chosen folder can
  be redirected by a link planted there. On Linux a process running as the user does it; on Windows a helper started
  with the user's token, or impersonation for each write, chosen by the file-transfer epic. What file transfer and
  clipboard do while no user is signed in is decided in the "Clipboard and file transfer protocol" epic and put to
  the owner there. Nothing is ever written as SYSTEM or root into a location a user can write.
- **Device handles in the service.** Virtual gamepad and virtual display devices are created and removed by the host
  service, so a session agent restart does not unplug them; the session agent only applies the display layout. This
  is inferred from how the ViGEmBus client works; the M9 epics confirm it.
- **Parsing before authentication is safe code.** Everything that parses bytes from an unauthenticated peer
  (handshake, pairing, discovery, address probes, relay framing, port-mapping replies) lives in `Doment.Protocol`,
  which compiles with unsafe code disallowed. Code that may use pointers for speed (error correction, media) only
  receives data from an authenticated, paired device or from the session agent. This is the condition for parsing as
  SYSTEM. The M10 security review (R142) decides whether the network endpoint moves to a low-privilege process, which
  would cost a second local hop and a second cross-process protocol.

## Worker link

The host service reaches the session agent and the terminal host only through one portable boundary, the worker
link, defined in `Doment.Worker`. Host code never calls a capture, encode, input or pseudo-terminal seam directly.

- **Typed channels:** media (encoded video, audio), encoder control, input, cursor, display topology, clipboard,
  on-host prompts, and terminal (bytes, snapshots, resize, lifecycle).
- **Contract.** It is written so that the in-process implementation cannot hide a fault that the cross-process one
  would have:
  - the link opens with a version exchange (see Process model);
  - a frame is a lease on a ring slot with an explicit release, and a full ring drops frames (R22);
  - a slot carries a whole frame, or one part of a frame as the encoder emits it, flagged first and last, so the hop
    adds no wait for a whole frame;
  - every control request is asynchronous and is answered by an acknowledgement tagged with a frame number;
  - the link has explicit states (worker absent, starting, running, session changed, console unavailable, version
    out of range) and a liveness heartbeat, with the per-worker outcome given under Process model;
  - stream discontinuities (new parameter sets, a resolution or HDR change, recovery after device loss) are in-band
    events;
  - each slot header carries the frame's stage timestamps as raw monotonic ticks, so frame timing (R12) works across
    processes;
  - the service packetises straight from the ring slot (one copy at most), and both ends wait on events from
    dedicated threads, never on thread-pool reads.
- **Two implementations:** in-process (unit tests and the M1 walking skeleton) and cross-process (a local socket or
  pipe, plus shared memory for the session agent). The terminal host needs the cross-process one on Linux in M4.
  R176 has it built and fault-tested in M2, in the epic "Local worker link", with a simulated session agent, so the
  socket half is not met first in M4 and the shared-memory half first in M7.

## Module map

A project may reference only the projects on its References line. Code used by two or more of host, client and
server lives in `Doment.Core`. Executables are composition roots (arguments, configuration and wiring only), except
`Doment.Server`, which holds the server's own logic.

| Project | Holds | References | Kind | First built |
|---|---|---|---|---|
| `Doment.Protocol` | Wire formats and parsers for everything that can arrive unauthenticated; control message definitions. No unsafe code, no native calls | - | portable | M1 |
| `Doment.Core` | Session security, transport, error correction, congestion control, pacing, bitstream parsers, terminal state model, input, clipboard and file protocols, statistics and frame timeline, clock, relay forwarding, wake packets, the platform seam interfaces | Protocol, Darkraise | portable | M1 |
| `Doment.Simulation` | A simulated implementation of every seam, synthetic and recorded sources, the verifying sink | Core | portable | M1 |
| `Doment.Worker` | The worker link contract and its two implementations; the worker side: terminal host logic and the media worker runtime. The shared-memory ring is the only part of this project allowed pointer code | Core | portable | M1 |
| `Doment.Host` | Network endpoint, policy decision point, session inventory, supervision of workers | Worker | portable | M1 |
| `Doment.Client` | Device list, connection ladder, session, terminal attach, attention events | Core | portable | M1 |
| `Doment.Server` | The directory, enrolment, brokering, relay and wake-helper roles and the `doment-server` entry point | Core | portable | M1 |
| `Doment.Cli` | `doment` | Client; Simulation in simulation builds only | portable | M1 |
| `Doment.Agent` | `doment-agent` | Host; Platform.Linux from M4; Simulation in simulation builds only | Linux-bound | M1 |
| `Doment.Platform.Linux` | Linux seam implementations (pseudo-terminal, key file, power, wake readiness) | Core | Linux-bound | M4 |
| `Doment.Platform.Windows` | Windows seam implementations | Core, Darkraise.Win32UI | Windows-bound | M7 |
| `Doment.Service` | `doment-service.exe` | Host, Platform.Windows | Windows-bound | M7 |
| `Doment.Session` | `doment-session.exe` | Worker, Platform.Windows | Windows-bound | M7 |
| `Doment.App` | `Doment.exe` | Client, Platform.Windows, Darkraise.Win32UI | Windows-bound | M8 |

Rules:

- References are transitive, so a References line lists direct references only.
- **Worker code never references `Doment.Host`.** Worker executables and the worker side of `Doment.Worker` never
  reference it, so "no keys, no sockets" is a boundary the compiler enforces, not a convention. Where the terminal
  host is a mode of another binary (the agent on Linux, the session agent on Windows), the boundary is the project:
  terminal host logic lives in `Doment.Worker`. The "Windows terminal host" epic may give it an executable of its own
  and records that here.
- **Simulation never ships in a release binary.** An executable references `Doment.Simulation` only in a simulation
  build (`DomentSimulation=true`, set by test, bench and harness builds, which build or publish in Debug); a publish
  in any other configuration fails with DOMENT030 when that property is set or `Doment.Simulation` is among the
  resolved references. The walking skeleton's synthetic stream (R11) runs in such a build of the agent.
- Test projects sit beside the project they test, under `tests/`. The test bench and the measurement harness are
  build-only tools under `tools/`.
- The "Repository, build and NativeAOT" epic created the nine M1 projects and `Doment.Core.Tests`, and merged none.

## Platform seams and build order

Each seam is one named interface, declared in `Doment.Core`. Its signature is written by the first epic that
consumes the seam, not before, because a signature with no consumer is a guess.

| Seam | Interface | Called by | Signature declared in | First real implementation |
|---|---|---|---|---|
| Capture | `IFrameCapture` | Session agent | M1 Walking skeleton | M7 Desktop Duplication |
| Video encode | `IVideoEncoder` | Session agent | M1 Measurement harness, completed in M2 Encoder control logic | M7 NVENC, Quick Sync, Media Foundation |
| Video decode | `IVideoDecoder` | Client | M1 Measurement harness, completed in M6 Video bitstream parsers | M7 Direct3D 11 video decode |
| Presentation | `IFramePresenter` | Client | M1 Measurement harness, completed in M6 Frame pacing logic | M7 flip-model swap chain |
| Audio capture | `IAudioCapture` | Session agent | M3 Low-latency audio codec | M7 WASAPI loopback |
| Audio playback | `IAudioPlayback` | Client | M3 Low-latency audio codec | M7 WASAPI render |
| Input injection | `IInputInjector` | Session agent | M6 Input protocol and key mapping | M7 |
| Virtual display | `IVirtualDisplay` | Host service | M6 Display and cursor signalling | M9, exception X1 |
| Virtual gamepad | `IVirtualGamepad` | Host service | M6 Input protocol and key mapping | M9, exception X2 |
| Pseudo-terminal | `IPseudoTerminal` | Terminal host | M4 Host terminal service | M4 Linux, M7 Windows pseudo-console |

Every seam has a simulated implementation in `Doment.Simulation`, written by the epic that declares its signature.

The requirements already imply more platform-bound functions. Each gets a seam in the epic named here, and a row in
the table above when it does: device key storage (M2, R14), high-resolution timers and thread scheduling (M2),
packet marking and network interfaces (M2, R24; M5, R66), LAN discovery (M3, R44), power actions and wake readiness
(M5, R69-R70), session events and worker launch (M7, R83), client input capture (M7, R103), clipboard access (M9,
R131), on-host prompts (M8, R113).

Seam rules:

1. **Opaque frames.** A video frame is metadata (size, timeline, dirty rectangles, cursor, HDR data) plus a surface
   owned by the platform family that made it. Portable code never reads pixels on the production path. Capture and
   encode come from one family, decode and presentation from one family, chosen once in the composition root.
   Reading pixels back is a separate optional capability, used by the verifying sink and the sharpness measurement.
2. **Injected clock.** Stages stamp the frame timeline through a clock passed in, so pacing and latency logic run
   against a simulated clock (R74).
3. **Hot-path discipline.** Seam calls come from dedicated threads owned by the caller, do not allocate at steady
   state, and use no `async` on the frame path.
4. **Status, not exceptions.** Device loss, a mode change, a missing driver or denied access are returned as status
   values. Every seam says how it is recreated, so the session survives (R87), and reports "unavailable" at start-up
   when its component is absent (R129, R134).
5. **Capabilities.** Each seam reports the capability set that negotiation uses (R27).
6. **One contract suite per seam**, run against the simulated implementation on Linux and against the real
   implementation on its platform, so the two are held to the same behaviour.

Build order:

- **Portable projects first, on Linux.** Portable projects target `net10.0`, call no operating-system-specific API,
  and are built and verified on Linux from M1 to M6. R6 (compile for linux-x64 and win-x64 on Linux) is enforced by
  the "Repository, build and NativeAOT" epic.
- **Linux-bound** code lives in `Doment.Platform.Linux` and `Doment.Agent`.
- **Windows-bound projects from M7**, and Windows-bound code is reached only through an interface declared in a
  portable project.
- **The Linux solution filter from M7.** Linux builds use a solution filter without the Windows-bound projects,
  because `Darkraise.Win32UI` targets `net10.0-windows` and stops a Linux build with NETSDK1100. Whether Linux also
  compile-checks those projects is decided in the M7 "Windows build and CI" epic.

## Consuming darkraise-framework

### The reference

Every reference to the framework is a `ProjectReference` through one MSBuild property, `DarkraiseFrameworkPath`.
Allowed framework projects, relative to that path:

- `src/Darkraise/Darkraise.csproj`, from any project;
- `src/Darkraise.Win32UI/Darkraise.Win32UI.csproj` and
  `src/Darkraise.Win32UI.Generators/Darkraise.Win32UI.Generators.csproj`, only from a project whose
  `TargetFramework` starts with `net10.0-windows`.

The build refuses any other framework project (DOMENT012, see the next section).

### One framework worktree per doment checkout

`DarkraiseFrameworkPath` defaults to `external/darkraise-framework` inside the checkout being built: a git worktree
of the framework repository, ignored by doment's git. The primary checkout and every linked doment worktree each have
their own, so two doment branches with different pins build side by side, a framework edit in one does not disturb
another, and no build writes into a checkout that other apps use. The two stub files `external/Directory.Build.targets`
and `external/Directory.Packages.props` end MSBuild's upward search there, so doment's root build files apply to
doment's projects only.

Overrides: the property itself (`-p:DarkraiseFrameworkPath=<path>`) or the environment variable
`DARKRAISE_FRAMEWORK_PATH`. Both must be absolute paths; the property wins when both are set, and the pin check
applies to the overridden path. A relative override fails the build (DOMENT004), because project references resolve
relative to each project.

Other properties set by the root `Directory.Build.props`, each only when it is empty:

| Property | Default | Meaning |
|---|---|---|
| `DomentRepoRoot` | the directory of the root `Directory.Build.props` | Checkout root, with a trailing slash |
| `DomentFrameworkPinFile` | `$(DomentRepoRoot)build/darkraise-framework.pin` | The pin file |
| `FrameworkPinStrict` | `false` | `true` turns DOMENT001 and DOMENT002 into errors |
| `DomentRegisterFile` | `$(DomentRepoRoot)docs/third-party-exceptions.md` | The exception register |
| `DomentBuildOnly` | `true` for a project under `tests/` or `tools/`, else `false` | Shipping or build-only |
| `DomentAuditStrict` | `false` | `true` turns the NuGet audit warnings NU1901 to NU1904 into errors |

The root build files also keep DOMENT001 and DOMENT002 out of "warnings as errors", so strict mode is the only thing
that turns them into errors. `DomentPlatform`, `DomentSimulation` and `DomentFormatCheck` are set by the root
`Directory.Build.targets` (see Repository and build).

### The pin

`build/darkraise-framework.pin` holds one line: the full framework commit this doment commit is built and tested
against. Its first value was the framework remote's master on 2026-11-24, `e3cb121d83147eef363559d6f6bd4becda4b9e89`.

The framework's standing rule is that commits stay local and the owner pushes. A doment feature branch may therefore
pin a framework commit that exists only on this machine. On doment's master and on pull requests into it, CI
requires the pin to be an ancestor of the framework's remote master (DOMENT005), as the gate does when it runs on
doment's main branch; on any other branch CI requires only that the pin exists on the framework's remote, because its
framework checkout fetches it from there. With `DOMENT_GATE_PIN_ON_MASTER=1` the gate applies the ancestor check on
any branch or a detached HEAD.

### `tools/framework.sh`

`tools/framework.sh sync | pin | release` manages the checkout's framework worktree. It exits 0 on success, 1 on a
refusal or failure and 2 on bad usage, and its messages go to stderr, each starting with `framework.sh: `.

- The worktree is `$DARKRAISE_FRAMEWORK_PATH` when set, else `<checkout>/external/darkraise-framework`.
- The framework clone is `$DARKRAISE_FRAMEWORK_REPO` when set, else `darkraise-framework` beside doment's primary
  checkout. With neither, the script fails and names both places it looked.
- **`sync`** creates the worktree at the pin, or moves an existing one to it with `git switch --detach <pin>`. It
  fetches the commit first when the clone lacks it, and skips Git LFS downloads (the build does not need the
  framework's test corpus). It leaves the worktree on a detached HEAD and never moves, resets or deletes a branch. It
  refuses to move a worktree that is not clean, or whose HEAD is reachable from no framework branch and no
  remote-tracking ref, and says which. It also runs `git worktree prune` in the framework repository, which drops the
  entry of any framework worktree whose directory is gone, other apps' included.
- **`pin`** writes the worktree's commit into the pin file. It refuses when the worktree is not clean, and warns when
  the commit is not on a branch of the framework's remote.
- **`release`** removes the worktree through the framework repository (`git worktree remove`). It refuses when the
  worktree is not clean or its HEAD is reachable from no framework branch and no remote-tracking ref, and names the
  first offending path or the commit.

**Clean** means one thing everywhere (the build check, `sync`, `pin` and `release`): `git status` over the whole
worktree reports no modified, staged or untracked file, and no ignored file outside directories named `bin`, `obj`,
`.vs` and `.idea`. The framework ignores `*.user`, and MSBuild imports a `<project>.csproj.user` file, so an ignored
file elsewhere can change the build.

**Reachable** means `git for-each-ref --contains HEAD refs/heads refs/remotes` lists at least one ref.

A doment worktree is removed only after `release`.

### The framework checks

They run once per build, whatever the number of projects:

| Code | When | Kind |
|---|---|---|
| DOMENT003 | The framework directory does not exist; names the path and `tools/framework.sh sync` | Error, before restore |
| DOMENT004 | `DarkraiseFrameworkPath` or `DARKRAISE_FRAMEWORK_PATH` is not an absolute path | Error, before restore |
| DOMENT001 | The worktree is not at the pin, or not clean; names the actual and the pinned commit and the first offending path | Warning, so framework work in progress still builds; an error with `FrameworkPinStrict=true` |
| DOMENT002 | The framework directory is not a git checkout, or git is not installed, so the commit cannot be verified | Warning; an error with `FrameworkPinStrict=true` |
| DOMENT006 | The pin file does not hold one full 40-character commit hash | Error |
| DOMENT005 | On doment's `master` or `main` (or any branch or a detached HEAD with `DOMENT_GATE_PIN_ON_MASTER=1`), the pin is not an ancestor of the framework's `origin/master` | Gate error |

The gate command and CI build with `FrameworkPinStrict=true`, so a doment commit cannot pass its gates against a
framework tree other than the pinned commit.

### Working on the framework

Framework changes are made in the checkout's framework worktree, on a framework branch, following the framework's own
workflow and conventions. A change reaches doment through a commit that moves the pin (`tools/framework.sh pin`),
and the pin moves in a commit of its own. A doment commit passes its gate only against a clean worktree at the pin,
so the framework change is committed and the pin moved before the doment commit that needs it. On doment's main
branch the pin must be a commit on the framework's remote master. Rolling back is reverting the pin commit.

### Contribution rule

A piece goes into the framework when it is product-neutral and another darkraise app could use it: no doment
protocol, session or policy type appears in its public surface. Product logic stays in doment. Where the framework
already has a facility (logging, dependency injection, settings), doment uses it instead of writing its own. Known
contributions: the audio codec (M3), the video surface control (M7), the terminal control (M8).

### Limits

1. **Feature-branch pins can become unbuildable.** A doment feature-branch commit that pinned an unmerged or
   unpushed framework commit can stop building once that framework branch is rewritten or deleted. Only commits whose
   pin is on framework master are guaranteed to stay buildable.
2. **The framework repository is private** and doment's is public, so only someone with framework access can build
   doment, and CI reads it through a read-only deploy key on the framework repository (`doment CI (read-only)`, held
   in doment's secret `DARKRAISE_FRAMEWORK_DEPLOY_KEY`).
3. **Removing a doment worktree without `release` discards uncommitted framework work.** The framework worktree is
   ignored by doment's git, so removing a doment worktree any other way deletes it without a prompt.
4. **Write access to doment implies read access to the framework.** Anyone who can push a doment branch can change
   `ci.yml` to print the deploy key. Leaving the workflow alone is no barrier either: every ghr runner is one user
   with one persistent `HOME`, so a branch's build, restore or test code can leave a git hook (through `~/.gitconfig`)
   or an `~/.ssh/config` entry that runs during a later job's framework checkout, while the key is present.
   `persist-credentials: false` only removes the key once the checkout step ends. Today only the owner has write
   access.
5. **No merge queue while ghr serves doment.** ghr does not refuse `merge_group` jobs, and a merge queue runs a fork
   pull request's code as base-repository code.
6. **The key is readable on the runner host during the framework checkout.** It is in that step's process
   environment, which another job running on the ghr host as the same user can read. That is inside ghr's trust
   domain: every repository it serves is the owner's.

## Third-party register and gate

### The register

`docs/third-party-exceptions.md` is the only list of components in doment that are not doment code,
darkraise-framework, .NET, an operating-system API or a GPU-driver interface. People approve it and the build parses
it. It has three tables:

1. **Exceptions:** components that ship or are installed with doment (rows `X<n>`).
2. **Build-and-test-only tools:** components that never reach a shipped binary (rows `B<n>`).
3. **Platform packages:** packages the .NET SDK adds without a `PackageReference` in any doment project, or that
   arrive through an allowed framework project and are published by Microsoft.

A new row in table 1 or 2 needs the owner's approval; a new platform-packages row is a reviewed change. The register's
own preface gives the columns and the matching rules (exact identifiers, a trailing `.*` after a prefix as the only
wildcard, case-insensitive).

**Classification.** A project ships unless its path relative to the checkout root starts with `tests/` or `tools/`;
those are build-only.

### The build check

MSBuild logic imported by the root `Directory.Build.targets`, so every project gets it without opting in. It is one
inline C# source, `build/Doment.BuildChecks.cs`, compiled by MSBuild's RoslynCodeTaskFactory, so it needs nothing
beyond the .NET SDK (and git for the pin check). In every build, per project, it fails on:

| Code | When |
|---|---|
| DOMENT010 | A package in the project's restore output (direct, transitive, SDK-added, or arriving through a referenced project such as the framework; analyzer-only packages included) is in no table. Names the project, the package and version, the register and how it arrived: `direct reference`, `through <package>` or `through project <name>` |
| DOMENT011 | A shipping project resolves a build-and-test-only package (names the row), or references a build-only project |
| DOMENT012 | A `ProjectReference` resolves under `$(DarkraiseFrameworkPath)` or outside the checkout and is not an allowed framework project; checked before restore |
| DOMENT013 | The register is malformed: a missing table or column, a duplicate ID, or an empty required cell; names the row and the column |

Each build also logs `DOMENT-PACKAGES: <n>`, the number of distinct packages in the project's restore output.

### The gate command

```
build/gate.sh [<tree>]
```

`<tree>` defaults to the repository that holds the script. The gate checks every git-tracked `*.csproj`, `*.fsproj`
and `*.vbproj` in the tree, whether or not a solution lists it, except those under `tests/build/fixtures/`, which
holds deliberately wrong fixtures. Each project gets the build check above with `FrameworkPinStrict=true`, and the
framework checks run once for the tree. The gate also fails on:

| Code | When |
|---|---|
| DOMENT020 | A tracked project file does not import the root `Directory.Build.targets` |
| DOMENT021 | `.config/dotnet-tools.json` names a tool that is not a build-and-test-only row |
| DOMENT022 | A tracked `.dll`, `.exe`, `.so`, `.dylib`, `.a`, `.lib`, `.sys`, `.nupkg` or `.snupkg` file is listed in no files cell of table 1 or 2 |
| DOMENT005 | On `master` or `main`, or on any branch or a detached HEAD with `DOMENT_GATE_PIN_ON_MASTER=1`: the pin is not an ancestor of the framework's `origin/master` (fetched first, unless `DOMENT_GATE_NO_FETCH=1`) |

It prints every violation once, not only the first, then one summary line:

```
gate: <p> projects checked, <k> packages seen, <v> violations
```

It exits 0 when there is no violation, 1 when there is any, and 2 when `<tree>` is not a git work tree or its path
holds one of `;`, `%`, `$`, `@`, `"`, `,`, `&` and `<`, which MSBuild cannot take in a path (`&` and `<` also break
the inline build tasks, whose bodies MSBuild re-parses as XML after expanding the path into them). The refusal
covers the tree path only; a `DARKRAISE_FRAMEWORK_PATH` holding these characters is not checked. On `master` or
`main` with a malformed pin or no framework worktree, the gate skips the ancestry check and leaves the report to the
framework check, so each problem is reported once. `.gitattributes` makes every text file LF and marks the binary
types above as not text.

### What the check cannot see

Source code copied or ported from a third party, native libraries loaded by name at run time, and bundled assets of
third-party origin (fonts, images, data files). Each still needs a register row by rule; review and the M10 security
review enforce it.

### Tests

`tests/build/run.sh [<regex>]` proves the framework checks, `tools/framework.sh`, the register parser, the build
check and the gate on stand-in repositories and generated fixture trees, with no network access.
`tests/build/repository-build.acceptance.sh [<regex>]` proves the repository and build rules below on the real
checkout and on stand-in trees under `artifacts/acceptance/`, with the user's normal NuGet sources.

## Repository and build

### Toolchain

- `global.json` pins SDK 10.0.404 with `rollForward` `latestPatch` and selects Microsoft Testing Platform as the
  test runner. SDK 10.0.404 is installed under `/usr/local/share/dotnet` and linked as `/usr/local/bin/dotnet`, which
  every shell on the machine now resolves first; apt's 10.0.302 stays installed (its runtime 10.0.10 fails the
  NativeAOT restore on GHSA-p3jp-9v83-76w9). Undo: remove `/usr/local/share/dotnet` and the link.
- clang comes from apt (`apt remove clang` undoes it); no build file sets `CppCompilerAndLinker`.
- On a CI runner the SDK comes from `actions/setup-dotnet` (from `global.json`, installed under `$RUNNER_TEMP/dotnet`)
  and clang from ghr's managed packages (see CI).
- `docs/dforge/research/2026-11-24-build-probes.md` records the probes the build mechanisms rest on.

### Solution

`doment.slnx` lists the projects of the Module map built so far, under `/src/`, and `tests/Doment.Core.Tests` under
`/tests/`. Every project targets `net10.0`; the libraries set `IsAotCompatible`, and `Doment.Server` (`doment-server`),
`Doment.Cli` (`doment`) and `Doment.Agent` (`doment-agent`) set `PublishAot` and `TrimmerSingleWarn=false`. The
executables share `Doment.Core.StandardOptions` (`--version`, `--help`, usage with exit 2), and the version is
`VersionPrefix` 0.1.0 in the root `Directory.Build.props`. `tests/Directory.Build.props` holds the test package
versions (xUnit v3 4.0.2, Microsoft Testing Platform 2.5.1). Publish output goes to `artifacts/`, which git ignores.

### Conventions

`build/Doment.Conventions.props` sets nullable, implicit usings, the latest language, warnings as errors, the
`latest-recommended` analysis level, code style in the build, and CA1416 as an error. The root `.editorconfig` is the
framework's, without its `DRUI020` line, with LF line endings, and with IDE0161, IDE0028 and IDE0300 to IDE0305 at
`warning`; each change carries a `# doment:` comment. Every build checks formatting with CSharpier 1.2.6
(`.config/dotnet-tools.json`, `printWidth` 130 as the framework's `.csharpierrc`). doment and the framework move their
CSharpier version together.

### Build properties

| Property | Set by | Values |
|---|---|---|
| `DomentPlatform` | `build/Doment.Platform.targets`, after the project body, from the Module map's Kind column | `portable`, `linux` (`Doment.Agent`, `Doment.Platform.Linux`) or `windows` (`Doment.Platform.Windows`, `Doment.Service`, `Doment.Session`, `Doment.App`); only a global property overrides it |
| `DomentSimulation` | `build/Doment.Simulation.targets` | `false` by default; `true` gives `Doment.Cli` and `Doment.Agent` the `Doment.Simulation` reference and `DOMENT_SIMULATION` |
| `DomentFormatCheck` | `build/Doment.Format.targets`, after the project body | `true`; only a global `false` turns the format check off |
| `DomentAuditStrict` | `build/Doment.Conventions.props` | `false` by default, `true` in `build/check.sh` |

A portable project cannot switch CA1416 off in its own file with `NoWarn`, `RunAnalyzers`, `EnableNETAnalyzers`,
an `AnalysisLevel` or `AnalysisLevelInteroperability` ending in `none`, or by clearing `TreatWarningsAsErrors` and
`WarningsAsErrors`: `build/Doment.Platform.targets` sets them back after the project body. Diagnostics:

| Code | When |
|---|---|
| DOMENT030 | A publish in a configuration other than Debug with `DomentSimulation=true` or `Doment.Simulation` among the resolved references |
| DOMENT031 | A compiled file is not formatted; one line per file |
| DOMENT032 | CSharpier is not restored (`dotnet tool restore`) |
| DOMENT033 | A portable project declares a native import, references `System.Runtime.InteropServices.NativeLibrary`, carries an assembly-level `SupportedOSPlatform`, or does not target `net10.0` |

The assembly findings of DOMENT033 come from `build/Doment.PortableCheck.cs`, a reader of the output assembly's
metadata tables in netstandard 2.0 code, because the inline task factory cannot reference
`System.Reflection.Metadata`. A Windows-only call guarded by `OperatingSystem.IsWindows()`, an API .NET does not
annotate, `#pragma` or `SuppressMessage` suppressions, and a CA1416 severity set in an `.editorconfig` or
`.globalconfig` below the root pass these checks; review catches them.

### `build/check.sh`

```
build/check.sh [<step>...]      steps: build, portable, aot, test; default: all four in this order
```

It checks the tree that holds it, found without git, with `-c Release -p:FrameworkPinStrict=true
-p:DomentFormatCheck=true -p:DomentAuditStrict=true` on every call. `build` builds `doment.slnx`; `portable` builds
each portable project for linux-x64 and win-x64 (win-x64 with `PublishAot=false`); `aot` publishes each `PublishAot`
project to `artifacts/publish/<name>/linux-x64/`, fails on any warning line, and runs the binary with `--version`;
`test` runs `dotnet test --solution doment.slnx`. It exports `DOTNET_ROOT` as the directory of the `dotnet` on PATH,
runs each call in a process group of its own under a timeout (600 s, 1200 s for a publish, or
`DOMENT_CHECK_TIMEOUT`), kills that group on expiry and on INT or TERM, and stops at the first failed step. It
prints `check: <step> ok` or `check: <step> failed` with indented cause lines, and last
`check: <n> steps run, <f> failed`; it exits 0, 1 on a failure, 2 on an unknown step.

## CI

### The workflow

`.github/workflows/ci.yml`, workflow `CI`, has one job, `build`, with a matrix of two entries, `check` and
`acceptance` (`fail-fast: false`).

- **Triggers:** a push of any branch (no tags), a pull request into master, and `workflow_dispatch`; never
  `pull_request_target`, `workflow_run`, `issue_comment`, `merge_group` or `schedule`.
- **Token:** `permissions: contents: read`, nothing else.
- **Concurrency:** a newer push to the same branch cancels that branch's run in progress; every master run has a group
  of its own, so no master run is cancelled.
- **Timeouts:** 30 minutes for `check` and 130 for `acceptance`, twice the first green run's durations (11 and 63
  minutes, 2026-11-26) rounded up; `docs/dforge/research/2026-11-25-ci-pool-probe.md` records them.
- **Steps:** check out doment (`fetch-depth: 0`, `lfs: false`, `persist-credentials: false`); read the pin with bash
  alone, check that it is one 40-character hash and that `ssh` is present; check out the framework at the pin into
  `external/darkraise-framework` with the deploy key (same flags, plus `GIT_LFS_SKIP_SMUDGE=1`), with an annotation
  naming the pin when that fails; `build/ci.sh verify`; `actions/setup-dotnet` from `global.json` into
  `$RUNNER_TEMP/dotnet`; `dotnet --version`; `dotnet tool restore`, under `flock` on
  `$HOME/.nuget/doment-tool-restore.lock`, because two jobs restoring the same tool into the shared package folder at
  once fail; then `build/ci.sh <entry>`.
- **Invariants:** no step before the framework checkout runs a file from the checked-out tree, since such a file could
  write `GITHUB_ENV` and capture the key; every `uses:` is an `actions/*` action at a full commit SHA (the repository
  also requires SHA pinning); the job environment disables node reuse, the MSBuild server and the shared compiler, and
  no step runs `dotnet build-server shutdown`, which would stop other jobs' servers on the shared runner user
  (`build/check.sh` skips its own when `GITHUB_ACTIONS=true`).

### Fork controls

- **The job condition** runs a `pull_request` job only when the head repository is doment itself, so a fork's pull
  request that leaves the workflow alone shows as skipped. It does not stop a fork that edits the workflow.
- **ghr's job-started hook** ends the runner's worker for any job whose event comes from a fork.
- **The repository's approval setting** requires the owner's approval before any external contributor's workflow
  runs (`fork-pr-contributor-approval`: `all_external_contributors`).

### Runners

Jobs run only on `[self-hosted, doment-linux]`, a ghr pool on the owner's host; no workflow names a GitHub-hosted
label. ghr registers a runner only while a job is queued. Every runner is the user `ghrunner` with one `HOME`, so jobs
share `~/.nuget/packages`. The jobs need `clang`, `zlib1g-dev`, `jq`, `file`, `procps`, `util-linux` (`flock`) and
`openssh-client`, which come from ghr's managed packages (a host-wide list, `ghr package install <name>`);
`build/ci.sh verify` names any that is missing.

### The secret

`DARKRAISE_FRAMEWORK_DEPLOY_KEY` holds the private half of the read-only deploy key `doment CI (read-only)` on
`darkraise/darkraise-framework`. Only the framework checkout step references it, and `build/ci.sh verify` checks that
the checkout left no `core.sshCommand` and no private key under `RUNNER_TEMP`.

### `build/ci.sh`

`build/ci.sh verify|check|acceptance` holds everything after the key's step, so each failure path is tested locally
with stand-ins (`tests/build/ci-pushed-branches.acceptance.sh`).

- `verify` checks that the deploy key is gone, that the framework checkout is clean and holds no LFS objects, that
  the runner has the packages above, and that the workspace has at least 20 GB free; it prints every failure.
- `check` runs `build/check.sh`, then always `build/gate.sh`, and fails when either failed.
- `acceptance` runs `tests/build/repository-build.acceptance.sh`, `tests/build/repository-build-nativeaot.acceptance.sh`
  and `tests/build/ci-pushed-branches.acceptance.sh`, each whatever the previous result.

### `DOMENT_GATE_PIN_ON_MASTER`

The workflow sets `DOMENT_CI_PIN_ON_MASTER=1` for the `check` entry of a push to master or a pull request into master,
and `0` otherwise. `build/ci.sh check` passes it to the gate call alone as `DOMENT_GATE_PIN_ON_MASTER`, with
`DOMENT_GATE_NO_FETCH=1`, after printing `ci: gate DOMENT_GATE_PIN_ON_MASTER=<value>`: a pull request's checkout is a
detached merge commit, which the gate's own master-or-main rule never matches. Every `tests/build` runner unsets the
variable.

## Rules handed to later epics

### Gates declared

- The exception-register gate is `build/gate.sh`; `tests/build/run.sh` and
  `tests/build/repository-build.acceptance.sh` are part of the tests gate.
- The build, tests and NativeAOT gates are `build/check.sh build`, `test` and `aot`, with `portable` part of the
  build gate.

### Device identity, pairing and encrypted sessions

- The build must also reject, inside `Doment.Protocol`, the pointer-arithmetic library calls that need no `unsafe`
  keyword, without adding an analyzer package or a build-only project reference to it.

### Clipboard and file transfer protocol

- The path suite (R80) gains a case where a local user plants a link in the destination folder.
- Name the process that writes under the user's identity, and decide the behaviour with no user signed in.

### Host terminal service

- Decide the Linux unit layout and service account, how a restarted service finds running terminal hosts, the
  version range and its out-of-range outcome, and apply the never-killed rule, all from Process model.
- Whatever is decided on R176, the service rejects malformed data from the terminal host and survives the terminal
  host being killed, hung and restarted.

### Host service and session agent (M7)

- The same fault cases for the session agent, and the ring full.

### Windows build and CI

- The first project that references `Darkraise.Win32UI` adds the platform rows its restore output shows (its
  generator targets `netstandard2.0`, so more .NET packages than the three NativeAOT ones are expected).
- On Linux the gate still checks Windows-bound projects: it restores them with `EnableWindowsTargeting=true` passed
  as a global property and does not compile them. That the restore then succeeds on Linux is inference, verified in
  that epic.
- A Windows-bound project gets `DomentPlatform=windows` from the list in `build/Doment.Platform.targets`; a new one
  is added there.

### Desktop app (M8)

- Restore the framework's `DRUI020` editorconfig line when a project references `Darkraise.Win32UI.Generators`.
- Choose install locations or names so that `doment.exe` and `Doment.exe`, one file name on Windows, never share a
  directory.

### Windows terminal host (M7) and Installers and update (M11)

- An update or a rollback replaces binaries without stopping a running terminal host. On Windows a running
  executable cannot be overwritten, so versions install side by side or the old file is renamed.

## Changing this record

This file is the living record. A later epic that changes a decision recorded here (a process, a project or its
references, a seam, the framework arrangement, the register or the gate) edits this file in the same change, and its
spec says so. The 2026-11-24 spec is not edited afterwards; it stays the record of why the first decisions were made.
