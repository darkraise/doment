# Repository, build and NativeAOT — requirements

**Source:** docs/dforge/specs/2026-11-24-doment-design.md, section 6, epic "Repository, build and NativeAOT"; docs/architecture.md, "Rules handed to later epics"
**Covers:** docs/dforge/specs/2026-11-24-repository-build-nativeaot-design.md, docs/dforge/specs/2026-11-25-ci-pushed-branches-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | R5 One solution builds the portable core, the server, the Linux agent and the command-line client; each publishes with NativeAOT for linux-x64 with zero trim and AOT warnings. | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A1-A6, A15-A16 | done | - |
| 2 | R6 The portable core references no Windows-only API, enforced by compiling it for both linux-x64 and win-x64 on Linux. | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A7-A9, A14, A28 | done | - |
| 3 | R7 Formatting and analyzer rules match darkraise-framework conventions and are enforced by the build. | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A10-A14 | done | - |
| 4 | Pin the .NET SDK in global.json; the ILCompiler advisory GHSA-p3jp-9v83-76w9; clang for the link step; wire the simulation build property (handed on by the architecture decisions) | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A1, A4-A5, A15-A16, A27 | done | - |
| 5 | build/check.sh runs build, portable compile, NativeAOT publish and tests, and docs record it | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A17-A20, A25-A26 | done | - |
| 6 | NU1900 (vulnerability data unavailable) fails a plain local build under TreatWarningsAsErrors; candidate for the non-strict list | - | - | deferred | preflight-31 PARK |
| 7 | A23: the gate accepts a tree path holding & or < (refused under amendment A5: RoslynCodeTaskFactory fails MSB3761 on such a path in every build, not only the gate) | - | - | deferred | amendment A5; acceptance case skipped; final-review rejection upheld |
| 8 | Owner decision: approve or object to the four transitive xUnit v3 test packages (Microsoft.ApplicationInsights, Microsoft.Bcl.AsyncInterfaces, Microsoft.Win32.Registry, System.Security.AccessControl) listed by rule in third-party exceptions rows B1 and B2 | owner 2026-11-25 | - | done | owner approved the four packages under B1 and B2 |
| 9 | Owner decision: whether build/check.sh opts out of .NET telemetry for test runs | owner 2026-11-25 | - | done | owner chose opt-out: check.sh exports DOTNET_CLI_TELEMETRY_OPTOUT and TESTINGPLATFORM_TELEMETRY_OPTOUT; gate.sh exports DOTNET_CLI_TELEMETRY_OPTOUT |
| 10 | The gate refuses & and < only in the tree path; a DARKRAISE_FRAMEWORK_PATH holding those characters is not refused | - | A23 | done | gate.sh refuses the same characters in DARKRAISE_FRAMEWORK_PATH |
| 11 | A23's case with ' and a space in the path fetches the framework's origin, so an offline acceptance run may fail with DOMENT005 | - | A23 | done | the case sets DOMENT_GATE_NO_FETCH=1 |
| 12 | Probe P1 needed Microsoft.NET.ILLink.Tasks 10.0.15 primed into ~/.nuget/packages | - | - | deferred | Task 1 discovery; recorded in the build probes research note |
| 13 | The darkraise-framework .editorconfig has no final newline, so the doment lines follow its last line with no blank separator | - | - | deferred | Task 3 discovery; A10 strips only # doment: lines |
| 14 | The architecture acceptance copies only index-listed build files, so a new build file must be staged before that suite can see it | - | - | deferred | Task 4 discovery; gotcha, no change needed |
| 15 | dn pins console verbosity to minimal, so -v:d assertions must read a detailed file logger | - | - | deferred | Task 5 discovery; handled in the format_ cases |
| 16 | The real restore closure of Doment.Core.Tests is exactly the probe P5 package list | - | - | deferred | Task 6 discovery; handled by the pkg-test-closure ruling |
| 17 | net10.0-windows stand-ins in the architecture acceptance run only DomentReferenceCheck and never reach the restore hooks | - | - | deferred | Task 9 discovery; no DomentPlatform flag needed |
| 18 | CA1401 rejects a public P/Invoke under the root settings, so native fixture classes are internal | - | - | deferred | Task 10 discovery; handled in the fixtures |
| 19 | /nonexistent exists on this host, so a framework path there gives DOMENT002 instead of DOMENT003 | - | - | deferred | Task 11 discovery; A18 uses a path under the test directory |
| 20 | Download-dependency versions in project.assets.json are exact ranges such as [10.0.15, 10.0.15] | - | - | deferred | Task 12 discovery; handled by the portable and aot steps |
| 21 | A20's platform-packages case diffs against merge-base HEAD master, so on master (after the merge) it finds no row and fails | docs/dforge/plans/2026-11-25-ci-pushed-branches.md | A13 | planned | found 2026-11-25; fails on any run from master, including CI |
