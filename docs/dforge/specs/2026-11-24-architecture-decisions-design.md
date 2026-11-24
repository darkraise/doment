# Architecture decisions — design

**Date:** 2026-11-24
**Epic:** M1 Foundations, "Architecture decisions" (R1-R4 of docs/dforge/specs/2026-11-24-doment-design.md)
**Execution strategy:** sequential — inline execution
**Depth:** full — new-subsystem

## Decisions

Questions put to the owner on 2026-11-24, with the answers quoted, and the approach choices made in this epic.

1. **Build-and-test-only tools under the third-party rule.** Asked: how should the exception register treat tools that
   never ship in a binary (xUnit v3, Microsoft Testing Platform, csharpier)? Owner: "Separate build-only class
   (Recommended)". The register gets a second class, and the check fails when a tool of that class reaches a project
   that ships.
2. **How doment references darkraise-framework (R3).** Offered: a pinned git submodule (recommended), the shared sibling
   checkout plus a pin file, or a pinned NuGet package. Owner: "create a darkraise framework worktree and reference to
   it, since we still need to code in framework". Section 6 designs the pin around that worktree.
   **Approach:** inline - skip 3: the owner chose. An advisor pass on the submodule variant had run before the answer;
   its findings that do not depend on the submodule are carried into sections 5, 6 and 9. Where the worktree lives
   was not asked and is put to the owner with A10; whether a pin may name an unpushed commit is put with A25.
3. **Terminal sessions across a host service restart.** Asked: the product spec has the host service own the
   pseudo-terminals (section 10, R104) and R145 requires "no lost terminal sessions" across a service restart; both
   cannot hold. Owner: "Yes: separate terminal host (Recommended)". The question stated that "the wording of section 10
   and R104 changes".
4. **Which host process terminates the network connection.** Not asked: one candidate meets the requirements.
   **Approach:** advisor - load-bearing (constrains the M2 transport and the M7 service). Chosen: the host service is the
   only network endpoint and the trust anchor; the session agent is a local worker. Rejected: the session agent
   terminating media connections itself (breaks R118, drops the session whenever the agent restarts, two flows through
   NAT traversal); a third low-privilege network process (a second local hop and a second cross-process protocol on
   every channel from the first day; kept possible, see section 2). Advisor verdict: sound, with conditions that are
   now rules in sections 2, 3 and 9.
5. **How the exception check is built.** **Approach:** inline - skip 5: not load-bearing. The mechanism is confined to
   build files and can be replaced without touching product code; its behaviour is fixed by the acceptance statements.
6. **Fast mode** was not offered: the handoff asked for a written spec.

CI: none exists yet (the "CI for pushed branches" epic adds it), so no platform is uncovered.

## 1. What this epic delivers

R1 to R3 ask for decisions to be recorded; R4 asks for a register and a build that fails. The epic therefore delivers
documents, one build check and the framework reference, and no product code:

| File | Purpose |
|---|---|
| `docs/architecture.md` | The architecture record: sections 2 to 6 of this spec, the rules of section 9 and the gate command's invocation, kept current by every later epic |
| `docs/third-party-exceptions.md` | The exception register (section 7), read by people and by the check |
| `Directory.Build.props` | `DarkraiseFrameworkPath` and the shipping or build-only classification |
| `Directory.Build.targets`, `build/` | The framework presence and pin checks and the third-party check |
| `build/darkraise-framework.pin` | The framework commit this doment commit is built against |
| `external/Directory.Build.targets`, `external/Directory.Packages.props` | Empty stubs that keep doment's root build files out of the framework's projects |
| `tools/framework.sh` | Creates or moves a checkout's framework worktree to the pin, records a new pin, and removes the worktree without losing work |
| `tests/build/` | Fixture trees and the script that proves sections 6 and 7 |
| `docs/dforge/specs/2026-11-24-doment-design.md` | Amended as section 8 lists |

The spec is the decision log of 2026-11-24. `docs/architecture.md` is the living record: when a later epic changes a
decision it edits that file, not this spec.

## 2. Process model (R1)

| Role | Executable | Runs as | Owns |
|---|---|---|---|
| Host service | Linux: `doment-agent` (M1; its systemd unit in M4). Windows: `doment-service.exe` (M7) | Linux: decided in M4 under the constraints below. Windows: SYSTEM | The device key and the paired-device list; the handshake; the one policy decision point (R18); every network socket; the transport and the reliable control channel; the session inventory; the wake helper and relay-node roles; keyboard modifier state; the handles of system-wide virtual devices; supervision of the session agent |
| Session agent | Windows: `doment-session.exe` (M7). Linux and macOS desktop hosts: M16 | SYSTEM in the console session | Everything that needs the interactive session: capture, encode, audio capture, input injection, cursor, display topology, clipboard access, on-host prompts and the session indicator. No keys, no network sockets |
| Terminal host | Linux: a mode of the `doment-agent` binary, so R45's single binary holds (M4). Windows: a mode of `doment-session.exe`, started with the user's token (M7) | The user whose shells it runs; one instance per user and privilege level | Pseudo-terminals, the terminal state and scrollback used for snapshots, session identifiers, each session's process tree. No keys, no network sockets |
| Client | `doment` command-line client (M1); `Doment.exe` Win32UI app (M8) | The user | The client device key, the client side of the connection ladder, decode, presentation, audio playback, input capture, terminal rendering |
| Server | `doment-server` (M3) | An unprivileged account | Directory, connection brokering, relay, wake helper; never a device private key or plaintext (R33) |
| Shared portable core | Libraries (section 4) | - | Everything two or more roles share |

