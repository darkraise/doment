# Repository, build and NativeAOT — design

**Date:** 2026-11-24
**Epic:** M1 Foundations, "Repository, build and NativeAOT" (R5-R7 of docs/dforge/specs/2026-11-24-doment-design.md)
**Execution strategy:** sequential — inline execution
**Depth:** full — new-subsystem

## Decisions

Questions put to the owner on 2026-11-24, with the answers quoted.

1. **Process.** Owner: "Full dforge flow (Recommended)".
2. **Toolchain.** First asked with the apt upgrade to SDK 10.0.402 recommended; owner: "apt upgrade + clang
   (Recommended)". Checking the advisory afterwards showed that GHSA-p3jp-9v83-76w9 (CVE-2026-111497, the .NET Brotli
   decoder) affects `Microsoft.DotNet.ILCompiler`, `Microsoft.NETCore.App.Runtime.linux-x64` and
   `Microsoft.NETCore.App.Runtime.NativeAOT.linux-x64` from 10.0.0 up to but not including 10.0.14, so SDK 10.0.402
   (runtime 10.0.13) does not fix it, and Microsoft's Debian 13 apt feed offers nothing newer than 10.0.402. Asked
   again; owner: "/usr/local install (Recommended)": SDK 10.0.404 installed by Microsoft's dotnet-install script into
   `/usr/local/share/dotnet`, linked as `/usr/local/bin/dotnet`, which PATH finds before apt's `/usr/bin/dotnet`;
   apt's install stays untouched. clang comes from apt.
3. **Rows #6-#9 of the architecture-decisions register.** Owner: "Fold into this epic (Recommended)". Row #10 (push
   the framework branch `docs/doment-framework-worktree`) stays the owner's.
4. **How R5-R7 are enforced.** Offered: build checks plus one check command (recommended); configuration only (the
   do-less option, which misses R6's win-x64 compile and R7's "enforced by the build"); analyzer packages
   (CSharpier.MSBuild, BannedApiAnalyzers), which need new register rows and a change to DOMENT011. Owner: "Build
   checks + check.sh (Recommended)".
5. **Where the formatting check runs.** Owner: "Every build (Recommended)".
6. **Not asked, decided here:** all nine M1 projects of the module map are created (none is merged, because the walking
   skeleton uses each of them in M1); test package versions live in `tests/Directory.Build.props` as in the framework,
   without central package management; line endings are LF for every text file.

CI: none exists yet (the "CI for pushed branches" epic adds it), so no platform is uncovered.

## 1. What this epic delivers

- The pinned toolchain: SDK 10.0.404 on this machine and in `global.json`, and clang for the NativeAOT link step.
- `doment.slnx` with the nine M1 projects of `docs/architecture.md`'s module map and one test project, every reference
  as the map gives it.
- The framework's formatting and analyzer conventions, enforced in every build (R7).
- The portable-project rules, enforced in every build and by a linux-x64 plus win-x64 compile (R6).
- NativeAOT publish of `doment`, `doment-agent` and `doment-server` for linux-x64 with zero trim and AOT warnings
  (R5), and the simulation build property.
- `build/check.sh`, the one command that runs build, portable compile, NativeAOT publish and tests, for the CI and
  gates epics to call.
- Fixes for rows #6-#9 of `docs/dforge/registers/2026-11-24-architecture-decisions.md`.
- `docs/architecture.md` and `README.md` updated in the same change.

## 2. Toolchain

- **SDK.** 10.0.404 (runtime 10.0.15, released 2026-11-10), installed with `dotnet-install.sh --version 10.0.404
  --install-dir /usr/local/share/dotnet` and the link `/usr/local/bin/dotnet -> /usr/local/share/dotnet/dotnet`.
  Undo: remove the directory and the link. apt's `dotnet-sdk-10.0` 10.0.302 stays installed and unused.
- **`global.json`** at the repository root:
  `{"sdk": {"version": "10.0.404", "rollForward": "latestPatch"}, "test": {"runner": "Microsoft.Testing.Platform"}}`.
  `latestPatch` accepts later 10.0.4xx patches, which carry security fixes such as this one, and refuses another
  feature band, whose analyzers could break a pinned framework commit. A machine with only an older SDK stops at SDK
  resolution with the SDK's own message.
