# Review record: 2026-11-25-ci-pushed-branches

Plan: docs/dforge/plans/2026-11-25-ci-pushed-branches.md
Retained: 2026-11-27

Review depth: full (spec,task-risk:1)
Acceptance QA: complete — 22 pass, 0 fail, 0 flaky, 2 cannot-test, 1 demo
final review lens security — 0 Critical, 0 Important, 0 Minor; fixed 0, rejected 0
final review lens silent-failures — 0 Critical, 0 Important, 0 Minor; fixed 0, rejected 0
final review lens test-quality — 0 Critical, 2 Important, 0 Minor; fixed 2, rejected 0
final review lens code-quality — 0 Critical, 0 Important, 0 Minor; fixed 0, rejected 0; parts lang-bash=0,docs-comments=0
Test ratio: 1424 test / 239 code lines (d891a98..153b201)
Final review: clean (commits d891a98..153b201, 3 parked)

## Amendments

## A1 — Task 3
Reason: The new suite inherits `build/ci.sh`'s inputs from the CI job environment (`RUNNER_TEMP`, `DOMENT_CI_PIN_ON_MASTER`), which breaks the A6 and A9 rows on pull request and master runs.
Cost if wrong: None; the unset only isolates the suite.
### Old
````text
1. Create the suite per C6, copying the nativeaot suite's environment block (its `export` and `unset` lines, with `DOMENT_GATE_PIN_ON_MASTER` added to `unset` and `GITHUB_ACTIONS` too), helpers and runner loop; `DESC` gets `[A25]="check.sh skips the build-server shutdown on CI"`.
````
### New
````text
1. Create the suite per C6, copying the nativeaot suite's environment block (its `export` and `unset` lines, with `DOMENT_GATE_PIN_ON_MASTER`, `GITHUB_ACTIONS`, `DOMENT_CI_PIN_ON_MASTER`, `DOMENT_CI_ZLIB_INCLUDE`, `DOMENT_CI_MIN_FREE_GB`, `DOMENT_CI_FRAMEWORK` and `RUNNER_TEMP` added to `unset`, so the CI job's own values never reach a case), helpers and runner loop; `DESC` gets `[A25]="check.sh skips the build-server shutdown on CI"`. Every `build/ci.sh` case sets the inputs it relies on explicitly in its call's environment.
````

## A2 — Task 1
Reason: Under the default `bash -e` shell, a multi-name `command -v` with one tool missing ends the probe step before the fork-refusal check, which contradicts Step 4.
Cost if wrong: A few extra output lines.
### Old
````text
3. Probe workflow `.github/workflows/ci.yml`: `name: CI`; `on: push` with `branches: ['**']`; `permissions: contents: read`; one job `probe`, `runs-on: [self-hosted, doment-linux]`, `timeout-minutes: 10`, no `uses:` step, one `run:` step that prints `host`, `runner: $RUNNER_NAME`, `user: $(whoami)`, `home: $HOME`, for each of `~/.ssh` and `~/.nuget/packages` whether it exists and how many entries it has, `cgroup: $(cat /proc/self/cgroup)`, `hook: $ACTIONS_RUNNER_HOOK_JOB_STARTED`, the output of `command -v clang jq file ps pgrep ssh`, and `df -Pk "$GITHUB_WORKSPACE"`; then fails with `::error::ghr's fork refusal is not installed` unless `$ACTIONS_RUNNER_HOOK_JOB_STARTED` names a readable file containing `refusing a job started from another repository`.
````
### New
````text
3. Probe workflow `.github/workflows/ci.yml`: `name: CI`; `on: push` with `branches: ['**']`; `permissions: contents: read`; one job `probe`, `runs-on: [self-hosted, doment-linux]`, `timeout-minutes: 10`, no `uses:` step, one `run:` step that prints `host`, `runner: $RUNNER_NAME`, `user: $(whoami)`, `home: $HOME`, for each of `~/.ssh` and `~/.nuget/packages` whether it exists and how many entries it has, `cgroup: $(cat /proc/self/cgroup)`, `hook: $ACTIONS_RUNNER_HOOK_JOB_STARTED`, for each of `clang`, `jq`, `file`, `ps`, `pgrep`, `ssh` its own line `command -v <tool> || echo "missing: <tool>"` (a `run:` step without `shell:` runs under `bash -e`, so a failing `command -v` would end the step before the hook check), and `df -Pk "$GITHUB_WORKSPACE"`; then fails with `::error::ghr's fork refusal is not installed` unless `$ACTIONS_RUNNER_HOOK_JOB_STARTED` names a readable file containing `refusing a job started from another repository`. The hook check is the only line of the step allowed to fail it.
````

