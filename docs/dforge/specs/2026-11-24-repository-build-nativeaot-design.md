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
7. **Decided on the architecture critic's findings** (see `## Critic findings`): style severities in the
   `dotnet_diagnostic` form; `DomentFormatCheck` and `DomentPlatform` honoured only as global properties; NuGet audit
   warnings fatal only in `build/check.sh`; nuget.org-dependent cases in the acceptance script; tree paths holding
   `%`, `$`, `@` or `;` refused by the gate.

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
- **`DomentPlatform`** is a new property that drives the portable rules of section 5 and the portable compile of
  section 7. A project cannot choose it: the root `Directory.Build.targets` sets it after the project body, from one
  list that mirrors the module map's Kind column (`linux` for `Doment.Agent` and `Doment.Platform.Linux`, `windows`
  for `Doment.Platform.Windows`, `Doment.Service`, `Doment.Session` and `Doment.App`, `portable` for every other
  project), as `DomentBuildOnly` is already reset after the project body. Only a global property overrides it, which
  the build-test harness uses for its `-windows` fixtures. The repository acceptance also checks each project's value
  against the module map.
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

- `.editorconfig` at the root is the framework's `.editorconfig` at the pinned commit with three documented changes,
  each with a comment saying why:
  1. `end_of_line = lf` in both places it says `crlf` (the framework itself stores `.cs` and `.sh` files as LF
     through its `.gitattributes`, so its `crlf` setting does not describe its own files);
  2. without the `DRUI020` line, which configures a `Darkraise.Win32UI.Generators` diagnostic that no doment project
     can raise before the desktop app (M8 adds it back when it references that generator);
  3. `dotnet_diagnostic.<id>.severity = warning` lines for the two rules the framework marks `:warning`
     (`csharp_style_namespace_declarations = file_scoped:warning` is IDE0161; `dotnet_style_prefer_collection_expression
     = true:warning` is IDE0028 and IDE0300 to IDE0305). Microsoft documents that a command-line build ignores the
     `option = value:severity` suffix and honours only the `dotnet_diagnostic` form, so without these lines the two
     rules the framework enforces in its editor would not be enforced by the build. The plan's first task builds a
     fixture with a block-scoped namespace to confirm the build then fails.
- `.csharpierrc` is the framework's (`printWidth` 130), and `.csharpierignore` lists `artifacts/` and
  `tests/build/fixtures/.run/`.
- The root `Directory.Build.props` sets, for every doment project, the framework's compiler settings:
  `Nullable=enable`, `ImplicitUsings=enable`, `LangVersion=latest`, `TreatWarningsAsErrors=true`,
  `AnalysisLevel=latest-recommended`, and CA1416 among `WarningsAsErrors`. It adds one setting the framework does not
  have, `EnforceCodeStyleInBuild=true`, without which no IDE rule runs in a command-line build at all.
- **NuGet audit.** In a plain build, the audit warnings NU1901 to NU1904 stay warnings (`WarningsNotAsErrors`), so a
  newly published advisory does not stop local work or the build of an older commit during a rollback.
  `build/check.sh` passes `-p:DomentAuditStrict=true`, which makes them errors, so CI and the gates fail on any known
  vulnerable package. Whether NuGet honours `WarningsNotAsErrors` for these codes under SDK 10.0.404 is checked in the
  plan's first task; if it does not, the plain build sets `NuGetAuditLevel` per the same switch instead.
- Each library's own `.csproj` sets `IsAotCompatible=true` (not the shared build files, which also reach the
  build-test fixtures), turning on the trim, AOT and single-file analyzers at build time, so a warning shows in the
  build that introduces it rather than at the next publish.
- `AllowUnsafeBlocks` stays at its default (`false`) everywhere; a later epic turns it on in the project that needs it.

**How the build enforces formatting.**

