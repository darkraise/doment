# CI for pushed branches — requirements

**Source:** docs/dforge/specs/2026-11-24-doment-design.md, section 6, epic "CI for pushed branches"; docs/architecture.md, "Rules handed to later epics", "CI for pushed branches"
**Covers:** docs/dforge/specs/2026-11-25-ci-pushed-branches-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | R8 Every pushed branch is built and tested on CI on Linux, including the NativeAOT publish. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A1-A4, A14, A20 | verify | A14 owed: the CI run of the finishing master push (row 7) |
| 2 | Install the SDK from global.json (actions/setup-dotnet with global-json-file), have clang on the runner, run dotnet tool restore, then build/check.sh and build/gate.sh. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A2, A11 | done | - |
| 3 | Check out the framework at the pin into external/darkraise-framework with a read-only credential for the private repository, with LFS downloads skipped. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A3, A9, A10, A21, A23 | done | - |
| 4 | Build with FrameworkPinStrict=true. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A3 | done | - |
| 5 | On the main branch and on pull requests into it, fail when the pin is not an ancestor of the framework's remote master. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A5, A6, A20 | done | - |
| 6 | Never run on pull_request_target. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A7, A22, A24 | done | - |
| 7 | After the finishing merge, push doment master and verify A13, A14 and A17 | - | - | open | timeout 300 git push origin master; A14: gh run list -R darkraise/doment --branch master --event push --workflow CI --limit 1 --json databaseId,conclusion shows success for both jobs (gh api .../runs/<id>/jobs); A17: gh workflow run CI -R darkraise/doment --ref master, then its run starts jobs check and acceptance; A13: in the main checkout on master after the merge, timeout 2400 bash tests/build/repository-build-nativeaot.acceptance.sh '^A(17|20)$' prints ok A17 and ok A20 |
| 7 | The CI pool probe note states facts the probe did not print without saying where they came from (docs/dforge/research/2026-11-25-ci-pool-probe.md) | - | - | open | - |
| 8 | Find why file disappeared from the ghr host twice on 2026-11-26 (check job of run 45735004164, attempts 1 and 2) | - | - | open | - |
| 9 | The probe note publishes runner host details | - | - | deferred | final review: the same host name, runner names and hook paths are in every public job log |
| 10 | A8, A9s, A6s, A12 and A23 assert C5 content on every workflow file, so a second workflow fails them | - | - | deferred | final review rejection upheld: fails loudly; revisit when a second workflow is added (M7 Windows CI) |
| 11 | tests/build/run.sh portable_target_framework and real_framework_strict need nuget.org | - | - | deferred | Task 5 ruling: no requirement asks for offline tests/build runs |
| 12 | Plan Task 6: gh run list right after gh pr create can return no run, so gh run watch null fails | - | - | deferred | Task 6 ruling: loud failure, the session re-polls |
| 13 | tests/build/ci-pushed-branches.qa.acceptance.sh reads only the 100 latest runs for A10, A20 and A24 | - | - | deferred | final-residual R4: nothing runs the QA suite; the cases fail loudly |
| 14 | tests/build/ci-pushed-branches.qa.acceptance.sh A13 copies /usr/local/share/dotnet by a fixed path | - | - | deferred | final-residual R5: nothing runs the QA suite; CI covers A13's second half |
