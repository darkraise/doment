# CI for pushed branches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: dforge:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every push of a doment branch, and every same-repository pull request into master, builds, tests and NativeAOT-publishes doment on the ghr `doment-linux` pool, with the private framework checked out at the pin through a read-only deploy key.

**Architecture:** One workflow, `.github/workflows/ci.yml`, with one matrix job (`check`, `acceptance`) on `[self-hosted, doment-linux]`. Inline steps check out doment and the framework; everything after the key's step goes through one tracked script, `build/ci.sh verify|check|acceptance`, so every failure path is tested locally with stand-ins in a new suite, `tests/build/ci-pushed-branches.acceptance.sh`. `build/gate.sh` gains `DOMENT_GATE_PIN_ON_MASTER`; `build/check.sh` skips its build-server shutdown on CI; two cases of the NativeAOT suite stop depending on this host.

**Tech Stack:** GitHub Actions (YAML), bash, `gh`, `jq`, .NET SDK 10.0.404, ghr self-hosted runners.

**Spec:** docs/dforge/specs/2026-11-25-ci-pushed-branches-design.md

**Execution:** inline — `claude --model opus --effort high` — the highest task total is 8 (Task 5), the floor row for 6 to 8 is opus/high, and Tasks 1 and 5 have risk 3

**Parallelism:** sequential — inline execution

**Task check:** none — full suite every 3 tasks

**Integration check:** `bash build/check.sh && bash tests/build/repository-build.acceptance.sh && bash tests/build/repository-build-nativeaot.acceptance.sh && bash tests/build/ci-pushed-branches.acceptance.sh`

**CI:** none

**Worktree setup:** `bash tools/framework.sh sync && dotnet tool restore`

**Plan review:** 2026-11-25 — dforge:judge-opus — executability 12 / coherence 15 / coverage 15 / assumptions 12 (round 1)

## Global Constraints

- Jobs run only on `[self-hosted, doment-linux]`. No workflow names `ubuntu-*`, `windows-*` or `macos-*`.
- Workflow triggers: only `push` (`branches: ['**']`), `pull_request` (`branches: [master]`) and `workflow_dispatch`. Never `pull_request_target`, `workflow_run`, `issue_comment`, `merge_group` or `schedule`.
- Top-level `permissions: contents: read`, nothing else.
- Every `uses:` is an `actions/*` action at a full 40-character commit SHA, its version tag in a trailing comment.
- The secret `DARKRAISE_FRAMEWORK_DEPLOY_KEY` is referenced in the framework checkout step only. No step before that step runs a file from the checked-out tree.
- Both checkouts use `persist-credentials: false` and `lfs: false`; the framework checkout also has step environment `GIT_LFS_SKIP_SMUDGE: 1`.
- No workflow step runs `dotnet build-server shutdown` (every ghr runner is one user, so it would stop other jobs' servers).
- Every script and test bounds each `dotnet`, `git` network and `gh` call with `timeout`, disables node reuse, the MSBuild server and the shared compiler (`MSBUILDDISABLENODEREUSE=1`, `DOTNET_CLI_USE_MSBUILD_SERVER=0`, `UseSharedCompilation=false`), and leaves no process behind.
- Pushes go to `origin` (`darkraise/doment`, public) only from the run's worktree branch, the throwaway branch `ci/bad-pin`, and master at finishing; consent recorded in the spec's Decision 7 (2026-11-25). Never force-push, never push a tag, never rewrite a pushed commit. The first push publishes the 54 local master commits not on `origin/master`.
- GitHub changes allowed by Decision 7: the deploy key on `darkraise/darkraise-framework`, the doment secret, the two doment Actions settings, one pull request opened and closed. Nothing else on GitHub is changed. The ghr host (spec §3.6 item 1) is the owner's: the session never changes it.
- The private half of the deploy key exists only in a `mktemp -d` directory under the session's scratchpad, piped into `gh secret set`, then deleted in the same command sequence.
- Every text file LF. Bash scripts start `#!/usr/bin/env bash` and `set -uo pipefail` (as the other `tests/build` and `build` scripts do).
- `docs/architecture.md` is the living record; Task 6 does the CI section.
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period, no attribution lines; workflow changes are `chore(ci)`. `docs/dforge/` is gitignored: `git add -f` there.

## Contracts

**C1. Files.**

| Path | Made by | Role |
|---|---|---|
| `.github/workflows/ci.yml` | Task 1 (probe), Task 5 (real) | the `CI` workflow |
| `build/ci.sh` | Task 4 | runner checks and the two entries' command sequences |
| `tests/build/ci-pushed-branches.acceptance.sh` | Task 3 | this spec's acceptance suite |
| `docs/dforge/research/2026-11-25-ci-pool-probe.md` | Task 1 | what the probe printed, and the measured durations (Task 5) |

**C2. `DOMENT_GATE_PIN_ON_MASTER`** (Task 2). Read by `build/gate.sh`. When it is `1`, the DOMENT005 block (today guarded by `branch == master || branch == main`) runs whatever `git branch --show-current` prints, an empty result (detached HEAD) included. Any other value or unset: today's rule, unchanged. The DOMENT005 line stays `error DOMENT005: pin <pin> is not an ancestor of the framework's origin/master`. Every `tests/build` runner (`run.sh`, `architecture-decisions.acceptance.sh`, `repository-build.acceptance.sh`, `repository-build-nativeaot.acceptance.sh`, and the new suite) lists it on its `unset` line.

**C3. `build/check.sh` on CI** (Task 3). When `GITHUB_ACTIONS` is exactly `true`, `finish()` does not run `dotnet build-server shutdown`; everything else in `finish()` stays. Otherwise unchanged.

**C4. `build/ci.sh`** (Task 4). `build/ci.sh verify|check|acceptance`. Finds its tree as `build/check.sh` does: `ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)`, no git. Exit 0 success, 1 any failed check or command, 2 bad usage (no argument, an unknown one, or more than one), printing `usage: build/ci.sh verify|check|acceptance` to stderr. Messages on stdout. Inputs: `PATH`; `DOMENT_CI_ZLIB_INCLUDE` (default `/usr/include`); `DOMENT_CI_MIN_FREE_GB` (default `20`); `DOMENT_CI_FRAMEWORK` (default `$ROOT/external/darkraise-framework`); `RUNNER_TEMP` (when unset or empty, the key-file check is skipped); `DOMENT_CI_PIN_ON_MASTER` (`check` only; `1` or anything else meaning `0`).
- `verify` runs every check below, prints every failure, and exits 1 when any failed:
  - `git -C <fw> config --get core.sshCommand` prints a value → `::error::the deploy key is still configured in the framework checkout (core.sshCommand)`;
  - a regular file under `RUNNER_TEMP` (searched recursively) contains `PRIVATE KEY-----` → `::error::a private key is still present under RUNNER_TEMP: <path>`;
  - `<fw>/.git/lfs/objects` holds any file → `::error::LFS objects were downloaded into the framework checkout`;
  - `git -C <fw> status --porcelain=v1 -z --ignored=matching --untracked-files=all` lists a path whose components include none of `bin`, `obj`, `.vs`, `.idea` → `::error::the framework checkout is not clean: <first such path>`;
  - for each of `clang`→`clang`, `jq`→`jq`, `file`→`file`, `ps`→`procps`, `pgrep`→`procps` not found by `command -v`, and `zlib.h` not a file in `DOMENT_CI_ZLIB_INCLUDE` (package `zlib1g-dev`) → `::error::<package> is missing on the runner; add it to the ghr pool's managed packages`;
  - free space of the file system holding `$ROOT` (`df -Pk`, whole GB rounded down) below `DOMENT_CI_MIN_FREE_GB` → `::error::workspace has <g> GB free at <ROOT>, needs <n> GB`;
  - on success prints `ci: verify ok`.
