# Architecture decisions — requirements

**Source:** docs/dforge/specs/2026-11-24-doment-design.md, section 6, epic "Architecture decisions"
**Covers:** docs/dforge/specs/2026-11-24-architecture-decisions-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | R1 The process model (system service, per-session agent, client, self-hosted server, shared portable core) and the module boundaries are recorded, with one named interface per platform seam: capture, video encode, video decode, presentation, audio capture, audio playback, input injection, virtual display, virtual gamepad, pseudo-terminal. | docs/dforge/plans/2026-11-24-architecture-decisions.md | A1-A5 | done | - |
| 2 | R2 The build order is recorded: which projects are portable and built first on Linux and which are Windows-bound; Windows-bound code is reached only through the platform seams, and every seam has a simulated implementation used by tests. | docs/dforge/plans/2026-11-24-architecture-decisions.md | A4-A6 | done | - |
| 3 | R3 How doment consumes darkraise-framework is decided and recorded (package or project reference, version pinning), with the rule that reusable, product-neutral pieces are contributed to the framework and product logic stays in doment. | docs/dforge/plans/2026-11-24-architecture-decisions.md | A7, A10-A14, A25-A26 | done | - |
| 4 | R4 A third-party exception register lists every component that is not doment code, darkraise-framework, .NET, an operating-system API or a GPU-driver interface, each with its reason, licence, the interface it sits behind and its replacement plan; the build fails on a dependency that is not listed. | docs/dforge/plans/2026-11-24-architecture-decisions.md | A15-A24 | done | - |
| 5 | Product spec amendments from the owner's answers of 2026-11-24 (terminal host, network endpoint, exception register location) | docs/dforge/plans/2026-11-24-architecture-decisions.md | A8, A9 | done | - |
| 6 | .gitattributes forces LF only for the pin file; the .sh scripts may check out CRLF under Git for Windows autocrlf | docs/dforge/specs/2026-11-24-repository-build-nativeaot-design.md | A21 | planned | - |
| 7 | gate_master_pin_file cannot tell the gate's own DOMENT006/DOMENT003 lines from the build's identical ones | docs/dforge/specs/2026-11-24-repository-build-nativeaot-design.md | A22 | planned | - |
| 8 | gate.sh writes the temporary framework-check project without XML-escaping the tree path (& or < in a path breaks it) | docs/dforge/specs/2026-11-24-repository-build-nativeaot-design.md | A23 | planned | - |
| 9 | The gate's plain-directory ancestry skip and the new git-failure die paths have no test | docs/dforge/specs/2026-11-24-repository-build-nativeaot-design.md | A24 | planned | - |
| 10 | Push and merge the framework branch docs/doment-framework-worktree (bd20326e) in darkraise-framework | - | - | open | - |
| 11 | tools/framework.sh and gate.sh call GNU timeout, which macOS lacks by default | - | - | deferred | Task 2 ruling: macOS runs none of these scripts through M6; a command -v timeout check is the later one-line fix |
| 12 | One clean-tree definition across framework.sh sync and the MSBuild check for paths with spaces or non-ASCII characters | - | - | deferred | Task 2 ruling: both read git status -z identically; UTF-8 decoding applied in DomentGit.Run |
| 13 | dotnet build 10.0.302 appends -consoleloggerparameters:Summary after -clp:NoSummary | - | - | deferred | handled in Task 1: run.sh and gate.sh replace the console logger; recorded as a gotcha |
| 14 | check_reachable reports a failing git for-each-ref as an unreachable HEAD | - | - | deferred | handled in Task 4: fails closed by design |
| 15 | EnableWindowsTargeting=true on a net10.0 project makes restore ask for Microsoft.WindowsDesktop.App.Ref | - | - | deferred | handled in Task 5: fixture_project sets it only for -windows target frameworks |
