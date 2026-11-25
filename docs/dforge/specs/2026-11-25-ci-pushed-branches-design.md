# CI for pushed branches — design

**Execution strategy:** sequential — inline execution
**Depth:** full — risk

## Decisions

1. **Where the jobs run.** Asked: the ghr homelab pool with doment added, GitHub-hosted `ubuntu-latest`, or ghr with
   a hosted fallback. Answer: **"Ghr pool, label doment-linux"**.
2. **Credential for the private framework.** Asked: a deploy key, a fine-grained personal access token, or a GitHub
   App token. Answer: **"Deploy key (Recommended)"**.
3. **Triggers.** Asked: push plus same-repository pull requests, or push only. Answer: **"push + same-repo PRs
   (Recommended)"**.
4. **Test scope.** Asked whether CI also runs the build-system acceptance suites in `tests/build`. Answer: **"Yes,
   separate job (Recommended)"**, with A20 fixed in this epic so master can be green.
5. **clang and zlib on the runner.** Asked: ghr-managed apt packages, or the workflow installs them. Answer:
   **"ghr-managed apt (Recommended)"**.
6. **Workflow shape.** Asked: one job with a two-entry matrix, two jobs with the setup duplicated (the do-less
   layout), or two jobs with a composite action. Answer: **"One job, 2-entry matrix (Recommended)"**.

## 1. Goal and scope