Rules:

- **One network endpoint per host.** Only the host service opens network sockets. One authenticated connection per client
  carries every channel (control, terminal, video, audio, input, clipboard, files, power), which is what R118 and R53
  need, and it stays up while the session agent restarts or the console session changes (R83, R84, R87).
- **Policy in one place.** Only the host service authorises (R18). Workers accept a link only from the host service,
  checked by the operating system (socket peer credentials, pipe access control), and trust what it sends.
- **Terminals outlive the service.** A restart, crash, update or rollback of the host service leaves the terminal host
  and its shells running; the service finds running terminal hosts when it starts and lists their sessions again
  (R52, R145). Three things follow:
  - *Outside the service's kill scope.* On Linux the terminal host runs in a systemd unit of its own,
    outside the service's control group (systemd's default kills every process of a restarted unit), as the
    configured user, and the service finds it through a socket at a fixed per-user path. The "Host terminal service"
    epic chooses between a per-user unit with lingering and a template system unit, and how the service is allowed to
    start it; that choice also fixes the Linux service account. Its acceptance restarts the service unit and finds the
    shell alive. On Windows the host service launches the terminal host with the user's token, outside any job that
    closes with the service.
  - *Never killed by the service.* A terminal host that stops answering has its sessions listed as unavailable, with
    a log line naming its process and its last heartbeat. A session agent that stops answering is killed and
    restarted (R83).
  - *Versions differ for days.* A terminal host keeps running the binary it was started from until its last session
    ends, then starts again from the installed one. The worker link therefore opens with a version exchange and the
    service speaks to a terminal host at least one minor version older or newer (an update, a rollback under R148).
    Outside that range the service lists the sessions as "restart needed on the host", logs both versions and leaves
    the shells running.
- **Workers at lower privilege are untrusted input.** The terminal host runs as the user while the service runs as
  SYSTEM or a service account, so whatever it sends is parsed like network input: by safe code, with every length
  and offset copied out before it is validated. The framing and the parsers of the socket and pipe form of the worker
  link live in `Doment.Protocol`, so the compiler holds this rule. The terminal channel uses the socket or pipe only;
  shared memory is used only with the session agent, which runs at the service's own privilege.
- **User data under the user's identity.** Shells, received files and clipboard content are read and written under
  the identity of the signed-in user, never as SYSTEM or root: a SYSTEM write into a user-chosen folder can be
  redirected by a link planted there. On Linux a process running as the user does it; on Windows a helper started
  with the user's token or impersonation for each write, chosen by the file-transfer epic. What file transfer and
  clipboard do while no user is signed in is decided in the "Clipboard and file transfer protocol" epic and put to
  the owner there; nothing is ever written as SYSTEM or root into a location a user can write.
- **Device handles in the service.** Virtual gamepad and virtual display devices are created and removed by the host
  service so that an agent restart does not unplug them; the session agent only applies the display layout. Inference
  from how the ViGEmBus client works; the M9 epics confirm it.
- **Parsing before authentication is safe code.** Everything that parses bytes from an unauthenticated peer
  (handshake, pairing, discovery, address probes, relay framing, port-mapping replies) lives in `Doment.Protocol`,
  which compiles with unsafe code disallowed. Code that may use pointers for speed (error correction, media) only
  receives data from an authenticated, paired device or from the session agent. This is the condition for parsing as
  SYSTEM; the M10 security review (R142) decides whether the endpoint moves to a low-privilege process, which costs a
  second local hop and a second cross-process protocol.

## 3. Worker link

The host service reaches the session agent and the terminal host only through one portable boundary, the worker link,
defined in `Doment.Worker`. Host code never calls a capture, encode, input or pseudo-terminal seam directly.

- **Typed channels:** media (encoded video, audio), encoder control, input, cursor, display topology, clipboard,
  on-host prompts, terminal (bytes, snapshots, resize, lifecycle).
- **Contract, written so that an in-process implementation cannot hide a cross-process fault:**
  - the link opens with a version exchange (section 2);
  - a frame is a lease on a ring slot with an explicit release, and a full ring drops frames (R22);
  - a slot carries a whole frame or one part of a frame as the encoder emits it, flagged first and last, so the hop
    adds no whole-frame wait;
  - every control request is asynchronous and answered by an acknowledgement tagged with a frame number;
  - the link has explicit states (worker absent, starting, running, session changed, console unavailable, version
    out of range) and a liveness heartbeat, with the per-worker outcome of section 2;
  - stream discontinuities (new parameter sets, a resolution or HDR change, recovery after device loss) are in-band
    events;
  - each slot header carries the frame's stage timestamps as raw monotonic ticks, so R12 works across processes;
  - the service packetises straight from the ring slot (one copy at most), and both ends wait on events from dedicated
    threads, never on thread-pool reads.
- **Two implementations:** in-process (unit tests and the M1 walking skeleton) and cross-process (a local socket or
  pipe, plus shared memory for the session agent). The terminal host needs the cross-process one on Linux in M4.
  Section 8 proposes building and fault-testing it in M2 with a simulated session agent, instead of meeting it first
  at M7.