## A3 — Task 2
Reason: Step 3 item 3 edits `docs/architecture.md` and Step 5 commits it, but Files does not list it.
Cost if wrong: None.
### Old
````text
- Modify: `tests/build/architecture-decisions.acceptance.sh`, `tests/build/repository-build.acceptance.sh`, `tests/build/repository-build-nativeaot.acceptance.sh` (their `unset` lines)
````
### New
````text
- Modify: `tests/build/architecture-decisions.acceptance.sh`, `tests/build/repository-build.acceptance.sh`, `tests/build/repository-build-nativeaot.acceptance.sh` (their `unset` lines)
- Modify: `docs/architecture.md` (the two sentences that describe DOMENT005 as applying on master or main)
````

## A4 — Task 3
Reason: Spec A13's "from master on this host" half is run by no task and recorded in no finishing check.
Cost if wrong: One NativeAOT suite run (two cases) at finishing.
### Old
````text
Expected: `ok   A25`, `ok   A17`, `ok   A20`. A17 on an SDK outside `/usr/local/share/dotnet` (A13's second half) is checked by Task 5's CI run.

- [ ] **Step 5: Commit**

```bash
git add build/check.sh tests/build/repository-build-nativeaot.acceptance.sh tests/build/ci-pushed-branches.acceptance.sh
git commit -m "fix(build): make check.sh and A17 A20 CI-ready"
```
````
### New
````text
Expected: `ok   A25`, `ok   A17`, `ok   A20`. A17 on an SDK outside `/usr/local/share/dotnet` (A13's second half) is checked by Task 5's CI run. A13's first half (the suite run from master on this host) can run only after the finishing merge: append to the Note of row 7 of `docs/dforge/registers/2026-11-25-ci-pushed-branches.md` `; A13: in the main checkout on master after the merge, timeout 2400 bash tests/build/repository-build-nativeaot.acceptance.sh '^A(17|20)$' prints ok A17 and ok A20`, and add `A13` to that row's Item text ("verify A13, A14 and A17").

- [ ] **Step 5: Commit**

```bash
git add build/check.sh tests/build/repository-build-nativeaot.acceptance.sh tests/build/ci-pushed-branches.acceptance.sh
git commit -m "fix(build): make check.sh and A17 A20 CI-ready"
git add -f docs/dforge/registers/2026-11-25-ci-pushed-branches.md
git commit -m "docs(registers): add the A13 master check"
```
````

## A5 — Task 5
Reason: The command's exit status ignores a failing suite, a failing `gh api` and a failing `gh run view`, and it writes to `/ci-green.log` when `TMPDIR` is unset.
Cost if wrong: None; the Expected lines are unchanged.
### Old
````text
Run: `timeout 600 bash tests/build/ci-pushed-branches.acceptance.sh && timeout 60 gh api repos/darkraise/doment/actions/runs/<green id>/jobs --jq '.jobs[] | [.name, .conclusion, (.labels | join(","))] | @tsv' && timeout 120 gh run view <green id> -R darkraise/doment --log > "$TMPDIR/ci-green.log" && missing=0; for p in 'ci: verify ok' 'ci: gate DOMENT_GATE_PIN_ON_MASTER=0' 'check: 4 steps run, 0 failed' ' 0 violations' 'ci: suite tests/build/repository-build.acceptance.sh exit=0' 'ci: suite tests/build/repository-build-nativeaot.acceptance.sh exit=0' 'ci: suite tests/build/ci-pushed-branches.acceptance.sh exit=0' 'ok   A17' 'ok   A20' '10.0.404'; do grep -qF -- "$p" "$TMPDIR/ci-green.log" || { echo "missing: $p"; missing=1; }; done; [ "${missing:-0}" -eq 0 ] && timeout 120 gh run view <bad-pin id> -R darkraise/doment --log | grep -F 'cannot check out darkraise-framework at 0123456789abcdef0123456789abcdef01234567'`
````
### New
````text
Run: `log="${TMPDIR:-/tmp}/ci-green.log"; missing=0; timeout 600 bash tests/build/ci-pushed-branches.acceptance.sh || { echo "missing: suite pass"; missing=1; }; timeout 60 gh api repos/darkraise/doment/actions/runs/<green id>/jobs --jq '.jobs[] | [.name, .conclusion, (.labels | join(","))] | @tsv' || { echo "missing: jobs read"; missing=1; }; timeout 120 gh run view <green id> -R darkraise/doment --log > "$log" || { echo "missing: green log"; missing=1; }; for p in 'ci: verify ok' 'ci: gate DOMENT_GATE_PIN_ON_MASTER=0' 'check: 4 steps run, 0 failed' ' 0 violations' 'ci: suite tests/build/repository-build.acceptance.sh exit=0' 'ci: suite tests/build/repository-build-nativeaot.acceptance.sh exit=0' 'ci: suite tests/build/ci-pushed-branches.acceptance.sh exit=0' 'ok   A17' 'ok   A20' '10.0.404'; do grep -qF -- "$p" "$log" || { echo "missing: $p"; missing=1; }; done; timeout 120 gh run view <bad-pin id> -R darkraise/doment --log | grep -F 'cannot check out darkraise-framework at 0123456789abcdef0123456789abcdef01234567' || { echo "missing: bad-pin annotation"; missing=1; }; rm -f "$log"; [ "$missing" -eq 0 ]`
````

## A6 — Header
Reason: Spec §3.2 step 8 gives `DOMENT_CI_PIN_ON_MASTER` to the `check` entry only, and the Global Constraints require every `dotnet` call to be bounded by `timeout`.
Cost if wrong: The `acceptance` entry sees `0` instead of `1`, and `build/ci.sh acceptance` ignores the variable.
### Old
````text
**C5. Workflow `CI`** (Task 5). `name: CI`; triggers and permissions per Global Constraints (`push` with `branches: ['**']`, `pull_request` with `branches: [master]`, `workflow_dispatch`; `permissions: contents: read`). Job id `build`, `name: ${{ matrix.suite }}`, `strategy: {fail-fast: false, matrix: {suite: [check, acceptance]}}`, `runs-on: [self-hosted, doment-linux]`, job `if:` `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`, `timeout-minutes` 60 for `check` and 180 for `acceptance` (`${{ matrix.suite == 'check' && 60 || 180 }}`) until Task 6 sets the measured values. Job `env`: `MSBUILDDISABLENODEREUSE: 1`, `DOTNET_CLI_USE_MSBUILD_SERVER: 0`, `UseSharedCompilation: false`, `DOTNET_CLI_TELEMETRY_OPTOUT: 1`, `TESTINGPLATFORM_TELEMETRY_OPTOUT: 1`, `DOTNET_NOLOGO: 1`. `concurrency`: `group: ci-${{ github.event_name }}-${{ github.ref }}${{ github.ref == 'refs/heads/master' && format('-{0}', github.run_id) || '' }}`, `cancel-in-progress: true`. Steps in order, ids in brackets: doment checkout [`doment`] (`actions/checkout`, `with: {fetch-depth: 0, lfs: false, persist-credentials: false}`); pin read and `ssh` check [`pin`], output `pin`; framework checkout [`framework`] (`actions/checkout`, `with: {repository: darkraise/darkraise-framework, ref: ${{ steps.pin.outputs.pin }}, path: external/darkraise-framework, ssh-key: ${{ secrets.DARKRAISE_FRAMEWORK_DEPLOY_KEY }}, fetch-depth: 0, lfs: false, persist-credentials: false}`, `env: {GIT_LFS_SKIP_SMUDGE: 1}`); failure annotation; `bash build/ci.sh verify`; setup-dotnet with `global-json-file: global.json` and step env `DOTNET_INSTALL_DIR: ${{ runner.temp }}/dotnet`; `dotnet --version`; `timeout 600 dotnet tool restore`; `bash build/ci.sh ${{ matrix.suite }}` with step env `DOMENT_CI_PIN_ON_MASTER: ${{ ((github.event_name == 'push' && github.ref == 'refs/heads/master') || (github.event_name == 'pull_request' && github.base_ref == 'master')) && '1' || '0' }}`. The pin step's failure message: `::error::build/darkraise-framework.pin does not hold one 40-character commit hash`; the missing-`ssh` message: `::error::openssh-client is missing on the runner; add it to the ghr pool's managed packages`. The framework-failure step: `if: failure() && steps.framework.outcome == 'failure'`, message `::error::cannot check out darkraise-framework at <pin>: push that framework commit to its origin, check the DARKRAISE_FRAMEWORK_DEPLOY_KEY secret, or check that outbound SSH to github.com is open`.
````
### New
````text
**C5. Workflow `CI`** (Task 5). `name: CI`; triggers and permissions per Global Constraints (`push` with `branches: ['**']`, `pull_request` with `branches: [master]`, `workflow_dispatch`; `permissions: contents: read`). Job id `build`, `name: ${{ matrix.suite }}`, `strategy: {fail-fast: false, matrix: {suite: [check, acceptance]}}`, `runs-on: [self-hosted, doment-linux]`, job `if:` `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`, `timeout-minutes` 60 for `check` and 180 for `acceptance` (`${{ matrix.suite == 'check' && 60 || 180 }}`) until Task 6 sets the measured values. Job `env`: `MSBUILDDISABLENODEREUSE: 1`, `DOTNET_CLI_USE_MSBUILD_SERVER: 0`, `UseSharedCompilation: false`, `DOTNET_CLI_TELEMETRY_OPTOUT: 1`, `TESTINGPLATFORM_TELEMETRY_OPTOUT: 1`, `DOTNET_NOLOGO: 1`. `concurrency`: `group: ci-${{ github.event_name }}-${{ github.ref }}${{ github.ref == 'refs/heads/master' && format('-{0}', github.run_id) || '' }}`, `cancel-in-progress: true`. Steps in order, ids in brackets: doment checkout [`doment`] (`actions/checkout`, `with: {fetch-depth: 0, lfs: false, persist-credentials: false}`); pin read and `ssh` check [`pin`], output `pin`; framework checkout [`framework`] (`actions/checkout`, `with: {repository: darkraise/darkraise-framework, ref: ${{ steps.pin.outputs.pin }}, path: external/darkraise-framework, ssh-key: ${{ secrets.DARKRAISE_FRAMEWORK_DEPLOY_KEY }}, fetch-depth: 0, lfs: false, persist-credentials: false}`, `env: {GIT_LFS_SKIP_SMUDGE: 1}`); failure annotation; `bash build/ci.sh verify`; setup-dotnet with `global-json-file: global.json` and step env `DOTNET_INSTALL_DIR: ${{ runner.temp }}/dotnet`; `timeout 60 dotnet --version`; `timeout 600 dotnet tool restore`; `bash build/ci.sh ${{ matrix.suite }}` with step env `DOMENT_CI_PIN_ON_MASTER: ${{ matrix.suite == 'check' && ((github.event_name == 'push' && github.ref == 'refs/heads/master') || (github.event_name == 'pull_request' && github.base_ref == 'master')) && '1' || '0' }}` (spec §3.2 step 8: only the `check` entry gets `1`; the `acceptance` entry always gets `0`). The pin step's failure message: `::error::build/darkraise-framework.pin does not hold one 40-character commit hash`; the missing-`ssh` message: `::error::openssh-client is missing on the runner; add it to the ghr pool's managed packages`. The framework-failure step: `if: failure() && steps.framework.outcome == 'failure'`, message `::error::cannot check out darkraise-framework at <pin>: push that framework commit to its origin, check the DARKRAISE_FRAMEWORK_DEPLOY_KEY secret, or check that outbound SSH to github.com is open`.
````
