# Third-party exception register (test fixture)

Free prose outside the three tables is ignored.

## Exceptions

| ID | Component | Packages or files | Used for | Reason | Licence | Behind | Replacement | Approved |
|---|---|---|---|---|---|---|---|---|
| X1 | Fixture codec | `Fx.Codec.*` | Decoding test media | No first-party codec yet | MIT | `IVideoDecoder` | First-party codec | 2026-11-24 |

## Build-and-test-only tools

| ID | Component | Packages or tool | Used for | Licence | Approved |
|---|---|---|---|---|---|
| B1 | Fixture test framework | `Fx.Test`, `Fx.Test.*` | Unit tests | MIT | 2026-11-24 |
| B2 | Fixture formatter | `fx-format` | Formatting | MIT | 2026-11-24 |

## Platform packages

| Package | Added by | First seen |
|---|---|---|
| `Microsoft.NET.ILLink.Tasks` | .NET SDK, with `PublishAot` or `IsAotCompatible` | 2026-11-24 |
