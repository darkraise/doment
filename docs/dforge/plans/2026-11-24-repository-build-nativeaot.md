# Repository, build and NativeAOT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: dforge:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin the toolchain, create `doment.slnx` with the nine M1 projects, enforce the framework's formatting and analyzer conventions and the portable rules in every build, publish the three executables with NativeAOT, add `build/check.sh`, and fix gate rows #6-#9.

**Architecture:** Everything is MSBuild logic imported by the root `Directory.Build.props` and `Directory.Build.targets` (new `.targets` files under `build/`, new inline task sources compiled by RoslynCodeTaskFactory), the projects under `src/` and `tests/`, and two bash scripts (`build/check.sh` and a new acceptance script). No package is added beyond the register's B1 to B3 rows and SDK-added platform packages.

**Tech Stack:** .NET SDK 10.0.404, C# (net10.0), MSBuild, NativeAOT with clang, xUnit v3 on Microsoft Testing Platform, CSharpier 1.2.6, bash.

**Spec:** docs/dforge/specs/2026-11-24-repository-build-nativeaot-design.md

**Execution:** inline — `claude --model opus --effort high` — the highest task total is 7 (Tasks 4, 5, 9, 11, 12), the floor row for 6 to 8 is opus/high

**Parallelism:** sequential — inline execution

**Task check:** none — full suite every 3 tasks

**Integration check:** `bash tests/build/run.sh && bash tests/build/architecture-decisions.acceptance.sh && bash tests/build/repository-build.acceptance.sh`

**CI:** none

**Worktree setup:** `bash tools/framework.sh sync && { [ ! -f .config/dotnet-tools.json ] || dotnet tool restore; }`

**Plan review:** 2026-11-24 — dforge:judge-opus — executability 13 / coherence 15 / coverage 15 / assumptions 12 (round 1)

## Global Constraints

- SDK: `global.json` is `{"sdk": {"version": "10.0.404", "rollForward": "latestPatch"}, "test": {"runner": "Microsoft.Testing.Platform"}}`; SDK 10.0.404 lives in `/usr/local/share/dotnet`, linked as `/usr/local/bin/dotnet`; apt's 10.0.302 stays installed and untouched.
- clang comes from apt; no build file sets `CppCompilerAndLinker`.
- Every project targets `net10.0`. `Darkraise` is referenced as `$(DarkraiseFrameworkPath)src/Darkraise/Darkraise.csproj` only.
- No package beyond register rows B1 (`xunit.v3`, `xunit.v3.*`, `xunit.analyzers`), B2 (`Microsoft.Testing.Platform`, `Microsoft.Testing.Platform.*`, `Microsoft.Testing.Extensions.*`), B3 (`csharpier`) and platform-packages rows for packages the .NET SDK adds. Any other package in a restore closure stops the task and goes to the owner (in the auto run: the pending list).
- Test package versions: `XunitV3Version` 4.0.2, `TestingPlatformVersion` 2.5.1, in `tests/Directory.Build.props`; no central package management.
- CSharpier 1.2.6, `printWidth` 130.
- Every text file LF. Every `.cs` file formatted by CSharpier 1.2.6 and free of warnings under the root settings.
- Every script and test bounds each `dotnet` and network call with `timeout`, disables node reuse, the MSBuild server and the shared compiler (`MSBUILDDISABLENODEREUSE=1`, `DOTNET_CLI_USE_MSBUILD_SERVER=0`, `UseSharedCompilation=false`), and leaves no process behind; after any manual `dotnet` session, run `dotnet build-server shutdown`.
- `docs/architecture.md` is the living record: a task that changes a recorded decision edits it in the same commit (Task 13 does the bulk).
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period, no attribution lines.

## Contracts

**C1. Files.**

| Path | Made by | Role |
|---|---|---|
| `docs/dforge/research/2026-11-24-build-probes.md` | Task 1 | One section per probe P1 to P8: command, date, result, consequence for the plan |
| `tests/build/repository-build.acceptance.sh` | Task 1 | `bash tests/build/repository-build.acceptance.sh [<extended regex>]`; same structure and soft-assertion helpers as `tests/build/architecture-decisions.acceptance.sh` (a `TESTS` array of `"A<n>: <title>|t_A<n>"`, `PASS <name>` / `FAIL <name>` lines, last line `<p> passed, <f> failed`, exit 0 only with no failure); runs on the real checkout with the user's normal NuGet sources and package folder; temporary trees under `artifacts/acceptance/` (removed on exit) |
| `build/Doment.Conventions.props` | Task 4 | Compiler and analyzer settings, imported by the root `Directory.Build.props` |
| `build/Doment.Format.targets` | Task 5 | The format check, imported by the root `Directory.Build.targets` |
| `build/Doment.Simulation.targets` | Task 8 | The DOMENT030 check, imported by the root `Directory.Build.targets` |
| `build/Doment.Platform.targets` | Task 9 | `DomentPlatform`, the CA1416 `NoWarn` reset and the target-framework check, imported by the root `Directory.Build.targets` before the other new targets files |
| `build/Doment.PortableCheck.cs` | Task 10 | Inline task `DomentPortableAssemblyCheck`, its own `UsingTask` in `build/Doment.Platform.targets` |
| `build/check.sh` | Task 11 | See C4 |

**C2. Properties.**

- `DomentPlatform`: `portable`, `linux` or `windows`. Set by `build/Doment.Platform.targets` after the project body: `linux` for `Doment.Agent` and `Doment.Platform.Linux`; `windows` for `Doment.Platform.Windows`, `Doment.Service`, `Doment.Session`, `Doment.App`; `portable` for every other project. A global property (`-p:DomentPlatform=...`) wins; a project's own value does not.
- `DomentFormatCheck`: set to `true` after the project body by `build/Doment.Format.targets`, so only a global `-p:DomentFormatCheck=false` turns the check off.
- `DomentAuditStrict`: default `false`. `false` keeps NU1901 to NU1904 out of warnings as errors; `true` (passed by `build/check.sh`) makes them errors.
- `DomentSimulation`: default `false`. `true` gives `Doment.Cli` and `Doment.Agent` a `ProjectReference` to `Doment.Simulation` and the constant `DOMENT_SIMULATION`.

**C3. Diagnostics** (each an MSBuild error with the code shown).

- `DOMENT030`: `a release publish cannot include Doment.Simulation; build simulation binaries in Debug`
- `DOMENT031`: `<file> is not formatted; run dotnet csharpier format <file>` — one per unformatted file, `<file>` relative to the project directory.
- `DOMENT032`: `CSharpier is not restored; run dotnet tool restore`
- `DOMENT033`: `<project name> is portable but <finding>`, where `<finding>` is one of: `declares a native import <type>.<method> from <library>`; `references System.Runtime.InteropServices.NativeLibrary`; `carries the assembly attribute SupportedOSPlatform("<platform>")`; `targets <tfm>; portable projects target net10.0`.

**C4. `build/check.sh`.**

