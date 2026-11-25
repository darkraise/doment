# Review record: 2026-11-24-repository-build-nativeaot

Plan: docs/dforge/plans/2026-11-24-repository-build-nativeaot.md
Retained: 2026-11-25

Review depth: full (spec)
Acceptance QA: complete — 26 pass, 1 fail, 0 flaky, 0 cannot-test, 1 demo
final review lens security — 0 Critical, 0 Important, 0 Minor; fixed 0, rejected 0
final review lens silent-failures — 0 Critical, 1 Important, 0 Minor; fixed 1, rejected 0
final review lens test-quality — 0 Critical, 4 Important, 0 Minor; fixed 3, rejected 1
final review lens code-quality — 0 Critical, 3 Important, 0 Minor; fixed 2, rejected 1; parts lang-bash=2,lang-csharp=0,type-design=0,docs-comments=1
Test ratio: 2210 test / 1463 code lines (7b665fd..14d9667)
Final review: clean (commits 7b665fd..14d9667)

## Amendments

## A1 — Task 2
Reason: Spec A21 requires `git check-attr eol` to report `lf` for `*.csproj`, which the test never checks.
Cost if wrong: One redundant path in a `git check-attr` call.
### Old
````text
- `tests/build/repository-build.acceptance.sh::A21` (integration): given the checkout, asserts that `git ls-files --eol` shows `i/lf` for every tracked text file (no `i/crlf`, no `i/mixed`), that `git check-attr eol` reports `lf` for `build/gate.sh`, `tests/build/run.sh`, `build/Doment.BuildChecks.cs`, `Directory.Build.props`, `README.md` and `build/darkraise-framework.pin`, and that `git check-attr text` reports `unset` for `x.dll`, `x.exe`, `x.so`, `x.dylib`, `x.a`, `x.lib`, `x.sys`, `x.nupkg`, `x.snupkg`, `x.png`, `x.jpg` and `x.ico`; fails today because `.gitattributes` sets `eol=lf` only for the pin file.
````
### New
````text
- `tests/build/repository-build.acceptance.sh::A21` (integration): given the checkout, asserts that `git ls-files --eol` shows `i/lf` for every tracked text file (no `i/crlf`, no `i/mixed`), that `git check-attr eol` reports `lf` for `build/gate.sh`, `tests/build/run.sh`, `build/Doment.BuildChecks.cs`, `Directory.Build.props`, `src/Doment.Core/Doment.Core.csproj` (`git check-attr` resolves a path whether or not the file exists yet), `README.md` and `build/darkraise-framework.pin`, and that `git check-attr text` reports `unset` for `x.dll`, `x.exe`, `x.so`, `x.dylib`, `x.a`, `x.lib`, `x.sys`, `x.nupkg`, `x.snupkg`, `x.png`, `x.jpg` and `x.ico`; fails today because `.gitattributes` sets `eol=lf` only for the pin file.
````

## A2 — Task 5
Reason: Spec A13 is a manifest that names CSharpier with no restored package; the plan's case removes the manifest instead.
Cost if wrong: One extra build call in the harness.
### Old
````text
- `tests/build/run.sh::format_tool_missing` (integration): given a stand-in without `.config/dotnet-tools.json` and an empty `DOTNET_CLI_HOME`-style tool cache (set `HOME` to an empty directory for the call), asserts `error DOMENT032: CSharpier is not restored; run dotnet tool restore` once; fails today for the same reason.
````
### New
````text
- `tests/build/run.sh::format_tool_missing` (integration): given a stand-in with the same `.config/dotnet-tools.json` copy as the other `format_` cases, built with `HOME` and `NUGET_PACKAGES` both set to one empty directory for the call (so the manifest names csharpier 1.2.6 but no package folder holds it), asserts exactly one line `error DOMENT032: CSharpier is not restored; run dotnet tool restore`; then, with the manifest also removed from the stand-in, asserts the same line exactly once again; fails today for the same reason.
````

## A3 — Task 8
Reason: Spec A16's Debug half is a publish; `dotnet build` never reaches the `PrepareForPublish` hook the check uses.
Cost if wrong: About one to two minutes more per acceptance run.
### Old
````text
- `...::A16` (integration): `dotnet publish src/Doment.Cli -c Release -r linux-x64 -p:DomentSimulation=true` (and the same for `Doment.Agent`) fails with DOMENT030; `-c Debug` of the same builds succeeds (`dotnet build`, not publish, to keep the case quick).
````
### New
````text
- `...::A16` (integration): `dotnet publish src/Doment.Cli -c Release -r linux-x64 -p:DomentSimulation=true` (and the same for `Doment.Agent`) fails with DOMENT030; the same publish with `-c Debug` and `-o artifacts/acceptance/a16/<project name>` exits 0 with no `DOMENT030` line (a publish, so the `PrepareForPublish` hook is reached in Debug too).
````

## A4 — Task 9
Reason: The module map has no `Doment.Core.Tests` row, so "its module-map Kind" is undefined for one solution project.
Cost if wrong: None beyond a few lines of test code.
### Old
````text
- `tests/build/repository-build.acceptance.sh::A28` (integration): each project of `doment.slnx` reports `-getProperty:DomentPlatform` equal to its module-map Kind in `docs/architecture.md` (portable → `portable`, Linux-bound → `linux`), and `Doment.Agent` is the only `linux` one.
````
### New
````text
- `tests/build/repository-build.acceptance.sh::A28` (integration): each project of `doment.slnx` that has a row in the module map of `docs/architecture.md` reports `-getProperty:DomentPlatform` equal to its Kind there (portable → `portable`, Linux-bound → `linux`, Windows-bound → `windows`); `Doment.Core.Tests`, which has no module-map row, reports `portable`, as the spec's section 3 table gives it; any other solution project without a module-map row fails the case; and `Doment.Agent` is the only `linux` one.
````