- `.config/dotnet-tools.json` pins `csharpier` 1.2.6 (register row B3; the gate's DOMENT021 already accepts it).
- A target imported by the root `Directory.Build.targets` runs `dotnet csharpier check` on the project's own `.cs`
  compile items (not the files the SDK generates under `obj/`) before compilation. It fails with **DOMENT031**, naming
  each unformatted file, and passes CSharpier's output through.
- It records a stamp under `obj/`, so a project is not checked again while none of its inputs has changed. The inputs
  are its checked files, `.csharpierrc`, `.csharpierignore`, `.editorconfig` and `.config/dotnet-tools.json`, so a new
  print width or a CSharpier upgrade checks every project again.
- It does not run in design-time builds (`DesignTimeBuild=true`), so editors stay responsive.
- When the tool is not restored it fails with **DOMENT032**: `CSharpier is not restored; run dotnet tool restore`.
- The property `DomentFormatCheck` turns it off only as a global property (`-p:DomentFormatCheck=false`): the root
  `Directory.Build.targets` sets it to `true` after the project body, which a global property overrides and a
  project's own value does not. The build-test harness passes `false` from its `dn` helper, because its stand-in
  repositories and fixture trees have no tool manifest, and drops it only in the format-check cases. The gate needs
  nothing: it runs only restore and its own check target, never compilation.

## 5. Portable projects (R6)

A project with `DomentPlatform=portable` fails the build when it uses an operating-system-specific feature. Three
mechanisms share the work:

1. **CA1416** (platform compatibility, an error) rejects a call to an API that .NET marks as Windows-only, such as
   `Microsoft.Win32.Registry`, when the call is not guarded.
2. **DOMENT033**, a check after compilation that reads the project's output assembly, fails on each of: a native
   import (a method with a P/Invoke entry, which covers both `DllImport` and `LibraryImport`), a reference to
   `System.Runtime.InteropServices.NativeLibrary`, and an assembly-level `SupportedOSPlatform` attribute (which would
   silence CA1416). It names the project and each finding. The reader is its own inline task, in its own source file
   (`build/Doment.PortableCheck.cs`) under its own `UsingTask` with an explicit reference to
   `System.Reflection.Metadata`, so the existing tasks, which compile against the factory's reduced netstandard 2.0
   set (`build/Doment.BuildChecks.cs:2-3`), are untouched. The plan's first task proves that this reference loads under
   SDK 10.0.404; if it does not, the fallback is a minimal reader of the PE metadata tables in netstandard 2.0 code,
   as the existing JSON reader is.
   A second DOMENT033 target, before restore (`BeforeTargets="_GenerateRestoreGraphProjectEntry;CollectPackageReferences"`,
   as `DomentReferenceCheck` hooks), fails a portable project whose `TargetFramework` is not exactly `net10.0`. Both
   targets run only when `'$(DomentPlatform)' == 'portable' and '$(UsingMicrosoftNETSdk)' == 'true'`, so the gate's
   generated framework-check project, which imports the root build files but is no SDK project, is not affected.
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
  -p:DomentFormatCheck=true -p:DomentAuditStrict=true -o artifacts/publish/<name>/linux-x64`. A step fails on a
  non-zero exit, and also on any MSBuild diagnostic of the form `: warning <CODE>:` (`: warning [A-Z]+[0-9]+:`) in the
  publish output, so a trim or AOT warning fails it whether or not the SDK already turned it into an error. Then it
  runs each binary with `--version` and fails unless it exits 0 and its first line matches
  `^<name> 0\.1\.0([+-]|$)`.
- **Simulation property.** `DomentSimulation` (default `false`). When `true`, `Doment.Cli` and `Doment.Agent` gain the
  `ProjectReference` to `Doment.Simulation` and the compile constant `DOMENT_SIMULATION`; when `false`, neither
  references it. A publish in any configuration but `Debug` with `DomentSimulation=true` fails with **DOMENT030**:
  `a release publish cannot include Doment.Simulation; build simulation binaries in Debug`. The check is a target
  hooked `BeforeTargets="PrepareForPublish"`, so it fires for `dotnet publish` and for `msbuild -t:Publish` alike.
  Test, bench and harness builds that set the property build or publish in Debug.

## 7. `build/check.sh`

```
build/check.sh [<step>...]      steps: build, portable, aot, test; default: all four in this order
```

- Works on the repository that holds the script. Each `dotnet` call uses the gate's console-logger flags and runs
  with node reuse, the MSBuild server and the shared compiler off. It runs in a process group of its own (`setsid`)
  under a timeout (600 s; 1200 s for one publish; `DOMENT_CHECK_TIMEOUT` overrides both, in seconds), and on expiry
  the whole group is killed, so a hung MSBuild node, ILC or test host does not outlive the run.
- Every step passes the same global properties: `-c Release -p:FrameworkPinStrict=true -p:DomentFormatCheck=true
  -p:DomentAuditStrict=true`.
- **build:** `dotnet build doment.slnx` with those properties.
- **portable:** the linux-x64 and win-x64 builds of section 5, for every project of `doment.slnx` whose
  `DomentPlatform` is `portable` (read with `-getProperty`, as the gate reads its properties).
- **aot:** section 6.
- **test:** `dotnet test --solution doment.slnx` with those properties.
- Prints `check: <step> ok`, or `check: <step> failed` followed by the cause, and stops at the first failed step. The
  cause is: the call's deduplicated `error` lines for a failed call; the matched warning lines for a publish that
  exited 0 with warnings; the binary's exit code and first output line beside the expected `<name> 0.1.0` for a
  `--version` mismatch; `timed out after <s> s: <command>` for a timeout. Last line: `check: <n> steps run, <f> failed`. Exits 0 when every step passed, 1 on a failure, 2 on
  an unknown step.
- The gate is not one of its steps; the "Gates declared" epic lists both commands.

## 8. Rows carried from the architecture decisions

- **#6, line endings.** `.gitattributes` becomes `* text=auto eol=lf`, with `-text` for the binary types the gate
  knows (`*.dll`, `*.exe`, `*.so`, `*.dylib`, `*.a`, `*.lib`, `*.sys`, `*.nupkg`, `*.snupkg`) and for `*.png`,
  `*.jpg`, `*.ico`. Every tracked text file is LF in the index, and Git for Windows with `core.autocrlf=true` checks
  the scripts out as LF, so they run under Git Bash. The existing `build/darkraise-framework.pin text eol=lf` line is
  covered by the new rule and removed. The same commit runs `git add --renormalize .`. A later file that needs CRLF
  (a Windows `.cmd`, say) gets its own attribute line.
- **#7, gate lines that duplicate the build's.** The master-branch section of `gate.sh` stops emitting its own
  DOMENT006 and DOMENT003 lines. When the pin is malformed or the framework directory is missing it skips the ancestry
  check silently, because the framework check, which runs on every gate, reports both. Each of those lines in the
  gate's output then comes from the build alone.
- **#8, XML escaping.** `gate.sh` writes the temporary framework-check project with the tree path escaped for XML
  (`&`, `<`, `>`, `"`, `'`), so a tree path holding those characters, or a space, works in every gate call (the `-p:`
  values pass them unchanged). MSBuild gives `%`, `$`, `@` and `;` a meaning of their own in property values and
  imports throughout the build, not only in the gate, so a tree path holding any of them is refused up front: the
  gate exits 2 with `gate: <tree> contains '<char>', which MSBuild cannot take in a path`.
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
  no network, packages only from its private feed), one per behaviour of sections 4 to 6 and 8 that needs no package
  from nuget.org: each DOMENT code fires on a fixture that breaks its rule and stays silent on one that keeps it; the
  format check's stamp, inputs and design-time skip (the format cases drop the harness's global
  `DomentFormatCheck=false` and copy the real tool manifest; CSharpier itself comes from the user's tool cache);
  the simulation reference and DOMENT030; gate rows #7 to #9.
