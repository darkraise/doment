# Repository, build and NativeAOT — requirements

**Source:** docs/dforge/specs/2026-11-24-doment-design.md, section 6, epic "Repository, build and NativeAOT"; docs/architecture.md, "Rules handed to later epics"
**Covers:** docs/dforge/specs/2026-11-24-repository-build-nativeaot-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | R5 One solution builds the portable core, the server, the Linux agent and the command-line client; each publishes with NativeAOT for linux-x64 with zero trim and AOT warnings. | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A1-A6, A15-A16 | doing | - |
| 2 | R6 The portable core references no Windows-only API, enforced by compiling it for both linux-x64 and win-x64 on Linux. | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A7-A9, A14, A28 | doing | - |
| 3 | R7 Formatting and analyzer rules match darkraise-framework conventions and are enforced by the build. | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A10-A14 | doing | - |
| 4 | Pin the .NET SDK in global.json; the ILCompiler advisory GHSA-p3jp-9v83-76w9; clang for the link step; wire the simulation build property (handed on by the architecture decisions) | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A1, A4-A5, A15-A16, A27 | doing | - |
| 5 | build/check.sh runs build, portable compile, NativeAOT publish and tests, and docs record it | docs/dforge/plans/2026-11-24-repository-build-nativeaot.md | A17-A20, A25-A26 | doing | - |
| 6 | NU1900 (vulnerability data unavailable) fails a plain local build under TreatWarningsAsErrors; candidate for the non-strict list | - | - | deferred | preflight-31 PARK |
| 7 | A23: the gate accepts a tree path holding & or < (refused under amendment A5: RoslynCodeTaskFactory fails MSB3761 on such a path in every build, not only the gate) | - | - | deferred | amendment A5; acceptance case skipped; final-review rejection upheld |
