# Architecture decisions — requirements

**Source:** docs/dforge/specs/2026-11-24-doment-design.md, section 6, epic "Architecture decisions"
**Covers:** docs/dforge/specs/2026-11-24-architecture-decisions-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | R1 The process model (system service, per-session agent, client, self-hosted server, shared portable core) and the module boundaries are recorded, with one named interface per platform seam: capture, video encode, video decode, presentation, audio capture, audio playback, input injection, virtual display, virtual gamepad, pseudo-terminal. | docs/dforge/plans/2026-11-24-architecture-decisions.md | A1-A5 | planned | - |
| 2 | R2 The build order is recorded: which projects are portable and built first on Linux and which are Windows-bound; Windows-bound code is reached only through the platform seams, and every seam has a simulated implementation used by tests. | docs/dforge/plans/2026-11-24-architecture-decisions.md | A4-A6 | planned | - |
| 3 | R3 How doment consumes darkraise-framework is decided and recorded (package or project reference, version pinning), with the rule that reusable, product-neutral pieces are contributed to the framework and product logic stays in doment. | docs/dforge/plans/2026-11-24-architecture-decisions.md | A7, A10-A14, A25-A26 | planned | - |
| 4 | R4 A third-party exception register lists every component that is not doment code, darkraise-framework, .NET, an operating-system API or a GPU-driver interface, each with its reason, licence, the interface it sits behind and its replacement plan; the build fails on a dependency that is not listed. | docs/dforge/plans/2026-11-24-architecture-decisions.md | A15-A24 | planned | - |
| 5 | Product spec amendments from the owner's answers of 2026-11-24 (terminal host, network endpoint, exception register location) | docs/dforge/plans/2026-11-24-architecture-decisions.md | A8, A9 | planned | - |