R8: every pushed branch of `darkraise/doment` is built and tested on CI on Linux, including the NativeAOT publish.
The epic also carries the rules `docs/architecture.md` handed to it ("Rules handed to later epics", "CI for pushed
branches"), listed in `docs/dforge/registers/2026-11-25-ci-pushed-branches.md`.

Out of scope: Windows CI (M7 "Windows build and CI"), the network test bench (R10), declaring gates in `gates.md`
(epic "Gates declared"), publishing or releases, and caching beyond what ghr already shares between runners.

## 2. Where it stands (checked 2026-11-25)

- No `.github/workflows` directory exists. `darkraise/doment` is public. Its fork pull request approval policy is
  `first_time_contributors` (`gh api repos/darkraise/doment/actions/permissions/fork-pr-contributor-approval`), and
  actions are not required to be pinned to a commit SHA (`gh api repos/darkraise/doment/actions/permissions`:
  `sha_pinning_required: false`).
- doment's local master is 54 commits ahead of `origin/master`. darkraise-framework is private; its local master is
  59 commits ahead of its origin, and doment's pin `e3cb121d` is on the framework's `origin/master`.
- `build/gate.sh` runs the pin-ancestry check (DOMENT005) only when `git branch --show-current` prints `master` or
  `main` (`build/gate.sh:131`). A `pull_request` checkout is a detached merge commit, so the check would never run on
  a pull request. A push run checks out a local branch of the pushed name, so on a push to master the existing rule
  already applies.
- Case A17 of `tests/build/repository-build-nativeaot.acceptance.sh` runs the test executable with
  `DOTNET_ROOT=/usr/local/share/dotnet`, this host's SDK location; a runner whose SDK comes from setup-dotnet has no
  SDK there.
- Case A20 of the same suite diffs against `git merge-base HEAD master`: on master that is HEAD itself, so it finds no
  row and fails (register `docs/dforge/registers/2026-11-24-repository-build-nativeaot.md`, row 21); on a CI run of
  another branch there is no local `master` ref, so it fails there too. Its gate call also fetches the framework's
  remote, which a CI run without a credential cannot do.
- ghr facts, from its repository: jobs run natively on the ghr host, not in a container (`ghr/README.md`); ghr serves
  a public repository only with `allow_public` set, and refuses any job whose event comes from a fork by ending the
  runner's worker before any step runs (`ghr/SECURITY.md`, `ghr/docs/configuration.md`); it does not refuse
  `issue_comment` or `merge_group` workflows (`ghr/SECURITY.md`); every runner runs as one user, so a job can read
  another running job's process environment (`ghr/docs/self-hosted-artifacts.md`, "One runner user"). From the
  framework's plan (`darkraise-framework/docs/dforge/plans/2026-11-25-ci-on-ghr.md`): runners are created per job, run
  one job at a time, and their shared tool cache is read-only to jobs.

## 3. Design

### 3.1 Workflow and triggers

One workflow, `.github/workflows/ci.yml`, named `CI`:

- `on: push` with `branches: ['**']`: every branch, no tag.
- `on: pull_request` with `branches: [master]`.
- `on: workflow_dispatch`, which only people with write access can use, so a run can be repeated by hand. GitHub
  offers it only once the workflow is on the default branch.
- No `pull_request_target`, `workflow_run`, `issue_comment`, `merge_group` or `schedule` trigger.
- `permissions: contents: read` at the top level.
- `concurrency`: group `ci-${{ github.event_name }}-${{ github.ref }}`, with `github.run_id` appended when the ref is
  `refs/heads/master`, and `cancel-in-progress: true`. A newer push to a feature branch cancels its older run; every
  master run has a group of its own, so no other run cancels it.

The job's `if:` is
`github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`. It skips
a fork's pull request only while the fork leaves the workflow file alone: a `pull_request` run uses the workflow from
the pull request's merge commit, so a fork can remove the condition or add a workflow of its own for
`[self-hosted, doment-linux]`. Two independent controls outside the workflow keep fork code off the homelab host:
ghr's job-started hook refuses every `pull_request`, `pull_request_review`, `pull_request_review_comment`,
`pull_request_target` and `workflow_run` job whose head repository is not the served one, killing the runner's worker
before any step and failing closed on an unreadable payload (`ghr/hooks/job-started.sh`; it has no switch); and the
repository requires approval of every fork pull request run (§3.6 item 3). The `if:` remains so a well-behaved fork's run shows as skipped rather than refused.

A same-repository branch with an open pull request gets two runs per push (the push and the pull request's merge
commit), four jobs in all. That is accepted: the pull request run checks the merged tree, the push run the branch. It
is why the pool needs at least two concurrent runners (§3.6); queue time is measured on the first runs.

### 3.2 The job

One job, `build`, with `strategy.matrix.suite: [check, acceptance]`, `fail-fast: false` and `name: ${{ matrix.suite }}`,
so the two entries run as parallel jobs shown as `check` and `acceptance`. `runs-on: [self-hosted, doment-linux]`.
Job environment: `MSBUILDDISABLENODEREUSE=1`, `DOTNET_CLI_USE_MSBUILD_SERVER=0`, `UseSharedCompilation=false`,
`DOTNET_CLI_TELEMETRY_OPTOUT=1`, `TESTINGPLATFORM_TELEMETRY_OPTOUT=1`, `DOTNET_NOLOGO=1`, so no step starts an MSBuild
node or compiler server, and ghr stops each runner's systemd unit with `KillMode=control-group`, so nothing outlives
the job. No workflow step runs `dotnet build-server shutdown`: every ghr runner is the same user, so it would stop
other jobs' servers, the framework's CI jobs included. For the same reason `build/check.sh`, which runs that shutdown
on every exit (`build/check.sh:80`), skips it when `GITHUB_ACTIONS` is `true`; local runs keep it.

Invariant: no step before the framework checkout runs a file from the checked-out tree. A tree script run there could
write `GITHUB_ENV` or `GITHUB_PATH` and capture the key in the checkout step.

Steps, shared by both entries (each `uses:` names an `actions/*` action at a full 40-character commit SHA, its version
in a comment):

1. `actions/checkout` of doment with `fetch-depth: 0` (the acceptance suites read history), `lfs: false` and
   `persist-credentials: false` (no later step talks to doment's remote).
2. Inline: read the pin from `build/darkraise-framework.pin` into a step output; a malformed pin fails here with an
   error annotation. Check that `ssh` is on `PATH`, failing with the missing-package annotation of step 6.
3. `actions/checkout` (id `framework`) of `darkraise/darkraise-framework` at the pin into
   `external/darkraise-framework`, with `ssh-key: ${{ secrets.DARKRAISE_FRAMEWORK_DEPLOY_KEY }}`, `fetch-depth: 0` (it
   fetches `+refs/heads/*:refs/remotes/origin/*`, so `refs/remotes/origin/master` is present for DOMENT005),
   `lfs: false`, `persist-credentials: false`, and step environment `GIT_LFS_SKIP_SMUDGE=1` (`lfs: false` alone does
   not stop a runner-user LFS filter from smudging the framework's corpus). The secret is referenced in this step only.
4. `if: failure() && steps.framework.outcome == 'failure'`: print
   `::error::cannot check out darkraise-framework at <pin>: push that framework commit to its origin, check the DARKRAISE_FRAMEWORK_DEPLOY_KEY secret, or check that outbound SSH to github.com is open`.
5. `build/ci.sh verify` (see §3.3).
6. `actions/setup-dotnet` with `global-json-file: global.json` and `DOTNET_INSTALL_DIR=$RUNNER_TEMP/dotnet`, always:
   no SDK directory is shared between jobs.
7. `dotnet tool restore`.
8. `build/ci.sh check` or `build/ci.sh acceptance`, by the matrix entry. The `check` entry also gets
   `DOMENT_CI_PIN_ON_MASTER`, `1` for a push to master or a pull request into master and `0` otherwise.

`timeout-minutes` per entry: a starting budget of 60 for `check` and 180 for `acceptance`; once the first green runs
are measured, each is set to about twice its measured duration.

### 3.3 `build/ci.sh`

One tracked bash script, so every failure path can be tested locally with stand-ins. It finds its tree the way
`build/check.sh` does (from its own location, without git) and exits 0 on success, 1 on a failed check or command, 2
on bad usage. Inputs a test can replace: `PATH` (for the tools), `DOMENT_CI_ZLIB_INCLUDE` (default `/usr/include`),
`DOMENT_CI_MIN_FREE_GB` (default 20), `DOMENT_CI_FRAMEWORK` (default `<tree>/external/darkraise-framework`),
`RUNNER_TEMP`.

- `verify`, after the key's step has ended:
  - the key is gone: `git -C <framework> config --get core.sshCommand` prints nothing, and no file under `RUNNER_TEMP`
    holds a `PRIVATE KEY` header;
  - no LFS content: `<framework>/.git/lfs/objects` is absent or empty;
  - the framework is clean by the build's definition (`git status --porcelain=v1 -z --ignored=matching
    --untracked-files=all`, ignoring only `bin`, `obj`, `.vs`, `.idea`, as `build/Doment.BuildChecks.cs` does),
    else `::error::the framework checkout is not clean: <first path>`;
  - the tools: `clang`, `zlib.h` under `DOMENT_CI_ZLIB_INCLUDE`, `jq`, `file`, `ps`, `pgrep`, each missing one failing
    with `::error::<package> is missing on the runner; add it to the ghr pool's managed packages` (packages `clang`,
    `zlib1g-dev`, `jq`, `file`, `procps`);
  - free space in the workspace at least `DOMENT_CI_MIN_FREE_GB`, else
    `::error::workspace has <g> GB free at <dir>, needs <n> GB`.
- `check`: runs `build/check.sh`, then `build/gate.sh` even when `build/check.sh` failed; prints
  `ci: gate DOMENT_GATE_PIN_ON_MASTER=<0|1>` and passes that value, with `DOMENT_GATE_NO_FETCH=1`, to the gate call
  only; fails when either failed.
- `acceptance`: runs `tests/build/repository-build.acceptance.sh`, `tests/build/repository-build-nativeaot.acceptance.sh`
  (its A25 runs `tests/build/run.sh` and `tests/build/architecture-decisions.acceptance.sh`) and
  `tests/build/ci-pushed-branches.acceptance.sh`, each even when an earlier one failed; fails when any did.

### 3.4 Gate change

`build/gate.sh` gains one environment variable: with `DOMENT_GATE_PIN_ON_MASTER=1`, it runs the DOMENT005
pin-ancestry check whatever the branch name, a detached HEAD included. Without it, the current rule stays (master or
main only), so local runs on feature branches behave as today.

### 3.5 Tests

- New suite `tests/build/ci-pushed-branches.acceptance.sh`, in the structure of the other `tests/build` suites (bash
  and `jq`; the workflow checks are text matches on the YAML). It holds the static workflow checks and the `build/ci.sh`
  cases with stand-in trees and stand-in tools, and the `acceptance` entry runs it.
- Case A17 of `repository-build-nativeaot.acceptance.sh` takes `DOTNET_ROOT` from the `dotnet` on `PATH`
  (`readlink -f "$(command -v dotnet)"`'s directory, as `build/check.sh` does) instead of `/usr/local/share/dotnet`.
- Case A20 diffs a fixed range, from the parent of the repository-build-nativeaot plan's first commit to that plan's
  last commit, both recorded as full SHAs in the suite, instead of `merge-base HEAD master`..HEAD. It then checks
  exactly the rows that epic added, on master and on any branch, and a later epic's rows (M7's Windows-only platform
  rows among them) never reach it. A comment beside the SHAs says the rows are still checked against the current
  restore output, so a later epic that drops one of those packages fails A20 for that reason. Its gate call sets
  `DOMENT_GATE_NO_FETCH=1`, as A23 does.
- Every `tests/build` runner (`run.sh`, `architecture-decisions.acceptance.sh`, `repository-build.acceptance.sh`,
  `repository-build-nativeaot.acceptance.sh`) adds `DOMENT_GATE_PIN_ON_MASTER` to its `unset` line, so a value in the
  caller's environment cannot change a case such as `run.sh`'s `gate_main_pin`.
- Each fix is rerun on this host; whatever else fails only on the runner is found by the first pushed run (see
  Riskiest assumption) and fixed the same way, without new skips.

### 3.6 Owner setup outside the repository

Each is a one-time step done by the owner, or by the session with the owner's consent at the spec review:

1. ghr: serve `darkraise/doment` with `allow_public` set, in a pool labelled `doment-linux` of at least two concurrent
   runners, with `clang`, `zlib1g-dev`, `jq`, `file`, `procps` and `openssh-client` in its managed apt packages.
2. Deploy key: an ed25519 key pair generated into a temporary directory; the public half added to
   `darkraise-framework` as a read-only deploy key, the private half piped into
   `gh secret set DARKRAISE_FRAMEWORK_DEPLOY_KEY -R darkraise/doment` and then deleted, so it is kept nowhere else.
3. Repository settings on `darkraise/doment`, done before item 1 makes ghr serve doment: fork pull request approval
   set to "Require approval for all external contributors", and "Require actions to be pinned to a full-length commit
   SHA" turned on. Approving a fork run executes nothing on ghr, which refuses it; what runs a fork's code on the host
   is merging its pull request or pushing its branch into doment, so the owner reads the whole diff (build scripts,
   project files and tests, not only the workflow) before doing either.
4. Pushes, to the public repository: the first branch push also publishes the 54 commits of local master that are
   not on `origin/master`; pushes that add or change a workflow file need SSH or a token with the `workflow` scope.
   Verifying the epic takes a feature-branch push, one throwaway branch whose pin is a 40-character hash that is not
   in the framework's remote (A10), one same-repository pull request into master opened and closed (A20), and at
   finishing a push of doment master.

### 3.7 Limits

- Write access to doment implies read access to the private framework: anyone who can push a branch can change
  `ci.yml` to print the secret. `persist-credentials: false` keeps the key from build, restore and test code of a
  branch that leaves the workflow alone, not from the workflow itself. Today only the owner has write access.
- doment has no merge queue and must not get one while ghr serves it: ghr does not refuse `merge_group` jobs, and a
  merge queue runs a fork pull request's code as base-repository code.
- During the framework checkout the key is in that step's process environment, which another job running on the ghr
  host as the same user can read (`ghr/docs/self-hosted-artifacts.md`, "One runner user"). That is inside ghr's trust
  domain: every repository it serves is the owner's.

### 3.8 Documentation

`docs/architecture.md`:

- "Rules handed to later epics", "CI for pushed branches": replaced by a "CI" section recording the workflow, its
  triggers, the fork controls (job condition, ghr's refusal, the approval setting), the runner label and packages, the
  secret name, `build/ci.sh` and `DOMENT_GATE_PIN_ON_MASTER`.
- The pin section (lines 237-239), which says all of CI requires the pin on the framework's remote master: CI
  requires that only on master and pull requests into it, and elsewhere only that the pin exists on the framework's
  remote.
- Lines 281 and 362, which describe DOMENT005 as "on master or main" only: add the variable.
- Limits (lines 301-309): add the two limits of §3.7; line 306-307's credential sentence names the deploy key.
- The Toolchain paragraph (lines 395-399): the CI runner's SDK comes from setup-dotnet and its clang from ghr.

## Acceptance

A1. [test, high] A push of any branch to `darkraise/doment` starts the `CI` workflow, and both of its jobs (`check`, `acceptance`) run on a runner labelled `self-hosted` and `doment-linux`.
A2. [test, high] The `check` job runs with the SDK `global.json` names (`dotnet --version` prints 10.0.404), restores the local tools, runs all four steps of `build/check.sh` and then `build/gate.sh`, and fails when either exits non-zero.
A3. [test, high] Both jobs check out the framework at the commit in `build/darkraise-framework.pin` into `external/darkraise-framework`, with no LFS object under its `.git/lfs/objects`, and the build runs with `FrameworkPinStrict=true`.
A4. [test, high] `build/ci.sh acceptance` runs `tests/build/repository-build.acceptance.sh`, `tests/build/repository-build-nativeaot.acceptance.sh` and `tests/build/ci-pushed-branches.acceptance.sh`, runs each even when an earlier one failed (shown locally with failing stand-in suites), and fails when any failed.
A5. [test, neg, high] With `DOMENT_GATE_PIN_ON_MASTER=1`, the gate fails with DOMENT005 on a pin that is not an ancestor of the framework's `origin/master`, on a feature branch and on a detached HEAD; without it, on a branch other than master or main, the same pin does not fail the gate.
A6. [test, high] The workflow passes `DOMENT_CI_PIN_ON_MASTER=1` exactly for a push to master and a pull request into master, and the `check` log prints `ci: gate DOMENT_GATE_PIN_ON_MASTER=<value>`.
A7. [test, neg, high] Every workflow's `on:` declares only `push`, `pull_request` and `workflow_dispatch`, and a pull request from a fork that leaves the workflow unchanged has its job skipped by the job condition.
A8. [test, neg, high] No job's `runs-on` names a GitHub-hosted label (`ubuntu-*`, `windows-*`, `macos-*`), and every `uses:` names an `actions/*` action at a full 40-character commit SHA.
A9. [test, neg, high] The secret `DARKRAISE_FRAMEWORK_DEPLOY_KEY` is referenced by the framework checkout step only; after that step `build/ci.sh verify` finds no `core.sshCommand` and no private key under `RUNNER_TEMP` (and fails on a stand-in that has either); the workflow grants `contents: read` and nothing else.
A10. [test, high] A pushed branch whose pin is not in the framework's remote fails at the framework checkout, with an error annotation naming the pin and saying to push the framework commit, check the secret or check outbound SSH.
A11. [test, high] `build/ci.sh verify` fails, before any build, with an error annotation naming the package, when `clang`, `zlib.h`, `jq`, `file`, `ps` or `pgrep` is missing (shown locally with stand-in `PATH` and include directory).
A12. [test, high] A newer push to the same non-master branch cancels that branch's run in progress; no run on master is cancelled by another run.
A13. [test, high] Cases A17 and A20 of `tests/build/repository-build-nativeaot.acceptance.sh` pass when that suite runs from master on this host, and its case A17 passes with an SDK that is not under `/usr/local/share/dotnet`.
A14. [test, high] The `CI` run of the doment master push made at finishing passes both jobs.
A15. [demo, high] `docs/architecture.md` records the workflow, its triggers and fork controls, the runner label and packages, the secret name, `build/ci.sh` and `DOMENT_GATE_PIN_ON_MASTER`, and the sentences §3.8 lists are corrected.
A16. [test, neg, high] Only the gate call of `build/ci.sh check` sees `DOMENT_GATE_PIN_ON_MASTER`, and every `tests/build` runner unsets it, so the acceptance job passes on a master push.
A17. [test, high] After the finishing master push, a `workflow_dispatch` run on a branch starts both entries.
A18. [test, high] `build/ci.sh verify` fails, before any build, with an error annotation naming the dirty path, the free space found, or the LFS objects found, on a stand-in framework that is not clean, a minimum free space above what the disk has, or a stand-in with LFS objects.
A19. [test, high] `build/ci.sh check` runs the gate even when `build/check.sh` failed (shown locally with a failing stand-in), and fails when either failed.
A20. [test, high] A same-repository pull request into master starts `CI`, both entries pass, and the `check` log shows `ci: gate DOMENT_GATE_PIN_ON_MASTER=1`.
A21. [test, high] The deploy key on `darkraise-framework` reports `read_only: true` (`gh api repos/darkraise/darkraise-framework/keys`).
A22. [test, high] `gh api repos/darkraise/doment/actions/permissions/fork-pr-contributor-approval` reports `all_external_contributors`, and `gh api repos/darkraise/doment/actions/permissions` reports `sha_pinning_required: true`.
A23. [test, neg, high] No step before the framework checkout runs a file from the checked-out tree.
A24. [test, high] The probe job prints `$ACTIONS_RUNNER_HOOK_JOB_STARTED` and fails unless that file holds ghr's fork refusal.
A25. [test, neg, high] With `GITHUB_ACTIONS=true`, `build/check.sh` runs no `dotnet build-server shutdown`; without it, it still does.

## Riskiest assumption

Three parts, in the order the plan checks them:

1. **The pool picks up the jobs.** The `doment-linux` pool is new owner setup, and the framework's own pool had run no
   job by 2026-11-25 (`darkraise-framework/docs/dforge/specs/2026-11-25-ci-on-ghr-design.md`). A job no runner serves
   stays queued with no log line. The plan's first pushed run is a probe job on `[self-hosted, doment-linux]` that
   prints the host and runner name, `$ACTIONS_RUNNER_HOOK_JOB_STARTED` (failing unless that file holds ghr's fork
   refusal, A24), `whoami`, `$HOME`, whether `~/.ssh` and `~/.nuget/packages` exist and are
   non-empty, and the job's cgroup; still queued after 15 minutes, it is cancelled and the owner is asked.
2. **The framework checkout is clean and LFS-free under strict mode.** Here the framework is a worktree made with LFS
   smudging off (`tools/framework.sh`); on the runner it is an `actions/checkout` clone, and a runner-user LFS filter
   could smudge or modify paths. `GIT_LFS_SKIP_SMUDGE=1` on the checkout and `build/ci.sh verify` name the cause if so.
3. **The build and the acceptance suites pass on a fresh single-use ghr runner.** They have only ever run on this
   development host, with its NuGet package folder, its SDK under `/usr/local/share/dotnet` (case A17 already depends
   on that) and a long-lived framework worktree.

All three: unverified — the plan's first task verifies it: it pushes the probe, then the workflow, on a feature branch
before the other tasks, and what the first runs show is fixed before anything is built on it.

## Critic findings

Round 1 (dforge:judge-opus, 2026-11-25): 0 Blocker, 2 High, 5 Medium, 2 Nit; every finding fixed in the spec.

- [High, fixed] `DOMENT_GATE_PIN_ON_MASTER` reached the acceptance suites and would break `run.sh`'s `gate_main_pin` on master: passed to the gate call of `build/ci.sh check` only, unset by every `tests/build` runner (§3.3, §3.5, A16).
- [High, fixed] A fixed A20 base diffed to HEAD would check later epics' rows, including M7's Windows-only ones: A20 diffs a fixed range (§3.5).
- [Medium, fixed] The job's `if:` skipped `workflow_dispatch`: condition rewritten (§3.1, A17).
- [Medium, fixed] `persist-credentials: true` left the deploy key readable by later steps: `false`, with `DOMENT_GATE_NO_FETCH=1` on the gate call (§3.2 step 3, §3.3, A9).
- [Medium, fixed] Pool pickup was missing from the riskiest assumption: added as part 1, with a probe job and a 15-minute limit.
- [Medium, fixed] Pool size unstated: at least two concurrent runners (§3.6), queue time measured (§3.1).
- [Medium, fixed] Framework cleanliness under strict mode unverified: `build/ci.sh verify` (§3.3, A18) and riskiest assumption part 2.
- [Nit, fixed] Whether the gate runs after a failed `build/check.sh`: it does (§3.3, A19).
- [Nit, fixed] No free-space check: 20 GB minimum (§3.3, A18).

## Review rulings

Fable, round 1 (2026-11-25): 1 Blocker, 2 High, 10 Medium, 6 Nit; 19 rulings, 1 item for the owner.

- Fork pull requests (Blocker): §3.1 states what the job condition does not do; fork code is kept off the host by ghr's fork refusal and the approval setting (§3.6 item 3, A22); A7 reworded; the limit goes into `docs/architecture.md`. The owner's choice between the ghr refusal with the approval setting and the approval setting alone is asked at the spec review.
- Same-repository pull requests (High): A20 added; the check log prints the value passed (§3.3, A6); A5 covers a detached HEAD; §3.6 item 4 opens and closes one pull request.
- Untestable negative statements (High): the checks and command sequences moved into `build/ci.sh` with replaceable inputs, tested locally (§3.3, A4, A9, A11, A18, A19); A10 stays a live check on a throwaway branch.
- Concurrency on master: a group per master run; A12 reworded.
- Deploy key boundary: §3.7 Limits states that write access to doment implies read access to the framework; recorded in `docs/architecture.md`.
- A9 observable: `build/ci.sh verify` asserts the key is gone; the no-tree-code-before-the-checkout invariant (§3.2, A23).
- LFS: `GIT_LFS_SKIP_SMUDGE=1` on the framework checkout; no LFS object asserted (§3.3, A3).
- Read-only key: A21; the private half piped into `gh secret set` and deleted (§3.6 item 2).
- A20's gate call sets `DOMENT_GATE_NO_FETCH=1` (§3.5).
- Pool facts: citations corrected to ghr's own documents and the framework plan (§2); the probe prints the runner's user, home and caches.
- This epic's tests: `tests/build/ci-pushed-branches.acceptance.sh`, run by the `acceptance` entry (§3.5, A4).
- SDK install directory: always `$RUNNER_TEMP/dotnet` (§3.2 step 6).
- Tools the suites need: `jq`, `file`, `procps`, `openssh-client` (§3.3, §3.6 item 1; `ssh` checked before the checkout).
- Process cleanup: applied differently. A host-wide `dotnet build-server shutdown` would stop other jobs' servers, since every ghr runner is the same user; the job environment disables node reuse, the MSBuild server and the shared compiler instead, so the job starts none (§3.2).

Fable, round 2 (2026-11-25): 0 Blocker and 0 High left open; 7 rulings, nothing undecided.

- Fork pull requests: closed; ghr's hook refuses every fork-controlled event and has no switch, so no owner choice remains (§3.1).
- ghr's refusal on the host (High): the probe checks the installed hook (A24); the approval setting is turned on before ghr serves doment (§3.6 item 3).
- Merge boundary: §3.6 item 3 puts the owner's review at merging or pushing a fork's code; §3.7 forbids a merge queue.
- Process cleanup: the false "deliberately not run" sentence replaced; the session also made `build/check.sh` skip its own shutdown on CI, since that shutdown would stop the framework jobs' servers on the shared runner user (§3.2, A25).
- A7 is an allowlist of triggers.
- §3.1 cross-references corrected to §3.6.
- Step 4 is conditioned on the framework step's outcome and names blocked outbound SSH.
- The clean check uses the build's definition (§3.3).
- Action pinning: A8, plus the repository's SHA-pinning setting (§3.6 item 3, A22).
- A17 is verified after the finishing master push; §3.6 item 4 names the `workflow` scope and the 54 commits the first push publishes.
- §3.8 lists the `docs/architecture.md` sentences to change.
