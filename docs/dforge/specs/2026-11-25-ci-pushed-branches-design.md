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

- No `.github/workflows` directory exists. `darkraise/doment` is public; `gh api repos/darkraise/doment/actions/runners`
  lists 0 runners (ghr registers a just-in-time runner per job, so 0 is expected between jobs).
- doment's local master is 54 commits ahead of `origin/master`. darkraise-framework is private; its local master is
  59 commits ahead of its origin, and doment's pin `e3cb121d` is on the framework's `origin/master`.
- `build/gate.sh` runs the pin-ancestry check (DOMENT005) only when `git branch --show-current` prints `master` or
  `main` (`build/gate.sh:131`). A `pull_request` checkout is a detached merge commit, so the check would never run on
  a pull request.
- Acceptance case A17 runs the test executable with `DOTNET_ROOT=/usr/local/share/dotnet`, this host's SDK location
  (`tests/build/repository-build-nativeaot.acceptance.sh`, `t_A17`); a runner whose SDK comes from setup-dotnet has no
  SDK there.
- Acceptance case A20's platform-packages check diffs against `git merge-base HEAD master`, which is HEAD itself on
  master, so it fails on every master run (register `docs/dforge/registers/2026-11-24-repository-build-nativeaot.md`,
  row 21).
- The framework's own CI moves to its ghr pool on 2026-11-25 (`darkraise-framework`,
  `docs/dforge/specs/2026-11-25-ci-on-ghr-design.md`): pool runners are single-use, run natively on the ghr host, and
  their shared tool cache is read-only to jobs.

## 3. Design

### 3.1 Workflow and triggers

One workflow, `.github/workflows/ci.yml`, named `CI`:

- `on: push` with `branches: ['**']`: every branch, no tag.
- `on: pull_request` with `branches: [master]`. The job's `if:` is
  `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`, so a
  fork's pull request starts no job and its code never reaches a runner, while push and dispatch runs start both
  entries.
- No `pull_request_target`, no `workflow_run`, no `schedule`. `workflow_dispatch` is allowed (it runs only for people
  with write access) so a run can be repeated by hand.
- `permissions: contents: read` at the top level.
- `concurrency`: group `ci-<event>-<ref>`; `cancel-in-progress` is true except on `refs/heads/master`, so a newer push
  to a feature branch cancels its older run and master runs always finish.

A same-repository branch with an open pull request gets two runs per push (the push and the pull request's merge
commit), four jobs in all. That is accepted: the pull request run checks the merged tree, the push run the branch. It
is why the pool needs at least two concurrent runners (§3.5); queue time is measured on the first runs.

### 3.2 The job

One job, `build`, with `strategy.matrix.suite: [check, acceptance]`, `fail-fast: false` and `name: ${{ matrix.suite }}`,
so the two entries run as parallel jobs shown as `check` and `acceptance`. `runs-on: [self-hosted, doment-linux]`. Steps, shared by both entries:

1. `actions/checkout` of doment with `fetch-depth: 0` (the acceptance suites read history) and `lfs: false`.
2. Read the pin from `build/darkraise-framework.pin` into a step output; a malformed pin fails here with an error
   annotation.