- **Cases that need nuget.org packages** (A6's NativeAOT fixture, which needs the ILCompiler packages, and anything
  built with `-r win-x64`, which needs the win-x64 apphost pack) run in the repository acceptance script instead, on
  temporary projects under `artifacts/` that import the real root build files and restore from the user's normal
  sources and package folder.
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
A10. [test, high] The root `.editorconfig` equals the framework's at the pinned commit apart from the three documented changes (`end_of_line = lf`, no `DRUI020` line, the `dotnet_diagnostic` lines for IDE0161, IDE0028 and IDE0300 to IDE0305), and `.csharpierrc` equals the framework's.
A11. [test, neg, high] A fixture project fails its command-line build when it has a block-scoped namespace, when it initialises a collection without a collection expression where IDE0300 applies, or when it has code that a `latest-recommended` CA rule flags.
A12. [test, neg, high] A fixture project with an unformatted `.cs` file fails `dotnet build` with DOMENT031 naming the file; after `dotnet csharpier format` it builds; a second build with no source change does not run CSharpier again; after `.csharpierrc` changes, the next build runs it again; a design-time build does not run it.
A13. [test, neg, high] With the CSharpier tool not restored, a build fails with DOMENT032 and the text `run dotnet tool restore`.
A14. [test, neg, high] A project that sets `DomentFormatCheck=false` or `DomentPlatform=linux` in its own file still gets the format check and the portable checks; only `-p:DomentFormatCheck=false` on the command line skips the format check.
A15. [test, high] Building `Doment.Cli` or `Doment.Agent` with `-p:DomentSimulation=true` adds `Doment.Simulation` to its references and defines `DOMENT_SIMULATION`; without the property neither does.
A16. [test, neg, high] `dotnet publish -c Release -p:DomentSimulation=true` of `Doment.Cli` or `Doment.Agent` fails with DOMENT030; the same build in Debug succeeds.
A17. [test, high] `build/check.sh test` runs the solution's tests under Microsoft Testing Platform with xUnit v3 and passes, including the tests of the name-and-version type.
A18. [test, high] `build/check.sh` with no argument runs build, portable, aot and test in that order, prints one `check: <step> ok` line per step and `check: 4 steps run, 0 failed`, and exits 0; with a step made to fail it stops there and exits 1; with an unknown step it exits 2.
A19. [test, neg, high] After `build/check.sh` returns, no MSBuild node, MSBuild server, compiler server, ILC or test host process that it started is still running, both after a normal run and after a run of the build step with `DOMENT_CHECK_TIMEOUT=1`, which prints `timed out after 1 s` and exits 1.
A20. [test, high] `build/gate.sh` on the repository reports 0 violations with the new projects, and every platform-packages row added by this epic names a package the .NET SDK adds.
A21. [test, high] Every tracked text file is LF in the index, and `git check-attr eol` reports `lf` for `*.sh`, `*.cs`, `*.csproj`, `*.md` and the pin file, and `-text` for the listed binary types (row #6).
A22. [test, neg, high] On `master`, with a malformed pin the gate prints DOMENT006 exactly once, with the framework directory missing it prints DOMENT003 exactly once, and `build/gate.sh` contains no DOMENT006 or DOMENT003 text of its own (row #7).
A23. [test, neg, high] The gate run on a tree holding one project, at a path containing `&`, `<`, `'` and a space, reports 0 violations; on a tree whose path contains `;`, `%`, `$` or `@` it exits 2 naming the character (row #8).
A24. [test, neg, high] On `master`, with the framework path a plain directory inside another git repository, the gate reports DOMENT002 and no DOMENT005 and fetches nothing; with a corrupt index the gate exits 1 with `gate: git ls-files failed in <tree>` (row #9).
A25. [test, high] `tests/build/run.sh` and `tests/build/architecture-decisions.acceptance.sh` pass after the change.
A26. [demo, high] `docs/architecture.md` records the toolchain, the solution, the three properties, `build/check.sh`, DOMENT030 to DOMENT033, the gate fixes and the rules handed to later epics of section 9, and `README.md` gives the prerequisites and the two commands.
A27. [test, neg, high] With a package that has a known advisory in a project's restore output, a plain `dotnet build` succeeds with an NU190x warning, and `build/check.sh build` fails naming the advisory.
A28. [test, high] Each project's `DomentPlatform`, read with `-getProperty`, equals its Kind in the module map of `docs/architecture.md`, and `Doment.Agent` is the only `linux` project.

## Riskiest assumption

That the pinned framework commit `e3cb121d83147eef363559d6f6bd4becda4b9e89` compiles under SDK 10.0.404. The
framework builds with warnings as errors at `AnalysisLevel=latest-recommended`, so a rule that the 10.0.4xx band
added or tightened would stop every doment build. Evidence so far: the architecture-decisions plan's
`real_framework_strict` case built it under SDK 10.0.302 on 2026-11-24. Under 10.0.404:
unverified — the plan's first task verifies it, right after installing the SDK. If it fails, the fix is a framework
change on a framework branch, moved into doment through `tools/framework.sh pin`, and the owner pushes it before this
epic's branch can merge (the pin must be on the framework's remote master).

Three smaller assumptions the same first task checks before anything is built on them, each with its fallback in the
section named: that a command-line build fails on IDE0161 once the `dotnet_diagnostic` line is set (section 4); that
an inline task can reference `System.Reflection.Metadata` under SDK 10.0.404 (section 5); and that NuGet honours
`WarningsNotAsErrors` for NU1901 to NU1904 (section 4).

## Out of scope

- CI workflows (the "CI for pushed branches" epic) and `docs/dforge/gates.md` (the "Gates declared" epic).
- Real behaviour in any executable or library (the walking skeleton and later epics).
- Windows-bound projects and the Linux solution filter (M7).
- linux-arm64 publish of the agent (R45, M4).
- Row #10, pushing the framework branch, which is the owner's action.

## Critic findings

Architecture critic, 2026-11-24: 1 Blocker, 3 High, 7 Medium, 5 Nit; every one fixed in the spec.

- [Blocker] `EnforceCodeStyleInBuild` does not apply the framework's `option = value:warning` severities — fixed:
  third editorconfig change with `dotnet_diagnostic` lines (section 4, A10, A11), confirmed in the first task.
- [High] The `DomentFormatCheck=false` opt-out missed the harness's stand-in repositories — fixed: global-only
  property, passed by the harness's `dn` helper (section 4, A14).
- [High] The offline harness cannot restore NativeAOT or win-x64 packages, and central `IsAotCompatible` would break
  existing fixtures — fixed: `IsAotCompatible` per library `.csproj`; those cases move to the acceptance script
  (sections 4 and 10).
- [High] `System.Reflection.Metadata` in the shared inline source could break every existing task — fixed: own source
  and `UsingTask`, proven in the first task, with a fallback (section 5, Riskiest assumption).
- [Medium] The target-framework half of DOMENT033 had no hook — fixed: named target and condition (section 5).
- [Medium] A project could declare itself non-portable — fixed: `DomentPlatform` derived centrally (section 3, A28).
- [Medium] The format stamp ignored the formatter's configuration — fixed: config files and the tool manifest are
  inputs (section 4, A12).
- [Medium] A timed-out call left child processes — fixed: `setsid`, group kill, timeout case in A19 (section 7).
- [Medium] Some `check.sh` failures printed no cause — fixed: the cause of each failure kind (section 7).
- [Medium] Row #8 escaped only one of the gate's path-bearing calls — fixed: XML escaping for the generated project,
  refusal of MSBuild-special characters (section 8, A23).
- [Medium] A14 left a design question open — fixed: decided (A14).
- [Medium] Warnings as errors made every new advisory break every build — fixed: fatal only in `check.sh` (section 4,
  A27).
- [Nit] The warning match was too broad — fixed: MSBuild diagnostic form (section 6).
- [Nit] The `--version` prefix match was loose — fixed: anchored pattern (section 6).
- [Nit] The DOMENT030 hook and condition were unspecified — fixed: `BeforeTargets="PrepareForPublish"`, any
  configuration but Debug (section 6).
- [Nit] The test step dropped the global properties — fixed: every step passes them (section 7).
- [Nit] The line-ending migration was unstated — fixed: `git add --renormalize .` (section 8).
