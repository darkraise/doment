# Review record: 2026-11-24-architecture-decisions

Plan: docs/dforge/plans/2026-11-24-architecture-decisions.md
Retained: 2026-11-24

Review depth: full (spec,task-risk:2)
Acceptance QA: complete — 16 pass, 0 fail, 0 flaky, 0 cannot-test, 10 demo
final review lens security — 0 Critical, 1 Important, 0 Minor; fixed 1, rejected 0
final review lens silent-failures — 0 Critical, 2 Important, 0 Minor; fixed 1, rejected 1
final review lens test-quality — 0 Critical, 6 Important, 0 Minor; fixed 5, rejected 1
final review lens code-quality — 0 Critical, 5 Important, 0 Minor; fixed 1, rejected 4; parts lang-bash=4,docs-comments=1
Test ratio: 2351 test / 1458 code lines (abe30d2..4a8b062)
Final review: clean (commits abe30d2..4a8b062)

## Amendments

## A1 — Task 3
Reason: "extends Task 1's call" invites the pin check on the restore hook, where its result is not shared with the build phase, so DOMENT001 prints twice.
Cost if wrong: one extra inner target.
### Old
````text
2. `build/Doment.Framework.targets`: a `UsingTask` with RoslynCodeTaskFactory, `Code Type="Class" Source="$(MSBuildThisFileDirectory)Doment.BuildChecks.cs"`. `DomentFrameworkCheck` is hooked `BeforeTargets="CoreCompile"` and extends Task 1's once-per-build `MSBuild` call (Contracts) with the pin and cleanliness check. If `pin_once_per_build` counts two lines, apply the fallback Contracts names.
````
### New
````text
2. `build/Doment.Framework.targets`: a `UsingTask` with RoslynCodeTaskFactory, `Code Type="Class" Source="$(MSBuildThisFileDirectory)Doment.BuildChecks.cs"`. `DomentFrameworkCheck` is hooked `BeforeTargets="CoreCompile"`, has `DependsOnTargets="DomentPresenceCheck"`, and makes its own once-per-build `MSBuild` call (the same project file, exactly the properties and removals Contracts lists) to a second inner target that runs `DomentFrameworkState`. Task 1's pre-restore call stays presence and path only (DOMENT003, DOMENT004): restore runs as a separate build with its own global properties, so a pin check reached from the restore hook would log DOMENT001 a second time. If `pin_once_per_build` counts two lines, apply the fallback Contracts names.
````

## A2 — Task 1
Reason: Contracts' helper list includes `fixture_project` and `$DOMENT_FIXTURE_*`, which Task 5 creates; "exactly as Contracts states" makes Task 1 write them too.
Cost if wrong: none; Task 5 Step 3.3 already creates them.
### Old
````text
5. `tests/build/run.sh`: the runner and helpers exactly as Contracts states. `new_doment_repo` copies only the files that exist.
````
### New
````text
5. `tests/build/run.sh`: the runner and the helpers this task's Produces line names, exactly as Contracts states. `new_doment_repo` copies only the files that exist. `fixture_project` and the `$DOMENT_FIXTURE_*` variables are written by Task 5, not here.
````