3. `actions/checkout` of `darkraise/darkraise-framework` at the pin into `external/darkraise-framework`, with
   `ssh-key: ${{ secrets.DARKRAISE_FRAMEWORK_DEPLOY_KEY }}`, `fetch-depth: 0` (so `origin/master` is present for
   DOMENT005), `lfs: false` and `persist-credentials: false`, so the key is removed when the step ends and no later
   step (the pushed branch's own build and test code included) can read it. The secret is referenced in this step
   only. The gate needs no fetch of its own: the checkout already brought `refs/remotes/origin/master`.
4. On failure of step 3, an `if: failure()` step prints
   `::error::cannot check out darkraise-framework at <pin>: push that framework commit to its origin, or check the DARKRAISE_FRAMEWORK_DEPLOY_KEY secret`.
5. Framework clean check: `git -C external/darkraise-framework status --porcelain` must print nothing; otherwise the
   step fails with `::error::the framework checkout is not clean: <first path>`, so a strict-mode DOMENT001 on CI
   comes with its cause.
6. Runner check: `clang` on `PATH` and `zlib.h` present (zlib1g-dev); each missing one fails with
   `::error::<package> is missing on the runner; add it to the ghr pool's managed packages`. Under 20 GB free in the
   workspace fails with `::error::workspace has <g> GB free at <dir>, needs 20 GB`.
7. `actions/setup-dotnet` with `global-json-file: global.json`. `DOTNET_INSTALL_DIR` is the runner's own when that
   directory exists and is writable, `$RUNNER_TEMP/dotnet` otherwise (the ghr tool cache is read-only to jobs).
8. `dotnet tool restore`.
9. The entry's commands:
   - `check`: `build/check.sh`, then `build/gate.sh`; the gate runs even when `build/check.sh` failed, and the step
     fails when either did. Only the gate call gets `DOMENT_GATE_NO_FETCH=1`, and `DOMENT_GATE_PIN_ON_MASTER=1` when
     the run is a push to master or a pull request into master; no other command sees either variable.
   - `acceptance`: `tests/build/repository-build.acceptance.sh`, then
     `tests/build/repository-build-nativeaot.acceptance.sh` (its A25 runs `tests/build/run.sh` and
     `tests/build/architecture-decisions.acceptance.sh`). Each suite runs even when an earlier one failed; the step
     fails when any did.

`timeout-minutes` per entry: a starting budget of 60 for `check` and 180 for `acceptance`; once the first green runs
are measured, each is set to about twice its measured duration.

Only GitHub-owned actions are used (`actions/checkout`, `actions/setup-dotnet`), each pinned to a full commit SHA with
its version in a comment.

### 3.3 Gate change

`build/gate.sh` gains one environment variable: with `DOMENT_GATE_PIN_ON_MASTER=1`, it runs the DOMENT005
pin-ancestry check whatever the branch name. Without it, the current rule stays (master or main only), so local runs
on feature branches behave as today.

### 3.4 Test fixes

- A17 takes `DOTNET_ROOT` from the `dotnet` on `PATH` (`readlink -f "$(command -v dotnet)"`'s directory, as
  `build/check.sh` does) instead of `/usr/local/share/dotnet`.
- A20 diffs a fixed range, from the parent of the repository-build-nativeaot plan's first commit to that plan's last
  commit, both recorded as full SHAs in the suite, instead of `merge-base HEAD master`..HEAD. It then checks exactly
  the rows that epic added, on master and on any branch, and a later epic's rows (M7's Windows-only platform rows
  among them) never reach it.
- Every `tests/build` runner (`run.sh`, `architecture-decisions.acceptance.sh`, `repository-build.acceptance.sh`,
  `repository-build-nativeaot.acceptance.sh`) adds `DOMENT_GATE_PIN_ON_MASTER` to its `unset` line, so a value in the
  caller's environment cannot change a case such as `run.sh`'s `gate_main_pin`.
- The plan reruns both suites on this host after each fix; whatever else fails only on the runner is found by the
  first pushed run (see Riskiest assumption) and fixed the same way, without new skips.

### 3.5 Owner setup outside the repository

Each is a one-time step done by the owner, or by the session with the owner's consent at the spec review:

1. ghr: serve `darkraise/doment` with a pool labelled `doment-linux` of at least two concurrent runners, with
   `clang` and `zlib1g-dev` in its managed apt packages.
2. Deploy key: an ed25519 key pair; the public half added to `darkraise-framework` as a read-only deploy key, the
   private half stored as the doment Actions secret `DARKRAISE_FRAMEWORK_DEPLOY_KEY`.
3. Pushes: verifying this epic needs pushes of a doment branch, and at finishing a push of doment master (54+
   commits).

### 3.6 Documentation

`docs/architecture.md`: the "CI for pushed branches" rules are replaced by a "CI" section recording the workflow, its
triggers and fork rule, the runner label, the secret name, the toolchain packages and `DOMENT_GATE_PIN_ON_MASTER`.
The gate's environment variable is added where the gate is described.

## Acceptance

