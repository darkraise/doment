# Build probes — 2026-11-24

Probes P1 to P8 of the repository, build and NativeAOT plan (Task 1), run on 2026-11-24 under SDK 10.0.404
(runtime 10.0.15) at `/usr/local/share/dotnet`, linked as `/usr/local/bin/dotnet`, with clang 19.1.7 from apt. Unless a
probe says otherwise, each used a throwaway project under the session scratchpad with empty `Directory.Build.props`
and `Directory.Build.targets`, the repository's `global.json`, and `MSBUILDDISABLENODEREUSE=1`,
`DOTNET_CLI_USE_MSBUILD_SERVER=0` and `UseSharedCompilation=false`. The projects were deleted afterwards.

## P1 — the pinned framework under SDK 10.0.404

- **Command:** `bash tests/build/run.sh '^real_framework_strict$'`
- **Result:** first run failed at restore, not on an analyzer rule:
  `Darkraise.csproj : error NU1101: Unable to find package Microsoft.NET.ILLink.Tasks`. SDK 10.0.404 adds
  `Microsoft.NET.ILLink.Tasks` 10.0.15 for `IsAotCompatible=true`; `~/.nuget/packages`, the case's offline fallback
  folder, held only 10.0.10 (added by 10.0.302). After one normal restore of a scratch `IsAotCompatible=true` project
  put 10.0.15 in `~/.nuget/packages`, the case passed: `ok real_framework_strict`, `1 passed, 0 failed`.
- **Consequence:** the framework commit `e3cb121d` compiles under 10.0.404 with the root settings; the plan goes on.
  After any SDK patch move, `real_framework_strict` needs the new `Microsoft.NET.ILLink.Tasks` in `~/.nuget/packages`
  first (any normal restore of an `IsAotCompatible` or `PublishAot` project does it). Restoring the framework project
  in place would leave ignored `obj/` files in the framework worktree, which the pin check reports.

## P2 — IDE rules in a command-line build

- **Command:** `dotnet build` of a net10.0 project with `EnforceCodeStyleInBuild=true`, `TreatWarningsAsErrors=true`,
  `AnalysisLevel=latest-recommended`, `AnalysisModeStyle=Default`, the framework's `.editorconfig` plus
  `dotnet_diagnostic.IDE0161.severity`, `IDE0028` and `IDE0300` to `IDE0305` at `warning`; source with a block-scoped
  namespace, `int[] a = new int[] { 1, 2 };`, two unused usings and a badly indented line. Repeated with
  `GenerateDocumentationFile=true`.
- **Result:** exit 1 with exactly two diagnostics: `error IDE0161` (file-scoped namespace) and `error IDE0300`
  (collection initialization). No IDE0055 for the indentation and no IDE0005 for the usings, with or without the
  documentation file. The framework's `.editorconfig` sets no IDE severities of its own.
- **Consequence for Task 3:** IDE0055 needs no `none` entry; CSharpier remains the only formatting check.

## P3 — `System.Reflection.Metadata` in an inline task

- **Command:** a `RoslynCodeTaskFactory` task that opens a built assembly (one `DllImport` and one `LibraryImport`
  method) with `PEReader` and counts method definitions with an import, run with `dotnet msbuild -t:Run`. Tried with
  `<Reference Include="System.Reflection.Metadata" />`, with the full path of the 10.0.15 reference assembly
  (`packs/Microsoft.NETCore.App.Ref/10.0.15/ref/net10.0/`), with the full path of the shared runtime's assembly, and
  with the reference assembly plus that pack's `System.Runtime.dll` and `System.Collections.Immutable.dll`.
- **Result:** none compiles. The bare name: `error MSB3755: Could not find reference "System.Reflection.Metadata"`.
  Either path: `error CS0012: The type 'ValueType' is defined in an assembly that is not referenced ... 'System.Runtime,
  Version=10.0.0.0'`. Adding `System.Runtime.dll`: `error CS0518: Predefined type 'System.Object' is not defined or
  imported`, because the factory compiles against netstandard and the net10.0 reference assemblies conflict with it.
- **Consequence for Task 10:** use the netstandard 2.0 fallback reader of the PE metadata tables.

## P4 — NuGet audit codes under `TreatWarningsAsErrors`

- **Command:** `dotnet restore --force` of a net10.0 project with `TreatWarningsAsErrors=true`, `WarningsNotAsErrors`
  `$(WarningsNotAsErrors);NU1901;NU1902;NU1903;NU1904`, `PackageReference` `Newtonsoft.Json` 12.0.1, and, under
  `-p:Strict=true`, `WarningsAsErrors` `$(WarningsAsErrors);NU1901;NU1902;NU1903;NU1904`. Also `dotnet build`, and a
  control with `-p:WarningsNotAsErrors=`.
- **Result:** non-strict restore and build exit 0 with
  `warning NU1903: Package 'Newtonsoft.Json' 12.0.1 has a known high severity vulnerability,
  https://github.com/advisories/GHSA-5crp-9r3c-p9vr`. Strict restore exits 1 with `error NU1903: Warning As Error`.
  The control (no `WarningsNotAsErrors`) exits 1 with the same error.
- **Consequence for Task 4:** the `WarningsNotAsErrors` mechanism works, and `WarningsAsErrors` adds the codes back
  for `DomentAuditStrict=true`; the spec's fallback is not needed. `Newtonsoft.Json` 12.0.1 carries
  GHSA-5crp-9r3c-p9vr (high) and serves as A27's known-vulnerable package.

## P5 — win-x64 restore of a NativeAOT executable and an xUnit v3 project