## A3 — Task 8
Reason: the combined per-project invocation counts DOMENT001 once per project, skips package checks when the pin fails, and repeats referenced projects' pre-restore errors.
Cost if wrong: one extra `dotnet msbuild` call per tree.
### Old
````text
1. `build/gate.sh`: resolve the tree (`git -C <tree> rev-parse --show-toplevel`, exit 2 on failure). List the tracked project files with `git ls-files -z`, dropping `tests/build/fixtures/`. For each one, read `-getProperty:DomentRootTargetsImported`; anything other than `true` is DOMENT020. Otherwise run `dotnet msbuild <p> -restore -t:DomentFrameworkCheck;DomentThirdPartyCheck -p:FrameworkPinStrict=true`, print its `error DOMENT` lines, count them, and add its `DOMENT-PACKAGES` value. Write the tracked files with the extensions `.dll .exe .so .dylib .a .lib .sys .nupkg .snupkg` to a temporary list, and run `dotnet msbuild build/Gate.proj -t:DomentGateFiles` with the tree, the register (`<tree>/docs/third-party-exceptions.md`) and the list. On branch `master` or `main`, run `timeout 120 git -C <tree's framework path> fetch --quiet origin` (on failure print `gate: warning: could not fetch the framework's remote` and continue), then `git -C <tree's framework path> merge-base --is-ancestor <pin> refs/remotes/origin/master`, and report DOMENT005 when it fails. Print every violation, then the summary line.
````
### New
````text
1. `build/gate.sh`: resolve the tree (`git -C <tree> rev-parse --show-toplevel`, exit 2 on failure). List the tracked project files with `git ls-files -z`, dropping `tests/build/fixtures/`. For each one, read `-getProperty:DomentRootTargetsImported`; anything other than `true` is DOMENT020. For each other project run `dotnet msbuild <p> -restore -t:DomentThirdPartyCheck -p:FrameworkPinStrict=true`, collect its `error DOMENT` lines, and add its `DOMENT-PACKAGES` value. Then, when at least one project passed the import check, run `dotnet msbuild <first such project> -t:DomentFrameworkCheck -p:FrameworkPinStrict=true` once and collect its `error DOMENT` lines: the framework check is the same for the whole tree, and in a combined `-t:DomentFrameworkCheck;DomentThirdPartyCheck` call a pin error would skip the package check. Before counting, strip MSBuild's trailing ` [<project path>]` from every collected line and drop exact duplicates, because a restore also runs the pre-restore checks of every referenced project, so the same DOMENT003, DOMENT011 or DOMENT012 line arrives once per referencing project. Write the tracked files with the extensions `.dll .exe .so .dylib .a .lib .sys .nupkg .snupkg` to a temporary list, and run `dotnet msbuild build/Gate.proj -t:DomentGateFiles` with the tree, the register (`<tree>/docs/third-party-exceptions.md`) and the list. On branch `master` or `main`, run `timeout 120 git -C <tree's framework path> fetch --quiet origin` (on failure print `gate: warning: could not fetch the framework's remote` and continue), then `git -C <tree's framework path> merge-base --is-ancestor <pin> refs/remotes/origin/master`, and report DOMENT005 when it fails. Print every remaining violation, then the summary line.
````

## A4 — Task 8
Reason: read as a package source, "adds ... the run's packages folder" makes every gate case restore into `~/.nuget/packages`, because `gate.sh` passes no packages path.
Cost if wrong: none.
### Old
````text
Each case runs `build/gate.sh <tree>` on a `new_doment_repo` copy, synced against a stand-in framework. Its `src/App` is removed with `git rm`, its `docs/third-party-exceptions.md` is the real register with `Fx.Tool` added to table 2 as row B9, and it has a `nuget.config` that clears every source and adds only the run feed and the run's packages folder. The packages are those of Task 7.
````
### New
````text
Each case runs `build/gate.sh <tree>` on a `new_doment_repo` copy, synced against a stand-in framework. Its `src/App` is removed with `git rm`, its `docs/third-party-exceptions.md` is the real register with `Fx.Tool` added to table 2 as row B9, and it has a `nuget.config` that clears every source, adds the run feed as its only package source, and sets `globalPackagesFolder` to the run's packages folder in its `<config>` section, because `gate.sh` passes no restore properties and must not restore into `~/.nuget/packages`. The packages are those of Task 7.
````

## A5 — Task 8
Reason: after the merge to `master`, every suite run makes the gate fetch the real private framework remote.
Cost if wrong: on `master` the case depends on the local clone's `refs/remotes/origin/master` already containing the pin.
### Old
````text
- `tests/build/run.sh::gate_repository` (integration): `build/gate.sh` run on this repository gives exit 0 and a summary line with `0 violations`. It fails today because the gate does not exist.
````
### New
````text
- `tests/build/run.sh::gate_repository` (integration): `build/gate.sh` run on this repository with `DOMENT_GATE_NO_FETCH=1` gives exit 0 and a summary line with `0 violations`. When `DOMENT_GATE_NO_FETCH=1`, `gate.sh` skips its framework fetch and checks ancestry against the refs already present, so this case makes no network call when the repository is on `master`. It fails today because the gate does not exist.
````

## A6 — Task 9
Reason: `rg -c` succeeds for any count of 1 or more, so the "at least 8 level-2 headings" check asserts nothing.
Cost if wrong: none.
### Old
````text
Run: `test -f docs/architecture.md && rg -c '^## ' docs/architecture.md && bash tests/build/run.sh '^real_framework_strict$'`
Expected: the file exists with at least 8 level-2 headings, and `1 passed, 0 failed` (the worktree is back at the pin)
````
### New
````text
Run: `test -f docs/architecture.md && test "$(rg -c '^## ' docs/architecture.md)" -ge 8 && bash tests/build/run.sh '^real_framework_strict$'`
Expected: exit 0, ending with `1 passed, 0 failed` (the file has at least 8 level-2 headings and the worktree is back at the pin)
````

## A7 — Task 10
Reason: `rg -c` succeeds on any match, so "at least twice" and "one register row" are not asserted.
Cost if wrong: a legitimate second "Local worker link" line in the register fails the check, and the executor has to read the file to see why.
### Old
````text
Run: `rg -c 'R176' docs/dforge/specs/2026-11-24-doment-design.md && rg -n 'Local worker link' docs/dforge/registers/2026-11-24-m2-sessions-transport.md && rg -n 'third-party-exceptions.md' docs/dforge/specs/2026-11-24-doment-design.md`
Expected: R176 found at least twice, one register row, and the pointer present
````
### New
````text
Run: `test "$(rg -c 'R176' docs/dforge/specs/2026-11-24-doment-design.md)" -ge 2 && test "$(rg -c 'Local worker link' docs/dforge/registers/2026-11-24-m2-sessions-transport.md)" -eq 1 && rg -n 'third-party-exceptions.md' docs/dforge/specs/2026-11-24-doment-design.md`
Expected: exit 0: R176 on at least two lines, exactly one register line, and the pointer line printed
````

## A8 — Header
Reason: the real framework project's own restore needs a package the SDK adds (`IsAotCompatible=true`), which the run feed cannot supply, so `real_framework_strict` cannot pass under the offline constraint as written.
Cost if wrong: if the package is not cached, the case fails at restore and goes up as a ruling.
### Old
````text
- `tests/build/run.sh` needs no network. Fixture restores use `-p:RestoreSources=<run feed>` and `-p:RestorePackagesPath=<run temp>/pkgs`, and never touch `~/.nuget/packages` or nuget.org.
````
### New
````text
- `tests/build/run.sh` needs no network. Fixture restores use `-p:RestoreSources=<run feed>` and `-p:RestorePackagesPath=<run temp>/pkgs`, and never touch `~/.nuget/packages` or nuget.org. One exception: `real_framework_strict`, which restores the real framework, also passes `-p:RestoreAdditionalProjectFallbackFolders=$HOME/.nuget/packages` (expanded to an absolute path), so a package the SDK adds to the framework's own project (`IsAotCompatible=true` in `src/Darkraise/Darkraise.csproj` brings `Microsoft.NET.ILLink.Tasks`) resolves offline; NuGet only reads a fallback folder and never writes to it. If that case still fails at restore (NU1101 or an audit error), the package, its version and the error go up as a ruling (`scripts/plan-amend`).
````

## A9 — Header
Reason: `dotnet build` on SDK 10.0.302 overrides `-clp:NoSummary`, so diagnostics print twice; and the suite and the gate leave MSBuild nodes and the compiler server running after every run.
Cost if wrong: slower test builds; if the replacement logger hides a line the gate needs, Task 8's cases fail and one flag changes.
### Old
````text
- Every `dotnet` invocation in a script uses `-nologo -tl:off -clp:NoSummary`, so each diagnostic is printed exactly once.
````
### New
````text
- Every `dotnet` invocation in a script, including `dn` (this overrides the flag list in Contracts' `dn` line), uses `-nologo -tl:off -clp:NoSummary -noConsoleLogger "-logger:ConsoleLogger,Microsoft.Build;NoSummary;Verbosity=minimal"`, so each diagnostic is printed exactly once. `-clp:NoSummary` alone is not enough, because `dotnet build` (SDK 10.0.302) appends `-consoleloggerparameters:Summary` after it. Exception: if `build/gate.sh`'s `-getProperty:DomentRootTargetsImported` call prints nothing with the two logger flags, that call drops them and keeps `-nologo -tl:off -clp:NoSummary`, which `dotnet msbuild` honours.
- `tests/build/run.sh` and `build/gate.sh` each export `MSBUILDDISABLENODEREUSE=1`, `DOTNET_CLI_USE_MSBUILD_SERVER=0` and `UseSharedCompilation=false` before their first `dotnet` call, so a run leaves no MSBuild node or compiler server running, whether the gate is called from the suite or on its own. Neither script calls `dotnet build-server shutdown`, which would also stop servers the user started.
````