- `build/check.sh [<step>...]`; steps `build`, `portable`, `aot`, `test`; no argument runs all four in that order.
- Tree root: the parent of the script's own directory, computed with `cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P`, never with git. The solution is `<root>/doment.slnx`.
- Global properties on every call: `-c Release -p:FrameworkPinStrict=true -p:DomentFormatCheck=true -p:DomentAuditStrict=true`.
- First line: `check: dotnet <SDK version> at <DOTNET_ROOT>`, the SDK that PATH resolves and the `DOTNET_ROOT` the script exports.
- Output: `check: <step> ok`, or `check: <step> failed` followed by cause lines indented by four spaces; last line `check: <n> steps run, <f> failed`. The portable step also prints one progress line per build, `check: portable <project name> <rid>`, before it runs.
- Exit 0 when every step passed, 1 at the first failed step (no later step runs), 2 on usage: `check: unknown step '<s>'; steps: build, portable, aot, test`.
- `DOMENT_CHECK_TIMEOUT` (seconds) overrides every call's timeout; a timeout's cause line is `timed out after <s> s: <command>`.
- aot step: for each project of the solution whose `PublishAot` is `true`, publish to `<root>/artifacts/publish/<AssemblyName>/linux-x64/`, then run `<that dir>/<AssemblyName> --version`, whose first line must match `^<AssemblyName> <VersionPrefix>([+-]|$)` with the version's dots literal.
- Warning pattern `(^|[: ])warning [A-Z]+[0-9]+:`; error pattern `(^|[: ])error [A-Z]+[0-9]+:`.

**C5. `Doment.Core.StandardOptions`** (public static class, file `src/Doment.Core/StandardOptions.cs`).

- `public static string ProductVersion { get; }` — the `AssemblyInformationalVersionAttribute` of `Doment.Core`.
- `public static int Run(string name, IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr)` — `["--version"]`: writes `<name> <ProductVersion>` and a newline to stdout, returns 0; `["--help"]`: writes `usage: <name> [--version | --help]` and a newline to stdout, returns 0; anything else, no arguments included: writes that usage line to stderr, returns 2.

**C6. Projects.** As the spec's section 3 table: paths `src/Doment.<Name>/Doment.<Name>.csproj` and `tests/Doment.Core.Tests/Doment.Core.Tests.csproj`; assembly names `doment-server` (Server), `doment` (Cli), `doment-agent` (Agent); `VersionPrefix` `0.1.0` in the root `Directory.Build.props`.

## Assumptions (evidence)

- The pinned framework commit compiles under SDK 10.0.404: unverified — Task 1 verifies it (probe P1).
- A command-line build fails on IDE0161 and IDE0300 with `dotnet_diagnostic` lines and `EnforceCodeStyleInBuild=true`; which other IDE rules fire: unverified — Task 1 verifies it (P2).
- An inline task can reference `System.Reflection.Metadata` under SDK 10.0.404: unverified — Task 1 verifies it (P3). A `System.Text.Json` reference from the same factory failed (`docs/dforge/plans/2026-11-24-architecture-decisions.md:111`), so Task 10 is sized for the fallback reader.
- NuGet honours `WarningsNotAsErrors` for NU1901 to NU1904 under `TreatWarningsAsErrors`: unverified — Task 1 verifies it (P4).
- A `PublishAot=true` executable restores and builds with `-r win-x64` on Linux, and the restore closures of it and of an xUnit v3 4.0.2 test project are inside the register: unverified — Task 1 verifies it (P5).
- `dotnet test --solution` under Microsoft Testing Platform accepts the gate's logger flags: unverified — Task 1 verifies it (P6).
- `'` in a tree path works through the gate's property functions: unverified — Task 1 verifies it (P7).
- CSharpier skips a file listed in `.csharpierignore` even when passed by path: unverified — Task 1 verifies it (P8).
- doment's root build files never reach a framework project: `external/Directory.Build.targets` and `external/Directory.Packages.props` are empty `<Project />` stubs that end MSBuild's upward search above `external/darkraise-framework` (`docs/architecture.md`, "One framework worktree per doment checkout"; file read 2026-11-24), the framework's own `Directory.Build.props` ends the props search, and an overridden framework path lies outside the checkout. So the new targets need no framework-exclusion condition, and the existing `real_framework_strict` case, which builds the real framework under the root settings, keeps passing only if this holds.
- The Microsoft Testing Platform test executable's runtime: an apphost picks the highest installed patch of the 10.0 runtime under `DOTNET_ROOT`; A17 checks the effect directly with a probe executable rather than relying on a `--info` output format.
- CSharpier 1.2.6 is the framework's formatter version: `csharpier --version` printed `1.2.6` on 2026-11-24.
- GHSA-p3jp-9v83-76w9 is fixed from 10.0.14 for `Microsoft.DotNet.ILCompiler` and the linux-x64 runtime packs: GitHub advisory API, read 2026-11-24.
- `Newtonsoft.Json` 12.0.1 carries advisory GHSA-5crp-9r3c-p9vr (high), used as the known-vulnerable package of A27's stand-in: unverified — Task 1 verifies it (P4 restores it).

- Plan review round 1 scored executability 13 and assumptions 12 (borderline). Decision: no second round. Every Important finding was fixed in place (test counts, A10's `# doment:` marker, A20's baseline, the batching and no-stamp tests, the LibraryImport text, the runtime check, the P5 win-x64 test restore, commit scopes), and the framework-reach finding is answered by the evidence above. The remaining uncertainty is the eight probes, which Task 1 settles before any task depends on them.

## Task index

1. Toolchain, probes and the acceptance script
2. Line endings and gate fixes
3. Editorconfig from the framework
4. Compiler and analyzer conventions
5. Format check in every build
6. Solution, libraries and the test project
7. Executables
8. Simulation property
9. Portable platform rules
10. Portable assembly check
11. Check command core
12. Portable and NativeAOT steps
13. Documentation

---

### Task 1: Toolchain, probes and the acceptance script

**Files:**
- Create: `global.json`
- Create: `docs/dforge/research/2026-11-24-build-probes.md`
- Create: `tests/build/repository-build.acceptance.sh`
- Modify: `build/gate.sh` (the comment above `DN_FLAGS`), `tests/build/run.sh` (the comment above `DN_LOGGER`), `tests/build/architecture-decisions.acceptance.sh` (the matching comment above its `DN_FLAGS`)

**Interfaces:**
- Produces: C1 `tests/build/repository-build.acceptance.sh` and `docs/dforge/research/2026-11-24-build-probes.md`.

**Items:** 2026-11-24-repository-build-nativeaot#4

**Depends on:** none

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

