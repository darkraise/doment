# Third-party exception register

This file is the only list of components in doment that are not doment code, darkraise-framework, .NET, an operating-system API or a GPU-driver interface. The build parses it: every build fails on a package in a project's restore output that no table lists, and on a malformed table (DOMENT010 to DOMENT013). The gate command also checks tracked project files, `.config/dotnet-tools.json` and tracked binaries against it.

A new row in the Exceptions or Build-and-test-only tools table needs the owner's approval. A new Platform packages row is a reviewed change and needs no replacement plan. The epic that first references a component lists its exact packages, transitive ones included.

What the check cannot see, so nobody assumes otherwise: source code copied or ported from a third party, native libraries loaded by name at run time, and bundled assets of third-party origin (fonts, images, data files). Each still needs a row by rule; review and the M10 security review enforce it.

Licences of B1 to B3 were read on their repositories on 2026-11-24 (`xunit/xunit`, `microsoft/testfx`, `belav/csharpier`).

## Exceptions

| ID | Component | Packages or files | Used for | Reason | Licence | Behind | Replacement | Approved |
|---|---|---|---|---|---|---|---|---|
| X1 | Indirect Display driver (candidate: Virtual Display Driver) | - | Virtual displays | No first-party driver before M17; signature validity is confirmed in its M9 epic | MIT | `IVirtualDisplay` | doment's own driver in M17 | 2026-11-24 |
| X2 | ViGEmBus | - | Virtual gamepads | No first-party driver before M17; the project was archived in 2023 | BSD-3-Clause | `IVirtualGamepad` | doment's own driver in M17 | 2026-11-24 |

## Build-and-test-only tools

| ID | Component | Packages or tool | Used for | Licence | Approved |
|---|---|---|---|---|---|
| B1 | xUnit v3 | `xunit.v3`, `xunit.v3.*`, `xunit.analyzers` | Unit tests | Apache-2.0 | 2026-11-24 |
| B2 | Microsoft Testing Platform | `Microsoft.Testing.Platform`, `Microsoft.Testing.Platform.*`, `Microsoft.Testing.Extensions.*` | Test runner | MIT | 2026-11-24 |
| B3 | CSharpier | `csharpier` | Formatting | MIT | 2026-11-24 |

## Platform packages

| Package | Added by | First seen |
|---|---|---|
| `Microsoft.DotNet.ILCompiler` | .NET SDK (NativeAOT publish for linux-x64) | 2026-11-24 |
| `runtime.linux-x64.Microsoft.DotNet.ILCompiler` | .NET SDK (NativeAOT publish for linux-x64) | 2026-11-24 |
| `Microsoft.NET.ILLink.Tasks` | .NET SDK (NativeAOT publish for linux-x64) | 2026-11-24 |