## 4. Module map (R1)

A project may reference only projects on its "References" line. Code used by two or more of host, client and server
lives in `Doment.Core`. Executables are composition roots (arguments, configuration and wiring only), except
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

- References are transitive, so the line lists direct references only.
- Worker executables and the worker side never reference `Doment.Host`: "no keys, no sockets" is then a boundary the
  compiler holds, not a convention. Where the terminal host is a mode of another binary (the agent on Linux, the
  session agent on Windows), the boundary is the project: terminal host logic lives in `Doment.Worker`. The "Windows
  terminal host" epic may give it an executable of its own and records that in `docs/architecture.md`.
- **Simulation never ships in a release binary.** An executable references `Doment.Simulation` only in a simulation
  build (one build property, set by test, bench and harness builds); a release publish with that property set fails.
  The walking skeleton's synthetic stream (R11) runs in such a build of the agent.
- Test projects sit beside the project they test under `tests/`; the test bench and the measurement harness are
  build-only tools under `tools/`.
- The "Repository, build and NativeAOT" epic creates the M1 projects and may merge two of them if one stays empty
  through M1; it records the change in `docs/architecture.md`.

## 5. Platform seams and build order (R1, R2)

One named interface per seam, declared in `Doment.Core`. The signature is written by the first epic that consumes the
seam, not before, because a signature with no consumer is a guess.

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

Every one has a simulated implementation in `Doment.Simulation`, written by the epic that declares the signature.

Further platform-bound functions the requirements already imply get a seam in the epic named, and a row in
`docs/architecture.md` when they do: device key storage (M2, R14), high-resolution timers and thread scheduling (M2),
packet marking and network interfaces (M2, R24; M5, R66), LAN discovery (M3, R44), power actions and wake readiness
(M5, R69-R70), session events and worker launch (M7, R83), client input capture (M7, R103), clipboard access (M9,
R131), on-host prompts (M8, R113).

Seam rules:

1. **Opaque frames.** A video frame is metadata (size, timeline, dirty rectangles, cursor, HDR data) plus a surface
   owned by the platform family that made it. Portable code never reads pixels on the production path. Capture and
   encode come from one family, decode and presentation from one family, chosen once in the composition root. Reading
   pixels back is a separate optional capability used by the verifying sink and the sharpness measurement.
2. **Injected clock.** Stages stamp the frame timeline through a clock passed in, so pacing and latency logic run
   against a simulated clock (R74).
3. **Hot-path discipline.** Seam calls come from dedicated threads owned by the caller, do not allocate at steady
   state, and use no `async` on the frame path.
4. **Status, not exceptions.** Device loss, a mode change, a missing driver or denied access are returned as status
   values; every seam says how it is recreated so the session survives (R87), and reports "unavailable" at start-up
   when its component is absent (R129, R134).
5. **Capabilities.** Each seam reports the capability set that negotiation uses (R27).
6. **One contract suite per seam**, run against the simulated implementation on Linux and against the real
   implementation on its platform, so the two are held to the same behaviour.

Build order:

- **Portable** projects target `net10.0`, call no operating-system-specific API, and are built and verified on Linux
  from M1 to M6. R6 (compile for linux-x64 and win-x64 on Linux) is enforced by the "Repository, build and NativeAOT"
  epic.
- **Linux-bound** code lives in `Doment.Platform.Linux` and `Doment.Agent`.
- **Windows-bound** projects start at M7. Windows-bound code is reached only through an interface declared in a
  portable project.
- **Linux builds from M7** use a solution filter without the Windows-bound projects, because `Darkraise.Win32UI`
  targets `net10.0-windows` and stops a Linux build with NETSDK1100. Whether Linux also compile-checks them is decided
  in the M7 "Windows build and CI" epic.

## 6. Consuming darkraise-framework (R3)

- **Source reference.** Every reference is a `ProjectReference` through the one property `DarkraiseFrameworkPath`.
  Any project may reference `src/Darkraise/Darkraise.csproj`; a project that targets `net10.0-windows` may also
  reference `src/Darkraise.Win32UI` and its generator. Any other framework project is refused by the check in
  section 7.
- **One framework worktree per doment checkout.** The property defaults to `external/darkraise-framework` inside the
  checkout being built: a git worktree of the framework repository, ignored by doment's git. The primary checkout and
  every linked doment worktree each have their own, so two doment branches with different pins build side by side, a
  framework edit in one does not disturb another, and no build writes into a checkout that other apps use. The two
  stub files in `external/` end MSBuild's upward search there, so doment's root build files apply to doment's
  projects only. The property, or the environment variable `DARKRAISE_FRAMEWORK_PATH`, overrides the default with an
  absolute path (the property wins when both are set, and the pin check applies to the overridden path); a relative
  override fails the build, because project references resolve relative to each project.
- **The pin.** `build/darkraise-framework.pin` holds one line, the full framework commit this doment commit is built
  and tested against. Initial value: the remote's master, `e3cb121d83147eef363559d6f6bd4becda4b9e89` on 2026-11-24
  (the local framework master is ahead of it by unpushed documentation commits, which CI could not fetch).
- **Pushed where something else must fetch it.** The framework's standing rule is that commits stay local and the
  owner pushes. A doment feature branch may therefore pin a framework commit that exists only on this machine. CI,
  and the gate when it runs on doment's main branch, require the pin to be an ancestor of the framework's remote
  master.