- `tests/build/repository-build.acceptance.sh::A1` (integration): given the checkout, asserts that `dotnet --version` run in the repository root prints a version matching `^10\.0\.4[0-9]{2}$` and not below `10.0.404`, and that `global.json` parses to `sdk.version` `10.0.404`, `sdk.rollForward` `latestPatch` and `test.runner` `Microsoft.Testing.Platform`; fails today because there is no `global.json` and the SDK on PATH is 10.0.302.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/repository-build.acceptance.sh '^A1:'`
Expected: `FAIL A1: ...`. Step 3's item 3 (the harness and `t_A1`) is written first so that this run is possible; the toolchain install comes after it.

- [ ] **Step 3: Implement**

1. Install the toolchain (owner decision 2 of the spec): download `https://dot.net/v1/dotnet-install.sh` to the scratchpad, run it with `--version 10.0.404 --install-dir /usr/local/share/dotnet` under `timeout 900`, link `/usr/local/bin/dotnet` to `/usr/local/share/dotnet/dotnet`, and `apt-get install -y clang` under `timeout 900`. Confirm `command -v dotnet` resolves to `/usr/local/bin/dotnet` in a fresh login shell.
2. Write `global.json` exactly as Global Constraints gives it.
3. Write the acceptance script's harness by copying the structure of `tests/build/architecture-decisions.acceptance.sh` (environment exports except `NuGetAudit=false`, soft assertions, the `TESTS` runner), without its stand-in feed: this script uses the user's normal sources. Add `t_A1`.
4. Run the probes and record each in the probes file (command, date, result, consequence). Probes use throwaway projects under the scratchpad that import the repository's root build files where a probe needs them, and are deleted afterwards:
   - P1: `bash tests/build/run.sh '^real_framework_strict$'` under SDK 10.0.404. If it fails on an analyzer rule in framework code, stop the plan: the fix is a framework change and a pin move, which goes to the pending list.
   - P2: a net10.0 project with `EnforceCodeStyleInBuild=true`, `TreatWarningsAsErrors=true`, `AnalysisLevel=latest-recommended`, `AnalysisModeStyle=Default`, the framework's `.editorconfig` plus `dotnet_diagnostic.IDE0161.severity = warning` and `dotnet_diagnostic.IDE0028.severity`, `IDE0300` to `IDE0305` at `warning`, and a source file with a block-scoped namespace, an array initialiser `int[] a = new int[] { 1, 2 };`, unused usings and a badly indented line. Record every diagnostic id that fails the build. Consequence: whether IDE0055 needs `none` (Task 3).
   - P3: an inline `RoslynCodeTaskFactory` task with `<Reference Include="System.Reflection.Metadata" />` that opens a built assembly with `PEReader` and counts `MethodDefinition`s with an import. Record whether it compiles and runs. Consequence for Task 10: the reference path, or the netstandard 2.0 fallback reader.
   - P4: a net10.0 project with `TreatWarningsAsErrors=true`, `WarningsNotAsErrors` holding `NU1901;NU1902;NU1903;NU1904`, and `PackageReference` `Newtonsoft.Json` 12.0.1: does `dotnet restore` succeed with NU1903; with `WarningsAsErrors` adding them back, does it fail. Consequence for Task 4: the mechanism, or the spec's fallback (`TreatWarningsAsErrors` false in restore evaluations unless strict).
   - P5: a `PublishAot=true` console project built with `-r win-x64` on Linux, and an xUnit v3 4.0.2 test project with `Microsoft.Testing.Extensions.TrxReport` 2.5.1 and `UseMicrosoftTestingPlatformRunner=true`, restored both without a runtime identifier and with `-r win-x64`; list the restore closures (`project.assets.json` libraries, and `downloadDependencies`) and match each against `docs/third-party-exceptions.md`. Consequence for Tasks 6 and 12: the platform rows to add, whether the portable step passes `-p:PublishAot=false` for win-x64, and any package for the owner.
   - P6: `dotnet test --solution <probe>.slnx -nologo -tl:off -clp:NoSummary -noConsoleLogger "-logger:ConsoleLogger,Microsoft.Build;NoSummary;Verbosity=minimal"` on the P5 test project. Consequence for Task 11: keep or drop the logger flags on the test step.
   - P7: `build/gate.sh` on a copy of a no-project tree at a path containing `'` and a space. Consequence for Task 2: `'` stays allowed or joins the refused list.
   - P8: `dotnet csharpier check <file>` on an unformatted file listed in `.csharpierignore`. Consequence for Task 5's test layout.
5. Correct the three comments that name SDK 10.0.302 for the console-logger workaround: re-run the workaround's reason under 10.0.404 (`dotnet build` with `-clp:NoSummary` alone, on any probe project) and write the version that still shows it, or say that the workaround is kept for 10.0.302 and later if it no longer reproduces.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/repository-build.acceptance.sh '^A1:' && bash tests/build/run.sh && bash tests/build/architecture-decisions.acceptance.sh`
Expected: `PASS A1: ...`, then both existing suites end with `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add global.json docs/dforge/research/2026-11-24-build-probes.md tests/build/repository-build.acceptance.sh build/gate.sh tests/build/run.sh tests/build/architecture-decisions.acceptance.sh
git commit -m "chore(build): pin SDK 10.0.404 and record probes"
```

### Task 2: Line endings and gate fixes

**Files:**
- Modify: `.gitattributes`
- Modify: `build/gate.sh` (the tree resolution after `TREE=$(git -C ...)`, the `printf '<Project>...'` that writes `framework-check.proj`, and the master-branch block starting `if [[ $branch == master || $branch == main ]]`)
- Test: `tests/build/run.sh` (new cases), `tests/build/repository-build.acceptance.sh` (A21)

**Interfaces:**
- Consumes: C1 acceptance script.
- Produces: nothing other tasks consume.

**Items:** 2026-11-24-architecture-decisions#6, 2026-11-24-architecture-decisions#7, 2026-11-24-architecture-decisions#8, 2026-11-24-architecture-decisions#9

**Depends on:** Task 1

**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