## A5 — Task 2
Reason: `&` and `<` in the checkout path break every build at the RoslynCodeTaskFactory `Source` attribute (MSB3761), so under spec section 8's own rule they are refused, not accepted.
Cost if wrong: A later task must make the task sources load from such a path; the refusal list in `gate.sh` shrinks by two characters.
### Old
````text
- `tests/build/run.sh::gate_tree_path_characters` (integration): given a stand-in doment repository holding one net10.0 fixture project, copied to a directory whose name contains `&`, `<`, `'` and a space, asserts the gate exits 0 with `0 violations`; and for each of `;`, `%`, `$`, `@`, `"`, `,` in the directory name asserts exit 2 and `gate: <tree> contains '<char>', which MSBuild cannot take in a path`; fails today because the generated project is not XML-escaped and nothing refuses the special characters. (Drop `'` from the allowed set and add it to the refused set if Task 1's P7 says so.)
- `tests/build/run.sh::gate_plain_directory_framework` (integration): given a stand-in doment repository on `master` whose `DARKRAISE_FRAMEWORK_PATH` is a plain directory inside another git repository that has a remote, asserts the output holds `error DOMENT002:`, no `DOMENT005`, and that the enclosing repository's `FETCH_HEAD` was not created; fails today only if the skip regresses (it guards the existing skip, row #9).
- `tests/build/run.sh::gate_ls_files_failure` (integration): given a stand-in doment repository and a `git` wrapper first on PATH that forwards every call to the real git except that its N-th `ls-files` call exits 128, asserts for N = 1, 2, 3 that the gate exits 1 and prints `gate: git ls-files failed in <tree>`; fails today only if a `die` path regresses (row #9).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/repository-build.acceptance.sh '^A21:'; bash tests/build/run.sh '^gate_(master_pin_lines|tree_path_characters|plain_directory_framework|ls_files_failure)$'`
Expected: A21 FAIL; `gate_master_pin_lines` and `gate_tree_path_characters` not ok; the other two may already pass.

- [ ] **Step 3: Implement**

1. `.gitattributes`: `* text=auto eol=lf`, then `-text` lines for the twelve binary patterns of A21; remove the pin-file line. Run `git add --renormalize .` and include the result in this commit.
2. `gate.sh`, after the tree is resolved: refuse a tree path containing any of `;`, `%`, `$`, `@`, `"`, `,` with the C-style message above and exit 2.
3. `gate.sh`, `framework-check.proj`: XML-escape the tree path (`&` first, then `<`, `>`, `"`, `'`) before writing it into the two `Import` elements.
````
### New
````text
- `tests/build/run.sh::gate_tree_path_characters` (integration): given a stand-in doment repository holding one net10.0 fixture project, copied to a directory whose name contains `'`, `>` and a space, asserts the gate exits 0 with `0 violations`; and for each of `;`, `%`, `$`, `@`, `"`, `,`, `&`, `<` in the directory name asserts exit 2 and `gate: <tree> contains '<char>', which MSBuild cannot take in a path`; fails today because nothing refuses the special characters. (`&` and `<` are refused because RoslynCodeTaskFactory re-parses the `UsingTask` body after property expansion, so `Source="$(MSBuildThisFileDirectory)Doment.BuildChecks.cs"` under such a path fails with MSB3761 in every build, not only the gate; this is spec section 8's rule for characters that break the whole build. If the success case fails and passes with `>` removed from the directory name, move `>` to the refused set the same way and say so in this task's ledger line.)
- `tests/build/run.sh::gate_plain_directory_framework` (integration): given a stand-in doment repository on `master` whose `DARKRAISE_FRAMEWORK_PATH` is a plain directory inside another git repository that has a remote, asserts the output holds `error DOMENT002:`, no `DOMENT005`, and that the enclosing repository's `FETCH_HEAD` was not created; fails today only if the skip regresses (it guards the existing skip, row #9).
- `tests/build/run.sh::gate_ls_files_failure` (integration): given a stand-in doment repository and a `git` wrapper first on PATH that forwards every call to the real git except that its N-th `ls-files` call exits 128, asserts for N = 1, 2, 3 that the gate exits 1 and prints `gate: git ls-files failed in <tree>`; fails today only if a `die` path regresses (row #9).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/build/repository-build.acceptance.sh '^A21:'; bash tests/build/run.sh '^gate_(master_pin_lines|tree_path_characters|plain_directory_framework|ls_files_failure)$'`
Expected: A21 FAIL; `gate_master_pin_lines` and `gate_tree_path_characters` not ok; the other two may already pass.

- [ ] **Step 3: Implement**

1. `.gitattributes`: `* text=auto eol=lf`, then `-text` lines for the twelve binary patterns of A21; remove the pin-file line. Run `git add --renormalize .` and include the result in this commit.
2. `gate.sh`, after the tree is resolved: refuse a tree path containing any of `;`, `%`, `$`, `@`, `"`, `,`, `&`, `<` with the C-style message above and exit 2. Name the departure from spec A23 (`&` and `<` refused rather than accepted, row #8) in this task's ledger line so the final report carries it to the owner.
3. `gate.sh`, `framework-check.proj`: XML-escape the tree path (`&` first, then `<`, `>`, `"`, `'`) before writing it into the two `Import` elements; spec section 8 #8 asks for it, and it guards the generated project if the refused list ever shrinks.
````