A1. [test, high] A push of any branch to `darkraise/doment` starts the `CI` workflow, and both of its jobs (`check`, `acceptance`) run on a runner labelled `self-hosted` and `doment-linux`.
A2. [test, high] The `check` job runs with the SDK `global.json` names (`dotnet --version` prints 10.0.404 or a later 10.0.4xx), restores the local tools, runs all four steps of `build/check.sh` and then `build/gate.sh`, and fails when either exits non-zero.
A3. [test, high] Both jobs check out the framework at the commit in `build/darkraise-framework.pin` into `external/darkraise-framework` with no LFS content downloaded, and the build runs with `FrameworkPinStrict=true`.
A4. [test, high] The `acceptance` job runs `tests/build/repository-build.acceptance.sh` and `tests/build/repository-build-nativeaot.acceptance.sh`, runs the second even when the first fails, and fails when either fails.
A5. [test, neg, high] With `DOMENT_GATE_PIN_ON_MASTER=1`, the gate fails with DOMENT005 on a pin that is not an ancestor of the framework's `origin/master`, whatever the branch; without it, on a branch other than master or main, the same pin does not fail the gate.
A6. [test, high] The workflow sets `DOMENT_GATE_PIN_ON_MASTER=1` exactly for a push to master and a pull request into master.
A7. [test, neg, high] No workflow declares `pull_request_target`, and a pull request whose head repository is not `darkraise/doment` starts no job.
A8. [test, neg, high] No job's `runs-on` names a GitHub-hosted label (`ubuntu-*`, `windows-*`, `macos-*`).
A9. [test, neg, high] The secret `DARKRAISE_FRAMEWORK_DEPLOY_KEY` is referenced by the framework checkout step only, the key is not readable by any later step, and the workflow grants `contents: read` and nothing else.
A10. [test, high] When the pin cannot be checked out from the framework's remote, the job fails with an error annotation naming the pin and saying to push the framework commit or check the secret.
A11. [test, high] When `clang` or `zlib.h` is missing on the runner, the job fails before any build with an error annotation naming the missing package.
A12. [test, high] A newer push to the same non-master branch cancels that branch's run in progress; a run on master is never cancelled.
A13. [test, high] Cases A17 and A20 of `tests/build/repository-build-nativeaot.acceptance.sh` pass when that suite runs from master on this host, and its case A17 passes with an SDK that is not under `/usr/local/share/dotnet`.
A14. [test, high] The `CI` run of the doment master push made at finishing passes both jobs.
A15. [demo, high] `docs/architecture.md` records the workflow, its triggers and fork rule, the runner label, the secret name, the toolchain packages and `DOMENT_GATE_PIN_ON_MASTER`.
A16. [test, neg, high] Only the `check` entry's gate call sees `DOMENT_GATE_PIN_ON_MASTER`, and every `tests/build` runner unsets it, so the acceptance job passes on a master push.
A17. [test, high] A `workflow_dispatch` run on a branch starts both entries.
A18. [test, high] A framework checkout that is not clean, or a workspace under 20 GB free, fails the job before any build with an error annotation naming the dirty path or the free space found.
A19. [test, high] In the `check` entry the gate runs even when `build/check.sh` failed, and the job fails when either did.

## Riskiest assumption

Three parts, in the order the plan checks them:

1. **The pool picks up the jobs.** The `doment-linux` pool is new owner setup, and the framework's own pool had run no
   job by 2026-11-25 (`darkraise-framework/docs/dforge/specs/2026-11-25-ci-on-ghr-design.md`). A job no runner serves
   stays queued with no log line. The plan's first pushed run is a probe job on `[self-hosted, doment-linux]` that
   prints the host and runner name; still queued after 15 minutes, it is cancelled and the owner is asked.
2. **The framework checkout is clean under strict mode.** Here the framework is a worktree made with LFS smudging
   off (`tools/framework.sh`); on the runner it is an `actions/checkout` clone, and a system-level LFS filter could
   leave paths modified. The clean check (§3.2 step 5) names the cause if so.
3. **The build and the acceptance suites pass on a fresh single-use ghr runner.** They have only ever run on this
development host, with its NuGet package folder, its SDK under `/usr/local/share/dotnet` (A17 already depends on that)
and a long-lived framework worktree.

All three: unverified — the plan's first task verifies it: it pushes the workflow on a feature branch before the other tasks,
and what the first run shows is fixed before anything is built on it.

## Critic findings

Round 1 (dforge:judge-opus, 2026-11-25): 0 Blocker, 2 High, 5 Medium, 2 Nit; every finding fixed in the spec.

- [High, fixed] `DOMENT_GATE_PIN_ON_MASTER` reached the acceptance suites and would break `run.sh`'s `gate_main_pin` on master: set on the `check` gate call only, unset by every `tests/build` runner (§3.2 step 9, §3.4, A16).
- [High, fixed] A fixed A20 base diffed to HEAD would check later epics' rows, including M7's Windows-only ones: A20 diffs a fixed range (§3.4).
- [Medium, fixed] The job's `if:` skipped `workflow_dispatch`: condition rewritten (§3.1, A17).
- [Medium, fixed] `persist-credentials: true` left the deploy key readable by later steps: `false`, with `DOMENT_GATE_NO_FETCH=1` on the gate call (§3.2 steps 3 and 9, A9).
- [Medium, fixed] Pool pickup was missing from the riskiest assumption: added as part 1, with a probe job and a 15-minute limit.
- [Medium, fixed] Pool size unstated: at least two concurrent runners (§3.5), queue time measured (§3.1).
- [Medium, fixed] Framework cleanliness under strict mode unverified: clean check step (§3.2 step 5, A18) and riskiest assumption part 2.
- [Nit, fixed] Whether the gate runs after a failed `build/check.sh`: it does (§3.2 step 9, A19).
- [Nit, fixed] No free-space check: 20 GB minimum (§3.2 step 6, A18).
