# doment

## Prerequisites

- .NET SDK 10.0.404 or a later 10.0.4xx (`global.json` pins it)
- clang, for the NativeAOT link
- git
- The framework worktree: `bash tools/framework.sh sync`
- The formatter: `dotnet tool restore`

## Commands

- `build/check.sh [build|portable|aot|test]...` builds, compiles the portable projects for linux-x64 and win-x64,
  publishes the NativeAOT executables and runs the tests; with no argument it runs all four steps.
- `build/gate.sh` checks every tracked project, tool and binary against `docs/third-party-exceptions.md`.

`docs/architecture.md` records how the repository and its build work.