- `check`: runs `bash "$ROOT/build/check.sh"`, then always `bash "$ROOT/build/gate.sh"` with `DOMENT_GATE_NO_FETCH=1` and `DOMENT_GATE_PIN_ON_MASTER=<v>` in that call's environment only, after printing `ci: gate DOMENT_GATE_PIN_ON_MASTER=<v>` (`<v>` is `1` when `DOMENT_CI_PIN_ON_MASTER` is `1`, else `0`). Exit 1 when either failed.
- `acceptance`: runs, in order and each whatever the previous result, `bash "$ROOT/tests/build/repository-build.acceptance.sh"`, `bash "$ROOT/tests/build/repository-build-nativeaot.acceptance.sh"`, `bash "$ROOT/tests/build/ci-pushed-branches.acceptance.sh"`; before each prints `ci: suite <repository-relative path>`, after each `ci: suite <path> exit=<rc>`. Exit 1 when any failed.

**C5. Workflow `CI`** (Task 5). `name: CI`; triggers and permissions per Global Constraints (`push` with `branches: ['**']`, `pull_request` with `branches: [master]`, `workflow_dispatch`; `permissions: contents: read`). Job id `build`, `name: ${{ matrix.suite }}`, `strategy: {fail-fast: false, matrix: {suite: [check, acceptance]}}`, `runs-on: [self-hosted, doment-linux]`, job `if:` `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`, `timeout-minutes` 60 for `check` and 180 for `acceptance` (`${{ matrix.suite == 'check' && 60 || 180 }}`) until Task 6 sets the measured values. Job `env`: `MSBUILDDISABLENODEREUSE: 1`, `DOTNET_CLI_USE_MSBUILD_SERVER: 0`, `UseSharedCompilation: false`, `DOTNET_CLI_TELEMETRY_OPTOUT: 1`, `TESTINGPLATFORM_TELEMETRY_OPTOUT: 1`, `DOTNET_NOLOGO: 1`. `concurrency`: `group: ci-${{ github.event_name }}-${{ github.ref }}${{ github.ref == 'refs/heads/master' && format('-{0}', github.run_id) || '' }}`, `cancel-in-progress: true`. Steps in order, ids in brackets: doment checkout [`doment`] (`actions/checkout`, `with: {fetch-depth: 0, lfs: false, persist-credentials: false}`); pin read and `ssh` check [`pin`], output `pin`; framework checkout [`framework`] (`actions/checkout`, `with: {repository: darkraise/darkraise-framework, ref: ${{ steps.pin.outputs.pin }}, path: external/darkraise-framework, ssh-key: ${{ secrets.DARKRAISE_FRAMEWORK_DEPLOY_KEY }}, fetch-depth: 0, lfs: false, persist-credentials: false}`, `env: {GIT_LFS_SKIP_SMUDGE: 1}`); failure annotation; `bash build/ci.sh verify`; setup-dotnet with `global-json-file: global.json` and step env `DOTNET_INSTALL_DIR: ${{ runner.temp }}/dotnet`; `dotnet --version`; `timeout 600 dotnet tool restore`; `bash build/ci.sh ${{ matrix.suite }}` with step env `DOMENT_CI_PIN_ON_MASTER: ${{ ((github.event_name == 'push' && github.ref == 'refs/heads/master') || (github.event_name == 'pull_request' && github.base_ref == 'master')) && '1' || '0' }}`. The pin step's failure message: `::error::build/darkraise-framework.pin does not hold one 40-character commit hash`; the missing-`ssh` message: `::error::openssh-client is missing on the runner; add it to the ghr pool's managed packages`. The framework-failure step: `if: failure() && steps.framework.outcome == 'failure'`, message `::error::cannot check out darkraise-framework at <pin>: push that framework commit to its origin, check the DARKRAISE_FRAMEWORK_DEPLOY_KEY secret, or check that outbound SSH to github.com is open`.

**C6. New suite output** (Task 3). Same structure and helpers as `tests/build/repository-build-nativeaot.acceptance.sh` (`case_`, `note`, `rc_is`, `has`, `hasnt`, `run`, a `DESC` table, functions `t_A<n>`, `FILTER` as `$1`): one line per test, `ok   A<n>: <desc>` or `FAIL A<n>: <desc>` followed by its notes, last line `<p> passed, <f> failed`, exit 0 only when nothing failed. Tests are named by this spec's acceptance numbers.

## Assumptions (evidence)

- The `doment-linux` pool serves doment. Unverified — Task 1 verifies it (spec Riskiest assumption part 1); still queued after 15 minutes, the probe is cancelled and the owner is asked (auto run: `scripts/auto-run stop` with that reason, then ask).
- The framework checkout is clean and LFS-free on the runner. Unverified — Task 5's first run verifies it through `build/ci.sh verify` (spec part 2).
- The build and the suites pass on a fresh runner. Unverified — Task 5 verifies it (spec part 3); failures it shows are fixed in Task 5 without new skips, each as its own commit.
- `gh api repos/darkraise/doment/actions/permissions/fork-pr-contributor-approval` returned `{"approval_policy":"first_time_contributors"}` and `gh api repos/darkraise/doment/actions/permissions` returned `{"enabled":true,"allowed_actions":"all","sha_pinning_required":false}` (2026-11-25). Both have PUT counterparts in GitHub's REST API ("Set fork PR contributor approval permissions for a repository", "Set GitHub Actions permissions for a repository").
- `gh repo deploy-key add` adds a read-only key unless `--allow-write` is given (`gh repo deploy-key add --help`). Unverified on this host's `gh` version — Task 1 Step 4 reads `read_only`.
- ghr's job-started hook prints `ghr: refusing a job started from another repository` (`/root/repositories/ghr/hooks/job-started.sh`, 2026-11-25); the probe matches `refusing a job started from another repository` in the file `$ACTIONS_RUNNER_HOOK_JOB_STARTED` names.
- A20's fixed range: base `35192a629bedf8b342ebd5e6cdce851d1c89754c` (docs(registers): mark the build plan in flight), end `13ad5350a066e58bf4be3443203a5a9d07708c3a` (docs(plans): complete repository-build-nativeaot); `git diff <base> <end> -- docs/third-party-exceptions.md` adds exactly one `|`-row, `Microsoft.NET.ILLink.Tasks` (run 2026-11-25).
- `actions/checkout` with `fetch-depth: 0` fetches `+refs/heads/*:refs/remotes/origin/*`, checks out a 40-character `ref` detached, and with `persist-credentials: false` removes the key file and `core.sshCommand` when its main step ends (Fable round 1, from the action's source). Unverified on the pinned SHA — `build/ci.sh verify` asserts the removal on every run.
- The three-suite integration run took 1170 s on this host (`.dforge/suites.tsv`, commit 14d9667); the 180-minute starting budget for `acceptance` covers the NativeAOT suite's extra runs.
- A14 (the master push's run passes) and A17 (a dispatch run) can be checked only after the finishing master push, so no task runs them: register `2026-11-25-ci-pushed-branches` row 7 holds the push and both checks with their exact commands, and the run's switch notes repeat them for finishing.
- `gh auth status` (2026-11-25) shows Git operations over HTTPS with token scopes including `workflow` and `repo`, so pushing a workflow file over doment's HTTPS `origin` is allowed.
- Job labels and runner names are read with `gh api repos/darkraise/doment/actions/runs/<id>/jobs` (REST fields `labels`, `runner_name`, `started_at`, `completed_at`), not `gh run view --json jobs`, whose job objects may lack them.
- A12's cancellation is verified statically (the concurrency group and `cancel-in-progress`); GitHub's documented concurrency behaviour does the cancelling.
- Plan review round 1 (dforge:judge-opus; the agy panel seat returned no review, its headless run denied a command permission) scored executability 12 and assumptions 12, borderline: all 6 Important and 8 Minor findings were fixed in place, and with no Critical finding and no score of 8 or below no second round runs.
- `**CI:** none` because no CI configuration exists before this plan; the plan creates it, and its jobs run only on the ghr pool, which has no Pitfalls row in ci-parity.md, so no platform is uncovered.

## Task index

1. GitHub settings, deploy key and pool probe
2. Gate pin-on-master switch
3. CI-ready check script and NativeAOT suite cases
4. The build/ci.sh script
5. The CI workflow and its first runs
6. Pull request run, measured timeouts and documentation

---

### Task 1: GitHub settings, deploy key and pool probe

**Files:**
- Create: `.github/workflows/ci.yml` (probe version, replaced in Task 5)
- Create: `docs/dforge/research/2026-11-25-ci-pool-probe.md`

**Interfaces:**
- Consumes: none
- Produces: C1 `.github/workflows/ci.yml` (probe), C1 research note; the secret `DARKRAISE_FRAMEWORK_DEPLOY_KEY` and the read-only deploy key that Task 5 uses.

**Items:** 2026-11-25-ci-pushed-branches#3, 2026-11-25-ci-pushed-branches#6
**Depends on:** none
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 3 = 6
**Lenses:** security

- [ ] **Step 1: No new test, because this task changes GitHub settings and runs a throwaway probe job; its checks are the `gh api` reads and the probe job's own exit status in Step 4, which fail on every fault the task can make (a writable key, a missing secret, an unchanged setting, a pool that never picks up the job, a missing fork refusal)**

- [ ] **Step 2: Record the starting state**

Run: `timeout 30 gh api repos/darkraise/doment/actions/permissions/fork-pr-contributor-approval; timeout 30 gh api repos/darkraise/doment/actions/permissions; timeout 30 gh api repos/darkraise/darkraise-framework/keys --jq '.[] | [.id, .title, .read_only] | @tsv'; timeout 30 gh secret list -R darkraise/doment`
Expected: approval `first_time_contributors`, `sha_pinning_required` false, no key titled `doment CI (read-only)`, no secret `DARKRAISE_FRAMEWORK_DEPLOY_KEY`. A key or secret already present stops the task: ask (auto run: pending decision) before replacing it.

- [ ] **Step 3: Implement**

1. Settings first (spec §3.6 item 3, before ghr serves doment): `PUT repos/darkraise/doment/actions/permissions/fork-pr-contributor-approval` with `approval_policy=all_external_contributors`; `PUT repos/darkraise/doment/actions/permissions` with `enabled=true`, `allowed_actions=all`, `sha_pinning_required=true` (`gh api -X PUT … -F/-f`, each under `timeout 30`).
2. Deploy key, in one command sequence: `d=$(mktemp -d "<scratchpad>/key.XXXXXX")`; `ssh-keygen -q -t ed25519 -N '' -C 'doment CI (read-only)' -f "$d/key"`; `timeout 60 gh repo deploy-key add "$d/key.pub" -R darkraise/darkraise-framework --title 'doment CI (read-only)'` (no `--allow-write`); `timeout 60 gh secret set DARKRAISE_FRAMEWORK_DEPLOY_KEY -R darkraise/doment < "$d/key"`; `rm -rf "$d"` — the `rm` runs whatever the earlier commands returned.
3. Probe workflow `.github/workflows/ci.yml`: `name: CI`; `on: push` with `branches: ['**']`; `permissions: contents: read`; one job `probe`, `runs-on: [self-hosted, doment-linux]`, `timeout-minutes: 10`, no `uses:` step, one `run:` step that prints `host`, `runner: $RUNNER_NAME`, `user: $(whoami)`, `home: $HOME`, for each of `~/.ssh` and `~/.nuget/packages` whether it exists and how many entries it has, `cgroup: $(cat /proc/self/cgroup)`, `hook: $ACTIONS_RUNNER_HOOK_JOB_STARTED`, the output of `command -v clang jq file ps pgrep ssh`, and `df -Pk "$GITHUB_WORKSPACE"`; then fails with `::error::ghr's fork refusal is not installed` unless `$ACTIONS_RUNNER_HOOK_JOB_STARTED` names a readable file containing `refusing a job started from another repository`.
4. Commit (`chore(ci): add a runner pool probe`) and push the worktree branch: `timeout 300 git push -u origin HEAD`.
5. Wait for the run: find it with `timeout 60 gh run list -R darkraise/doment --branch <branch> --limit 1 --json databaseId,status,conclusion`, polling every 30 s. Still `queued` after 15 minutes: `timeout 60 gh run cancel <id>`, then stop and ask the owner whether ghr serves doment with label `doment-linux` (auto run: `scripts/auto-run stop --reason "the doment-linux pool picked up no job in 15 minutes"`). A probe that fails on the fork-refusal check stops the task the same way (reason `ghr's fork refusal is not installed on the doment-linux pool`): only the owner can fix the ghr host.
6. Write `docs/dforge/research/2026-11-25-ci-pool-probe.md`: the date, the run URL, and each printed fact as one bullet; the tools the probe found missing are listed as owner actions.

- [ ] **Step 4: Verify**

Run: `timeout 30 gh api repos/darkraise/doment/actions/permissions/fork-pr-contributor-approval --jq .approval_policy; timeout 30 gh api repos/darkraise/doment/actions/permissions --jq .sha_pinning_required; timeout 30 gh api repos/darkraise/darkraise-framework/keys --jq '.[] | select(.title == "doment CI (read-only)") | .read_only'; timeout 30 gh secret list -R darkraise/doment --json name --jq '.[].name'; timeout 60 gh api repos/darkraise/doment/actions/runs/<id>/jobs --jq '.jobs[] | [.conclusion, (.labels | join(",")), .runner_name] | @tsv'; ls <scratchpad> | grep -c '^key\.' || true`
Expected: `all_external_contributors`; `true`; `true` (A21); `DARKRAISE_FRAMEWORK_DEPLOY_KEY`; `success`, labels `self-hosted,doment-linux` and a runner name (A24); `0` key directories left. A missing tool in the probe output does not fail the task, but it is reported to the owner before Task 5.

- [ ] **Step 5: Commit**

```bash
git add -f docs/dforge/research/2026-11-25-ci-pool-probe.md
git commit -m "docs(research): record the CI pool probe"
```

### Task 2: Gate pin-on-master switch

**Files:**
- Modify: `build/gate.sh` (the block after `branch=$(git -C "$TREE" branch --show-current)`)
- Modify: `tests/build/run.sh` (`case_gate_main_pin`; the `unset` line near the top)
- Modify: `tests/build/architecture-decisions.acceptance.sh`, `tests/build/repository-build.acceptance.sh`, `tests/build/repository-build-nativeaot.acceptance.sh` (their `unset` lines)
- Test: `tests/build/run.sh`

**Interfaces:**
- Consumes: none
- Produces: C2

**Items:** 2026-11-25-ci-pushed-branches#5
**Depends on:** none
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the test `tests/build/run.sh::case_gate_main_pin`**

- `tests/build/run.sh::case_gate_main_pin` (integration): after its existing `git switch -q -c topic` case (exit 0, no DOMENT005), three more rows on the same fixture, whose pin `$c2` is not an ancestor of the fixture framework's `origin/master`: (a) on branch `topic` with `DOMENT_GATE_PIN_ON_MASTER=1`, the gate exits 1 with exactly one line `error DOMENT005: pin $c2 is not an ancestor of the framework's origin/master` and exactly one `error DOMENT` line; (b) the same with the tree on a detached HEAD (`git checkout -q --detach`), same result; (c) on the detached HEAD with `DOMENT_GATE_PIN_ON_MASTER=0`, exit 0 and no `DOMENT005`. Rows (a) and (b) fail today because the gate ignores the variable off master and main.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 1800 bash tests/build/run.sh gate_main_pin`
Expected: FAIL on rows (a) and (b) (exit 0, no DOMENT005 line).

- [ ] **Step 3: Implement**

1. `build/gate.sh`: the condition `if [[ $branch == master || $branch == main ]]` becomes true also when `${DOMENT_GATE_PIN_ON_MASTER:-}` is `1` (C2). The body, its fetch, its DOMENT_GATE_NO_FETCH handling and its message stay as they are.
2. Add `DOMENT_GATE_PIN_ON_MASTER` to the `unset` line of `tests/build/run.sh`, `tests/build/architecture-decisions.acceptance.sh`, `tests/build/repository-build.acceptance.sh` and `tests/build/repository-build-nativeaot.acceptance.sh`, so a caller's value cannot reach a case such as the unchanged `topic` row.
3. `docs/architecture.md`: in both places that describe DOMENT005 as applying "on master or main" (the gate's description in "Repository and build" and the pin-strict paragraph under "The pin"; find them with `grep -n 'DOMENT005' docs/architecture.md`), add that `DOMENT_GATE_PIN_ON_MASTER=1` applies it on any branch or a detached HEAD.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 1800 bash tests/build/run.sh gate_main_pin && DOMENT_GATE_PIN_ON_MASTER=1 timeout 1800 bash tests/build/run.sh gate_main_pin`
Expected: PASS both times (the second shows the `unset` line keeps the caller's value away from the `topic` row: A16's runner half).

- [ ] **Step 5: Commit**

```bash
git add build/gate.sh tests/build/run.sh tests/build/architecture-decisions.acceptance.sh tests/build/repository-build.acceptance.sh tests/build/repository-build-nativeaot.acceptance.sh docs/architecture.md
git commit -m "feat(build): let the gate check the pin off master"
```

### Task 3: CI-ready check script and NativeAOT suite cases

**Files:**
- Modify: `build/check.sh` (`finish()`)
- Modify: `tests/build/repository-build-nativeaot.acceptance.sh` (`t_A17`, `t_A20`)
- Create: `tests/build/ci-pushed-branches.acceptance.sh`

**Interfaces:**
- Consumes: C2 (the new suite's `unset` line)
- Produces: C3, C6

**Items:** 2026-11-24-repository-build-nativeaot#21
**Depends on:** none
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing tests**

- `tests/build/ci-pushed-branches.acceptance.sh::A25` (integration): a stand-in directory on `PATH` holds a `dotnet` script that appends its arguments to a log file and exits 0; `bash build/check.sh build` run from the real tree with that `PATH` and `GITHUB_ACTIONS=true` leaves no log line containing `build-server shutdown`; the same run without `GITHUB_ACTIONS` leaves exactly one. Fails today because `finish()` always shuts down.
- `tests/build/repository-build-nativeaot.acceptance.sh::A20` (integration, existing, changed by Step 3): run from the worktree branch, whose merge base with master is master itself, it passes and counts exactly one platform-packages row (`Microsoft.NET.ILLink.Tasks`). Fails today with `no platform-packages row was added by this epic`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `timeout 600 bash tests/build/ci-pushed-branches.acceptance.sh '^A25$'; timeout 1800 bash tests/build/repository-build-nativeaot.acceptance.sh '^A20$'`
Expected: `FAIL A25` (one shutdown line under `GITHUB_ACTIONS=true`); `FAIL A20` with `no platform-packages row was added by this epic`.

- [ ] **Step 3: Implement**

1. Create the suite per C6, copying the nativeaot suite's environment block (its `export` and `unset` lines, with `DOMENT_GATE_PIN_ON_MASTER` added to `unset` and `GITHUB_ACTIONS` too), helpers and runner loop; `DESC` gets `[A25]="check.sh skips the build-server shutdown on CI"`.
2. `build/check.sh` `finish()`: skip the `setsid timeout -k 10 120 dotnet build-server shutdown` block when `${GITHUB_ACTIONS:-}` is `true` (C3); `kill_child` and `rm -rf "$TMP"` still run. A one-line comment says why (shared runner user).
3. `t_A20`: replace `base=$(git -C "$REPO_ROOT" merge-base HEAD master)` and the diff `"$base" HEAD` with the fixed range `35192a629bedf8b342ebd5e6cdce851d1c89754c` to `13ad5350a066e58bf4be3443203a5a9d07708c3a`, held in two variables with a comment saying the rows are still checked against the current restore output; set `DOMENT_GATE_NO_FETCH=1` in the `ENVV` of its `build/gate.sh` call.
4. `t_A17`: replace `"DOTNET_ROOT=/usr/local/share/dotnet"` with the directory of `readlink -f "$(command -v dotnet)"`, computed as `build/check.sh` computes `DOTNET_ROOT`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash tests/build/ci-pushed-branches.acceptance.sh '^A25$' && timeout 2400 bash tests/build/repository-build-nativeaot.acceptance.sh '^A(17|20)$'`
Expected: `ok   A25`, `ok   A17`, `ok   A20`. A17 on an SDK outside `/usr/local/share/dotnet` (A13's second half) is checked by Task 5's CI run.

- [ ] **Step 5: Commit**

```bash
git add build/check.sh tests/build/repository-build-nativeaot.acceptance.sh tests/build/ci-pushed-branches.acceptance.sh
git commit -m "fix(build): make check.sh and A17 A20 CI-ready"
```

### Task 4: The build/ci.sh script

**Files:**
- Create: `build/ci.sh`
- Modify: `tests/build/ci-pushed-branches.acceptance.sh`

**Interfaces:**
- Consumes: C2 (passes `DOMENT_GATE_PIN_ON_MASTER` to the gate), C6
- Produces: C4

**Items:** 2026-11-25-ci-pushed-branches#2
**Depends on:** Task 2, Task 3
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing tests**

Each test copies `build/ci.sh` into a stand-in tree under the suite's `$OUTSIDE` (so `ROOT` is the stand-in) whose `build/check.sh`, `build/gate.sh` and three suite scripts are stubs that print their name and the values of `DOMENT_GATE_PIN_ON_MASTER` and `DOMENT_GATE_NO_FETCH`, and exit with a code the test sets. The `PATH` of each `ci.sh` call is exactly two directories and nothing else: a directory of symlinks to the real system tools `ci.sh` calls (start from `bash`, `env`, `git`, `df`, `find`, `grep`, `sed`, `awk`, `cat`, `dirname`, `basename`, `readlink`, `mktemp`, `rm`, `ls`, `head`, `wc`, `sort`, `tr`, `cut`, `timeout`, and add any other the implementation calls), and a stub directory holding `clang`, `jq`, `file`, `ps`, `pgrep` as scripts that exit 0, minus the tool a case removes. The suite itself keeps its own `PATH`. The framework is a stand-in git repository at `DOMENT_CI_FRAMEWORK`.

- `…::A4` (integration): `ci.sh acceptance` with the first suite stub exiting 1 runs all three stubs in order (three `ci: suite` start lines and `exit=1`, `exit=0`, `exit=0`) and exits 1; with all three exiting 0 it exits 0.
- `…::A6` (integration): `ci.sh check` with `DOMENT_CI_PIN_ON_MASTER=1` prints `ci: gate DOMENT_GATE_PIN_ON_MASTER=1`, the gate stub sees `1` and `DOMENT_GATE_NO_FETCH=1`, the check.sh stub sees neither variable set; with `DOMENT_CI_PIN_ON_MASTER` unset it prints `=0` and the gate stub sees `0`.
- `…::A19` (integration): `ci.sh check` with the check.sh stub exiting 1 still runs the gate stub and exits 1; check.sh 0 and gate 1 exits 1; both 0 exits 0.
- `…::A9` (integration, `verify` half): with a clean stand-in framework, all tools present, `DOMENT_CI_MIN_FREE_GB=0` and an empty `RUNNER_TEMP`, `verify` prints `ci: verify ok` and exits 0; with `git config core.sshCommand 'ssh -i x'` set in the framework it exits 1 with `::error::the deploy key is still configured in the framework checkout (core.sshCommand)`; with a file holding `-----BEGIN OPENSSH PRIVATE KEY-----` under `RUNNER_TEMP/sub/` it exits 1 with `::error::a private key is still present under RUNNER_TEMP: ` and that path.
- `…::A11` (integration): one row per tool — `clang`, `jq`, `file`, `ps`, `pgrep` left off `PATH`, and `zlib.h` absent from `DOMENT_CI_ZLIB_INCLUDE` — each exits 1 with `::error::<package> is missing on the runner; add it to the ghr pool's managed packages` for `clang`, `jq`, `file`, `procps`, `procps`, `zlib1g-dev` respectively.
- `…::A18` (integration): an untracked file `src/new.txt` in the stand-in framework gives exit 1 and `::error::the framework checkout is not clean: src/new.txt`, while an untracked `src/obj/x.txt` alone gives `ci: verify ok`; `DOMENT_CI_MIN_FREE_GB=100000` gives exit 1 and a line matching `^::error::workspace has [0-9]+ GB free at .*, needs 100000 GB$`; a file `.git/lfs/objects/aa/bb/x` in the framework gives exit 1 and `::error::LFS objects were downloaded into the framework checkout`.
- `…::usage` (unit, desc `ci.sh usage errors`): no argument, `nope`, and `check extra` each exit 2 with `usage: build/ci.sh verify|check|acceptance` on stderr.

All fail today because `build/ci.sh` does not exist.

- [ ] **Step 2: Run tests to verify they fail**

Run: `timeout 600 bash tests/build/ci-pushed-branches.acceptance.sh '^(A4|A6|A9|A11|A18|A19|usage)$'`
Expected: every listed test `FAIL` (no `build/ci.sh`).

- [ ] **Step 3: Implement**

1. `build/ci.sh` per C4: the three subcommands and the usage error; `verify` collects every failure before exiting; the gate variables go only into the gate call's environment (`DOMENT_GATE_NO_FETCH=1 DOMENT_GATE_PIN_ON_MASTER=$v bash …`); `acceptance` never stops at a failed suite.
2. The key-file search is `grep -rlF -- 'PRIVATE KEY-----' "$RUNNER_TEMP"` limited to regular files, skipped when `RUNNER_TEMP` is unset or empty.
3. The clean check parses the `-z` output (status code, space, path), splits each path on `/`, and ignores a path with a `bin`, `obj`, `.vs` or `.idea` component — the same allowance as `build/Doment.BuildChecks.cs`.
4. `chmod +x build/ci.sh` is not needed: the workflow and tests call `bash build/ci.sh`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash tests/build/ci-pushed-branches.acceptance.sh`
Expected: every test `ok`, last line `8 passed, 0 failed` (A4, A6, A9, A11, A18, A19, A25, usage).

- [ ] **Step 5: Commit**

```bash
git add build/ci.sh tests/build/ci-pushed-branches.acceptance.sh
git commit -m "feat(build): add the CI runner script"
```

### Task 5: The CI workflow and its first runs

**Files:**
- Modify: `.github/workflows/ci.yml` (the probe is replaced by C5)
- Modify: `tests/build/ci-pushed-branches.acceptance.sh`
- Modify: `docs/dforge/research/2026-11-25-ci-pool-probe.md` (durations)

**Interfaces:**
- Consumes: C4, C1 (the secret from Task 1)
- Produces: C5

**Items:** 2026-11-25-ci-pushed-branches#1, 2026-11-25-ci-pushed-branches#2, 2026-11-25-ci-pushed-branches#3, 2026-11-25-ci-pushed-branches#4, 2026-11-25-ci-pushed-branches#6
**Depends on:** Task 1, Task 4
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 3 = 8
**Lenses:** security

- [ ] **Step 1: Write the failing tests**

Static checks: text matches on `.github/workflows/*.yml` with `grep`/`awk` (the suite uses no YAML parser), each failing today because the probe workflow has none of the C5 content.

- `…::A7` (unit, neg): the `on:` block of every workflow file declares exactly the keys `push`, `pull_request`, `workflow_dispatch`; `push` has `branches: ['**']` and no `tags`; `pull_request` has `branches: [master]`; and the job `if:` equals the C5 expression.
- `…::A8` (unit, neg): no line matches `runs-on:.*(ubuntu|windows|macos)-`; the one `runs-on` is `[self-hosted, doment-linux]`; every `uses:` line matches `uses: actions/[a-z-]+@[0-9a-f]{40} # v[0-9]`.
- `…::A9s` (unit, neg, desc `secret used once, read-only token`): `secrets.DARKRAISE_FRAMEWORK_DEPLOY_KEY` occurs exactly once, inside the step with `id: framework`; both checkout steps carry `persist-credentials: false` and `lfs: false`; the framework step's `env` sets `GIT_LFS_SKIP_SMUDGE: 1`; the top-level `permissions` block is exactly `contents: read`.
- `…::A6s` (unit, desc `pin-on-master expression`): the run step's `DOMENT_CI_PIN_ON_MASTER` value equals the C5 expression.
- `…::A12` (unit): the `concurrency` block's `group` equals the C5 expression (it contains `github.run_id` guarded by `refs/heads/master`) and `cancel-in-progress: true`.
- `…::A23` (unit, neg): no step before the `id: framework` step has a `run:` that names a path inside the tree (`build/`, `tools/`, `tests/`, `src/`, `./`), except reading `build/darkraise-framework.pin` with `cat` or `<`; no step runs `dotnet build-server shutdown`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `timeout 600 bash tests/build/ci-pushed-branches.acceptance.sh '^(A6s|A7|A8|A9s|A12|A23)$'`
Expected: every listed test `FAIL`.

- [ ] **Step 3: Implement**

1. Resolve the action SHAs once: `timeout 30 gh api repos/actions/checkout/releases/latest --jq .tag_name` then `timeout 30 gh api repos/actions/checkout/commits/<tag> --jq .sha`; the same for `actions/setup-dotnet`. Write each as `uses: actions/<name>@<sha> # <tag>`.
2. Replace `.github/workflows/ci.yml` with C5 exactly, per spec §3.1 and §3.2. The pin step reads the file with bash only (`pin=$(<build/darkraise-framework.pin)`, strip `\r`), checks `^[0-9a-f]{40}$`, writes `pin=<value>` to `GITHUB_OUTPUT`, and checks `command -v ssh`.
3. Run the static tests (Step 4's first command) before pushing.
4. Commit the workflow and the suite together (`git add .github/workflows/ci.yml tests/build/ci-pushed-branches.acceptance.sh`, `chore(ci): build and test every pushed branch`), so the pushed run carries all 14 tests; push the worktree branch (`timeout 300 git push origin HEAD`), and watch the run: `timeout 14400 gh run watch <id> -R darkraise/doment --exit-status`.
5. When a job fails, read its log (`timeout 120 gh run view <id> -R darkraise/doment --log-failed`), fix the cause in the repository without new skips, commit each fix on its own (`fix(build): …` or `chore(ci): …`), push, and watch again. A failure that only the ghr host can fix (a missing package the verify step names, a full disk) stops the task: ask the owner (auto run: pending decision), with the annotation quoted.
6. A10: create the throwaway branch from the worktree branch's tip: `git switch -c ci/bad-pin`, set `build/darkraise-framework.pin` to `0123456789abcdef0123456789abcdef01234567`, commit, `timeout 300 git push origin ci/bad-pin`, wait for its run, then `timeout 60 git push origin --delete ci/bad-pin`, `git switch -` and `git branch -D ci/bad-pin`.
7. Append to the research note each job's duration from the green run (`timeout 60 gh api repos/darkraise/doment/actions/runs/<id>/jobs --jq '.jobs[] | [.name, .created_at, .started_at, .completed_at, .runner_name] | @tsv'`), queue time being `created_at` to `started_at`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash tests/build/ci-pushed-branches.acceptance.sh && timeout 60 gh api repos/darkraise/doment/actions/runs/<green id>/jobs --jq '.jobs[] | [.name, .conclusion, (.labels | join(","))] | @tsv' && timeout 120 gh run view <green id> -R darkraise/doment --log > "$TMPDIR/ci-green.log" && missing=0; for p in 'ci: verify ok' 'ci: gate DOMENT_GATE_PIN_ON_MASTER=0' 'check: 4 steps run, 0 failed' ' 0 violations' 'ci: suite tests/build/repository-build.acceptance.sh exit=0' 'ci: suite tests/build/repository-build-nativeaot.acceptance.sh exit=0' 'ci: suite tests/build/ci-pushed-branches.acceptance.sh exit=0' 'ok   A17' 'ok   A20' '10.0.404'; do grep -qF -- "$p" "$TMPDIR/ci-green.log" || { echo "missing: $p"; missing=1; }; done; [ "${missing:-0}" -eq 0 ] && timeout 120 gh run view <bad-pin id> -R darkraise/doment --log | grep -F 'cannot check out darkraise-framework at 0123456789abcdef0123456789abcdef01234567'`
Expected: `14 passed, 0 failed`; `check success self-hosted,doment-linux` and `acceptance success self-hosted,doment-linux` (A1, A3); no `missing:` line, so every pattern is in the green run's log (A2 with `10.0.404`, A4, A13's case A17 on the setup-dotnet SDK); the bad-pin run's annotation is found (A10).

- [ ] **Step 5: Commit**

```bash
git add -f docs/dforge/research/2026-11-25-ci-pool-probe.md
git commit -m "docs(research): record CI job durations"
```

### Task 6: Pull request run, measured timeouts and documentation

**Files:**
- Modify: `.github/workflows/ci.yml` (`timeout-minutes`)
- Modify: `docs/architecture.md`

**Interfaces:**
- Consumes: C5
- Produces: none

**Items:** 2026-11-25-ci-pushed-branches#5
**Depends on:** Task 5
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: No new test, because the only workflow change is two `timeout-minutes` numbers, whose fault (a YAML or expression error) the pull request run in Step 4 catches, since GitHub rejects or fails a malformed workflow; the documentation is prose no script reads**

- [ ] **Step 2: Set the measured timeouts**

From the research note's durations, set `timeout-minutes` for each entry to twice its measured duration rounded up to the next 10 minutes (C5's expression form, new numbers). Commit (`chore(ci): set job timeouts from measured runs`) and push.

- [ ] **Step 3: Implement the documentation**

`docs/architecture.md`, per spec §3.8: replace "Rules handed to later epics" → "CI for pushed branches" with a "CI" section (workflow, triggers, fork controls: the job condition, ghr's refusal, the approval setting; runner label and packages; the secret; `build/ci.sh`; `DOMENT_GATE_PIN_ON_MASTER`); correct the pin section's sentence that all of CI requires the pin on the framework's remote master (CI requires it on master and on pull requests into it, elsewhere only that the pin exists on the remote); extend Limits with spec §3.7's limits that are not already there — check each against the existing Limits list (`grep -n -A12 '### Limits' docs/architecture.md`) and add only the missing ones among: write access to doment implies read access to the framework; no merge queue while ghr serves doment; the key in the checkout step's environment on the shared runner user — and name the deploy key in the existing credential sentence; in the Toolchain paragraph say the CI runner's SDK comes from setup-dotnet and its clang from ghr.

- [ ] **Step 4: Verify with a pull request**

Run: `timeout 60 gh pr create -R darkraise/doment --base master --head <branch> --title "CI for pushed branches" --body "Verification run for the CI epic; closed without merging (the branch merges locally)."`, then find the pull request run with `timeout 60 gh run list -R darkraise/doment --branch <branch> --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId'`, then `timeout 14400 gh run watch <pr run id> -R darkraise/doment --exit-status && timeout 60 gh run view <pr run id> -R darkraise/doment --log | grep -F 'ci: gate DOMENT_GATE_PIN_ON_MASTER=1' && timeout 600 bash tests/build/ci-pushed-branches.acceptance.sh && timeout 60 gh pr close <number> -R darkraise/doment`
Expected: the pull request run (event `pull_request`) passes both entries and its `check` log has `ci: gate DOMENT_GATE_PIN_ON_MASTER=1` (A20, A6); the suite prints `14 passed, 0 failed`; the pull request is closed, not merged.

- [ ] **Step 5: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): record the CI workflow"
```
