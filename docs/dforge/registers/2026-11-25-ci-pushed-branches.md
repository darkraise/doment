# CI for pushed branches — requirements

**Source:** docs/dforge/specs/2026-11-24-doment-design.md, section 6, epic "CI for pushed branches"; docs/architecture.md, "Rules handed to later epics", "CI for pushed branches"
**Covers:** docs/dforge/specs/2026-11-25-ci-pushed-branches-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | R8 Every pushed branch is built and tested on CI on Linux, including the NativeAOT publish. | - | A1-A4, A14 | open | - |
| 2 | Install the SDK from global.json (actions/setup-dotnet with global-json-file), have clang on the runner, run dotnet tool restore, then build/check.sh and build/gate.sh. | - | A2, A11 | open | - |
| 3 | Check out the framework at the pin into external/darkraise-framework with a read-only credential for the private repository, with LFS downloads skipped. | - | A3, A9, A10 | open | - |
| 4 | Build with FrameworkPinStrict=true. | - | A3 | open | - |
| 5 | On the main branch and on pull requests into it, fail when the pin is not an ancestor of the framework's remote master. | - | A5, A6 | open | - |
| 6 | Never run on pull_request_target. | - | A7 | open | - |