- **Command:** a `PublishAot=true` console project, `dotnet build -r win-x64`, then `dotnet restore` without a
  runtime identifier, then `dotnet build -r win-x64 -p:PublishAot=false`; an xUnit v3 4.0.2 test project with
  `Microsoft.Testing.Extensions.TrxReport` 2.5.1 and `UseMicrosoftTestingPlatformRunner=true`, restored without a
  runtime identifier and with `-r win-x64`. Package libraries and `downloadDependencies` read from
  `obj/project.assets.json` and matched against `docs/third-party-exceptions.md`.
- **Result, executable:** `-r win-x64` restores and builds (`Build succeeded`). Package libraries:
  `Microsoft.DotNet.ILCompiler` 10.0.15, `Microsoft.NET.ILLink.Tasks` 10.0.15,
  `runtime.win-x64.Microsoft.DotNet.ILCompiler` 10.0.15. Without a runtime identifier the third is
  `runtime.linux-x64.Microsoft.DotNet.ILCompiler`. With `-p:PublishAot=false` and `-r win-x64` there are no package
  libraries. `downloadDependencies` hold only runtime, host and NativeAOT runtime packs, which the register check
  (package libraries only) does not read.
- **Result, test project:** the same closure with and without `-r win-x64` (plus runtime packs in
  `downloadDependencies` for win-x64). Inside the register: `xunit.v3`, `xunit.v3.assert`, `xunit.v3.common`,
  `xunit.v3.core.mtp-v2`, `xunit.v3.extensibility.core`, `xunit.v3.mtp-v2`, `xunit.v3.runner.common`,
  `xunit.v3.runner.inproc.console` (4.0.2), `xunit.analyzers` 2.2.0 (B1); `Microsoft.Testing.Platform`,
  `Microsoft.Testing.Platform.MSBuild`, `Microsoft.Testing.Extensions.Telemetry`,
  `Microsoft.Testing.Extensions.TrxReport`, `Microsoft.Testing.Extensions.TrxReport.Abstractions` (2.5.1, B2).
  **Outside the register:** `Microsoft.ApplicationInsights` 2.23.0 (from `Microsoft.Testing.Extensions.Telemetry`,
  which `xunit.v3.core.mtp-v2` references), `Microsoft.Bcl.AsyncInterfaces` 6.0.0 (from `xunit.v3.common`),
  `Microsoft.Win32.Registry` 5.0.0 and `System.Security.AccessControl` 6.0.1 (from `xunit.v3.runner.common`).
- **Consequence for Task 6:** the four packages outside the register would fail the test project with DOMENT010; they
  go to the owner (the auto run's pending list) before Task 6.
- **Consequence for Task 12:** a portable win-x64 build of a `PublishAot=true` project adds
  `runtime.win-x64.Microsoft.DotNet.ILCompiler`, which needs a platform row; passing `-p:PublishAot=false` for the
  win-x64 build avoids it and still compiles the project for win-x64.

## P6 — `dotnet test --solution` and the logger flags

- **Command:** `dotnet test --solution probe.slnx` on the P5 test project with
  `-nologo -tl:off -clp:NoSummary -noConsoleLogger "-logger:ConsoleLogger,Microsoft.Build;NoSummary;Verbosity=minimal"`,
  then with each flag alone.
- **Result:** every run with `-tl:off` or `-clp:NoSummary` exits 5: `Zero tests ran`, `Handshake failures`. Runs with
  no flags, `-nologo`, `--no-progress`, or `-nologo -c Release -p:FrameworkPinStrict=true -p:DomentFormatCheck=true`
  exit 0 with `Test run summary: Passed!`, `total: 1`.
- **Consequence for Task 11:** the test step drops `-tl:off`, `-clp:NoSummary`, `-noConsoleLogger` and `-logger`; it
  passes `-nologo` and the global properties only.

## P7 — `'` and a space in the tree path

- **Command:** `build/gate.sh` (with `DOMENT_GATE_NO_FETCH=1` and `DARKRAISE_FRAMEWORK_PATH` set to the real framework
  worktree) on a one-commit copy of the repository's tracked files, on a branch other than master, at
  `<scratchpad>/p7/it's a tree`, and on the same copy at a plain path. Control: the quoted tree with a zero pin.
- **Result:** both trees: `gate: 0 projects checked, 0 packages seen, 0 violations`, exit 0. The control:
  `error DOMENT001: darkraise-framework at <path> is at e3cb121d..., but the pin is 0000...`, exit 1, so the framework
  check ran through the quoted path.
- **Consequence for Task 2:** `'` stays allowed.

## P8 — `.csharpierignore` and a file passed by path

- **Command:** CSharpier 1.2.6 restored from a tool manifest, `.csharpierrc` as the framework's (`printWidth` 130),
  `.csharpierignore` holding `ignored/`; `dotnet csharpier check` on an unformatted `ignored/Bad.cs` by relative path,
  by absolute path, and on the same file under `kept/`.
- **Result:** the ignored file by either path: `Checked 0 files`, exit 0. The kept file: exit 1, listing the
  unformatted line.
- **Consequence for Task 5:** an ignored file passed by path is skipped, so a fixture under `tests/build/fixtures/.run/`
  (listed in `.csharpierignore`) would never be checked; cases A12 to A14 keep their unformatted files in stand-in
  repositories outside the checkout.

## The console-logger workaround

- **Command:** `dotnet build -nologo -tl:off -clp:NoSummary` of a probe library under 10.0.404, then with the
  replaced console logger.
- **Result:** with `-clp:NoSummary` alone the summary lines (`Build succeeded`, `Warning(s)`, `Time Elapsed`) still
  print; with the replaced logger none do.
- **Consequence:** the workaround stays; the three comments name SDK 10.0.302 and 10.0.404.