- **`tools/framework.sh`** has three verbs:
  - `sync` creates the checkout's framework worktree at the pin, or moves an existing clean one to it with
    `git switch --detach <pin>`, fetching the commit first when the local framework clone lacks it and skipping Git
    LFS downloads (the build does not need the framework's test corpus). It leaves the worktree on a detached HEAD
    and never moves, resets or deletes a branch. It finds the framework clone through `DARKRAISE_FRAMEWORK_REPO`,
    otherwise beside doment's primary checkout; when it finds none it fails and names both places it looked. It
    refuses to move a worktree that has changes.
  - `pin` writes the worktree's commit into the pin file. It refuses when the worktree has changes, and warns when
    the commit is not reachable from a branch of the framework's remote.
  - `release` removes the framework worktree through the framework repository (`git worktree remove`). It refuses
    when the worktree has a modified, staged or untracked file, or when its HEAD is reachable from no framework
    branch and no remote-tracking ref, and says which.

  A doment worktree is removed only after `release`. Known limit: the framework worktree is ignored by doment's git,
  so removing a doment worktree any other way discards uncommitted framework work without a prompt. `sync` also runs
  `git worktree prune` in the framework repository, which drops the entry of any worktree whose directory is gone,
  other apps' included.
- **Checks, once per build, before compilation:**
  - framework directory missing: one error that names the path and tells the reader to run `tools/framework.sh sync`;
  - worktree not at the pin, or not clean: warning DOMENT001 in an ordinary build, so framework work in progress
    still builds; an error when `FrameworkPinStrict=true`, which the gate command and CI set. Not clean means that
    `git status` over the whole worktree reports a modified, staged or untracked file, or an ignored file outside
    directories named `bin`, `obj`, `.vs` and `.idea` (the framework ignores `*.user`, and MSBuild imports a
    `<project>.csproj.user` file). The message names the pinned and the actual commit, and the first offending path
    when the tree is not clean. A doment commit therefore cannot pass its gates against a framework tree other than
    the pinned commit;
  - framework directory that is not a git checkout, or git not installed: the commit cannot be verified, which is
    warning DOMENT002 in an ordinary build and an error in strict mode.

  The root build files keep DOMENT001 and DOMENT002 out of "warnings as errors", so strict mode is the only thing
  that turns them into errors.
- **Working on the framework.** Framework changes are made in that worktree on a framework branch, following the
  framework's own workflow and conventions. A change reaches doment by a commit that moves the pin; the pin moves in a
  commit of its own. A doment commit passes its gate only against a clean worktree at the pin, so a framework change
  is committed and the pin moved before the doment commit that needs it. On doment's main branch the pin must be a
  commit on the framework's remote master (section 9 hands the check to CI). Rolling back is reverting the pin
  commit. Known limit: a doment feature-branch commit that pinned an unmerged or unpushed framework commit can stop
  building once that framework branch is rewritten or deleted; only commits whose pin is on framework master are
  guaranteed to stay buildable.
- **Contribution rule.** A piece goes into the framework when it is product-neutral and another darkraise app could
  use it: no doment protocol, session or policy type appears in its public surface. Product logic stays in doment.
  Where the framework already has a facility (logging, dependency injection, settings), doment uses it instead of
  writing its own. Known contributions: the audio codec (M3), the video surface control (M7), the terminal control
  (M8).
- **Limit.** The framework repository is private and doment's is public, so only someone with framework access can
  build doment, and CI needs a read-only credential for it.

Evidence (2026-11-24): a throwaway console app referencing an exported copy of `src/Darkraise` by `ProjectReference`
published with `dotnet publish -c Release -r linux-x64 -p:CppCompilerAndLinker=gcc` under NativeAOT with zero trim and
AOT warnings, and ran.

## 7. Third-party exception register and check (R4)

**The register** is `docs/third-party-exceptions.md`, the only source: people approve it and the check parses it.
Three tables with fixed columns:

1. **Exceptions** (ships or is installed with doment): ID, component, packages or files, used for, reason, licence,
   behind (the interface), replacement, approved (date). Initial rows: X1, an existing signed Indirect Display driver
   (candidate: Virtual Display Driver, MIT; signature validity confirmed in its M9 epic), behind `IVirtualDisplay`,
   replaced in M17; X2, ViGEmBus (BSD-3-Clause, archived 2023), behind `IVirtualGamepad`, replaced in M17. Licences
   read from the two GitHub repositories on 2026-11-24.
2. **Build-and-test-only tools** (never in a shipped binary): ID, component, packages or tool, used for, licence,
   approved. Initial rows, approved by the owner on 2026-11-24: xUnit v3, Microsoft Testing Platform, csharpier. An
   approved row covers the packages its component resolves transitively; the epic that first references the component
   lists them exactly in its spec, which the owner approves. A transitive package published by neither the
   component's publisher nor Microsoft is a new row.
3. **Platform packages**: package identifier, added by, first seen. A package belongs here only when the .NET SDK
   adds it without a `PackageReference` in any doment project file, or it arrives through an allowed framework
   project and Microsoft publishes it; a package that a doment project names itself needs a row in table 1 or 2.
   Initial rows are the three the .NET SDK adds for a NativeAOT publish for linux-x64, observed on 2026-11-24:
   `Microsoft.DotNet.ILCompiler`, `runtime.linux-x64.Microsoft.DotNet.ILCompiler`, `Microsoft.NET.ILLink.Tasks`. A new
   row, including the same package for another runtime identifier, is a reviewed change and needs no replacement plan.

Row identifiers are `X<n>` in table 1 and `B<n>` in table 2, each unique. A package cell lists exact identifiers; a
trailing `.*` after a written prefix is the only wildcard. A new row in table 1 or 2 needs the owner's approval, as
the product spec says.

**Classification.** Every project either ships (the default) or is build-only (everything under `tests/` and `tools/`).

**The check** is MSBuild logic imported by the root `Directory.Build.targets`, so every project gets it without
opting in, and it needs nothing beyond the .NET SDK. In every build, per project, it fails when:

- a package in the project's restore output is in no table. The restore output lists direct, transitive and
  SDK-added packages alike, including those that arrive through a referenced project such as the framework. This
  includes analyzer-only packages: a shipping project uses the analyzers bundled with the .NET SDK or a tool from
  the tool manifest;
- a project that ships resolves a package of table 2, or references a build-only project;
- a `ProjectReference` resolves to a project under `$(DarkraiseFrameworkPath)` or outside the checkout and is not
  one of the allowed framework projects;
- the register is malformed: a missing table or column, a duplicate ID, or an empty required cell.

Run as the gate command (one command that takes the tree to check, by default the repository; its exact invocation
is recorded in `docs/architecture.md` and used by `docs/dforge/gates.md` in the "Gates declared" epic), it checks
every project file tracked under that tree, whether or not the solution lists it, and also fails when:

- a tracked project file does not import the root build targets;
- `.config/dotnet-tools.json` names a tool that is not in table 2;
- a tracked binary (`.dll`, `.exe`, `.so`, `.dylib`, `.a`, `.lib`, `.sys`, `.nupkg`, `.snupkg`) is not listed in a
  files cell.

The gate skips exactly one directory, `tests/build/fixtures/`, which holds the deliberately wrong fixture trees of
section 10. A project anywhere else is checked.

Every error names the project, the package with its version, how it arrived (the direct reference that brought a
transitive package) and the register file. The gate command reports every violation, not only the first, and ends
with one summary line (projects checked, packages seen, violations).

**What it cannot see**, recorded so nobody assumes otherwise: source code copied or ported from a third party,
native libraries loaded by name at run time, and bundled assets of third-party origin (fonts, images, data files).
Each needs a register row by rule; review and the M10 security review enforce it.

Evidence (2026-11-24): `obj/project.assets.json` of the throwaway app listed the referenced framework project and the
three SDK-added packages under `libraries`.

## 8. Product spec amendments

Applied to docs/dforge/specs/2026-11-24-doment-design.md by this epic's plan.

Approved by the owner's answers above:

- R1: the list of processes gains the terminal host.
- R4 gains: "; build-and-test-only tools are listed in a separate class with what they are used for, their licence
  and the approval date, and never reach a shipped binary".
- Section 5, "Third-party rule": "approved in this spec ... (section 11)" becomes "approved by the owner and listed
  in docs/third-party-exceptions.md".
- Section 9, the row on terminal sessions that vanish: "The terminal host owns the pseudo-console and the session
  list".
- Section 10, "Terminals" and "Processes": a terminal host process, separate from the service and running as the
  user, owns the pseudo-terminals and the terminal state.
- R104: "The Windows terminal host owns terminal sessions through the pseudo-console with the same persistence
  behaviour as on Linux, and every session's process tree is in a job object."
- Section 10, "Open decisions": "how doment references the framework" is removed.
- Section 11: the register moves to `docs/third-party-exceptions.md`; section 11 keeps a pointer, and its closing
  line "Nothing else is excepted" becomes "Nothing else may ship; build-and-test-only tools are a separate class in
  the register".

Recorded by this epic under R1 (decision 4 and its advisor), confirmed when this spec is approved:

- Section 10, "Processes": the host service is the only network endpoint; the session agent owns everything that
  needs the interactive session.

Proposed, settled at the spec review (acceptance A9):

- New M2 epic "Local worker link" with **R176**: "The host service reaches the session agent and the terminal host
  only through the worker link, which has an in-process and a cross-process implementation on Linux; the
  cross-process one passes its contract suite with the worker killed, hung, restarted, running a version outside the
  supported range, and sending malformed data, and with the ring full."

## 9. Rules handed to later epics

Recorded in `docs/architecture.md` under the epic that must act:

- **Repository, build and NativeAOT:** pin the .NET SDK in `global.json`, because the framework compiles with
  warnings as errors at the latest analysis level and a newer SDK can break a pinned framework commit. The SDK on the
  development machine (10.0.302) restores `Microsoft.DotNet.ILCompiler` 10.0.10, which NuGet audit reports as
  GHSA-p3jp-9v83-76w9 (high); with warnings as errors the restore fails until the SDK is updated. clang is not
  installed; the linker step works with `-p:CppCompilerAndLinker=gcc`. Wire the simulation build property of
  section 4.
- **CI for pushed branches:** check out the framework at the pin into `external/darkraise-framework` with a read-only
  credential for the private repository, with LFS downloads skipped; build with `FrameworkPinStrict=true`; on the main
  branch and on pull requests into it, fail when the pin is not an ancestor of the framework's remote master; never
  run on `pull_request_target`.
- **Gates declared:** the exception-register gate is the gate command of section 7; `tests/build/run.sh` is part of
  the tests gate.
- **Device identity, pairing and encrypted sessions:** the build must also reject the pointer-arithmetic library
  calls that need no `unsafe` keyword inside `Doment.Protocol`, without adding an analyzer package or a build-only
  project reference to it.
- **Clipboard and file transfer protocol:** the path suite (R80) gains a case where a local user plants a link in the
  destination folder; the epic names the process that writes under the user's identity and decides the behaviour
  with no user signed in.
- **Host terminal service:** the Linux unit layout and service account, discovery by a restarted service, the
  version range and its out-of-range outcome, and the never-killed rule, all from section 2. Whatever is decided on
  R176, the service rejects malformed data from the terminal host and survives the terminal host killed, hung and
  restarted.
- **Host service and session agent (M7):** the same fault cases for the session agent, and the ring full.
- **Windows build and CI:** the first project that references `Darkraise.Win32UI` adds the platform rows its restore
  output shows (its generator targets `netstandard2.0`, so more .NET packages than the three of section 7 are
  expected). On Linux the gate command still checks Windows-bound projects: it restores them with
  `EnableWindowsTargeting=true` passed as a global property and does not compile them (that the restore then
  succeeds on Linux is inference, verified in that epic).
- **Windows terminal host (M7) and Installers and update (M11):** an update or a rollback replaces binaries without
  stopping a running terminal host; on Windows a running executable cannot be overwritten, so versions install side
  by side or the old file is renamed.

## 10. Testing

Everything this epic builds is build behaviour, so the tests are fixture trees under `tests/build/fixtures/` driven
by one script, `tests/build/run.sh`, which runs `dotnet build`, the gate command or `tools/framework.sh` on a fixture
and asserts the exit code and the message.

- `tests/build/fixtures/` has its own `Directory.Build.props` and `Directory.Build.targets`. They end MSBuild's
  upward search, import the real check from `build/`, and point it at the fixture's own register and repository
  root, so a test never depends on the real register and the repository's own gate run never meets a fixture.
- Fixtures need no network: the "unlisted package" fixtures use tiny packages packed by the script into a temporary
  folder feed, with a fixture NuGet configuration that clears every other source.
- Framework fixtures use a small stand-in framework repository created by the script (a commit, a pin, then a moved
  head, a modified file, an untracked source file, a changed root build file, an ignored `<project>.csproj.user`,
  a commit on no branch), so they never touch a real framework checkout. One of them builds two linked worktrees of
  a stand-in doment repository with different pins.
- One test builds a real project against the real framework worktree at the real pin with `FrameworkPinStrict=true`.

The documents (A1 to A9, A24) are accepted by reading them against this spec.

## Acceptance

A1. [demo, high] `docs/architecture.md` records the process model: host service, session agent, terminal host, client (command-line and desktop app), self-hosted server and the shared portable core, each with its executable, the account it runs as, the milestone it first appears in, and what it owns.
A2. [demo, high] It states that only the host service opens network sockets, holds the device key and authorises, that one authenticated connection per client carries every channel, and that the session agent and the terminal host are reached only through the worker link with the contract of section 3.
A3. [demo, high] It states that terminal sessions survive a restart, crash, update or rollback of the host service; that the terminal host runs outside the service's kill scope (Linux: its own systemd unit; Windows: no job shared with the service) and is never killed by the service; the version range the service accepts and what it does outside it; and that data from a worker at lower privilege is treated as untrusted input.
A4. [demo, high] It records the module map: every project of section 4 with what it holds, what it may reference, whether it is portable, Linux-bound or Windows-bound, and the milestone it is first built in, with the rules that worker code never references `Doment.Host` and that simulation never ships in a release binary.
A5. [demo, high] It names one interface for each of the ten platform seams (capture, video encode, video decode, presentation, audio capture, audio playback, input injection, virtual display, virtual gamepad, pseudo-terminal), each with the process that calls it, the epic that declares its signature and simulated implementation, and its first real implementation, followed by the six seam rules.
A6. [demo, high] It records the build order: portable projects built first on Linux, Windows-bound projects from M7 reached only through seams, and the Linux solution filter from M7.
A7. [demo, high] It records how doment consumes the framework: one worktree per doment checkout, the property and its overrides, the pin file, `tools/framework.sh`, how the pin moves and is rolled back, which framework projects may be referenced, the contribution rule and the three limits (feature-branch pins can become unbuildable; the framework repository is private; removing a doment worktree without `release` discards uncommitted framework work).
A8. [demo, high] The product spec carries the amendments of section 8: R1, R4, the section 5 third-party rule, the section 9 row, section 10 (processes, terminals, open decisions), R104 and section 11 with its closing line.
A9. [demo, medium] The product spec gains R176 and the epic "Local worker link" in M2 (sections 6, 7 and the M2 register), as section 8 words it. Q: Should the cross-process worker link (local socket plus shared-memory ring, with a simulated session agent) be built and fault-tested on Linux in M2, as new requirement R176 and a new M2 epic? Without it the socket half arrives in M4 with the terminal host and the shared-memory half first at M7.
A10. [test, medium] With no property set, a project that references `$(DarkraiseFrameworkPath)/src/Darkraise/Darkraise.csproj` builds from a doment checkout and from a linked doment worktree, each against its own `external/darkraise-framework`, and two such checkouts with different pins both build with `FrameworkPinStrict=true`. Q: Each doment checkout, including every task worktree, gets its own framework worktree inside it at `external/darkraise-framework`, instead of one shared `../darkraise-framework-doment` like the other apps. Is that the arrangement you want?
A11. [test, neg, high] When the framework directory does not exist, the build fails before compilation with one error that names the path it looked at and `tools/framework.sh sync`.
A12. [test, high] `tools/framework.sh sync` creates the framework worktree at the pinned commit when none exists and moves a clean one to the pin; after it, a build with `FrameworkPinStrict=true` succeeds.
A13. [test, neg, high] When the framework worktree's commit differs from the pin, or the worktree has a modified, staged or untracked file anywhere in it, or an ignored file outside `bin`, `obj`, `.vs` and `.idea`, an ordinary build succeeds with one warning DOMENT001 that names the pinned and the actual commit and the first offending path, and a build with `FrameworkPinStrict=true` fails with that message as an error.
A14. [test, neg, high] A relative path in `DarkraiseFrameworkPath` or `DARKRAISE_FRAMEWORK_PATH` fails the build with an error that asks for an absolute path.
A15. [test, high] A project whose resolved packages are all in the register builds, and the check reports no violation.
A16. [test, neg, high] A directly referenced package that is in no table fails the build with an error naming the project, the package and its version, and the register file.
A17. [test, neg, high] A package in no table that arrives transitively, through a package or through a referenced project, fails the build with an error naming it and the direct reference that brought it.
A18. [test, neg, high] A project that ships fails the build when it resolves a build-and-test-only package or references a build-only project; the same package in a project under `tests/` builds.
A19. [test, neg, high] A `ProjectReference` that resolves to a project under `$(DarkraiseFrameworkPath)` or outside the checkout fails the build unless it is an allowed framework project: the framework core from any project, Win32UI and its generator only from a project that targets `net10.0-windows`; a reference to any other framework project fails.
A20. [test, neg, high] A register with a missing table or column, a duplicate ID, or an empty reason, licence, interface, replacement or approval cell fails the check with an error naming the row and the column.
A21. [test, high] One gate command checks every project file tracked in the tree it is given, including one the solution does not list, reports every violation rather than the first, exits non-zero when there is any, and ends with a summary line of projects checked, packages seen and violations; run on the repository itself it skips `tests/build/fixtures/` and nothing else, and passes.
A22. [test, neg, high] The gate command fails on a tracked binary file of the listed extensions that no register row lists, naming the file.
A23. [test, neg, high] The gate command fails on a tracked project file that does not import the root build targets, and on a tool in `.config/dotnet-tools.json` that is not a build-and-test-only row.
A24. [demo, high] `docs/third-party-exceptions.md` holds the three tables of section 7: X1 and X2 with reason, licence, interface and replacement; xUnit v3, Microsoft Testing Platform and csharpier as build-and-test-only tools approved on 2026-11-24; and the three platform packages.
A25. [test, neg, medium] `tools/framework.sh sync` refuses to move a framework worktree that has changes and leaves a moved one on a detached HEAD without touching any branch; `tools/framework.sh pin` refuses to record a commit from a worktree that has changes, and records a commit that is not on the framework's remote with a warning; each says why. Q: May a doment feature branch pin a framework commit that exists only on this machine, with the push required only for CI and for doment's main branch?
A26. [test, neg, high] `tools/framework.sh release` refuses a framework worktree with an uncommitted change or a commit on no branch, and removes a clean one so that the framework repository no longer lists it.

## Riskiest assumption

That the seam and worker-link contracts recorded here, exercised on Linux only against simulated implementations
through M6, fit the real Windows capture, encode, decode and presentation pipeline at M7 without changes to the
portable projects. If that is wrong, M7 sends work back into M2 to M6; the product spec already names this as its
late-integration risk.

Evidence that the contracts have the right shape: Desktop Duplication returns a GPU texture per output with dirty
rectangles and the pointer separately (docs/dforge/research/2026-11-24-streaming-pipeline.md:14), and the research's
own seam sketch is a texture plus timestamp, dirty rectangles, cursor and HDR metadata (same file, line 379), which is
rule 1 of section 5. The host-topology advisor on 2026-11-24 found the local hop within the latency budget (tens of
microseconds against 16 ms) and named the in-process-only link as the place this assumption would fail, which is why
section 8 proposes R176.

What cannot be verified before M7: behaviour of the real encoders and decoders behind the interfaces. The two
assumptions the plan itself depends on are verified: the framework compiles under NativeAOT on Linux by source
reference (section 6 evidence), and the restore output lists every resolved package (section 7 evidence).

## Out of scope

The wire protocol and handshake (M2); the worker link's mechanism (M2 if R176 is approved, otherwise M4 and M7); seam
signatures (the epics of section 5); the solution, analyzers, formatting and `global.json` ("Repository, build and
NativeAOT"); CI ("CI for pushed branches"); `docs/dforge/gates.md` ("Gates declared").

## Review rulings

Fable spec review, round 1, 2026-11-24: 34 rulings, 3 undecided (asked with A9, A10 and A25), 1 High finding
answered by ruling 22. All rulings are applied above.

- 1. Decision 1 (build-only class) — stands.
- 2. Decision 2, mechanism (worktree, `ProjectReference`, pin file, warning in ordinary builds) — stands.
- 3. Decision 2, placement — not derivable from the owner's answer; A10 re-rated `medium` and asked.
- 4. Decision 3 (terminal host) — stands.
- 5. Decision 4 (network endpoint) — stands as the author's decision.
- 6. Section 8 — the two amendments that come from decision 4 moved out of "approved by the owner's answers".
- 7. Section 8 — R4's wording, the section 5 third-party rule and section 11's closing line added; A8 extended.
- 8. R1 — met once rulings 14 to 16 are applied.
- 9. R2 — met; stands.
- 10. R3 — met, subject to the answers to A10 and A25.
- 11. R4 — met once ruling 7 amends its wording.
- 12. Scope — only R176 (held as a proposal) and the no-signed-in-user sentence went beyond R1 to R4.
- 13. The critic's six High findings — all resolved by the revised text.
- 14. Windows terminal host — a mode of `doment-session.exe`; the M7 epic may split it.
- 15. "Started by the system" — reworded to "outside the service's kill scope", with the Windows launch stated.
- 16. `Doment.Server` — holds the server's own logic; the composition-root rule excepts it.
- 17. `Doment.Cli` — may reference Simulation in simulation builds.
- 18. Framework reference rule — covers projects under `$(DarkraiseFrameworkPath)`, not only outside the checkout.
- 19. Worker-link socket and pipe parsers — live in `Doment.Protocol`; the ring is the only pointer code in `Doment.Worker`.
- 20. Ring slots — carry a whole frame or one part of it, flagged first and last.
- 21. `tools/framework.sh sync` — detached HEAD, `git switch --detach`, never touches a branch, names where it looked.
- 22. Teardown guard — `tools/framework.sh release`, the known limit, and A26.
- 23. Strict cleanliness — ignored files count outside `bin`, `obj`, `.vs`, `.idea`; the message names the first path.
- 24. Table 3 — columns and a membership test.
- 25. Build-only closure — listed in the referencing epic's spec, which the owner approves.
- 26. No signed-in user — decided in the file-transfer epic and put to the owner there.
- 27. Fault cases — handed to M4 and M7 whatever the answer on R176.
- 28. Gate and Windows-bound projects on Linux — restore with `EnableWindowsTargeting`, no compile; handed to M7.
- 29. Analyzer-only packages — covered by the check; the `Doment.Protocol` check adds no package.
- 30. Update handoff — to "Windows terminal host" and "Installers and update".
- 31. Sequencing — framework commit, then the pin, then the doment commit that needs it.
- 32. A13 — re-rated `high`, question dropped: the owner's words already answer it.
- 33. A9 — question reworded: the socket half arrives in M4, the shared-memory half at M7.
- 34. Wording corrections — "network sockets", override precedence, table identifiers, the contents of
  `docs/architecture.md`, the limits named in A7.

## Critic findings

Architecture critic, 2026-11-24: 0 Blocker, 6 High, 11 Medium, 3 Nit. All six High findings were fixed in the spec.

- [High] One framework worktree shared by every doment worktree — fixed: one per checkout, inside it (section 6, A10).
- [High] The strict pin check missed untracked files and changes outside `src/` — fixed: the whole worktree must be
  clean (section 6, A13).
- [High] Version skew with long-lived terminal hosts — fixed: version exchange, a range in both directions, and a
  defined outcome outside it (sections 2 and 3, A3, R176).
- [High] No launch path for the Linux terminal host — fixed: started by systemd in its own unit, found through a
  per-user socket; the unit layout and the account are decided in M4 with a stated test (section 2).
- [High] The service parses data from a lower-privileged worker — fixed: such data is untrusted input, and shared
  memory is used only with the session agent (section 2, R176).
- [High] The gate checked the deliberately failing fixtures — fixed: one skipped directory with its own build files
  (sections 7 and 10, A21).
- [Medium] Heartbeat outcome undefined — fixed in section 2.
- [Medium] `runtime.<rid>` not expressible in the wildcard grammar — fixed: exact identifiers per runtime identifier.
- [Medium] Platform evidence covers only the framework core — handed to "Windows build and CI" (section 9).
- [Medium] Warnings could be promoted to errors — fixed: DOMENT001 and DOMENT002 are exempt.
- [Medium] Linked-worktree lookup unspecified — moot after the first fix.
- [Medium] "User data" rule named the SYSTEM session agent — fixed in section 2.
- [Medium] The shipping agent referenced `Doment.Simulation`, and a project not built until M4 — fixed in section 4.
- [Medium] `Doment.Host` bundled the endpoint with the worker side — fixed: `Doment.Worker`.
- [Medium] The initial pin was the unpushed local master — fixed: the remote's master.
- [Medium] Feature-branch pins can become unreachable — recorded as a known limit in section 6.
- [Medium] Scope of an approved build-only row — fixed in section 7.
- [Medium] Tracked-binary list omits fonts and assets — recorded under "What it cannot see".
- [Nit] The missing-directory message assumed a local clone with the commit — fixed: `tools/framework.sh sync`.
- [Nit] Checks ran once per project — fixed: once per build.
- [Nit] Amendment list missed two places in the product spec — fixed in section 8 and A8.