- **clang** from apt (Debian 13 offers 19). The build files set no `CppCompilerAndLinker`, so this machine and CI
  link the same way.
- `build/gate.sh`, `tools/framework.sh` and `tests/build/run.sh` keep calling `dotnet` from PATH, so they get 10.0.404
  without change. The comment in `gate.sh` naming SDK 10.0.302 for the console-logger workaround is checked against
  10.0.404 and kept or corrected.

## 3. Solution and projects

`doment.slnx` at the root lists every project below in a `/src/` and a `/tests/` folder. The fixtures under
`tests/build/fixtures/` are not in it.

| Project | Path | Output | `DomentPlatform` | References (direct) |
|---|---|---|---|---|
| `Doment.Protocol` | `src/Doment.Protocol` | library | `portable` | - |
| `Doment.Core` | `src/Doment.Core` | library | `portable` | Protocol, `Darkraise` |
| `Doment.Simulation` | `src/Doment.Simulation` | library | `portable` | Core |
| `Doment.Worker` | `src/Doment.Worker` | library | `portable` | Core |
| `Doment.Host` | `src/Doment.Host` | library | `portable` | Worker |
| `Doment.Client` | `src/Doment.Client` | library | `portable` | Core |
| `Doment.Server` | `src/Doment.Server` | `doment-server` | `portable` | Core |
| `Doment.Cli` | `src/Doment.Cli` | `doment` | `portable` | Client; Simulation in a simulation build |
| `Doment.Agent` | `src/Doment.Agent` | `doment-agent` | `linux` | Host; Simulation in a simulation build |
| `Doment.Core.Tests` | `tests/Doment.Core.Tests` | test executable | `portable` | Core |

- Every project targets `net10.0`. `Darkraise` is the framework's `src/Darkraise/Darkraise.csproj`, referenced through
  `$(DarkraiseFrameworkPath)` as `docs/architecture.md` requires.
- **`DomentPlatform`** is a new property, default `portable`, set to `linux` by a Linux-bound project and to `windows`
  by a Windows-bound one (from M7). It drives the portable rules of section 5 and the portable compile of section 7.
- **Executables** are composition roots with one shared behaviour for now: `--version` prints `<name> <version>` on
  stdout and exits 0, where `<name>` is the executable's name and `<version>` its informational version (`0.1.0`
  from `VersionPrefix` in the root `Directory.Build.props`, plus whatever suffix the SDK appends); `--help` prints a
  usage line and exits 0; no argument or any other argument prints the usage line on stderr and exits 2. The name and
  version come from one small type in `Doment.Core` (code shared by two or more roles lives there), which
  `Doment.Core.Tests` tests. The walking skeleton gives the executables their real commands.
- **Libraries** hold no code yet beyond that type. They exist so that their references, and the rules that hang on
  them, are in force from the first commit that adds code.
- **Test packages:** `tests/Directory.Build.props` imports the root one and sets the framework's versions,
  `XunitV3Version` 4.0.2 and `TestingPlatformVersion` 2.5.1. The test project references `xunit.v3` and
  `Microsoft.Testing.Extensions.TrxReport` (register rows B1 and B2), runs under Microsoft Testing Platform as an
  executable, and suppresses the framework's three test-only rules (CA1707, CA1861, xUnit1051).
- **Register.** Packages that the new projects' restore output adds are listed as the register says: a package the
  .NET SDK adds is a reviewed platform-packages row; any other package not covered by B1 or B2 stops the plan and goes
  to the owner.
- **Artifacts.** Publish output goes to `artifacts/` at the root, which `.gitignore` gains.

## 4. Formatting and analyzer conventions (R7)

**What the conventions are.**

- `.editorconfig` at the root is the framework's `.editorconfig` at the pinned commit with two documented changes:
  `end_of_line = lf` in both places it says `crlf` (the framework itself stores `.cs` and `.sh` files as LF through
  its `.gitattributes`, so its `crlf` setting does not describe its own files), and without the `DRUI020` line, which
  configures a `Darkraise.Win32UI.Generators` diagnostic that no doment project can raise before the desktop app (M8
  adds it back when it references that generator). Each change carries a comment saying why.
