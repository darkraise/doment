# CI for pushed branches — requirements

**Source:** docs/dforge/specs/2026-11-24-doment-design.md, section 6, epic "CI for pushed branches"; docs/architecture.md, "Rules handed to later epics", "CI for pushed branches"
**Covers:** docs/dforge/specs/2026-11-25-ci-pushed-branches-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | R8 Every pushed branch is built and tested on CI on Linux, including the NativeAOT publish. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A1-A4, A14, A20 | doing | - |
| 2 | Install the SDK from global.json (actions/setup-dotnet with global-json-file), have clang on the runner, run dotnet tool restore, then build/check.sh and build/gate.sh. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A2, A11 | doing | - |
| 3 | Check out the framework at the pin into external/darkraise-framework with a read-only credential for the private repository, with LFS downloads skipped. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A3, A9, A10, A21, A23 | doing | - |
| 4 | Build with FrameworkPinStrict=true. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A3 | doing | - |
| 5 | On the main branch and on pull requests into it, fail when the pin is not an ancestor of the framework's remote master. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A5, A6, A20 | doing | - |
| 6 | Never run on pull_request_target. | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A7, A22, A24 | doing | - |
| 7 | After the finishing merge, push doment master and verify A13, A14 and A17 | - | - | open | timeout 300 git push origin master; A14: gh run list -R darkraise/doment --branch master --event push --workflow CI --limit 1 --json databaseId,conclusion shows success for both jobs (gh api .../runs/<id>/jobs); A17: gh workflow run CI -R darkraise/doment --ref master, then its run starts jobs check and acceptance; A13: in the main checkout on master after the merge, timeout 2400 bash tests/build/repository-build-nativeaot.acceptance.sh '^A(17|20)$' prints ok A17 and ok A20 |
