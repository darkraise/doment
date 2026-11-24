# Architecture decisions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: dforge:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record doment's architecture, reference darkraise-framework through a pinned per-checkout worktree with build checks, and make the build fail on any third-party package the exception register does not list.

**Architecture:** Root MSBuild files import two check files from `build/`: the framework checks (presence, override, pin and cleanliness) and the third-party check. Both use one inline C# task source, `build/Doment.BuildChecks.cs`, compiled by MSBuild's RoslynCodeTaskFactory, so they need nothing beyond the .NET SDK and git. `tools/framework.sh` manages the framework worktree. `build/gate.sh` is the gate command. `tests/build/run.sh` proves all of it on stand-in repositories and fixture trees. Two documents record the decisions, and the product spec is amended.

**Tech Stack:** .NET SDK 10.0.302 (MSBuild 17/18 with RoslynCodeTaskFactory), bash 5, git 2.x.

**Spec:** docs/dforge/specs/2026-11-24-architecture-decisions-design.md

**Execution:** inline — `claude --model opus --effort high` — the highest task total is 8, and two tasks carry risk 3 (they guard framework work against loss)

**Parallelism:** sequential — inline execution

**Task check:** none — full suite every 3 tasks

**Integration check:** `bash tests/build/run.sh`

**CI:** none

**Worktree setup:** none

**Plan review:** 2026-11-24 — dforge:judge-opus — executability 10 / coherence 12 / coverage 17 / assumptions 11 (round 1)

## Global Constraints