- `.csharpierrc` is the framework's (`printWidth` 130), and `.csharpierignore` lists `artifacts/` and
  `tests/build/fixtures/.run/`.
- The root `Directory.Build.props` sets, for every doment project, the framework's compiler settings:
  `Nullable=enable`, `ImplicitUsings=enable`, `LangVersion=latest`, `TreatWarningsAsErrors=true`,
  `AnalysisLevel=latest-recommended`, and CA1416 among `WarningsAsErrors`. It adds one setting the framework does not
  have, `EnforceCodeStyleInBuild=true`, because without it the style rules that the editorconfig marks as warnings
  (file-scoped namespaces, collection expressions) are shown only in an editor, and R7 asks for the build to enforce
  them.
- Libraries set `IsAotCompatible=true`, which turns on the trim, AOT and single-file analyzers at build time, so a
  warning shows in the build that introduces it rather than at the next publish.
- `AllowUnsafeBlocks` stays at its default (`false`) everywhere; a later epic turns it on in the project that needs it.

**How the build enforces formatting.**

- `.config/dotnet-tools.json` pins `csharpier` 1.2.6 (register row B3; the gate's DOMENT021 already accepts it).
- A target imported by the root `Directory.Build.targets` runs `dotnet csharpier check` on the project's own `.cs`
  compile items (not the files the SDK generates under `obj/`) before compilation. It fails with **DOMENT031**, naming
  each unformatted file, and passes CSharpier's output through.
- It records a stamp under `obj/`, so a project whose checked files have not changed since the last passing check is
  not checked again.
- It does not run in design-time builds (`DesignTimeBuild=true`), so editors stay responsive.
- When the tool is not restored it fails with **DOMENT032**: `CSharpier is not restored; run dotnet tool restore`.
- The property `DomentFormatCheck` (default `true`) turns it off. The build-test fixtures set it to `false` in their
  own `Directory.Build.props`, because their stand-in repositories have no tool manifest. `build/check.sh` passes
  `-p:DomentFormatCheck=true` as a global property, so no project can turn it off there. The gate needs nothing: it
  runs only restore and its own check target, never compilation.

## 5. Portable projects (R6)

A project with `DomentPlatform=portable` fails the build when it uses an operating-system-specific feature. Three
mechanisms share the work:

1. **CA1416** (platform compatibility, an error) rejects a call to an API that .NET marks as Windows-only, such as
   `Microsoft.Win32.Registry`, when the call is not guarded.
2. **DOMENT033**, a check after compilation that reads the project's output assembly with
   `System.Reflection.Metadata` (in the existing inline task source, `build/Doment.BuildChecks.cs`), fails on each of:
   a native import (a method with a P/Invoke entry, which covers both `DllImport` and `LibraryImport`), a reference to
   `System.Runtime.InteropServices.NativeLibrary`, and an assembly-level `SupportedOSPlatform` attribute (which would
   silence CA1416). It names the project and each finding. Evaluation also fails with DOMENT033 when the project's
   `TargetFramework` is not exactly `net10.0`.
3. **The win-x64 compile**: `build/check.sh portable` builds every portable project with `-r linux-x64` and with
   `-r win-x64` on Linux. This proves each one restores and compiles for both runtimes (runtime-specific package
   assets, conditions on `RuntimeIdentifier`); finding Windows-only API calls is the job of 1 and 2, because the
   compiler's API checks depend on the target framework, not on the runtime identifier.

**What this cannot see.** A Windows-only call guarded by `OperatingSystem.IsWindows()` passes CA1416, and an API
.NET does not annotate passes both checks; review catches them. The framework's own native calls are the framework's
responsibility: the check reads doment assemblies only.

## 6. NativeAOT publish (R5) and the simulation property

- `Doment.Cli`, `Doment.Agent` and `Doment.Server` set `PublishAot=true` and `TrimmerSingleWarn=false` (so a
  warning inside a referenced assembly is reported once per call site instead of one summary per assembly), with
  `AssemblyName` `doment`, `doment-agent` and `doment-server`.
- `build/check.sh aot` publishes each with `dotnet publish -c Release -r linux-x64 -p:FrameworkPinStrict=true
  -p:DomentFormatCheck=true -o artifacts/publish/<name>/linux-x64`. A step fails on a non-zero exit, and also on any
  `warning` line in the publish output, so a trim or AOT warning fails it whether or not the SDK already turned it
  into an error. Then it runs each binary with `--version` and fails unless it exits 0 and prints `<name> 0.1.0`
  at the start of its output.
- **Simulation property.** `DomentSimulation` (default `false`). When `true`, `Doment.Cli` and `Doment.Agent` gain the
  `ProjectReference` to `Doment.Simulation` and the compile constant `DOMENT_SIMULATION`; when `false`, neither
  references it. A publish with `Configuration=Release` and `DomentSimulation=true` fails with **DOMENT030**: `a
  release publish cannot include Doment.Simulation; build simulation binaries in Debug`. Test, bench and harness
  builds set the property; they are not release publishes.

## 7. `build/check.sh`

```
build/check.sh [<step>...]      steps: build, portable, aot, test; default: all four in this order
```

- Works on the repository that holds the script. Each `dotnet` call has a timeout (600 s; 1200 s for one publish),
  uses the gate's console-logger flags, and runs with node reuse, the MSBuild server and the shared compiler off, so
  the command leaves no build process behind.
- **build:** `dotnet build doment.slnx -c Release -p:FrameworkPinStrict=true -p:DomentFormatCheck=true`.
- **portable:** the linux-x64 and win-x64 builds of section 5 (`-c Release`, with the same two global properties as
  build), for every project of `doment.slnx` whose
  `DomentPlatform` is `portable` (read with `-getProperty`, as the gate reads its properties).
- **aot:** section 6.
- **test:** `dotnet test --solution doment.slnx -c Release`.
- Prints `check: <step> ok` or `check: <step> failed` with the failing call's error lines, and stops at the first
  failed step. Last line: `check: <n> steps run, <f> failed`. Exits 0 when every step passed, 1 on a failure, 2 on
  an unknown step.
- The gate is not one of its steps; the "Gates declared" epic lists both commands.

## 8. Rows carried from the architecture decisions

- **#6, line endings.** `.gitattributes` becomes `* text=auto eol=lf`, with `-text` for the binary types the gate
  knows (`*.dll`, `*.exe`, `*.so`, `*.dylib`, `*.a`, `*.lib`, `*.sys`, `*.nupkg`, `*.snupkg`) and for `*.png`,
  `*.jpg`, `*.ico`. Every tracked text file is LF in the index, and Git for Windows with `core.autocrlf=true` checks
  the scripts out as LF, so they run under Git Bash. The existing `build/darkraise-framework.pin text eol=lf` line is
  covered by the new rule and removed.
- **#7, gate lines that duplicate the build's.** The master-branch section of `gate.sh` stops emitting its own
  DOMENT006 and DOMENT003 lines. When the pin is malformed or the framework directory is missing it skips the ancestry
  check silently, because the framework check, which runs on every gate, reports both. Each of those lines in the
  gate's output then comes from the build alone.
- **#8, XML escaping.** `gate.sh` writes the temporary framework-check project with the tree path escaped for XML
  (`&`, `<`, `>`, `"`, `'`) and for MSBuild (`%`, `$`, `@`, `;`), so a path holding those characters works.
- **#9, untested gate paths.** Tests for: the ancestry check's skip when the framework path is a plain directory
  inside another git repository (no DOMENT005, no fetch against the enclosing repository, and the framework check's
  DOMENT002); and the `die` paths when `git ls-files` fails after the tree was found (exit 1 and `gate: git ls-files
  failed in <tree>`).

Each gets a register row update: assigned to this spec, then done with its acceptance numbers.

## 9. Documentation

- `docs/architecture.md`: a "Repository and build" section (toolchain, solution, `DomentPlatform`,
  `DomentSimulation`, `DomentFormatCheck`, `build/check.sh`, DOMENT030 to DOMENT033); the gate section's fixes; and
  "Rules handed to later epics" with this epic's subsection replaced by what it hands on:
  - **CI for pushed branches:** install the SDK from `global.json` (`actions/setup-dotnet` with `global-json-file`),
    have clang on the runner, run `dotnet tool restore`, then `build/check.sh` and `build/gate.sh`.
  - **Gates declared:** the build, tests and NativeAOT gates are `build/check.sh build`, `test` and `aot` (with
    `portable` part of build); `tests/build/run.sh` stays part of the tests gate.
  - **Windows build and CI:** a Windows-bound project sets `DomentPlatform=windows`.
  - **Desktop app (M8):** restore the `DRUI020` editorconfig line when a project references
    `Darkraise.Win32UI.Generators`.
- `README.md`: prerequisites (SDK 10.0.404 or a later 10.0.4xx, clang, git, `tools/framework.sh sync`,
  `dotnet tool restore`) and the two commands.

## 10. Testing

- **Build-test cases** in `tests/build/` (the same shell harness, stand-in repositories and generated fixture trees,
  no network), one per behaviour of sections 4 to 6 and 8: each DOMENT code fires on a fixture that breaks its rule
  and stays silent on one that keeps it; the format check's stamp and design-time skip; the simulation reference and
  DOMENT030; gate rows #7 to #9.
- **Repository acceptance**, `tests/build/repository-build.acceptance.sh`, one function per acceptance statement
  that a script can check, on the real checkout: the solution builds clean, the module references equal the table in
  section 3, `build/check.sh` passes, the published binaries answer `--version`, the editorconfig matches the
  framework's apart from the documented changes, and every tracked text file is LF.
- **Unit tests** in `Doment.Core.Tests` for the name-and-version type.
- The existing `tests/build/run.sh` and `tests/build/architecture-decisions.acceptance.sh` keep passing. The new
  root settings (warnings as errors, code style in build, the portable checks) reach their generated fixture projects
  too, so the plan brings any generated fixture source that breaks a rule into line with it; it does not exempt
  fixtures from the analyzer rules, only from the format check.

## Acceptance

A1. [test, high] On this machine, `dotnet --version` run inside the checkout prints 10.0.404 or a later 10.0.4xx version, and `global.json` pins `10.0.404` with `rollForward` `latestPatch` and the Microsoft Testing Platform runner.
A2. [test, high] `dotnet build doment.slnx -c Release -p:FrameworkPinStrict=true` builds the ten projects of section 3 with zero warnings and zero errors.
A3. [test, high] With `DomentSimulation` unset, each project's direct project references equal its row in section 3, and no project other than the simulation library itself has `Doment.Simulation` among its direct or transitive references.
A4. [test, high] `build/check.sh aot` publishes `doment`, `doment-agent` and `doment-server` with NativeAOT for linux-x64, their publish output holds no warning line, and each binary run with `--version` exits 0 and prints its name followed by `0.1.0`.
A5. [test, neg, high] The `Microsoft.DotNet.ILCompiler` and `runtime.linux-x64.Microsoft.DotNet.ILCompiler` packages and the linux-x64 runtime packs that the three publishes use (as their `project.assets.json` files record them) are all 10.0.14 or later, and NuGet audit reports no vulnerability for any doment project.
A6. [test, neg, high] A fixture executable with `PublishAot=true` that calls trim- or AOT-unsafe code fails `build/check.sh aot`'s publish step (or its build), and the output names the IL warning code.
A7. [test, high] `build/check.sh portable` builds each of `Doment.Protocol`, `Core`, `Simulation`, `Worker`, `Host`, `Client`, `Server`, `Cli` and `Core.Tests` for linux-x64 and for win-x64 on Linux, and does not build `Doment.Agent`.
A8. [test, neg, high] A portable fixture project that calls `Microsoft.Win32.Registry.CurrentUser` without a guard fails its build with CA1416.
A9. [test, neg, high] A portable fixture project fails its build with DOMENT033, naming the project and the finding, when it declares a `DllImport`, declares a `LibraryImport`, references `NativeLibrary`, carries an assembly-level `SupportedOSPlatform` attribute, or targets anything but `net10.0`; the same code in a project with `DomentPlatform=linux` builds.
A10. [test, high] The root `.editorconfig` equals the framework's at the pinned commit apart from the two documented changes (`end_of_line = lf`, no `DRUI020` line), and `.csharpierrc` equals the framework's.
A11. [test, neg, high] A fixture project with a block-scoped namespace, or with code that a `latest-recommended` CA rule flags, fails its build.
A12. [test, neg, high] A fixture project with an unformatted `.cs` file fails `dotnet build` with DOMENT031 naming the file; after `dotnet csharpier format` it builds; a second build with no source change does not run CSharpier again; a design-time build does not run it.
A13. [test, neg, high] With the CSharpier tool not restored, a build fails with DOMENT032 and the text `run dotnet tool restore`.
A14. [test, medium] A project that sets `DomentFormatCheck=false` skips the format check in a plain `dotnet build`, and `build/check.sh` still checks it. Q: may a project turn the format check off for plain builds at all, given that `check.sh` and CI force it on? (The build-test fixtures need the switch; the alternative is a fixture-only mechanism a project cannot use.)
A15. [test, high] Building `Doment.Cli` or `Doment.Agent` with `-p:DomentSimulation=true` adds `Doment.Simulation` to its references and defines `DOMENT_SIMULATION`; without the property neither does.
A16. [test, neg, high] `dotnet publish -c Release -p:DomentSimulation=true` of `Doment.Cli` or `Doment.Agent` fails with DOMENT030; the same build in Debug succeeds.
A17. [test, high] `build/check.sh test` runs the solution's tests under Microsoft Testing Platform with xUnit v3 and passes, including the tests of the name-and-version type.
A18. [test, high] `build/check.sh` with no argument runs build, portable, aot and test in that order, prints one `check: <step> ok` line per step and `check: 4 steps run, 0 failed`, and exits 0; with a step made to fail it stops there and exits 1; with an unknown step it exits 2.
A19. [test, neg, high] After `build/check.sh` returns, no MSBuild node, MSBuild server or compiler server process that it started is still running.
A20. [test, high] `build/gate.sh` on the repository reports 0 violations with the new projects, and every platform-packages row added by this epic names a package the .NET SDK adds.
A21. [test, high] Every tracked text file is LF in the index, and `git check-attr eol` reports `lf` for `*.sh`, `*.cs`, `*.csproj`, `*.md` and the pin file, and `-text` for the listed binary types (row #6).
A22. [test, neg, high] On `master`, with a malformed pin the gate prints DOMENT006 exactly once, with the framework directory missing it prints DOMENT003 exactly once, and `build/gate.sh` contains no DOMENT006 or DOMENT003 text of its own (row #7).
A23. [test, high] The gate run on a tree whose path contains `&`, `<`, `'`, `%`, `$`, `;` and a space checks the framework with no XML or MSBuild error (row #8).
A24. [test, neg, high] On `master`, with the framework path a plain directory inside another git repository, the gate reports DOMENT002 and no DOMENT005 and fetches nothing; with a corrupt index the gate exits 1 with `gate: git ls-files failed in <tree>` (row #9).
A25. [test, high] `tests/build/run.sh` and `tests/build/architecture-decisions.acceptance.sh` pass after the change.
A26. [demo, high] `docs/architecture.md` records the toolchain, the solution, the three properties, `build/check.sh`, DOMENT030 to DOMENT033, the gate fixes and the rules handed to later epics of section 9, and `README.md` gives the prerequisites and the two commands.

## Riskiest assumption

That the pinned framework commit `e3cb121d83147eef363559d6f6bd4becda4b9e89` compiles under SDK 10.0.404. The
framework builds with warnings as errors at `AnalysisLevel=latest-recommended`, so a rule that the 10.0.4xx band
added or tightened would stop every doment build. Evidence so far: the architecture-decisions plan's
`real_framework_strict` case built it under SDK 10.0.302 on 2026-11-24. Under 10.0.404:
unverified — the plan's first task verifies it, right after installing the SDK. If it fails, the fix is a framework
change on a framework branch, moved into doment through `tools/framework.sh pin`, and the owner pushes it before this
epic's branch can merge (the pin must be on the framework's remote master).

## Out of scope

- CI workflows (the "CI for pushed branches" epic) and `docs/dforge/gates.md` (the "Gates declared" epic).
- Real behaviour in any executable or library (the walking skeleton and later epics).
- Windows-bound projects and the Linux solution filter (M7).
- linux-arm64 publish of the agent (R45, M4).
- Row #10, pushing the framework branch, which is the owner's action.