- `tests/build/repository-build.acceptance.sh::A21` (integration): given the checkout, asserts that `git ls-files --eol` shows `i/lf` for every tracked text file (no `i/crlf`, no `i/mixed`), that `git check-attr eol` reports `lf` for `build/gate.sh`, `tests/build/run.sh`, `build/Doment.BuildChecks.cs`, `Directory.Build.props`, `README.md` and `build/darkraise-framework.pin`, and that `git check-attr text` reports `unset` for `x.dll`, `x.exe`, `x.so`, `x.dylib`, `x.a`, `x.lib`, `x.sys`, `x.nupkg`, `x.snupkg`, `x.png`, `x.jpg` and `x.ico`; fails today because `.gitattributes` sets `eol=lf` only for the pin file.
- `tests/build/run.sh::gate_master_pin_lines` (integration): given a stand-in doment repository on `master`, (a) with a malformed pin, asserts the gate's output has exactly one line matching `error DOMENT006:`; (b) with a valid pin and `DARKRAISE_FRAMEWORK_PATH` pointing at a missing directory, exactly one `error DOMENT003:` line; and asserts `grep -c 'DOMENT006\|DOMENT003' build/gate.sh` is `0`; fails today because `gate.sh` writes its own copies of both lines.
- `tests/build/run.sh::gate_tree_path_characters` (integration): given a stand-in doment repository holding one net10.0 fixture project, copied to a directory whose name contains `&`, `<`, `'` and a space, asserts the gate exits 0 with `0 violations`; and for each of `;`, `%`, `$`, `@`, `"`, `,` in the directory name asserts exit 2 and `gate: <tree> contains '<char>', which MSBuild cannot take in a path`; fails today because the generated project is not XML-escaped and nothing refuses the special characters. (Drop `'` from the allowed set and add it to the refused set if Task 1's P7 says so.)
- `tests/build/run.sh::gate_plain_directory_framework` (integration): given a stand-in doment repository on `master` whose `DARKRAISE_FRAMEWORK_PATH` is a plain directory inside another git repository that has a remote, asserts the output holds `error DOMENT002:`, no `DOMENT005`, and that the enclosing repository's `FETCH_HEAD` was not created; fails today only if the skip regresses (it guards the existing skip, row #9).
- `tests/build/run.sh::gate_ls_files_failure` (integration): given a stand-in doment repository and a `git` wrapper first on PATH that forwards every call to the real git except that its N-th `ls-files` call exits 128, asserts for N = 1, 2, 3 that the gate exits 1 and prints `gate: git ls-files failed in <tree>`; fails today only if a `die` path regresses (row #9).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/repository-build.acceptance.sh '^A21:'; bash tests/build/run.sh '^gate_(master_pin_lines|tree_path_characters|plain_directory_framework|ls_files_failure)$'`
Expected: A21 FAIL; `gate_master_pin_lines` and `gate_tree_path_characters` not ok; the other two may already pass.

- [ ] **Step 3: Implement**

1. `.gitattributes`: `* text=auto eol=lf`, then `-text` lines for the twelve binary patterns of A21; remove the pin-file line. Run `git add --renormalize .` and include the result in this commit.
2. `gate.sh`, after the tree is resolved: refuse a tree path containing any of `;`, `%`, `$`, `@`, `"`, `,` with the C-style message above and exit 2.
3. `gate.sh`, `framework-check.proj`: XML-escape the tree path (`&` first, then `<`, `>`, `"`, `'`) before writing it into the two `Import` elements.
4. `gate.sh`, master block: when the pin is malformed or the framework directory is missing, skip the ancestry check without a violation (the framework check reports DOMENT006 or DOMENT003); keep the plain-directory skip and the fetch as they are.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/repository-build.acceptance.sh '^A21:' && bash tests/build/run.sh '^gate_'`
Expected: `PASS A21: ...`; every `gate_` case `ok`, then `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add -A .gitattributes build/gate.sh tests/build/run.sh tests/build/repository-build.acceptance.sh
git commit -m "fix(build): normalise line endings, harden the gate"
```

### Task 3: Editorconfig from the framework

**Files:**
- Create: `.editorconfig`
- Test: `tests/build/repository-build.acceptance.sh` (A10, first half)

**Interfaces:**
- Consumes: C1 acceptance script.
- Produces: the root `.editorconfig` that Tasks 4 and 5 build against.

**Items:** 2026-11-24-repository-build-nativeaot#3

**Depends on:** Task 1

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 0 = 4

- [ ] **Step 1: Write the failing test**

- `tests/build/repository-build.acceptance.sh::A10` (integration): given the checkout and its framework worktree at the pin, asserts that the root `.editorconfig`, with every line starting `# doment:` removed and every `dotnet_diagnostic.<id>.severity` line for IDE0161, IDE0028, IDE0300 to IDE0305 (and IDE0055 if Task 1's P2 required it) removed, equals `external/darkraise-framework/.editorconfig` with its `DRUI020` line and that line's comment block removed and `end_of_line = crlf` replaced by `end_of_line = lf`; fails today because there is no root `.editorconfig`. (Task 5 extends A10 with `.csharpierrc`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/repository-build.acceptance.sh '^A10:'`
Expected: `FAIL A10: ...`

- [ ] **Step 3: Implement**

1. Copy the framework's `.editorconfig` from the pinned worktree.
2. Apply the spec's section 4 changes, each introduced by comment lines starting `# doment:` that say why (A10 strips exactly those lines): both `end_of_line` values to `lf`; remove the `DRUI020` block; add, in the `[*.{cs,vb}]` section, `dotnet_diagnostic.IDE0161.severity = warning` and `dotnet_diagnostic.<id>.severity = warning` for IDE0028 and IDE0300 to IDE0305; add `dotnet_diagnostic.IDE0055.severity = none` only if P2 recorded IDE0055 firing.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/repository-build.acceptance.sh '^A10:'`
Expected: `PASS A10: ...`

- [ ] **Step 5: Commit**

```bash
git add .editorconfig tests/build/repository-build.acceptance.sh
git commit -m "chore(build): adopt the framework editorconfig"
```

### Task 4: Compiler and analyzer conventions

**Files:**
- Create: `build/Doment.Conventions.props`
- Modify: `Directory.Build.props` (import the new file at its end; add `VersionPrefix` 0.1.0)
- Modify: `tests/build/run.sh`, `tests/build/architecture-decisions.acceptance.sh` (generated fixture source that breaks a rule, such as `mk_project`'s `App_Tests` namespace)
- Test: `tests/build/run.sh` (new cases)

**Interfaces:**
- Consumes: the root `.editorconfig` (Task 3).
- Produces: C2 `DomentAuditStrict`; `VersionPrefix` of C6.

**Items:** 2026-11-24-repository-build-nativeaot#3

**Depends on:** Task 3

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

- `tests/build/run.sh::conventions_style` (integration): given three fixture projects under `tests/build/fixtures/.run/` (which take the root `.editorconfig` by directory), one with a block-scoped namespace, one with `int[] a = new int[] { 1, 2 };` where IDE0300 applies, one with a CA1822-flagged instance method that uses no instance data (a `latest-recommended` rule), asserts each `dotnet build` exits non-zero with an `error IDE0161`, `error IDE0300` and `error CA1822` line respectively, and that a fourth, clean fixture builds with exit 0 and no `warning` line; fails today because the root build files set none of these.
- `tests/build/run.sh::conventions_audit` (integration): the harness is offline, so this case pins the evaluated properties and A27 (Task 12) pins the behaviour with a real advisory. Given a clean fixture project, asserts `dotnet msbuild -getProperty:WarningsNotAsErrors` lists `NU1901`, `NU1902`, `NU1903` and `NU1904`; with `-p:DomentAuditStrict=true`, asserts `-getProperty:WarningsNotAsErrors` lists none of them and `-getProperty:WarningsAsErrors` lists all four; fails today because neither property mentions them. If Task 1's P4 chose the fallback, the case instead asserts that `-getProperty:TreatWarningsAsErrors -p:MSBuildRestoreSessionId=x` prints `false` without strict and `true` with it.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^conventions_'`
Expected: both `not ok`.

- [ ] **Step 3: Implement**

1. `build/Doment.Conventions.props`: `Nullable=enable`, `ImplicitUsings=enable`, `LangVersion=latest`, `TreatWarningsAsErrors=true`, `AnalysisLevel=latest-recommended`, `AnalysisModeStyle=Default`, `EnforceCodeStyleInBuild=true`, `CA1416` appended to `WarningsAsErrors`; the audit switch as P4 decided (C2 `DomentAuditStrict`).
2. Root `Directory.Build.props`: `VersionPrefix` 0.1.0; import the conventions file last.
3. Bring generated fixture sources in both harnesses into line with the rules (rename `App_Tests`, file-scoped namespaces, anything else the full runs flag); do not exempt fixtures from analyzer rules.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh && bash tests/build/architecture-decisions.acceptance.sh`
Expected: both end with `0 failed`, the two `conventions_` cases `ok`.

- [ ] **Step 5: Commit**

```bash
git add build/Doment.Conventions.props Directory.Build.props tests/build/run.sh tests/build/architecture-decisions.acceptance.sh
git commit -m "chore(build): enforce the framework analyzer rules"
```

### Task 5: Format check in every build

**Files:**
- Create: `.config/dotnet-tools.json`, `.csharpierrc`, `.csharpierignore`
- Create: `build/Doment.Format.targets`
- Modify: `Directory.Build.targets` (import the new file)
- Modify: `tests/build/run.sh` (`dn` passes `-p:DomentFormatCheck=false`; new cases), `tests/build/architecture-decisions.acceptance.sh` (`DN_FLAGS` gains `-p:DomentFormatCheck=false`)
- Test: `tests/build/run.sh`, `tests/build/repository-build.acceptance.sh` (A10 extended)

**Interfaces:**
- Consumes: root `.editorconfig` (Task 3).
- Produces: C2 `DomentFormatCheck`; C3 DOMENT031, DOMENT032.

**Items:** 2026-11-24-repository-build-nativeaot#3

**Depends on:** Task 4

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Cases A12 to A14 run in stand-in repositories outside the checkout (`new_doment_repo` plus copies of `.editorconfig`, `.csharpierrc`, `.csharpierignore`, `.config/dotnet-tools.json`; P8 decides whether `.run/` fixtures would be skipped), with `dn` called without the global `DomentFormatCheck=false`:

- `tests/build/run.sh::format_unformatted` (integration): given a fixture project whose `Program.cs` is `class   A{}`, asserts `dotnet build` exits non-zero with exactly one line `error DOMENT031: Program.cs is not formatted; run dotnet csharpier format Program.cs`; after `dotnet csharpier format Program.cs`, asserts the build exits 0; fails today because nothing checks formatting.
- `tests/build/run.sh::format_stamp` (integration): given the formatted fixture built once, asserts a second build's detailed log (`-v:d`) shows the format target skipped as up to date; after appending a newline-only change to `.csharpierrc`, asserts the next build runs the check again; and a build with `-p:DesignTimeBuild=true` does not run the check; fails today because the target does not exist.
- `tests/build/run.sh::format_tool_missing` (integration): given a stand-in without `.config/dotnet-tools.json` and an empty `DOTNET_CLI_HOME`-style tool cache (set `HOME` to an empty directory for the call), asserts `error DOMENT032: CSharpier is not restored; run dotnet tool restore` once; fails today for the same reason.
- `tests/build/run.sh::format_global_only` (integration): given a fixture project with `<DomentFormatCheck>false</DomentFormatCheck>` in its own file and an unformatted source, asserts the plain build still fails with DOMENT031, and the same build with `-p:DomentFormatCheck=false` exits 0; fails today for the same reason.
- `tests/build/run.sh::format_batching` (integration): given a fixture project with 101 formatted `.cs` files plus one unformatted file that sorts after them (`Zz.cs`), asserts exactly one `error DOMENT031: Zz.cs is not formatted; run dotnet csharpier format Zz.cs` and, in the `-v:d` log, two `dotnet csharpier check` command lines; fails today because the target does not exist.
- `tests/build/repository-build.acceptance.sh::A10` extension: asserts `.csharpierrc` parses to the same JSON as `external/darkraise-framework/.csharpierrc`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^format_'; bash tests/build/repository-build.acceptance.sh '^A10:'`
Expected: every `format_` case `not ok`; A10 FAIL.

- [ ] **Step 3: Implement**

1. `.config/dotnet-tools.json` with `csharpier` 1.2.6 (command `csharpier`); `.csharpierrc` as the framework's; `.csharpierignore` listing `artifacts/` and `tests/build/fixtures/.run/`.
2. `build/Doment.Format.targets`: set `DomentFormatCheck` to `true` after the project body (a global value wins); a target before `CoreCompile`, skipped when `DesignTimeBuild` is `true` or `DomentFormatCheck` is not `true`, that probes `dotnet csharpier --version` in the project directory (DOMENT032 on failure), then runs `dotnet csharpier check` on the project's `Compile` items outside `$(IntermediateOutputPath)`, 100 paths per call, raising one DOMENT031 per file CSharpier reports and passing its output through as messages; `Inputs` are those items plus whichever of the four config files exist, `Outputs` a stamp under `$(IntermediateOutputPath)` touched only on success.
3. Root `Directory.Build.targets`: import it.
4. Both harnesses pass `-p:DomentFormatCheck=false` by default; the `format_` cases opt out of it.
5. `dotnet tool restore` in the checkout.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh && bash tests/build/architecture-decisions.acceptance.sh && bash tests/build/repository-build.acceptance.sh`
Expected: every suite ends with `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .config/dotnet-tools.json .csharpierrc .csharpierignore build/Doment.Format.targets Directory.Build.targets tests/build/run.sh tests/build/architecture-decisions.acceptance.sh tests/build/repository-build.acceptance.sh
git commit -m "chore(build): check formatting in every build"
```

### Task 6: Solution, libraries and the test project

**Files:**
- Create: `doment.slnx`
- Create: `src/Doment.Protocol/Doment.Protocol.csproj`, `src/Doment.Core/Doment.Core.csproj`, `src/Doment.Simulation/Doment.Simulation.csproj`, `src/Doment.Worker/Doment.Worker.csproj`, `src/Doment.Host/Doment.Host.csproj`, `src/Doment.Client/Doment.Client.csproj`
- Create: `src/Doment.Core/StandardOptions.cs`
- Create: `tests/Directory.Build.props`, `tests/Doment.Core.Tests/Doment.Core.Tests.csproj`, `tests/Doment.Core.Tests/StandardOptionsTests.cs`
- Modify: `.gitignore` (`/artifacts/`), `docs/third-party-exceptions.md` (platform rows P5 named, if any)
- Test: `tests/Doment.Core.Tests/StandardOptionsTests.cs`, `tests/build/repository-build.acceptance.sh` (A2, A3, A17, A20 for these projects)

**Interfaces:**
- Consumes: root build files of Tasks 4 and 5.
- Produces: C5 `StandardOptions`; C6 library and test project paths; `doment.slnx`.

**Items:** 2026-11-24-repository-build-nativeaot#1, 2026-11-24-repository-build-nativeaot#5

**Depends on:** Task 5

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

- `tests/Doment.Core.Tests/StandardOptionsTests.cs::Run_Version_PrintsNameAndVersion` (unit): given `Run("doment", ["--version"], out, err)` with two `StringWriter`s, asserts the return is 0, `out` is `doment 0.1.0` followed by any `+`/`-` suffix and a newline (matched with `^doment 0\.1\.0([+-].*)?\n$`), and `err` is empty; fails today because the type does not exist.
- `...::Run_Help_PrintsUsageToStdout` (unit): `["--help"]` returns 0, `out` is exactly `usage: doment [--version | --help]\n`, `err` empty.
- `...::Run_OtherArguments_PrintUsageToStderr` (unit, theory with rows `[]`, `["--bogus"]`, `["--version", "x"]`): returns 2, `err` is exactly `usage: doment [--version | --help]\n`, `out` empty.
- `tests/build/repository-build.acceptance.sh::A2` (integration): `dotnet build doment.slnx -c Release -p:FrameworkPinStrict=true` exits 0 with no line matching the C4 warning pattern; fails today because there is no solution.
- `...::A3` (integration): each project's direct `ProjectReference` file names (read with `dotnet msbuild <proj> -getItem:ProjectReference`) equal its section 3 row, and no project but `Doment.Simulation` has `Doment.Simulation` in its `ReferencePath` after a build; fails today for the same reason. (Task 7 extends the rows with the executables.)
- `...::A17` (integration, first half): `dotnet test --solution doment.slnx -c Release` exits 0 and its output reports 5 tests passed and 0 failed (two facts and a three-row theory); fails today because there is no solution. (Task 11 moves the case onto `build/check.sh test` and adds the runtime-version check.)
- `...::A20` (integration): `DOMENT_GATE_NO_FETCH=1 build/gate.sh` exits 0 with `0 violations`, and every row of the register's Platform packages table has an "Added by" cell starting `.NET SDK`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/repository-build.acceptance.sh '^A(2|3|17|20):'`
Expected: A2, A3, A17 FAIL (A20 may pass on a tree with no projects).

- [ ] **Step 3: Implement**

1. The six library projects per the spec's section 3 table (references only as listed; each sets `IsAotCompatible=true` in its own file; `Doment.Core` references `$(DarkraiseFrameworkPath)src/Darkraise/Darkraise.csproj`).
2. `StandardOptions` per C5, AOT-safe (`typeof(StandardOptions).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()`).
3. `tests/Directory.Build.props` per the spec (imports the root one; the two version properties; `NoWarn` CA1707, CA1861, xUnit1051); the test project as an executable on Microsoft Testing Platform referencing `xunit.v3` and `Microsoft.Testing.Extensions.TrxReport`, and `Doment.Core`.
4. `doment.slnx` with `/src/` and `/tests/` folders; `/artifacts/` in `.gitignore`.
5. Add the platform rows P5 identified for the test and library restores, each "Added by" `.NET SDK (...)`; anything else goes to the pending list.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 dotnet test --solution doment.slnx -c Release && bash tests/build/repository-build.acceptance.sh '^A(2|3|17|20):'`
Expected: 5 tests passed, 0 failed; four PASS lines.

- [ ] **Step 5: Commit**

```bash
git add doment.slnx src tests/Directory.Build.props tests/Doment.Core.Tests .gitignore docs/third-party-exceptions.md tests/build/repository-build.acceptance.sh
git commit -m "feat(core): add the solution and library projects"
```

### Task 7: Executables

**Files:**
- Create: `src/Doment.Server/Doment.Server.csproj`, `src/Doment.Server/Program.cs`, `src/Doment.Cli/Doment.Cli.csproj`, `src/Doment.Cli/Program.cs`, `src/Doment.Agent/Doment.Agent.csproj`, `src/Doment.Agent/Program.cs`
- Modify: `doment.slnx`, `docs/third-party-exceptions.md` (rows P5 named for `PublishAot`, if any)
- Test: `tests/build/repository-build.acceptance.sh` (A3 rows, new A-exe case under A4's number)

**Interfaces:**
- Consumes: C5 `StandardOptions.Run`; C6.
- Produces: C6 executable projects and assembly names.

**Items:** 2026-11-24-repository-build-nativeaot#1

**Depends on:** Task 6

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 0 = 4

- [ ] **Step 1: Write the failing test**

- `tests/build/repository-build.acceptance.sh::A3` (integration, rows added): `Doment.Server` → Core, `Doment.Cli` → Client, `Doment.Agent` → Host; fails today because the projects do not exist.
- `tests/build/repository-build.acceptance.sh::A4` (integration, first half): for each executable, `dotnet run --project <proj> -c Release -- --version` exits 0 and prints `^<assembly name> 0\.1\.0([+-]|$)`; `-- --bogus` exits 2 with the usage line on stderr; fails today because the projects do not exist. (Task 12 replaces the `dotnet run` call with `build/check.sh aot`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/repository-build.acceptance.sh '^A(3|4):'`
Expected: both FAIL.

- [ ] **Step 3: Implement**

1. Three console projects with `PublishAot=true`, `TrimmerSingleWarn=false`, assembly names `doment-server`, `doment`, `doment-agent`, references per section 3 (simulation references come in Task 8); each `Program.cs` is a top-level `return StandardOptions.Run("<assembly name>", args, Console.Out, Console.Error);`.
2. Add them to `doment.slnx`; add the platform rows that P5 named for a `PublishAot` restore.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/repository-build.acceptance.sh '^A(2|3|4|20):'`
Expected: four PASS lines.

- [ ] **Step 5: Commit**

```bash
git add src/Doment.Server src/Doment.Cli src/Doment.Agent doment.slnx docs/third-party-exceptions.md tests/build/repository-build.acceptance.sh
git commit -m "feat(cli): add the three executables"
```

### Task 8: Simulation property

**Files:**
- Create: `build/Doment.Simulation.targets`
- Modify: `Directory.Build.targets` (import), `src/Doment.Cli/Doment.Cli.csproj`, `src/Doment.Agent/Doment.Agent.csproj`
- Test: `tests/build/run.sh` (new cases), `tests/build/repository-build.acceptance.sh` (A15, A16)

**Interfaces:**
- Consumes: C6 executable projects (Task 7).
- Produces: C2 `DomentSimulation`; C3 DOMENT030.

**Items:** 2026-11-24-repository-build-nativeaot#4

**Depends on:** Task 7

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

- `tests/build/run.sh::simulation_release_publish` (integration): given a fixture tree with a library project named `Doment.Simulation` and a console project `App` whose reference to it is conditioned on `'$(DomentSimulation)' == 'true'`, asserts `dotnet publish App -c Release -p:DomentSimulation=true` exits non-zero with exactly one `error DOMENT030: a release publish cannot include Doment.Simulation; build simulation binaries in Debug`, that `-c Debug -p:DomentSimulation=true` exits 0, and that `dotnet msbuild App -t:Publish -p:Configuration=Release -p:DomentSimulation=true` fails the same way; fails today because no target checks it.
- `tests/build/run.sh::simulation_reference_without_property` (integration): given a console project `App2` referencing a library `Mid` that unconditionally references `Doment.Simulation`, asserts `dotnet publish App2 -c Release` (property unset) fails with DOMENT030; fails today for the same reason.
- `tests/build/repository-build.acceptance.sh::A15` (integration): `Doment.Cli` and `Doment.Agent` built with `-p:DomentSimulation=true` list `Doment.Simulation.csproj` among `-getItem:ProjectReference` and `DOMENT_SIMULATION` in `-getProperty:DefineConstants`; without the property neither appears.
- `...::A16` (integration): `dotnet publish src/Doment.Cli -c Release -r linux-x64 -p:DomentSimulation=true` (and the same for `Doment.Agent`) fails with DOMENT030; `-c Debug` of the same builds succeeds (`dotnet build`, not publish, to keep the case quick).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^simulation_'; bash tests/build/repository-build.acceptance.sh '^A1[56]:'`
Expected: all fail.

- [ ] **Step 3: Implement**

1. `build/Doment.Simulation.targets`: a target `BeforeTargets="PrepareForPublish"`, when `Configuration` is not `Debug`, raising DOMENT030 if `DomentSimulation` is `true` or any `ReferencePath` item's file name is `Doment.Simulation`; `DomentSimulation` defaults to `false` when empty.
2. Root `Directory.Build.targets` imports it.
3. `Doment.Cli` and `Doment.Agent`: the conditional `ProjectReference` to `Doment.Simulation` and `DOMENT_SIMULATION` in `DefineConstants` under the same condition.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh '^simulation_' && bash tests/build/repository-build.acceptance.sh '^A(3|15|16):'`
Expected: both cases `ok`; three PASS lines.

- [ ] **Step 5: Commit**

```bash
git add build/Doment.Simulation.targets Directory.Build.targets src/Doment.Cli/Doment.Cli.csproj src/Doment.Agent/Doment.Agent.csproj tests/build/run.sh tests/build/repository-build.acceptance.sh
git commit -m "chore(build): keep simulation out of releases"
```

### Task 9: Portable platform rules

**Files:**
- Create: `build/Doment.Platform.targets`
- Modify: `Directory.Build.targets` (import it first among the new targets files)
- Modify: `tests/build/run.sh` (the `-windows` fixture cases pass `-p:DomentPlatform=windows`; new cases)
- Test: `tests/build/run.sh`, `tests/build/repository-build.acceptance.sh` (A28)

**Interfaces:**
- Consumes: root conventions (Task 4).
- Produces: C2 `DomentPlatform`; C3 DOMENT033 (target-framework finding).

**Items:** 2026-11-24-repository-build-nativeaot#2

**Depends on:** Task 8

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

- `tests/build/run.sh::portable_windows_api` (integration): given a net10.0 fixture project that calls `Microsoft.Win32.Registry.CurrentUser.OpenSubKey("x")` without a guard, asserts the build fails with an `error CA1416` line; the same project with `<NoWarn>$(NoWarn);CA1416</NoWarn>` in its own file still fails with `error CA1416`; built with `-p:DomentPlatform=linux` the `NoWarn` variant succeeds; fails today because CA1416 can be switched off by `NoWarn` (and, before Task 4's settings, was not an error).
- `tests/build/run.sh::portable_target_framework` (integration): given a fixture project targeting `net10.0-windows` (with `EnableWindowsTargeting=true`), asserts restore fails before compilation with exactly one `error DOMENT033: <name> is portable but targets net10.0-windows; portable projects target net10.0`; with `-p:DomentPlatform=windows` it builds; and the gate's generated framework-check project raises no DOMENT033 (`build/gate.sh` on a no-project stand-in exits 0); fails today because no target checks it.
- `tests/build/run.sh::portable_self_classification` (integration): given a fixture project named `App` with `<DomentPlatform>linux</DomentPlatform>` in its own file, asserts `-getProperty:DomentPlatform` prints `portable`; a project named `Doment.Agent` prints `linux`; fails today because the property does not exist.
- `tests/build/repository-build.acceptance.sh::A28` (integration): each project of `doment.slnx` reports `-getProperty:DomentPlatform` equal to its module-map Kind in `docs/architecture.md` (portable → `portable`, Linux-bound → `linux`), and `Doment.Agent` is the only `linux` one.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^portable_'; bash tests/build/repository-build.acceptance.sh '^A28:'`
Expected: all fail.

- [ ] **Step 3: Implement**

1. `build/Doment.Platform.targets`: `DomentPlatform` from C2's list (a global value wins); for `portable`, remove `CA1416` from `NoWarn`; a target with `BeforeTargets="_GenerateRestoreGraphProjectEntry;CollectPackageReferences"`, conditioned on `'$(DomentPlatform)' == 'portable' and '$(UsingMicrosoftNETSdk)' == 'true'`, raising the target-framework DOMENT033 when `TargetFramework` is not exactly `net10.0`.
2. Import it in the root `Directory.Build.targets` before the other new targets files.
3. The existing `framework_windows` and `framework_windows_api` cases (and any other `-windows` fixture) pass `-p:DomentPlatform=windows`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh && bash tests/build/repository-build.acceptance.sh '^A(2|28):'`
Expected: `0 failed`; two PASS lines.

- [ ] **Step 5: Commit**

```bash
git add build/Doment.Platform.targets Directory.Build.targets tests/build/run.sh tests/build/repository-build.acceptance.sh
git commit -m "chore(build): enforce portable platform rules"
```

### Task 10: Portable assembly check

**Files:**
- Create: `build/Doment.PortableCheck.cs`
- Modify: `build/Doment.Platform.targets` (its `UsingTask` and the post-compile target)
- Test: `tests/build/run.sh` (new case)

**Interfaces:**
- Consumes: C2 `DomentPlatform` (Task 9).
- Produces: C3 DOMENT033 (assembly findings).

**Items:** 2026-11-24-repository-build-nativeaot#2

**Depends on:** Task 9

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing test**

- `tests/build/run.sh::portable_assembly` (integration, a table of fixture rows, each a portable net10.0 library with one source file): asserts exactly one DOMENT033 line per row with the C3 text:
  - `[DllImport("libc")] static extern int getpid();` in class `Native` → `declares a native import Native.getpid from libc`;
  - `[LibraryImport("libc")] static partial int getppid();` in `partial class Native2` (with `AllowUnsafeBlocks` as the generator needs) → a line matching `declares a native import Native2\.\S+ from libc` (the source generator puts the import on a generated stub inside `Native2`, whose metadata name the check reports as it finds it);
  - `NativeLibrary.TryLoad("libc", out _)` → `references System.Runtime.InteropServices.NativeLibrary`;
  - `[assembly: System.Runtime.Versioning.SupportedOSPlatform("linux")]` → `carries the assembly attribute SupportedOSPlatform("linux")`;
  and the `DllImport` row built a second time without any change raises the same DOMENT033 again (no stamp); for each row, the same project built with `-p:DomentPlatform=linux` exits 0, a clean portable library exits 0 with no DOMENT033, and a build with `-p:DesignTimeBuild=true` raises none; fails today because nothing reads the assembly.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^portable_assembly$'`
Expected: `not ok portable_assembly`.

- [ ] **Step 3: Implement**

1. `build/Doment.PortableCheck.cs`: task `DomentPortableAssemblyCheck` (inputs: assembly path, project name) reading the ImplMap (with its MethodDef and owning TypeDef, and its ModuleRef name), the TypeRef table for `System.Runtime.InteropServices.NativeLibrary`, and the CustomAttribute rows on the Assembly whose constructor's type is `System.Runtime.Versioning.SupportedOSPlatformAttribute` (decoding its string argument from the blob). Use `System.Reflection.Metadata` if P3 passed; otherwise the netstandard 2.0 fallback reader the spec's section 5 names (the `#~`, `#Strings` and `#Blob` streams and the TypeRef, MemberRef, CustomAttribute, ImplMap, Assembly, TypeDef, MethodDef and ModuleRef tables, with coded-index and heap-size handling).
2. `build/Doment.Platform.targets`: its own `UsingTask` for the new source (with the `System.Reflection.Metadata` reference only on the P3 path); a target after `CoreCompile` (`AfterTargets="CoreCompile"`), for portable SDK projects, skipped when `DesignTimeBuild` is `true`, writing no stamp, logging every finding as DOMENT033.
3. `build/Doment.BuildChecks.cs` and its three `UsingTask`s stay unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh && bash tests/build/repository-build.acceptance.sh '^A2:'`
Expected: `0 failed`; `PASS A2: ...` (the real projects stay clean).

- [ ] **Step 5: Commit**

```bash
git add build/Doment.PortableCheck.cs build/Doment.Platform.targets tests/build/run.sh
git commit -m "chore(build): reject native calls in portable code"
```

### Task 11: Check command core

**Files:**
- Create: `build/check.sh`
- Test: `tests/build/repository-build.acceptance.sh` (A17 moved onto `check.sh test`, A18, A19)

**Interfaces:**
- Consumes: `doment.slnx` (Task 6); C2 `DomentAuditStrict`, `DomentFormatCheck`.
- Produces: C4 (steps `build` and `test`, output, exit codes, timeouts, trap; `portable` and `aot` are stubs that Task 12 fills and that this task's tests do not run).

**Items:** 2026-11-24-repository-build-nativeaot#5

**Depends on:** Task 10

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

- `tests/build/repository-build.acceptance.sh::A17` (rewritten): `build/check.sh test` exits 0 and prints `check: dotnet 10.0.4<nn> at <dir>` first, `check: test ok` and `check: 1 steps run, 0 failed`; a probe console app built under `artifacts/acceptance/` that prints `Environment.Version`, run through its apphost with `DOTNET_ROOT=<dir>` from that first line, prints 10.0.14 or later; fails today because `build/check.sh` does not exist.
- `...::A18` (integration): `build/check.sh build test` prints `check: build ok`, `check: test ok`, `check: 2 steps run, 0 failed` in that order and exits 0; `DARKRAISE_FRAMEWORK_PATH=/nonexistent build/check.sh` prints `check: build failed`, a cause line holding `DOMENT003`, `check: 1 steps run, 1 failed`, no `check: portable` line, and exits 1; `build/check.sh bogus` exits 2 with `check: unknown step 'bogus'; steps: build, portable, aot, test`. (Task 12 adds the no-argument success run with all four steps.)
- `...::A19` (integration): records the PIDs of `dotnet`, `MSBuild`, `VBCSCompiler`, `ilc` and `Doment.Core.Tests` processes before; after `build/check.sh build test` returns, after `DOMENT_CHECK_TIMEOUT=1 build/check.sh build` (which must print `timed out after 1 s:` and exit 1), and after `build/check.sh build` is sent SIGTERM two seconds into its run, asserts no process of those names exists that was not in the before-set (wait at most 10 s for each to go); fails today because `build/check.sh` does not exist.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/repository-build.acceptance.sh '^A1[789]:'`
Expected: three FAIL lines.

- [ ] **Step 3: Implement**

1. `build/check.sh` per C4: root without git; step parsing and the usage error; exports `MSBUILDDISABLENODEREUSE=1`, `DOTNET_CLI_USE_MSBUILD_SERVER=0`, `UseSharedCompilation=false` and `DOTNET_ROOT` (the directory of `readlink -f "$(command -v dotnet)"`); each call under `setsid` with `timeout -k 10 <s>` (600 s, 1200 s for a publish, or `DOMENT_CHECK_TIMEOUT`), its process group killed on expiry and by a trap on INT and TERM; the gate's logger flags (dropped on the test step if P6 said so); causes per C4 (deduplicated error lines, or the last 20 output lines when there is none, or the timeout line); `dotnet build-server shutdown` at exit.
2. Steps `build` and `test` per the spec's section 7; `portable` and `aot` print `check: <step> failed` with the cause `not implemented` until Task 12.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/repository-build.acceptance.sh '^A1[789]:'`
Expected: three PASS lines.

- [ ] **Step 5: Commit**

```bash
git add build/check.sh tests/build/repository-build.acceptance.sh
git commit -m "feat(build): add the check command"
```

### Task 12: Portable and NativeAOT steps

**Files:**
- Modify: `build/check.sh` (the `portable` and `aot` steps)
- Modify: `docs/third-party-exceptions.md` (platform rows for win-x64 restores, if P5 named any)
- Test: `tests/build/repository-build.acceptance.sh` (A4, A5, A6, A7, A18 extended, A27; the stand-in tree builder)

**Interfaces:**
- Consumes: C4 core (Task 11); C6 executables (Task 7); C2 `DomentPlatform`.
- Produces: C4 `portable` and `aot` steps.

**Items:** 2026-11-24-repository-build-nativeaot#1, 2026-11-24-repository-build-nativeaot#2, 2026-11-24-repository-build-nativeaot#4

**Depends on:** Task 11

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

The stand-in tree (spec section 10): under `artifacts/acceptance/<case>/`, copies of the root build files, `build/`, `global.json`, `.editorconfig`, `.csharpierrc`, `.csharpierignore`, `.config/`, a register of its own, a `doment.slnx` holding the fixture project, a copy of the pin, and `DARKRAISE_FRAMEWORK_PATH` set to the real framework worktree.

- `tests/build/repository-build.acceptance.sh::A4` (rewritten): `build/check.sh aot` exits 0, prints `check: aot ok`, creates `artifacts/publish/<name>/linux-x64/<name>` for `doment`, `doment-agent` and `doment-server`, and each binary's `--version` first line matches `^<name> 0\.1\.0([+-]|$)`; the publish output holds no line matching the C4 warning pattern; fails today because the step is a stub.
- `...::A5` (integration): after A4, every `obj/project.assets.json` of the three executables lists `Microsoft.DotNet.ILCompiler`, `runtime.linux-x64.Microsoft.DotNet.ILCompiler` and the linux-x64 runtime packs at a version of 10.0.14 or later, and `dotnet restore doment.slnx -p:DomentAuditStrict=true` reports no `NU190` line.
- `...::A6` (integration): a stand-in tree whose solution holds one `PublishAot` console project calling `Type.GetType(Console.ReadLine()!)!.GetMethods()`, run with the stand-in's `build/check.sh aot`, exits 1 with `check: aot failed` and a cause line naming `IL2057` or another `IL2`/`IL3` code; and the C4 warning pattern matches the recorded line `ILC : Trim analysis warning IL2026: Foo.Bar(): message`.
- `...::A7` (integration): `build/check.sh portable` exits 0 and its log shows a linux-x64 and a win-x64 build for each of `Doment.Protocol`, `Doment.Core`, `Doment.Simulation`, `Doment.Worker`, `Doment.Host`, `Doment.Client`, `Doment.Server`, `Doment.Cli`, `Doment.Core.Tests` and none for `Doment.Agent` (`check.sh` prints one `check: portable <project> <rid>` progress line per build, which the test reads).
- `...::A18` (extended): `build/check.sh` with no argument prints `check: build ok`, `check: portable ok`, `check: aot ok`, `check: test ok`, `check: 4 steps run, 0 failed` in that order and exits 0.
- `...::A27` (integration): a stand-in tree whose project references `Newtonsoft.Json` 12.0.1 and whose register lists it in table 1: a plain `dotnet build` of it exits 0 with a `warning NU1903` line; the stand-in's `build/check.sh build` exits 1 with a cause line naming `NU1903` and `GHSA-5crp-9r3c-p9vr`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/repository-build.acceptance.sh '^A(4|5|6|7|18|27):'`
Expected: FAIL for each except possibly A27 (whose `check.sh build` half already works).

- [ ] **Step 3: Implement**

1. `portable` step: list the solution's projects (`dotnet sln doment.slnx list`), read `-getProperty:DomentPlatform` for each, build each `portable` one with `-r linux-x64` and `-r win-x64` (adding `-p:PublishAot=false` for win-x64 if P5 required it), printing one `check: portable <project> <rid>` line per build.
2. `aot` step per C4: projects with `PublishAot=true`, publish, warning scan, `--version` check with the cause lines C4 names; names and version read from `-getProperty:AssemblyName` and `-getProperty:VersionPrefix`, nothing hard-coded.
3. Platform rows for any SDK-added package the win-x64 restores bring (from P5).

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/repository-build.acceptance.sh && bash build/check.sh`
Expected: `0 failed`; `check: 4 steps run, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add build/check.sh docs/third-party-exceptions.md tests/build/repository-build.acceptance.sh
git commit -m "feat(build): add portable and NativeAOT steps"
```

### Task 13: Documentation

**Files:**
- Modify: `docs/architecture.md`, `README.md`

Register rows are not edited here: every row this plan discharges already carries its acceptance numbers (rows #6 to #9 of the architecture-decisions register: A21 to A24), and dforge:finishing-a-development-branch moves them to done or verify from those cells.

**Interfaces:**
- Consumes: every Contract (documents them).
- Produces: nothing other tasks consume.

**Items:** 2026-11-24-repository-build-nativeaot#5

**Depends on:** Task 12

**Evaluation:** files 1 - spec 1 - coupling 1 - risk 0 = 3

- [ ] **Step 1: No new test, because the two files are prose that no script reads (A26 is a demo statement); `tests/build/repository-build.acceptance.sh::A28` already reads only the module map's Kind column, which this task does not change**

- [ ] **Step 2: Run the existing checks**

Run: `bash tests/build/repository-build.acceptance.sh '^A28:'`
Expected: PASS before the edit.

- [ ] **Step 3: Implement**

1. `docs/architecture.md`: the "Repository and build" section the spec's section 9 lists (toolchain and its undo, solution, the four properties, `build/check.sh`, DOMENT030 to DOMENT033, CSharpier moving with the framework); the gate section's changes (refused path characters with exit 2, the master block, line endings); the sentences section 9 names as made false; "Rules handed to later epics" with this epic's subsection replaced by the four hand-ons of section 9, including M8's `doment.exe`/`Doment.exe` rule and the `DRUI020` line.
2. `README.md`: prerequisites (SDK 10.0.404 or a later 10.0.4xx, clang, git, `tools/framework.sh sync`, `dotnet tool restore`) and the two commands (`build/check.sh`, `build/gate.sh`).

- [ ] **Step 4: Run the full suite**

Run: `bash tests/build/run.sh && bash tests/build/architecture-decisions.acceptance.sh && bash tests/build/repository-build.acceptance.sh && bash build/check.sh && DOMENT_GATE_NO_FETCH=1 bash build/gate.sh`
Expected: three suites `0 failed`; `check: 4 steps run, 0 failed`; `gate: ... 0 violations`.

- [ ] **Step 5: Commit**

```bash
git add docs/architecture.md README.md
git commit -m "docs(architecture): record the repository and build"
```