- English only: code, comments, docs, commits, errors, tests.
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period, with no attribution lines.
- Never push in either repository. Never switch or create branches in the framework's primary checkout `/root/repositories/darkraise-framework`; framework work happens in doment's framework worktree only.
- Every `dotnet` and network `git` call in a script carries a `timeout` (600 seconds for `dotnet`, 120 seconds for `git fetch`).
- `tests/build/run.sh` needs no network. Fixture restores use `-p:RestoreSources=<run feed>` and `-p:RestorePackagesPath=<run temp>/pkgs`, and never touch `~/.nuget/packages` or nuget.org.
- Every `dotnet` invocation in a script uses `-nologo -tl:off -clp:NoSummary`, so each diagnostic is printed exactly once.
- The check needs nothing beyond the .NET SDK, plus git for the pin check: no NuGet package, no compiled task assembly, no other runtime.
- Initial pin: `e3cb121d83147eef363559d6f6bd4becda4b9e89` (the framework's remote master on 2026-11-24).
- Allowed framework projects, relative to `$(DarkraiseFrameworkPath)`: `src/Darkraise/Darkraise.csproj` from any project; `src/Darkraise.Win32UI/Darkraise.Win32UI.csproj` and `src/Darkraise.Win32UI.Generators/Darkraise.Win32UI.Generators.csproj` only from a project whose `TargetFramework` starts with `net10.0-windows`.
- Classification: a project ships unless its path relative to `$(DomentRepoRoot)` starts with `tests/` or `tools/`.
- Clean framework tree (one definition, used by the build check, `sync`, `pin` and `release`): `git -C <worktree> status --porcelain=v1 --ignored=matching --untracked-files=all` prints no line except `!!` lines whose path has a segment named exactly `bin`, `obj`, `.vs` or `.idea`. The first offending path is the path of the first other line, in git's output order.
- Reachable HEAD: `git -C <worktree> for-each-ref --contains HEAD refs/heads refs/remotes` prints at least one ref. Never use `git branch --contains`, which lists a detached HEAD itself.
- Scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`; diagnostics go to stderr.

## Contracts

**MSBuild properties** (defaults set in root `Directory.Build.props` only when the property is empty, so a fixture's own props can set them first and then import the root file):

| Property | Default | Meaning |
|---|---|---|
| `DomentRepoRoot` | `$(MSBuildThisFileDirectory)` of the root props | Checkout root, trailing slash |
| `DarkraiseFrameworkPath` | `$(DARKRAISE_FRAMEWORK_PATH)` when set, else `$(DomentRepoRoot)external/darkraise-framework` | Framework worktree; an explicitly set property wins over the environment variable |
| `DomentFrameworkPinFile` | `$(DomentRepoRoot)build/darkraise-framework.pin` | Pin file |
| `FrameworkPinStrict` | `false` | `true` turns DOMENT001 and DOMENT002 into errors |
| `DomentRegisterFile` | `$(DomentRepoRoot)docs/third-party-exceptions.md` | Exception register |
| `DomentBuildOnly` | `true` when the project path relative to `DomentRepoRoot` starts with `tests/` or `tools/`, else `false` | Classification |
| `WarningsNotAsErrors` | appended with `DOMENT001;DOMENT002` | Keeps those two out of "warnings as errors" |
| `DomentRootTargetsImported` | `true`, set by root `Directory.Build.targets` | Read by the gate with `-getProperty` |

**Diagnostics.** Every message starts with its code. `<path>` is the full path. `<register>` is `$(DomentRegisterFile)`.

| Code | Kind | Message |
|---|---|---|
| DOMENT001 | warning; error when strict | Off the pin: `darkraise-framework at <path> is at <actual>, but the pin is <pinned>`, followed by `; not clean, first: <relative path>` when the tree is also not clean. At the pin but not clean: `darkraise-framework at <path> is at the pin <pinned> but not clean, first: <relative path>` |
| DOMENT002 | warning; error when strict | `darkraise-framework at <path> cannot be verified: <not a git checkout\|git not found>` |
| DOMENT003 | error, before restore | `darkraise-framework not found at <path>; run tools/framework.sh sync` |
| DOMENT004 | error, before restore | `<DarkraiseFrameworkPath\|DARKRAISE_FRAMEWORK_PATH> must be an absolute path, got '<value>'` |
| DOMENT006 | error | `<pin file> must hold one full 40-character commit hash` |
| DOMENT010 | error | `<project>: package <id> <version> is in no table of <register> (<how>)` |
| DOMENT011 | error | `<project> ships but resolves build-and-test-only package <id> <version>, row <B-id> of <register> (<how>)` or `<project> ships but references build-only project <path>` |
| DOMENT012 | error, before restore | `<project>: project reference <path> is not an allowed darkraise-framework project` |
| DOMENT013 | error | `<register>: <problem>`, where `<problem>` is `table '<heading>' is missing`, `table '<heading>' has no column '<column>'`, `duplicate ID <id>` or `row <id>, column '<column>' is empty` |
| DOMENT005 | gate error | `pin <pinned> is not an ancestor of the framework's origin/master` |
| DOMENT020 | gate error | `<project> does not import the root Directory.Build.targets` |
| DOMENT021 | gate error | `.config/dotnet-tools.json: tool <id> is not a build-and-test-only row of <register>` |
| DOMENT022 | gate error | `<file> is a tracked binary that no row of <register> lists` |

`<how>` is `direct reference`, `through <direct package id>` or `through project <project name>`. For a package reached several ways, it names the first direct reference in the order of the assets file.

**Targets.** The framework checks run once per build through one `MSBuild` task call, which Task 1 creates and Task 3 extends. It calls `build/Doment.Framework.targets` itself as a project with exactly these properties: `DomentCheckPath` (the resolved framework path), `DomentCheckPathSource` (`property`, `environment` or `default`), `DomentCheckPathValue` (the raw value), `DomentCheckPinFile` and `DomentCheckStrict`. It removes `TargetFramework`, `RuntimeIdentifier`, `SelfContained`, `Configuration`, `Platform` and `SolutionDir`. MSBuild caches that call's result for the build, so every project shares it. Fallback, if Task 3's two-project case still counts two DOMENT001 lines: the task also keeps a build-lifetime registered task object (`IBuildEngine4.RegisterTaskObject` with `RegisteredTaskObjectLifetime.Build`), keyed by path and pin, and logs only the first time. If that still logs twice under `-m`, the dedup approach goes up as a ruling (`scripts/plan-amend`) rather than weakening the test. `DomentFrameworkCheck` (presence, path, pin, cleanliness) runs from the pre-restore hook for DOMENT003 and DOMENT004, and `BeforeTargets="CoreCompile"` for DOMENT001, DOMENT002 and DOMENT006. It can also be called alone with `-t:DomentFrameworkCheck`. `DomentPresenceCheck` (Task 1's part of the framework check) and `DomentReferenceCheck` run from a hook before restore; `DomentReferenceCheck` can also be called alone with `dotnet msbuild <project> -t:DomentReferenceCheck`, which needs no restore. `DomentThirdPartyCheck` runs after `ResolvePackageAssets` in every build, can be called with `dotnet msbuild <project> -restore -t:DomentThirdPartyCheck`, and logs `DOMENT-PACKAGES: <n>` at high importance (n = distinct package IDs in the assets file).

**Register format** (`docs/third-party-exceptions.md`). Three level-2 headings, each followed by one Markdown table with exactly these columns in this order:

- `## Exceptions`: `ID | Component | Packages or files | Used for | Reason | Licence | Behind | Replacement | Approved`
- `## Build-and-test-only tools`: `ID | Component | Packages or tool | Used for | Licence | Approved`
- `## Platform packages`: `Package | Added by | First seen`

IDs are `X<n>` (table 1) and `B<n>` (table 2). A packages cell is a comma-separated list of backticked entries, or `-` when the component has nothing in the repository yet. An entry is an exact package ID, a file path, or a prefix followed by `.*`, which matches IDs that start with the prefix and a dot. Matching is case-insensitive. Every cell of tables 1 and 2 is required to be non-empty. Text outside the three tables is free prose.

**`tools/framework.sh`.** `sync | pin | release`; exit 0 on success, 1 on a refusal or failure, 2 on bad usage. Messages to stderr start with `framework.sh: `.

- Worktree path: `$DARKRAISE_FRAMEWORK_PATH` when set, else `<git toplevel>/external/darkraise-framework`.
- Framework clone: `$DARKRAISE_FRAMEWORK_REPO` when set, else `<parent of the primary checkout>/darkraise-framework`. The primary checkout is the directory that holds `git rev-parse --path-format=absolute --git-common-dir`.
- Refusal messages: `framework.sh: <path> is not clean (first: <relative path>)` and `framework.sh: <path> HEAD <commit> is on no framework branch or remote-tracking ref`. A missing clone gives `framework.sh: no darkraise-framework clone at <env value or (unset)> or <default path>`.
- `pin` warning: `framework.sh: warning: <commit> is not on any branch of the framework's remote`.

**`build/gate.sh [<tree>]`.** `<tree>` defaults to the repository that holds the script. It checks every git-tracked `*.csproj`, `*.fsproj` and `*.vbproj` under the tree, except those under `tests/build/fixtures/`. It prints every violation, then `gate: <p> projects checked, <k> packages seen, <v> violations`. Exit 0 when v is 0, 1 when it is not, 2 when `<tree>` is not a git work tree. `<k>` is the sum of the `DOMENT-PACKAGES` counts. Binaries and tools are checked by `dotnet msbuild build/Gate.proj -t:DomentGateFiles` with the tree, the register and a file listing the tracked binaries.

**`tests/build/run.sh [<regex>]`.** It runs every case whose name matches the extended regex (all cases when none is given). Each case prints `ok <case>` or `not ok <case>: <reason>`. The run ends with `<p> passed, <f> failed` and exits 0 only when f is 0. The run's temporary root is removed on exit. Shared helpers, defined once and used by every task:

- `new_framework_repo <dir>` makes a stand-in framework repository on `master` with a bare `origin`, pushed and fetched, so `refs/remotes/origin/master` exists. It holds an empty root `Directory.Build.props`, a `.gitignore` with `*.user`, `bin/`, `obj/`, `docs/dforge/` and `.worktrees/`, `src/Darkraise/Darkraise.csproj` (a `net10.0` library) with `src/Darkraise/Class1.cs`, `src/Darkraise.Api/Darkraise.Api.csproj` (`net10.0`, a disallowed project), `src/Darkraise.Win32UI/Darkraise.Win32UI.csproj` (`net10.0-windows`, `EnableWindowsTargeting=true`) and `src/Darkraise.Win32UI.Generators/Darkraise.Win32UI.Generators.csproj` (`netstandard2.0`). It prints the commit.
- `new_doment_repo <dir> <pin>` makes a stand-in doment git repository with `git init -b master`. It copies the real root `Directory.Build.props`, `Directory.Build.targets`, `.gitignore`, `build/`, `external/` and `tools/`, and, once it exists (Task 5), `tests/build/fixtures/register-valid/register.md` as its `docs/third-party-exceptions.md`. It writes `<pin>` to the pin file, adds `src/App/App.csproj` (a `net10.0` console app referencing `$(DarkraiseFrameworkPath)/src/Darkraise/Darkraise.csproj`) and commits.
- `dn <args>` runs `timeout 600 dotnet <args> -nologo -tl:off -clp:NoSummary` with the run's restore sources and packages path, and captures the output in `$OUT` and the exit code in `$RC`.
- `expect_rc <n>`, `expect_out <regex>`, `expect_no_out <regex>` and `expect_count <regex> <n>` assert on the last capture.
- `$DOMENT_FIXTURE_FRAMEWORK`, `$DOMENT_FIXTURE_PIN` and `$DOMENT_FIXTURE_PIN_FILE` are a stand-in framework repository made once per run, its commit and a pin file holding it. The fixture root props read them, so third-party fixtures pass the framework check silently.
- A case may print `note <case>: <text>` lines; the runner passes them through.

**Fixture trees.** Committed under `tests/build/fixtures/` are: `Directory.Build.props`, `Directory.Build.targets`, `nuget.config` (it clears every package source) and `register-valid/register.md`. Every case is generated by run.sh into `tests/build/fixtures/.run/<case>/`, which is git-ignored and emptied at the start and end of each run. A case holds `register.md` (a copy of `register-valid/register.md`, edited or given extra rows per case) and its projects, written by the helper `fixture_project <case> <relative dir> <target framework> [package=<id>/<version> | project=<path>]...`. The fixture props set `DomentRepoRoot` to the nearest directory above the project that holds `register.md` (`$([MSBuild]::GetDirectoryNameOfFileAbove($(MSBuildProjectDirectory), register.md))/`). They set `DomentRegisterFile=$(DomentRepoRoot)register.md`, and take `DarkraiseFrameworkPath` and `DomentFrameworkPinFile` from the run's `$DOMENT_FIXTURE_FRAMEWORK` and `$DOMENT_FIXTURE_PIN_FILE` (a file holding `$DOMENT_FIXTURE_PIN`). They then import the root `Directory.Build.props`; the fixture targets import the root `Directory.Build.targets`.

## Assumptions (evidence)

- RoslynCodeTaskFactory compiles a `Type="Class"` task from a separate source file (`<Code Source=...>`) with the default references, runs it in `dotnet build`, and `Log.LogError` with a code prints `error DOMENT010: ...`. Probe on 2026-11-24, SDK 10.0.302: a throwaway `Check.cs` task read `obj/project.assets.json` and logged the error.
- The inline task cannot use System.Text.Json: a `Reference` to it fails with MSB3755 by name, and with CS0012 and CS0518 by targeting-pack path (probes on 2026-11-24). `Doment.BuildChecks.cs` therefore carries its own small JSON reader for `project.assets.json` and `.config/dotnet-tools.json`.
- The SDK's `PackageDependencies` items carry package names only, and `_PackageDependenciesDesignTime` holds only top-level packages. A probe with packed `Fx.A -> Fx.B` printed `PD Fx.A`, `PD Fx.B` and `DT Fx.A/1.0.0` with empty metadata on 2026-11-24. Versions and "how it arrived" therefore come from the assets file (`libraries`, `targets`, `project.frameworks.*.dependencies`).
- A target with `BeforeTargets="_GenerateRestoreGraphProjectEntry;CollectPackageReferences"` runs before restore, and its `<Error>` stops a build whose `ProjectReference` points at a missing project, with only that error. Probe on 2026-11-24.
- `dotnet pack` of a generated project into a folder, followed by a restore with only that folder as a source, works offline. Probe on 2026-11-24: `Fx.A` and `Fx.B` packed and restored.
- Restoring a `net10.0-windows` project on Linux needs `Microsoft.WindowsDesktop.App.Ref` from a feed, which is not cached (NU1100 in a probe on 2026-11-24). Windows-targeted fixtures therefore run only `-t:DomentReferenceCheck` and never restore.
- `dotnet msbuild <project> -getProperty:<name>` prints the evaluated value (it printed `true` in a probe on 2026-11-24).
- The framework at the pin has no `Directory.Build.targets` or `Directory.Packages.props`, and its `.gitattributes` routes only `tests/assets/verification/corpus/**` through LFS. git-lfs is not installed (`git lfs` is "not a git command"), so a checkout writes pointer files; `sync` still sets `GIT_LFS_SKIP_SMUDGE=1` for machines that have it. Read on 2026-11-24.
- Building a doment project against the real framework at the pin restores no package (`src/Darkraise` has no `PackageReference`). Unverified — Task 3 verifies it with its real-framework case; if a package appears, Task 6 lists it under platform packages when it meets the membership test.
- MSBuild caches one target result per project file and global property set for a whole build, so a single `MSBuild` task call made from every project logs DOMENT001 once. Unverified — Task 3 verifies it with its two-project case.
- On the Files axis, the empty `external/` stubs, the one-line root import and `.gitignore` entries are counted as configuration, not as decisions.
- Plan review round 1 scored executability 10, coherence 12 and assumptions 11 (borderline). Decision: proceed without a second round. Every Important finding was fixed in place: the fixture layout and generation, `.gitignore` build output, the once-per-build call's exact properties and fallback, the gate's pin check, the "not a git checkout" test, the real-framework package note, the framework branch cut from `master`, and `Class1.cs` in the helper. No Critical finding was raised.

## Task index

1. Framework path property and presence checks
2. framework.sh sync and the pin file
3. Pin and cleanliness check
4. framework.sh pin and release
5. Register parser
6. The exception register
7. Package and project reference checks
8. Gate command
9. Architecture record
10. Product spec amendments

---

### Task 1: Framework path property and presence checks

**Files:**
- Create: `Directory.Build.props`
- Create: `Directory.Build.targets`
- Create: `build/Doment.Framework.targets`
- Create: `external/Directory.Build.targets`
- Create: `external/Directory.Packages.props`
- Modify: `.gitignore`
- Create: `tests/build/run.sh`

**Interfaces:**
- Consumes: none
- Produces: Contracts, the MSBuild properties table; DOMENT003 and DOMENT004; `DomentPresenceCheck`; the `tests/build/run.sh` runner and its helpers `new_framework_repo`, `new_doment_repo`, `dn`, `expect_rc`, `expect_out`, `expect_no_out` and `expect_count`.

**Items:** 3

**Depends on:** none

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

- `tests/build/run.sh::presence_missing` (integration): given `new_doment_repo` with no `external/darkraise-framework`, `dn build src/App` gives rc 1, exactly one line matching `error DOMENT003: darkraise-framework not found at .*/external/darkraise-framework; run tools/framework.sh sync`, and no `NU1105` or `MSB` error line. It fails today because no root build files exist.
- `tests/build/run.sh::override_relative` (integration): with `-p:DarkraiseFrameworkPath=../fw`, rc 1 and one line `error DOMENT004: DarkraiseFrameworkPath must be an absolute path, got '../fw'`. With the environment variable `DARKRAISE_FRAMEWORK_PATH=fw` and no property, rc 1 and `error DOMENT004: DARKRAISE_FRAMEWORK_PATH must be an absolute path, got 'fw'`. It fails today because nothing checks the value.
- `tests/build/run.sh::override_absolute_precedence` (integration): given a `new_framework_repo` at `$T/fw` and the environment variable `DARKRAISE_FRAMEWORK_PATH=$T/nowhere`, a build with `-p:DarkraiseFrameworkPath=$T/fw` gives rc 0. The same build without the property gives rc 1 with DOMENT003 naming `$T/nowhere`. It fails today because the property does not exist.
- `tests/build/run.sh::default_path_builds` (integration): given a `git worktree add --detach` of a `new_framework_repo` at `<doment>/external/darkraise-framework`, `dn build src/App` gives rc 0, and `git status --porcelain` in the doment repository prints nothing, so the worktree is ignored. It fails today because there is no default path.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh 'presence_missing|override_relative|override_absolute_precedence|default_path_builds'`
Expected: FAIL, 4 `not ok` lines. Write the runner, its helpers and these four cases first; the root build files do not exist yet.

- [ ] **Step 3: Implement**

1. Root `Directory.Build.props`: set the Contracts properties `DomentRepoRoot`, `DarkraiseFrameworkPath` (normalised with a trailing slash), `DomentFrameworkPinFile`, `FrameworkPinStrict`, `DomentRegisterFile` and `DomentBuildOnly`, and append `DOMENT001;DOMENT002` to `WarningsNotAsErrors`. Remember which source set the framework path (property, environment variable or default), so DOMENT004 can name it.
2. Root `Directory.Build.targets`: set `DomentRootTargetsImported=true` and import `build/Doment.Framework.targets`.
3. `build/Doment.Framework.targets`: `DomentPresenceCheck` hooked `BeforeTargets="_GenerateRestoreGraphProjectEntry;CollectPackageReferences"`. It makes the once-per-build `MSBuild` call of Contracts, with every property that call lists, so a multi-project build prints one error. The called target uses `[System.IO.Path]::IsPathRooted` on `DomentCheckPathValue` for DOMENT004, naming the source, then checks that the directory exists for DOMENT003.
4. `external/Directory.Build.targets` is `<Project />` and `external/Directory.Packages.props` is `<Project />`. `.gitignore` gains `/external/darkraise-framework/`, `bin/`, `obj/` and `/tests/build/fixtures/.run/`.
5. `tests/build/run.sh`: the runner and helpers exactly as Contracts states. `new_doment_repo` copies only the files that exist.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh 'presence_missing|override_relative|override_absolute_precedence|default_path_builds'`
Expected: `4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add Directory.Build.props Directory.Build.targets build/Doment.Framework.targets external .gitignore tests/build/run.sh
git commit -m "feat(build): add framework path and presence checks"
```

### Task 2: framework.sh sync and the pin file

**Files:**
- Create: `tools/framework.sh`
- Create: `build/darkraise-framework.pin`
- Modify: `tests/build/run.sh`

**Interfaces:**
- Consumes: Contracts, the `tests/build/run.sh` helpers (Task 1)
- Produces: Contracts, `tools/framework.sh` (the `sync` verb, the worktree and clone resolution, the clean and reachable definitions in Global Constraints); the pin file format (one line, 40 lowercase hex characters, newline-terminated)

**Items:** 3

**Depends on:** Task 1

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 3 = 8

**Lenses:** lang-bash, silent-failures

- [ ] **Step 1: Write the failing test**

- `tests/build/run.sh::sync_creates` (integration): given `new_framework_repo $T/darkraise-framework` (commit C1) and `new_doment_repo $T/doment C1` with `DARKRAISE_FRAMEWORK_REPO` unset, `tools/framework.sh sync` gives exit 0. Afterwards `git -C external/darkraise-framework rev-parse HEAD` is C1, `git -C external/darkraise-framework symbolic-ref -q HEAD` fails because HEAD is detached, and `dn build src/App` gives rc 0. It fails today because the script does not exist.
- `tests/build/run.sh::sync_moves_clean` (integration): after `sync_creates`, add commit C2 on the stand-in framework's `master` and write C2 to the pin. `sync` gives exit 0, the worktree HEAD is C2, and the framework's `refs/heads/master` is unchanged (C2). With a branch `feature` checked out in the worktree at C2, writing C1 to the pin and running `sync` gives exit 0: HEAD is detached at C1 and `refs/heads/feature` is still C2. It fails today because the script does not exist.
- `tests/build/run.sh::sync_refuses` (integration): three sub-cases on a synced worktree, after each of which the worktree HEAD and files are unchanged. (a) A modified tracked file gives exit 1 and stderr `framework.sh: <path> is not clean (first: src/Darkraise/<file>)`. (b) An ignored `docs/dforge/note.md` gives exit 1 and a not-clean message naming `docs/dforge/`, while an ignored `src/Darkraise/obj/x` alone does not block. (c) A commit made on the detached HEAD gives exit 1 and stderr matching `HEAD [0-9a-f]{40} is on no framework branch or remote-tracking ref`. It fails today because the script does not exist.
- `tests/build/run.sh::sync_fetches` (integration): given the stand-in clone made with `git clone` of the bare origin, a commit C3 pushed to origin from another clone, and C3 in the pin, `sync` gives exit 0 with HEAD at C3. It fails today because the script does not exist.
- `tests/build/run.sh::sync_no_clone` (integration): with no framework clone beside the doment repository and `DARKRAISE_FRAMEWORK_REPO=$T/none`, `sync` gives exit 1 and stderr `framework.sh: no darkraise-framework clone at $T/none or $T/darkraise-framework`. It fails today because the script does not exist.
- `tests/build/run.sh::sync_linked_worktree` (integration): given a linked doment worktree `$T/doment-wt` (from `git worktree add`), `sync` there creates `$T/doment-wt/external/darkraise-framework`, separate from the primary checkout's, found through the clone beside the primary checkout. `dn build src/App` gives rc 0 in both checkouts. It fails today because the script does not exist.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^sync_'`
Expected: FAIL, 6 `not ok` lines (`tools/framework.sh` not found)

- [ ] **Step 3: Implement**

1. `tools/framework.sh` with `sync` and a `usage` that prints the three verbs and exits 2; `pin` and `release` exit 2 with "not implemented" until Task 4. Resolve the worktree and clone exactly as Contracts says.
2. `sync`: first run `git worktree prune` in the clone (every time, as the spec says). When the worktree directory is missing, run `git -C <clone> worktree add --detach <path> <pin>`. When it exists, refuse unless it is clean and its HEAD is reachable (Global Constraints), then `git switch --detach <pin>`. Before either, if `git -C <clone> cat-file -e <pin>^{commit}` fails, run `timeout 120 git -C <clone> fetch --quiet origin`, and fail with `framework.sh: commit <pin> is not in <clone> or its remote` when it is still missing. Export `GIT_LFS_SKIP_SMUDGE=1`. Never run `reset`, `branch -f`, `branch -D` or `checkout -B`.
3. `build/darkraise-framework.pin` contains `e3cb121d83147eef363559d6f6bd4becda4b9e89` and a newline.
4. Run `tools/framework.sh sync` in this checkout. It creates `external/darkraise-framework` at the real pin from `/root/repositories/darkraise-framework` and is the only change to the real framework repository (one worktree entry). Confirm `git -C /root/repositories/darkraise-framework branch --show-current` still prints `master`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh` (the integration check: the full suite runs after every third task)
Expected: `10 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add tools/framework.sh build/darkraise-framework.pin tests/build/run.sh
git commit -m "feat(tools): add framework.sh sync and the pin"
```

### Task 3: Pin and cleanliness check

**Files:**
- Create: `build/Doment.BuildChecks.cs`
- Modify: `build/Doment.Framework.targets`
- Modify: `tests/build/run.sh`

**Interfaces:**
- Consumes: Contracts, the pin file format and the clean definition (Task 2)
- Produces: Contracts, DOMENT001, DOMENT002, DOMENT006 and `DomentFrameworkCheck`; `build/Doment.BuildChecks.cs` as the one inline task source, which Tasks 5, 7 and 8 extend

**Items:** 3

**Depends on:** Task 2

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6
**Approach:** inline - skip 5: not load-bearing; the mechanism is confined to build files and its behaviour is fixed by A13

- [ ] **Step 1: Write the failing test**

- `tests/build/run.sh::pin_mismatch` (integration): given a synced stand-in at C1 and a pin of C2, `dn build src/App` gives rc 0 and exactly one line matching `warning DOMENT001: darkraise-framework at .* is at C1, but the pin is C2` (with the real hashes). With `-p:FrameworkPinStrict=true`, rc 1 and the same text as `error DOMENT001`. With `-p:TreatWarningsAsErrors=true` and without strict mode, rc 0 and still a warning. It fails today because nothing compares the commit.
- `tests/build/run.sh::pin_not_clean` (integration): one table of rows, each applied to a fresh synced stand-in at the pin: a modified `src/Darkraise/Class1.cs`, a staged new file, an untracked `src/Darkraise/New.cs`, a modified root `Directory.Build.props`, and an ignored `src/Darkraise/Darkraise.csproj.user`. For each row an ordinary build gives rc 0 with one line `warning DOMENT001: darkraise-framework at <path> is at the pin <pin> but not clean, first: <that path>`, and a strict build gives rc 1. One more row combines a moved HEAD with an untracked file and expects the off-pin text ending `; not clean, first: <that path>`. A control row with only `src/Darkraise/obj/` and `bin/` content gives rc 0 and no DOMENT001 in strict mode. It fails today because cleanliness is not checked.
- `tests/build/run.sh::pin_unverifiable` (integration): two rows. In one, a plain copy of the stand-in without `.git` is placed outside any repository and passed with `-p:DarkraiseFrameworkPath=`. In the other, the plain copy sits at the default `<stand-in doment>/external/darkraise-framework`, inside doment's own git tree. Each gives rc 0 with one `warning DOMENT002: ... cannot be verified: not a git checkout` and no DOMENT001, and a strict build gives rc 1. It fails today because nothing checks for git.
- `tests/build/run.sh::pin_malformed` (integration): with a pin file holding `abc`, rc 1 and `error DOMENT006`. It fails today because the pin is not read.
- `tests/build/run.sh::pin_once_per_build` (integration): with pin C2 and the worktree at C1, a stand-in doment repository with `src/App` and `src/Lib`, both referencing the framework core and joined by `App.slnx`, gets `dn build App.slnx -m`: `expect_count 'warning DOMENT001' 1`. It fails today because nothing checks the pin.
- `tests/build/run.sh::two_pins_strict` (integration): a stand-in doment primary checkout pinned to C1 and a linked worktree pinned to C2, each synced, both give rc 0 with `-p:FrameworkPinStrict=true` and no DOMENT001. It fails today because strict mode does not exist.
- `tests/build/run.sh::real_framework_strict` (integration): a temporary project importing this repository's root build files, with `-p:DarkraiseFrameworkPath=<repo>/external/darkraise-framework` and the real pin file, references the real `src/Darkraise/Darkraise.csproj`. `dn build -p:FrameworkPinStrict=true` gives rc 0 and no `DOMENT` line. It fails today because nothing checks the pin. The case prints `note real_framework_strict: packages: <comma-separated package IDs from the libraries of type package in its project.assets.json, or none>`, which Task 6 reads.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^(pin_(mismatch|not_clean|unverifiable|malformed|once_per_build)|two_pins_strict|real_framework_strict)$'`
Expected: FAIL, 7 `not ok` lines

- [ ] **Step 3: Implement**

1. `build/Doment.BuildChecks.cs`: a `DomentFrameworkState` task (inputs: framework path, pin file, strict flag). It reads and validates the pin, and treats the path as a git checkout only when `git -C <path> rev-parse --show-toplevel` prints that same path (so a plain directory inside doment's tree is not mistaken for one). It runs `git` through `System.Diagnostics.Process` for `rev-parse HEAD` and the clean status of Global Constraints, and logs DOMENT001, DOMENT002 or DOMENT006 with the Contracts text. It logs an error instead of a warning when strict. A missing `git` executable gives DOMENT002 `git not found`.
2. `build/Doment.Framework.targets`: a `UsingTask` with RoslynCodeTaskFactory, `Code Type="Class" Source="$(MSBuildThisFileDirectory)Doment.BuildChecks.cs"`. `DomentFrameworkCheck` is hooked `BeforeTargets="CoreCompile"` and extends Task 1's once-per-build `MSBuild` call (Contracts) with the pin and cleanliness check. If `pin_once_per_build` counts two lines, apply the fallback Contracts names.
3. Remove the temporary project and its `obj` after the real-framework case. That case must not write into the real framework worktree except `bin/` and `obj/`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh '^(pin_(mismatch|not_clean|unverifiable|malformed|once_per_build)|two_pins_strict|real_framework_strict)$'`
Expected: `7 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add build/Doment.BuildChecks.cs build/Doment.Framework.targets tests/build/run.sh
git commit -m "feat(build): check framework pin and cleanliness"
```

### Task 4: framework.sh pin and release

**Files:**
- Modify: `tools/framework.sh`
- Modify: `tests/build/run.sh`

**Interfaces:**
- Consumes: Contracts, `tools/framework.sh` and its clean and reachable checks (Task 2)
- Produces: Contracts, the `pin` and `release` verbs

**Items:** 3

**Depends on:** Task 2

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 3 = 7

**Lenses:** lang-bash, silent-failures

- [ ] **Step 1: Write the failing test**

- `tests/build/run.sh::pinverb_records` (integration): on a synced worktree, a commit C2 on a new framework branch `feature` that was never pushed. `tools/framework.sh pin` gives exit 0, the pin file is exactly `C2\n`, and stderr has `framework.sh: warning: C2 is not on any branch of the framework's remote`. After pushing `feature` to the stand-in origin and fetching, `pin` gives exit 0 with no warning. It fails today because `pin` exits 2.
- `tests/build/run.sh::pinverb_refuses_dirty` (integration): with an untracked `src/Darkraise/New.cs`, `pin` gives exit 1 with the not-clean message, and the pin file is unchanged. It fails today because `pin` exits 2.
- `tests/build/run.sh::release_refuses` (integration): one row per state, each on a freshly synced worktree: a modified tracked file, a staged file, an untracked file, an ignored `docs/dforge/plan.md`, an ignored `.worktrees/x/file`, and a commit made on the detached HEAD. For each row `release` gives exit 1, stderr names the first offending path (or matches `HEAD [0-9a-f]{40} is on no framework branch or remote-tracking ref` for the commit row), the worktree directory and its files still exist, and `git -C <clone> worktree list` still lists it. It fails today because `release` exits 2.
- `tests/build/run.sh::release_removes_clean` (integration): a synced worktree with only `src/Darkraise/obj/` and `bin/` content gives exit 0. The directory is gone and `git -C <clone> worktree list --porcelain` no longer lists the path. A HEAD that is detached at a commit of branch `feature`, checked out in no worktree, is also released. Running `release` again gives exit 0 with `framework.sh: no framework worktree at <path>`. It fails today because `release` exits 2.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^(pinverb_|release_)'`
Expected: FAIL, 4 `not ok` lines

- [ ] **Step 3: Implement**

1. `pin`: refuse a worktree that is not clean. Otherwise write `git rev-parse HEAD` and a newline to the pin file of the checkout's toplevel. Then run `timeout 120 git fetch --quiet origin` in the worktree (a failed fetch prints `framework.sh: warning: could not fetch the framework's remote` and continues), and warn as Contracts says when `for-each-ref --contains <commit> refs/remotes` prints nothing.
2. `release`: exit 0 with the "no framework worktree" message when the path does not exist. Refuse when the tree is not clean or HEAD is not reachable, naming the path or the commit. Otherwise run `git -C <clone> worktree remove <path>`, without `--force`.
3. Leave `sync` unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh '^(pinverb_|release_)'`
Expected: `4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add tools/framework.sh tests/build/run.sh
git commit -m "feat(tools): add framework.sh pin and release"
```

### Task 5: Register parser

**Files:**
- Modify: `build/Doment.BuildChecks.cs`
- Create: `build/Doment.ThirdParty.targets`
- Modify: `Directory.Build.targets`
- Create: `tests/build/fixtures/Directory.Build.props`
- Create: `tests/build/fixtures/Directory.Build.targets`
- Create: `tests/build/fixtures/nuget.config`
- Create: `tests/build/fixtures/register-valid/register.md`
- Modify: `tests/build/run.sh`

**Interfaces:**
- Consumes: Contracts, `build/Doment.BuildChecks.cs` (Task 3) and the run helpers (Task 1)
- Produces: Contracts, the register format and its parser (the `DomentRegister` type, which Tasks 7 and 8 use), DOMENT013, the `DomentThirdPartyCheck` target skeleton, and the fixture tree layout

**Items:** 4

**Depends on:** Task 3

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7
**Approach:** inline - skip 5: not load-bearing; the register format is fixed in Contracts and its behaviour by A20

- [ ] **Step 1: Write the failing test**

- `tests/build/run.sh::register_valid` (integration): a generated case with an unedited copy of `register-valid/register.md` (all three tables, rows X1, B1, B2 and one platform package) and a `src/App` with no packages builds with rc 0 and no `DOMENT013`. It fails today because nothing reads the register.
- `tests/build/run.sh::register_malformed` (integration): one table of rows. run.sh generates a case under `tests/build/fixtures/.run/` per row, with an edited copy of `register-valid/register.md`. Each row gives rc 1 and exactly the line shown:
  - the `## Platform packages` heading removed: `error DOMENT013: <register>: table 'Platform packages' is missing`;
  - the `Licence` column removed from table 2: `table 'Build-and-test-only tools' has no column 'Licence'`;
  - B2 renamed to B1: `duplicate ID B1`;
  - X1's `Reason`, `Licence`, `Behind`, `Replacement` or `Approved` cell emptied, one row each: `row X1, column '<column>' is empty`.
  It fails today because nothing reads the register.
- `tests/build/run.sh::register_missing_file` (integration): with no `register.md` in a case (`DomentRegisterFile` points at a missing path), rc 1 and `error DOMENT013: <register>: table 'Exceptions' is missing`. It fails today because nothing reads the register.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^register_'`
Expected: FAIL, 3 `not ok` lines

- [ ] **Step 3: Implement**

1. `build/Doment.BuildChecks.cs`: a `DomentRegister` type that parses the three tables by heading and header row into rows of cells, validates them as Contracts says, and reports every problem rather than stopping at the first. Also a `DomentThirdPartyCheck` task that, for now, only loads and validates the register. Split packages cells into entries; `-` means none.
2. `build/Doment.ThirdParty.targets`: the `UsingTask` and the `DomentThirdPartyCheck` target `AfterTargets="ResolvePackageAssets"`, passing `DomentRegisterFile`. Root `Directory.Build.targets` imports it after `Doment.Framework.targets`.
3. The fixture root files exactly as Contracts' "Fixture trees" says. run.sh makes `$DOMENT_FIXTURE_FRAMEWORK` once per run with `new_framework_repo` and exports `$DOMENT_FIXTURE_PIN`.
4. From this task on, every build runs the register check. `new_doment_repo` therefore copies `register-valid/register.md` as the stand-in's register (Contracts). Until Task 6 writes the real register, `real_framework_strict` passes `-p:DomentRegisterFile=<repo>/tests/build/fixtures/register-valid/register.md`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh` (full suite, after the third task since the last full run)
Expected: every case passes; the summary line shows `0 failed`

- [ ] **Step 5: Commit**

```bash
git add build Directory.Build.targets tests/build
git commit -m "feat(build): parse the third-party register"
```

### Task 6: The exception register

**Files:**
- Create: `docs/third-party-exceptions.md`
- Modify: `tests/build/run.sh`

**Interfaces:**
- Consumes: Contracts, the register format (Task 5)
- Produces: the real register, which Tasks 7 and 8 read through the real-framework case and the repository gate run

**Items:** 4

**Depends on:** Task 5

**Evaluation:** files 1 - spec 1 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Extend the test `tests/build/run.sh::real_framework_strict`**

- `tests/build/run.sh::real_framework_strict` (integration): the case now leaves `DomentRegisterFile` at this repository's `docs/third-party-exceptions.md`, so the register check runs against the real register: rc 0 and no `DOMENT013` line. It fails today because the file does not exist (DOMENT013 `table 'Exceptions' is missing`).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^real_framework_strict$'`
Expected: FAIL with `error DOMENT013`

- [ ] **Step 3: Implement**

1. `docs/third-party-exceptions.md`: a short preface stating that the file is the only source, that the check parses it, that new rows in tables 1 and 2 need the owner's approval, and what the check cannot see (spec section 7, "What it cannot see"). Then the three tables in the Contracts format.
2. Table 1. X1: Indirect Display driver (candidate: Virtual Display Driver); packages or files `-`; used for virtual displays; reason: no first-party driver before M17; licence MIT; behind `IVirtualDisplay`; replacement: doment's own driver in M17; approved 2026-11-24; signature validity confirmed in its M9 epic. X2: ViGEmBus; `-`; virtual gamepads; reason: no first-party driver before M17 (archived 2023); BSD-3-Clause; `IVirtualGamepad`; replacement in M17; approved 2026-11-24.
3. Table 2, all approved 2026-11-24. B1 xUnit v3: `xunit.v3`, `xunit.v3.*`, `xunit.analyzers`; unit tests; Apache-2.0. B2 Microsoft Testing Platform: `Microsoft.Testing.Platform`, `Microsoft.Testing.Platform.*`, `Microsoft.Testing.Extensions.*`; test runner; MIT. B3 csharpier: `csharpier`; formatting; MIT. The epic that first references each component lists its exact transitive packages, as spec section 7 says.
4. Table 3, first seen 2026-11-24, added by ".NET SDK (NativeAOT publish for linux-x64)": `Microsoft.DotNet.ILCompiler`, `runtime.linux-x64.Microsoft.DotNet.ILCompiler`, `Microsoft.NET.ILLink.Tasks`. Run `bash tests/build/run.sh '^real_framework_strict$'` and read its `note real_framework_strict: packages:` line; add each package it names that meets the membership test.
5. Licences: X1 and X2 as the spec records them. For B1 to B3, read each project's licence on its repository and cite the date read in the preface; if one differs from the value above, use the one read.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh '^(real_framework_strict|register_)'`
Expected: `4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add docs/third-party-exceptions.md tests/build/run.sh
git commit -m "docs(register): add the third-party exception register"
```

### Task 7: Package and project reference checks

**Files:**
- Modify: `build/Doment.BuildChecks.cs`
- Modify: `build/Doment.ThirdParty.targets`
- Modify: `tests/build/run.sh`

**Interfaces:**
- Consumes: Contracts, `DomentRegister` (Task 5)
- Produces: Contracts, DOMENT010, DOMENT011, DOMENT012, `DomentReferenceCheck`, and the `DOMENT-PACKAGES` message

**Items:** 4

**Depends on:** Task 5

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6
**Approach:** inline - skip 5: not load-bearing; behaviour fixed by A15 to A19

- [ ] **Step 1: Write the failing test**

run.sh packs these tiny packages into the run feed, from generated projects in the run's temporary root with empty `Directory.Build.*`: `Fx.Listed` 1.0.0, `Fx.Unlisted` 1.0.0, `Fx.Parent` 1.0.0 (which depends on `Fx.Unlisted`), and `Fx.Tool` 1.0.0. Each case's register is `register-valid/register.md` with rows added for `Fx.Listed` (table 1, X8), `Fx.Parent` (table 1, X9) and `Fx.Tool` (table 2, B9). Each case below is generated under `tests/build/fixtures/.run/` with `fixture_project`.

- `tests/build/run.sh::packages_listed` (integration): a shipping `src/App` referencing `Fx.Listed` gives rc 0, no `error DOMENT`, and one line `DOMENT-PACKAGES: 1`. It fails today because the check reads no packages and logs no count.
- `tests/build/run.sh::package_unlisted_direct` (integration): `src/App` referencing `Fx.Unlisted` gives rc 1 and `error DOMENT010: <project path>: package Fx.Unlisted 1.0.0 is in no table of <register path> (direct reference)`. It fails today because nothing checks packages.
- `tests/build/run.sh::package_unlisted_transitive` (integration): `src/App` referencing `Fx.Parent` gives rc 1 and `... package Fx.Unlisted 1.0.0 is in no table ... (through Fx.Parent)`. `src/App2` referencing project `src/Lib`, where `src/Lib` references `Fx.Unlisted`, gives the App2 error ending `(through project Lib)`. It fails today because nothing checks packages.
- `tests/build/run.sh::buildonly_package` (integration): a shipping `src/App` referencing `Fx.Tool` gives rc 1 and `error DOMENT011: <project> ships but resolves build-and-test-only package Fx.Tool 1.0.0, row B9 of <register> (direct reference)`. The same reference from `tests/App.Tests` gives rc 0. It fails today because nothing classifies projects.
- `tests/build/run.sh::buildonly_project_ref` (integration): a shipping `src/App` with a `ProjectReference` to `tools/Helper` gives rc 1 and `error DOMENT011: <project> ships but references build-only project <path to Helper.csproj>`. It fails today because nothing checks project references.
- `tests/build/run.sh::framework_refs` (integration): one table against `$DOMENT_FIXTURE_FRAMEWORK`. A `net10.0` project referencing `src/Darkraise` builds with rc 0. A `net10.0` project referencing `src/Darkraise.Api` gives rc 1 with `error DOMENT012: <project>: project reference <path> is not an allowed darkraise-framework project`. A `net10.0` project referencing `src/Darkraise.Win32UI` gives rc 1 with DOMENT012, before restore and with no NU1201 line. A project referencing a `.csproj` in a sibling directory outside `DomentRepoRoot` gives rc 1 with DOMENT012. With `dotnet msbuild -t:DomentReferenceCheck`, a `net10.0-windows` project referencing `src/Darkraise.Win32UI` and `src/Darkraise.Win32UI.Generators` gives rc 0, and the same project referencing `src/Darkraise.Api` gives rc 1 with DOMENT012. It fails today because nothing checks project references.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^(packages_|package_|buildonly_|framework_refs)'`
Expected: FAIL, 6 `not ok` lines

- [ ] **Step 3: Implement**

1. `build/Doment.BuildChecks.cs`: a minimal JSON reader (objects, arrays, strings with escapes, numbers, `true`, `false`, `null`) into dictionaries and lists. `DomentThirdPartyCheck` reads `$(ProjectAssetsFile)`: the packages are the `libraries` entries of `type` `package`. The direct references come from `project.frameworks.<tfm>.dependencies` plus the `project` libraries. "How it arrived" comes from walking `targets.<target>.<id>/<version>.dependencies` breadth-first from each direct reference. Each package is classified against tables 1, 2 and 3 (case-insensitive, with the `.*` rule) and logged as DOMENT010 or DOMENT011 with the Contracts text, every violation reported. The task then logs `DOMENT-PACKAGES: <n>`.
2. A `DomentReferenceCheck` task over `@(ProjectReference)` full paths, with `DarkraiseFrameworkPath`, `DomentRepoRoot`, `TargetFramework` and `DomentBuildOnly`. A reference under the framework path must be one of the allowed projects of Global Constraints. A reference outside `DomentRepoRoot` and outside the framework path is refused. A shipping project referencing a project under `tests/` or `tools/` gets DOMENT011.
3. `build/Doment.ThirdParty.targets`: `DomentReferenceCheck` is hooked before restore with the same hook as `DomentPresenceCheck`, and is callable alone.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh '^(packages_|package_|buildonly_|framework_refs|real_framework_strict)'`
Expected: `7 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add build tests/build
git commit -m "feat(build): fail on unlisted packages and references"
```

### Task 8: Gate command

**Files:**
- Create: `build/gate.sh`
- Create: `build/Gate.proj`
- Modify: `build/Doment.BuildChecks.cs`
- Modify: `tests/build/run.sh`

**Interfaces:**
- Consumes: Contracts, `DomentRegister`, `DomentThirdPartyCheck`, `DOMENT-PACKAGES` (Tasks 5 and 7), `FrameworkPinStrict` (Task 1)
- Produces: Contracts, `build/gate.sh`, DOMENT005, DOMENT020, DOMENT021 and DOMENT022

**Items:** 4

**Depends on:** Task 7

**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Each case runs `build/gate.sh <tree>` on a `new_doment_repo` copy, synced against a stand-in framework. Its `src/App` is removed with `git rm`, its `docs/third-party-exceptions.md` is the real register with `Fx.Tool` added to table 2 as row B9, and it has a `nuget.config` that clears every source and adds only the run feed and the run's packages folder. The packages are those of Task 7.

- `tests/build/run.sh::gate_reports_all` (integration): a tree with tracked `src/A` (referencing `Fx.Unlisted`), `src/B` (referencing `Fx.Tool`), `src/C`, and an untracked `src/D` that references `Fx.Unlisted`. The exit code is 1, the output has one DOMENT010 for A and one DOMENT011 for B, nothing for D, and its last line is `gate: 3 projects checked, 2 packages seen, 2 violations`. It fails today because `build/gate.sh` does not exist.
- `tests/build/run.sh::gate_unlisted_project` (integration): a tracked `extra/E/E.csproj` that no solution lists, referencing `Fx.Unlisted`, is checked: exit 1 and a DOMENT010 naming `E.csproj`. It fails today because `build/gate.sh` does not exist.
- `tests/build/run.sh::gate_not_importing` (integration): a tracked `src/F/F.csproj` next to its own `src/F/Directory.Build.props` and `src/F/Directory.Build.targets` (both `<Project />`) gives exit 1 and `error DOMENT020: <path>/src/F/F.csproj does not import the root Directory.Build.targets`. It fails today because `build/gate.sh` does not exist.
- `tests/build/run.sh::gate_tool_manifest` (integration): a tracked `.config/dotnet-tools.json` with tools `csharpier` and `dotnet-ef` gives exit 1, one `error DOMENT021: .config/dotnet-tools.json: tool dotnet-ef is not a build-and-test-only row of <register>`, and nothing for `csharpier`. It fails today because `build/gate.sh` does not exist.
- `tests/build/run.sh::gate_binary` (integration): tracked `lib/native.so` and `assets/x.dll` give exit 1 and one DOMENT022 for each. After a register row (in the tree's copy) that lists `lib/native.so` in a files cell, only `assets/x.dll` is reported. It fails today because `build/gate.sh` does not exist.
- `tests/build/run.sh::gate_main_pin` (integration): on branch `master`, with a pin naming a commit on the stand-in framework's unpushed branch `feature`, the gate gives exit 1 and `error DOMENT005: pin <c> is not an ancestor of the framework's origin/master`. On branch `topic`, the same pin passes this check. It fails today because `build/gate.sh` does not exist.
- `tests/build/run.sh::gate_off_pin` (integration): a tree with tracked `src/C` (no packages) and its framework worktree on a commit other than the pin gives exit 1 and an `error DOMENT001` line. With the worktree at the pin but holding an untracked file, it also gives exit 1 and `error DOMENT001`. It fails today because `build/gate.sh` does not exist.
- `tests/build/run.sh::gate_skips_fixtures` (integration): a tree with a tracked `tests/build/fixtures/x/src/Bad/Bad.csproj` that references `Fx.Unlisted` gives exit 0 and `gate: 0 projects checked, 0 packages seen, 0 violations`. A tracked `tests/build/other/Bad.csproj` with the same reference is checked and fails. It fails today because `build/gate.sh` does not exist.
- `tests/build/run.sh::gate_repository` (integration): `build/gate.sh` run on this repository gives exit 0 and a summary line with `0 violations`. It fails today because the gate does not exist.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/run.sh '^gate_'`
Expected: FAIL, 9 `not ok` lines

- [ ] **Step 3: Implement**

1. `build/gate.sh`: resolve the tree (`git -C <tree> rev-parse --show-toplevel`, exit 2 on failure). List the tracked project files with `git ls-files -z`, dropping `tests/build/fixtures/`. For each one, read `-getProperty:DomentRootTargetsImported`; anything other than `true` is DOMENT020. Otherwise run `dotnet msbuild <p> -restore -t:DomentFrameworkCheck;DomentThirdPartyCheck -p:FrameworkPinStrict=true`, print its `error DOMENT` lines, count them, and add its `DOMENT-PACKAGES` value. Write the tracked files with the extensions `.dll .exe .so .dylib .a .lib .sys .nupkg .snupkg` to a temporary list, and run `dotnet msbuild build/Gate.proj -t:DomentGateFiles` with the tree, the register (`<tree>/docs/third-party-exceptions.md`) and the list. On branch `master` or `main`, run `timeout 120 git -C <tree's framework path> fetch --quiet origin` (on failure print `gate: warning: could not fetch the framework's remote` and continue), then `git -C <tree's framework path> merge-base --is-ancestor <pin> refs/remotes/origin/master`, and report DOMENT005 when it fails. Print every violation, then the summary line.
2. `build/Gate.proj`: a non-SDK `<Project>` with the `UsingTask` for the gate task and a `DomentGateFiles` target. In `Doment.BuildChecks.cs`, a `DomentGateFiles` task reads `.config/dotnet-tools.json` (the keys of `tools`) with the JSON reader of Task 7 and matches each tool against table 2. It also matches each listed binary against every files cell of tables 1 and 2, logging DOMENT021 and DOMENT022.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/build/run.sh` (full suite)
Expected: every case passes; summary `0 failed`

- [ ] **Step 5: Commit**

```bash
git add build/gate.sh build/Gate.proj build/Doment.BuildChecks.cs tests/build/run.sh
git commit -m "feat(build): add the third-party gate command"
```

### Task 9: Architecture record

**Files:**
- Create: `docs/architecture.md`
- Framework worktree (not a doment path; it exists once Task 2's `sync` has run): its `CLAUDE.md`, that is external/darkraise-framework/CLAUDE.md, changed on a framework branch (Step 3 item 2)

**Interfaces:**
- Consumes: Contracts (the names of `tools/framework.sh`, `build/gate.sh`, the properties and the diagnostics)
- Produces: `docs/architecture.md`, the living record later epics edit

**Items:** 1, 2, 3

**Depends on:** Task 8

**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

- [ ] **Step 1: No new test, because the record is prose that no script reads; A1 to A7 are accepted by reading it against the spec**

- [ ] **Step 2: Run test to verify it fails**

Run: `test -f docs/architecture.md`
Expected: FAIL (exit 1)

- [ ] **Step 3: Implement**

1. `docs/architecture.md`, written for a reader who has not seen the spec, with these sections:
   - **Process model (A1, A2, A3):** spec section 2, with its table and every rule: one network endpoint, policy in one place, terminals outlive the service (kill scope, never killed, version range and the out-of-range outcome), workers at lower privilege are untrusted input, user data under the user's identity, device handles in the service, parsing before authentication is safe code.
   - **Worker link:** spec section 3, the channels, the contract and its two implementations (R176 in M2).
   - **Module map (A4):** spec section 4, its table and its rules.
   - **Platform seams and build order (A5, A6):** spec section 5, the ten-seam table, the later seams, the six seam rules and the build order.
   - **Consuming darkraise-framework (A7):** spec section 6, the property and its overrides, the pin, `tools/framework.sh` with its three verbs and refusals, the checks and DOMENT001 to DOMENT006, working on the framework, the contribution rule, and the three limits.
   - **Third-party register and gate:** the classification, the check's rules with DOMENT010 to DOMENT022, what it cannot see, and the gate invocation `build/gate.sh [<tree>]` with its exit codes and summary line.
   - **Rules handed to later epics:** spec section 9, one subsection per epic.
   - **Changing this record:** the rule that a later epic that changes a decision edits this file.
2. In `external/darkraise-framework`, following the framework's own workflow (its `CLAUDE.md` "Git Workflow" and the modder rule: cross-repo work is a branch in the project's worktree, cut from a fresh `master`), run `git switch --detach master` and then `git switch -c docs/doment-framework-worktree`. Never touch the primary checkout. Add one line to the "One worktree per project" paragraph of `CLAUDE.md`, and commit it with the framework's commit format (`docs(claude): ...`). The line says that doment keeps one framework worktree inside each doment checkout, at `external/darkraise-framework`, managed by doment's `tools/framework.sh`. Do not push. Then run `tools/framework.sh sync` to return the worktree to the pin. It is clean, and its HEAD is reachable from the new branch. Report the unpushed framework branch in the task's closing note.

- [ ] **Step 4: Run test to verify it passes**

Run: `test -f docs/architecture.md && rg -c '^## ' docs/architecture.md && bash tests/build/run.sh '^real_framework_strict$'`
Expected: the file exists with at least 8 level-2 headings, and `1 passed, 0 failed` (the worktree is back at the pin)

- [ ] **Step 5: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): record the architecture"
```

### Task 10: Product spec amendments

**Files:**
- Modify: `docs/dforge/specs/2026-11-24-doment-design.md`
- Modify: `docs/dforge/registers/2026-11-24-m2-sessions-transport.md`

**Interfaces:**
- Consumes: none
- Produces: the amended product spec (R176, the "Local worker link" epic)

**Items:** 5

**Depends on:** none

**Evaluation:** files 1 - spec 1 - coupling 0 - risk 1 = 3

- [ ] **Step 1: No new test, because the amendments are prose that no script reads; A8 and A9 are accepted by reading them against spec section 8**

- [ ] **Step 2: Run test to verify it fails**

Run: `rg -c 'R176' docs/dforge/specs/2026-11-24-doment-design.md`
Expected: FAIL (no match, exit 1)

- [ ] **Step 3: Implement**

1. Apply every amendment of spec section 8 to the product spec, in the places it names: R1 gains the terminal host; R4 gains the build-and-test-only sentence; section 5's third-party rule; the section 9 row on vanishing terminal sessions; section 10's "Terminals" and "Processes" (including the two sentences recorded under decision 4), with its open decision on how doment references the framework removed; R104's new wording; section 11 becomes a pointer to `docs/third-party-exceptions.md`, with its new closing line.
2. Add **R176** with the spec's quoted wording under `### M2 Secure sessions and media transport`. Add the row `| M2 | Local worker link | R176 |` to the section 7 epics table, after the last M2 row.
3. Add the M2 register row with dforge's `scripts/register add docs/dforge/registers/2026-11-24-m2-sessions-transport.md "Local worker link"` (called as `bash <dforge plugin root>/scripts/register`, the root printed at session start). Then set its Assigned cell to `Local worker link` and its Acceptance cell to `R176`, matching the neighbouring rows, and run dforge's `scripts/register check` on the file.

- [ ] **Step 4: Run test to verify it passes**

Run: `rg -c 'R176' docs/dforge/specs/2026-11-24-doment-design.md && rg -n 'Local worker link' docs/dforge/registers/2026-11-24-m2-sessions-transport.md && rg -n 'third-party-exceptions.md' docs/dforge/specs/2026-11-24-doment-design.md`
Expected: R176 found at least twice, one register row, and the pointer present

- [ ] **Step 5: Commit**

```bash
git add docs/dforge/specs/2026-11-24-doment-design.md docs/dforge/registers/2026-11-24-m2-sessions-transport.md
git commit -m "docs(spec): amend the product spec for architecture"
```
