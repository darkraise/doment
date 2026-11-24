#!/usr/bin/env bash
# Build-check test runner: bash tests/build/run.sh [<extended regex>]
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
FILTER=${1:-}

# Keep the run from leaving MSBuild nodes, the MSBuild server or the compiler server behind.
export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_USE_MSBUILD_SERVER=0
export UseSharedCompilation=false
export DOTNET_NOLOGO=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
unset DARKRAISE_FRAMEWORK_PATH DARKRAISE_FRAMEWORK_REPO

TROOT=$(mktemp -d "${TMPDIR:-/tmp}/doment-build-tests.XXXXXX")
FIXTURE_RUN=$REPO_ROOT/tests/build/fixtures/.run
rm -rf "$FIXTURE_RUN"
trap 'rm -rf "$TROOT" "$FIXTURE_RUN"' EXIT
FEED=$TROOT/feed
mkdir -p "$FEED" "$TROOT/pkgs"

export GIT_AUTHOR_NAME=doment-tests GIT_AUTHOR_EMAIL=tests@doment.invalid
export GIT_COMMITTER_NAME=doment-tests GIT_COMMITTER_EMAIL=tests@doment.invalid
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null

# ---------------------------------------------------------------------------
# Helpers

OUT=
RC=0
FAIL_FILE=$TROOT/fail-reason

fail() {
  printf '%s' "$1" > "$FAIL_FILE"
  return 1
}

# `dotnet build` appends -consoleloggerparameters:Summary after the caller's -clp:NoSummary
# (SDK 10.0.302), so the console logger is replaced by one that is told NoSummary itself.
DN_LOGGER=(-noConsoleLogger "-logger:ConsoleLogger,Microsoft.Build;NoSummary;Verbosity=minimal")

dn() {
  OUT=$(timeout 600 dotnet "$@" -nologo -tl:off -clp:NoSummary "${DN_LOGGER[@]}" \
    "-p:RestoreSources=$FEED" "-p:RestorePackagesPath=$TROOT/pkgs" 2>&1) && RC=0 || RC=$?
}

expect_rc() {
  [[ $RC -eq $1 ]] || fail "expected rc $1, got $RC; output: $(tail -n 20 <<<"$OUT")"
}

expect_out() {
  grep -Eq -- "$1" <<<"$OUT" || fail "no output line matches /$1/; output: $(tail -n 20 <<<"$OUT")"
}

expect_no_out() {
  if grep -Eq -- "$1" <<<"$OUT"; then
    fail "an output line matches /$1/: $(grep -E -- "$1" <<<"$OUT" | head -n 3)"
  fi
}

expect_count() {
  local n
  n=$(grep -Ec -- "$1" <<<"$OUT" || true)
  [[ $n -eq $2 ]] || fail "expected $2 lines matching /$1/, got $n; output: $(tail -n 20 <<<"$OUT")"
}

write_file() {
  mkdir -p "$(dirname "$1")"
  cat > "$1"
}

new_framework_repo() {
  local dir=$1
  local origin=$dir.origin.git
  git init -q --bare "$origin"
  git init -q -b master "$dir"
  echo '<Project />' > "$dir/Directory.Build.props"
  printf '%s\n' '*.user' 'bin/' 'obj/' 'docs/dforge/' '.worktrees/' > "$dir/.gitignore"
  write_file "$dir/src/Darkraise/Darkraise.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
</Project>
XML
  write_file "$dir/src/Darkraise/Class1.cs" <<'CS'
namespace Darkraise;

public static class Class1
{
    public static string Name => "darkraise";
}
CS
  write_file "$dir/src/Darkraise.Api/Darkraise.Api.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
</Project>
XML
  write_file "$dir/src/Darkraise.Win32UI/Darkraise.Win32UI.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0-windows</TargetFramework>
    <EnableWindowsTargeting>true</EnableWindowsTargeting>
  </PropertyGroup>
</Project>
XML
  write_file "$dir/src/Darkraise.Win32UI.Generators/Darkraise.Win32UI.Generators.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>
</Project>
XML
  git -C "$dir" add -A
  git -C "$dir" commit -qm "Initial framework"
  git -C "$dir" remote add origin "$origin"
  git -C "$dir" push -q origin master
  git -C "$dir" fetch -q origin
  git -C "$dir" rev-parse HEAD
}

new_doment_repo() {
  local dir=$1 pin=$2 path
  git init -q -b master "$dir"
  for path in Directory.Build.props Directory.Build.targets .gitignore; do
    [[ -f $REPO_ROOT/$path ]] && cp "$REPO_ROOT/$path" "$dir/$path"
  done
  # Tracked and untracked-but-not-ignored files only, so a local framework worktree is never copied.
  while IFS= read -r path; do
    [[ -f $REPO_ROOT/$path ]] || continue
    mkdir -p "$dir/$(dirname "$path")"
    cp "$REPO_ROOT/$path" "$dir/$path"
  done < <(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard -- build external tools)
  if [[ -f $REPO_ROOT/tests/build/fixtures/register-valid/register.md ]]; then
    mkdir -p "$dir/docs"
    cp "$REPO_ROOT/tests/build/fixtures/register-valid/register.md" "$dir/docs/third-party-exceptions.md"
  fi
  mkdir -p "$dir/build"
  echo "$pin" > "$dir/build/darkraise-framework.pin"
  write_file "$dir/src/App/App.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="$(DarkraiseFrameworkPath)/src/Darkraise/Darkraise.csproj" />
  </ItemGroup>
</Project>
XML
  write_file "$dir/src/App/Program.cs" <<'CS'
System.Console.WriteLine(Darkraise.Class1.Name);
CS
  git -C "$dir" add -A
  git -C "$dir" commit -qm "Initial doment"
}

# The stand-in framework every fixture case builds against, at its own pin, so the framework
# check passes silently there.
export DOMENT_FIXTURE_FRAMEWORK=$TROOT/fixture-framework
DOMENT_FIXTURE_PIN=$(new_framework_repo "$DOMENT_FIXTURE_FRAMEWORK")
export DOMENT_FIXTURE_PIN
export DOMENT_FIXTURE_PIN_FILE=$TROOT/fixture-framework.pin
printf '%s\n' "$DOMENT_FIXTURE_PIN" > "$DOMENT_FIXTURE_PIN_FILE"

# fixture_project <case> <relative dir> <target framework> [package=<id>/<version> | project=<path>]...
# Writes <dir>/<name>.csproj under tests/build/fixtures/.run/<case>/, whose register.md starts as a
# copy of register-valid/register.md.
fixture_project() {
  local name=$1 dir=$2 tfm=$3 spec items=
  shift 3
  local root=$FIXTURE_RUN/$name
  mkdir -p "$root"
  [[ -f $root/register.md ]] || cp "$REPO_ROOT/tests/build/fixtures/register-valid/register.md" "$root/register.md"
  for spec in "$@"; do
    case $spec in
      package=*)
        spec=${spec#package=}
        items+="    <PackageReference Include=\"${spec%%/*}\" Version=\"${spec#*/}\" />"$'\n'
        ;;
      project=*) items+="    <ProjectReference Include=\"${spec#project=}\" />"$'\n' ;;
      *) echo "fixture_project: bad spec '$spec'" >&2; return 1 ;;
    esac
  done
  # EnableWindowsTargeting makes restore ask for Microsoft.WindowsDesktop.App.Ref even for net10.0.
  local windows=
  [[ $tfm == *-windows* ]] && windows=$'\n    <EnableWindowsTargeting>true</EnableWindowsTargeting>'
  write_file "$root/$dir/$(basename "$dir").csproj" <<XML
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>$tfm</TargetFramework>$windows
  </PropertyGroup>
  <ItemGroup>
$items  </ItemGroup>
</Project>
XML
}

# ---------------------------------------------------------------------------
# Cases

CASES=()

CASES+=(presence_missing)
case_presence_missing() {
  new_doment_repo "$T/doment" 0000000000000000000000000000000000000000
  cd "$T/doment"
  dn build src/App
  expect_rc 1
  expect_count 'error DOMENT003: darkraise-framework not found at .*/external/darkraise-framework; run tools/framework.sh sync' 1
  expect_no_out 'error (NU1105|MSB)'
}

CASES+=(override_relative)
case_override_relative() {
  new_doment_repo "$T/doment" 0000000000000000000000000000000000000000
  cd "$T/doment"
  dn build src/App -p:DarkraiseFrameworkPath=../fw
  expect_rc 1
  expect_count "error DOMENT004: DarkraiseFrameworkPath must be an absolute path, got '\.\./fw'" 1
  DARKRAISE_FRAMEWORK_PATH=fw dn build src/App
  expect_rc 1
  expect_count "error DOMENT004: DARKRAISE_FRAMEWORK_PATH must be an absolute path, got 'fw'" 1
}

CASES+=(override_absolute_precedence)
case_override_absolute_precedence() {
  local pin
  pin=$(new_framework_repo "$T/fw")
  new_doment_repo "$T/doment" "$pin"
  cd "$T/doment"
  DARKRAISE_FRAMEWORK_PATH=$T/nowhere dn build src/App "-p:DarkraiseFrameworkPath=$T/fw"
  expect_rc 0
  DARKRAISE_FRAMEWORK_PATH=$T/nowhere dn build src/App
  expect_rc 1
  expect_count "error DOMENT003: darkraise-framework not found at $T/nowhere; run tools/framework.sh sync" 1
}

CASES+=(default_path_builds)
case_default_path_builds() {
  local pin
  pin=$(new_framework_repo "$T/fw")
  new_doment_repo "$T/doment" "$pin"
  git -C "$T/fw" worktree add -q --detach "$T/doment/external/darkraise-framework" "$pin"
  cd "$T/doment"
  dn build src/App
  expect_rc 0
  local status
  status=$(git status --porcelain)
  [[ -z $status ]] || fail "git status is not empty: $status"
}

# Runs the checkout's tools/framework.sh, capturing stdout and stderr in $OUT and the exit code in $RC.
fw_sh() {
  OUT=$(bash tools/framework.sh "$@" 2>&1) && RC=0 || RC=$?
}

expect_eq() {
  [[ $1 == "$2" ]] || fail "$3: expected '$2', got '$1'"
}

# A stand-in framework clone beside a stand-in doment repository, synced to the clone's first commit.
synced_setup() {
  C1=$(new_framework_repo "$T/darkraise-framework")
  new_doment_repo "$T/doment" "$C1"
  cd "$T/doment"
  fw_sh sync
  expect_rc 0
  WT=$T/doment/external/darkraise-framework
}

framework_commit() {
  local dir=$1 file=$2
  echo "$file" > "$dir/$file"
  git -C "$dir" add "$file"
  git -C "$dir" commit -qm "Add $file"
  git -C "$dir" rev-parse HEAD
}

CASES+=(sync_creates)
case_sync_creates() {
  synced_setup
  expect_eq "$(git -C "$WT" rev-parse HEAD)" "$C1" "worktree HEAD"
  if git -C "$WT" symbolic-ref -q HEAD >/dev/null; then
    fail "worktree HEAD is not detached"
  fi
  dn build src/App
  expect_rc 0
}

CASES+=(sync_moves_clean)
case_sync_moves_clean() {
  synced_setup
  local c2
  c2=$(framework_commit "$T/darkraise-framework" c2.txt)
  echo "$c2" > build/darkraise-framework.pin
  fw_sh sync
  expect_rc 0
  expect_eq "$(git -C "$WT" rev-parse HEAD)" "$c2" "worktree HEAD after the move"
  expect_eq "$(git -C "$T/darkraise-framework" rev-parse refs/heads/master)" "$c2" "framework master"
  git -C "$WT" switch -q -c feature
  echo "$C1" > build/darkraise-framework.pin
  fw_sh sync
  expect_rc 0
  expect_eq "$(git -C "$WT" rev-parse HEAD)" "$C1" "worktree HEAD after leaving feature"
  if git -C "$WT" symbolic-ref -q HEAD >/dev/null; then
    fail "worktree HEAD is not detached after leaving feature"
  fi
  expect_eq "$(git -C "$WT" rev-parse refs/heads/feature)" "$c2" "feature branch"
}

CASES+=(sync_refuses)
case_sync_refuses() {
  synced_setup
  local c2
  c2=$(framework_commit "$T/darkraise-framework" c2.txt)
  echo "$c2" > build/darkraise-framework.pin

  echo changed >> "$WT/src/Darkraise/Class1.cs"
  fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: $WT is not clean \(first: src/Darkraise/Class1.cs\)$"
  expect_eq "$(git -C "$WT" rev-parse HEAD)" "$C1" "HEAD after refusing a modified file"
  grep -q '^changed$' "$WT/src/Darkraise/Class1.cs" || fail "the modified file was reverted"
  git -C "$WT" checkout -q -- src/Darkraise/Class1.cs

  mkdir -p "$WT/docs/dforge"
  echo note > "$WT/docs/dforge/note.md"
  fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: $WT is not clean \(first: docs/dforge/\)$"
  expect_eq "$(git -C "$WT" rev-parse HEAD)" "$C1" "HEAD after refusing an ignored file"
  [[ -f $WT/docs/dforge/note.md ]] || fail "the ignored file was removed"
  rm -rf "$WT/docs"

  local index
  index=$(git -C "$WT" rev-parse --path-format=absolute --git-path index)
  cp "$index" "$T/index.saved"
  echo garbage > "$index"
  fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: git status failed in $WT$"
  expect_no_out "is at $c2"
  cp "$T/index.saved" "$index"
  expect_eq "$(git -C "$WT" rev-parse HEAD)" "$C1" "HEAD after a failing git status"

  DARKRAISE_FRAMEWORK_PATH=fw fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: DARKRAISE_FRAMEWORK_PATH must be an absolute path, got 'fw'$"
  [[ ! -e fw ]] || fail "a relative framework path was created"

  mkdir -p "$WT/src/Darkraise/obj"
  echo x > "$WT/src/Darkraise/obj/x"
  fw_sh sync
  expect_rc 0
  expect_eq "$(git -C "$WT" rev-parse HEAD)" "$c2" "HEAD with only build output present"

  local stray
  stray=$(framework_commit "$WT" stray.txt)
  echo "$C1" > build/darkraise-framework.pin
  fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: $WT HEAD [0-9a-f]{40} is on no framework branch or remote-tracking ref$"
  expect_out "HEAD $stray "
  expect_eq "$(git -C "$WT" rev-parse HEAD)" "$stray" "HEAD after refusing an unreachable commit"
  [[ -f $WT/stray.txt ]] || fail "the stray commit's file is gone"

  local doment_head
  doment_head=$(git rev-parse HEAD)
  DARKRAISE_FRAMEWORK_PATH=$T/doment/src fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: $T/doment/src exists but is not a git worktree$"
  expect_eq "$(git rev-parse HEAD)" "$doment_head" "doment HEAD after refusing a plain directory"
  git symbolic-ref -q HEAD >/dev/null || fail "doment HEAD was detached"

  DARKRAISE_FRAMEWORK_PATH=$T/darkraise-framework fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: $T/darkraise-framework is the framework's primary checkout, not a worktree of it$"
  expect_eq "$(git -C "$T/darkraise-framework" branch --show-current)" master "framework primary checkout branch"

  git init -q -b master "$T/unrelated"
  git -C "$T/unrelated" commit -q --allow-empty -m "Unrelated"
  DARKRAISE_FRAMEWORK_PATH=$T/unrelated fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: $T/unrelated is not a worktree of the framework clone $T/darkraise-framework$"
}

CASES+=(sync_fetches)
case_sync_fetches() {
  local c1 c3
  c1=$(new_framework_repo "$T/source")
  git clone -q "$T/source.origin.git" "$T/darkraise-framework"
  git clone -q "$T/source.origin.git" "$T/other"
  c3=$(framework_commit "$T/other" c3.txt)
  git -C "$T/other" push -q origin master
  new_doment_repo "$T/doment" "$c3"
  cd "$T/doment"
  fw_sh sync
  expect_rc 0
  expect_eq "$(git -C external/darkraise-framework rev-parse HEAD)" "$c3" "worktree HEAD"
  [[ $c1 != "$c3" ]] || fail "the fetched commit is the first commit"
}

CASES+=(sync_no_clone)
case_sync_no_clone() {
  new_doment_repo "$T/doment" 0000000000000000000000000000000000000000
  cd "$T/doment"
  DARKRAISE_FRAMEWORK_REPO=$T/none fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: no darkraise-framework clone at $T/none or $T/darkraise-framework$"
  [[ ! -e external/darkraise-framework ]] || fail "a framework worktree was created"

  new_framework_repo "$T/darkraise-framework" >/dev/null
  DARKRAISE_FRAMEWORK_REPO=$T/none fw_sh sync
  expect_rc 1
  expect_out "^framework.sh: no darkraise-framework clone at $T/none \(DARKRAISE_FRAMEWORK_REPO\); unset it to use $T/darkraise-framework$"
  [[ ! -e external/darkraise-framework ]] || fail "the default clone was used although DARKRAISE_FRAMEWORK_REPO is set"
}

CASES+=(sync_linked_worktree)
case_sync_linked_worktree() {
  synced_setup
  git -C "$T/doment" worktree add -q -b linked "$T/doment-wt"
  cd "$T/doment-wt"
  fw_sh sync
  expect_rc 0
  [[ -d $T/doment-wt/external/darkraise-framework ]] || fail "no framework worktree in the linked checkout"
  expect_eq "$(git -C "$T/doment-wt/external/darkraise-framework" rev-parse --show-toplevel)" \
    "$T/doment-wt/external/darkraise-framework" "linked checkout's framework worktree"
  expect_eq "$(git -C "$T/doment-wt/external/darkraise-framework" rev-parse HEAD)" "$C1" "linked worktree HEAD"
  dn build src/App
  expect_rc 0
  cd "$T/doment"
  dn build src/App
  expect_rc 0
}

CASES+=(pin_mismatch)
case_pin_mismatch() {
  synced_setup
  local c2 text
  c2=$(framework_commit "$T/darkraise-framework" c2.txt)
  echo "$c2" > build/darkraise-framework.pin
  text="DOMENT001: darkraise-framework at $WT is at $C1, but the pin is $c2"
  dn build src/App
  expect_rc 0
  expect_count "warning $text$" 1
  dn build src/App -p:FrameworkPinStrict=true
  expect_rc 1
  expect_count "error $text$" 1
  dn build src/App -p:TreatWarningsAsErrors=true
  expect_rc 0
  expect_count "warning $text$" 1
  expect_no_out "error $text"
}

row_modified() { echo '// changed' >> "$WT/src/Darkraise/Class1.cs"; }
row_staged() { echo staged > "$WT/staged.txt"; git -C "$WT" add staged.txt; }
row_untracked() { echo '// new' > "$WT/src/Darkraise/New.cs"; }
row_root_props() { echo '<Project><!-- changed --></Project>' > "$WT/Directory.Build.props"; }
row_user_file() { echo '<Project />' > "$WT/src/Darkraise/Darkraise.csproj.user"; }
row_moved_untracked() {
  ROW_C2=$(framework_commit "$T/darkraise-framework" c2.txt)
  git -C "$WT" switch -q --detach "$ROW_C2"
  echo note > "$WT/notes.txt"
}

CASES+=(pin_not_clean)
case_pin_not_clean() {
  CASE_ROOT=$T
  local row path
  for row in modified:src/Darkraise/Class1.cs staged:staged.txt untracked:src/Darkraise/New.cs \
    root_props:Directory.Build.props user_file:src/Darkraise/Darkraise.csproj.user; do
    path=${row#*:}
    row=${row%%:*}
    T=$CASE_ROOT/$row
    mkdir -p "$T"
    synced_setup
    "row_$row"
    dn build src/App
    expect_rc 0
    expect_count "warning DOMENT001: darkraise-framework at $WT is at the pin $C1 but not clean, first: $path$" 1
    dn build src/App -p:FrameworkPinStrict=true
    expect_rc 1
    expect_count "error DOMENT001: darkraise-framework at $WT is at the pin $C1 but not clean, first: $path$" 1
  done

  T=$CASE_ROOT/moved_untracked
  mkdir -p "$T"
  synced_setup
  row_moved_untracked
  dn build src/App
  expect_rc 0
  expect_count "warning DOMENT001: darkraise-framework at $WT is at $ROW_C2, but the pin is $C1; not clean, first: notes.txt$" 1

  T=$CASE_ROOT/build_output
  mkdir -p "$T"
  synced_setup
  mkdir -p "$WT/src/Darkraise/obj" "$WT/bin"
  echo x > "$WT/src/Darkraise/obj/x"
  echo y > "$WT/bin/y"
  dn build src/App -p:FrameworkPinStrict=true
  expect_rc 0
  expect_no_out 'DOMENT001'
}

CASES+=(pin_unverifiable)
case_pin_unverifiable() {
  local c1
  c1=$(new_framework_repo "$T/darkraise-framework")
  new_doment_repo "$T/doment" "$c1"
  cp -r "$T/darkraise-framework" "$T/plain"
  rm -rf "$T/plain/.git"
  cd "$T/doment"
  dn build src/App "-p:DarkraiseFrameworkPath=$T/plain"
  expect_rc 0
  expect_count "warning DOMENT002: darkraise-framework at $T/plain cannot be verified: not a git checkout$" 1
  expect_no_out 'DOMENT001'
  dn build src/App "-p:DarkraiseFrameworkPath=$T/plain" -p:FrameworkPinStrict=true
  expect_rc 1
  expect_count "error DOMENT002: darkraise-framework at $T/plain cannot be verified: not a git checkout$" 1

  cp -r "$T/plain" "$T/doment/external/darkraise-framework"
  dn build src/App
  expect_rc 0
  expect_count "warning DOMENT002: darkraise-framework at $T/doment/external/darkraise-framework cannot be verified: not a git checkout$" 1
  expect_no_out 'DOMENT001'
  dn build src/App -p:FrameworkPinStrict=true
  expect_rc 1
  expect_count 'error DOMENT002: .* cannot be verified: not a git checkout$' 1
}

CASES+=(pin_git_missing)
case_pin_git_missing() {
  local root=$FIXTURE_RUN/pin_git_missing bin=$T/bin
  fixture_project pin_git_missing src/App net10.0
  mkdir -p "$bin"
  ln -s "$(command -v dotnet)" "$bin/dotnet"
  ln -s "$(command -v timeout)" "$bin/timeout"
  PATH=$bin dn build "$root/src/App"
  expect_rc 0
  expect_count "warning DOMENT002: darkraise-framework at $DOMENT_FIXTURE_FRAMEWORK/? cannot be verified: git not found$" 1
  PATH=$bin dn build "$root/src/App" -p:FrameworkPinStrict=true
  expect_rc 1
  expect_count "error DOMENT002: darkraise-framework at $DOMENT_FIXTURE_FRAMEWORK/? cannot be verified: git not found$" 1
}

CASES+=(pin_malformed)
case_pin_malformed() {
  synced_setup
  echo abc > build/darkraise-framework.pin
  dn build src/App
  expect_rc 1
  expect_count "error DOMENT006: $T/doment/build/darkraise-framework.pin must hold one full 40-character commit hash$" 1
}

CASES+=(pin_once_per_build)
case_pin_once_per_build() {
  synced_setup
  local c2
  c2=$(framework_commit "$T/darkraise-framework" c2.txt)
  echo "$c2" > build/darkraise-framework.pin
  write_file src/Lib/Lib.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="$(DarkraiseFrameworkPath)/src/Darkraise/Darkraise.csproj" />
  </ItemGroup>
</Project>
XML
  write_file App.slnx <<'XML'
<Solution>
  <Project Path="src/App/App.csproj" />
  <Project Path="src/Lib/Lib.csproj" />
</Solution>
XML
  dn build App.slnx -m
  expect_rc 0
  expect_count 'warning DOMENT001' 1
}

CASES+=(two_pins_strict)
case_two_pins_strict() {
  synced_setup
  local c2
  c2=$(framework_commit "$T/darkraise-framework" c2.txt)
  git -C "$T/doment" worktree add -q -b linked "$T/doment-wt"
  cd "$T/doment-wt"
  echo "$c2" > build/darkraise-framework.pin
  fw_sh sync
  expect_rc 0
  dn build src/App -p:FrameworkPinStrict=true
  expect_rc 0
  expect_no_out 'DOMENT001'
  cd "$T/doment"
  dn build src/App -p:FrameworkPinStrict=true
  expect_rc 0
  expect_no_out 'DOMENT001'
  # Control: the primary checkout's worktree checked against the linked checkout's pin fails.
  dn build src/App -p:FrameworkPinStrict=true "-p:DomentFrameworkPinFile=$T/doment-wt/build/darkraise-framework.pin"
  expect_rc 1
  expect_count "error DOMENT001: darkraise-framework at $WT is at $C1, but the pin is $c2$" 1
}

# Comma-separated IDs of the libraries of type package in a project.assets.json.
assets_packages() {
  awk '
    /^  "libraries": \{/ { inlib = 1; next }
    inlib && /^  \}/ { inlib = 0 }
    inlib && /^    "[^"]+\/[^"]+": \{/ { key = $0; sub(/^    "/, "", key); sub(/\/.*/, "", key); next }
    inlib && /"type": "package"/ { ids = ids (ids == "" ? "" : ",") key }
    END { print ids }
  ' "$1"
}

CASES+=(real_framework_strict)
case_real_framework_strict() {
  local fw=$REPO_ROOT/external/darkraise-framework
  [[ -d $fw ]] || fail "no framework worktree at $fw; run tools/framework.sh sync"
  mkdir -p "$T/real"
  printf '<Project>\n  <Import Project="%s/Directory.Build.props" />\n</Project>\n' "$REPO_ROOT" > "$T/real/Directory.Build.props"
  printf '<Project>\n  <Import Project="%s/Directory.Build.targets" />\n</Project>\n' "$REPO_ROOT" > "$T/real/Directory.Build.targets"
  write_file "$T/real/Real.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="$(DarkraiseFrameworkPath)/src/Darkraise/Darkraise.csproj" />
  </ItemGroup>
</Project>
XML
  cd "$T/real"
  dn build Real.csproj -p:FrameworkPinStrict=true "-p:DarkraiseFrameworkPath=$fw" \
    "-p:RestoreAdditionalProjectFallbackFolders=$HOME/.nuget/packages"
  expect_rc 0
  expect_no_out 'DOMENT[0-9]'
  local packages
  packages=$(assets_packages "$T/real/obj/project.assets.json")
  # Control: the same build against another pin fails, so the check did run on the real framework.
  printf '%040d\n' 0 > "$T/other.pin"
  dn build Real.csproj -p:FrameworkPinStrict=true "-p:DarkraiseFrameworkPath=$fw" \
    "-p:RestoreAdditionalProjectFallbackFolders=$HOME/.nuget/packages" "-p:DomentFrameworkPinFile=$T/other.pin"
  expect_rc 1
  expect_count "error DOMENT001: darkraise-framework at $fw is at [0-9a-f]{40}, but the pin is 0{40}$" 1
  echo "note real_framework_strict: packages: ${packages:-none}"
  cd "$T"
  rm -rf "$T/real"
}

CASES+=(pinverb_records)
case_pinverb_records() {
  synced_setup
  git -C "$WT" switch -q -c feature
  local c2
  c2=$(framework_commit "$WT" feature.txt)
  fw_sh pin
  expect_rc 0
  cmp -s build/darkraise-framework.pin <(printf '%s\n' "$c2") || fail "pin file is not exactly '$c2\\n': $(od -c build/darkraise-framework.pin | head -n 3)"
  expect_out "^framework.sh: warning: $c2 is not on any branch of the framework's remote$"
  git -C "$WT" push -q origin feature
  git -C "$WT" fetch -q origin
  fw_sh pin
  expect_rc 0
  expect_no_out 'warning'
  cmp -s build/darkraise-framework.pin <(printf '%s\n' "$c2") || fail "pin file changed after the second pin"
}

CASES+=(pinverb_refuses_dirty)
case_pinverb_refuses_dirty() {
  synced_setup
  git -C "$WT" switch -q -c feature
  framework_commit "$WT" feature.txt >/dev/null
  echo '// new' > "$WT/src/Darkraise/New.cs"
  local before
  before=$(<build/darkraise-framework.pin)
  fw_sh pin
  expect_rc 1
  expect_out "^framework.sh: $WT is not clean \(first: src/Darkraise/New.cs\)$"
  expect_eq "$(<build/darkraise-framework.pin)" "$before" "pin file after refusing"
}

release_row_modified() { echo '// changed' >> "$WT/src/Darkraise/Class1.cs"; ROW_FILE=src/Darkraise/Class1.cs; }
release_row_staged() { echo staged > "$WT/staged.txt"; git -C "$WT" add staged.txt; ROW_FILE=staged.txt; }
release_row_untracked() { echo '// new' > "$WT/src/Darkraise/New.cs"; ROW_FILE=src/Darkraise/New.cs; }
release_row_ignored_docs() { mkdir -p "$WT/docs/dforge"; echo plan > "$WT/docs/dforge/plan.md"; ROW_FILE=docs/dforge/plan.md; }
release_row_ignored_worktrees() { mkdir -p "$WT/.worktrees/x"; echo x > "$WT/.worktrees/x/file"; ROW_FILE=.worktrees/x/file; }
release_row_stray_commit() { framework_commit "$WT" stray.txt >/dev/null; ROW_FILE=stray.txt; }

CASES+=(release_refuses)
case_release_refuses() {
  local case_root=$T row expected
  for row in modified:src/Darkraise/Class1.cs staged:staged.txt untracked:src/Darkraise/New.cs \
    ignored_docs:docs/dforge/ ignored_worktrees:.worktrees/ stray_commit:HEAD; do
    expected=${row#*:}
    row=${row%%:*}
    T=$case_root/$row
    mkdir -p "$T"
    synced_setup
    "release_row_$row"
    fw_sh release
    expect_rc 1
    if [[ $expected == HEAD ]]; then
      expect_out "^framework.sh: $WT HEAD [0-9a-f]{40} is on no framework branch or remote-tracking ref$"
    else
      expect_out "^framework.sh: $WT is not clean \(first: ${expected//./\\.}\)$"
    fi
    [[ -f $WT/$ROW_FILE ]] || fail "$row: $ROW_FILE is gone after the refusal"
    [[ -f $WT/src/Darkraise/Class1.cs ]] || fail "$row: the worktree's files are gone after the refusal"
    git -C "$T/darkraise-framework" worktree list --porcelain | grep -qxF "worktree $WT" ||
      fail "$row: the worktree is no longer listed by the clone"
  done
}

CASES+=(release_removes_clean)
case_release_removes_clean() {
  synced_setup
  mkdir -p "$WT/src/Darkraise/obj" "$WT/bin"
  echo x > "$WT/src/Darkraise/obj/x"
  echo y > "$WT/bin/y"
  fw_sh release
  expect_rc 0
  [[ ! -e $WT ]] || fail "the worktree directory still exists"
  if git -C "$T/darkraise-framework" worktree list --porcelain | grep -qxF "worktree $WT"; then
    fail "the clone still lists the worktree"
  fi

  fw_sh sync
  expect_rc 0
  git -C "$WT" switch -q -c feature
  framework_commit "$WT" feature.txt >/dev/null
  git -C "$WT" switch -q --detach
  fw_sh release
  expect_rc 0
  [[ ! -e $WT ]] || fail "the worktree detached at feature's commit still exists"
  if git -C "$T/darkraise-framework" worktree list --porcelain | grep -qxF "worktree $WT"; then
    fail "the clone still lists the worktree detached at feature's commit"
  fi
  expect_eq "$(git -C "$T/darkraise-framework" branch --list feature --format='%(refname:short)')" feature "feature branch after release"

  fw_sh release
  expect_rc 0
  expect_out "^framework.sh: no framework worktree at $WT$"
}

CASES+=(register_valid)
case_register_valid() {
  fixture_project register_valid src/App net10.0
  dn build "$FIXTURE_RUN/register_valid/src/App"
  expect_rc 0
  expect_no_out 'DOMENT013'
}

# Drops the column named $2 from every table row in the section headed "## $1".
drop_column() {
  awk -v heading="## $1" -v column="$2" -F'|' -v OFS='|' '
    /^## / { inside = ($0 == heading); drop = 0 }
    inside && /^\|/ {
      if (!drop) { for (i = 1; i <= NF; i++) { cell = $i; gsub(/^ +| +$/, "", cell); if (cell == column) drop = i } }
      if (drop) { line = ""; for (i = 1; i <= NF; i++) if (i != drop) line = line (line == "" && i == 1 ? "" : "|") $i; $0 = line }
    }
    { print }
  ' "$3" > "$3.tmp" && mv "$3.tmp" "$3"
}

# Empties the cell of row $1 in the column named $2 (the row's table header gives the position).
empty_cell() {
  awk -v id="$1" -v column="$2" -F'|' -v OFS='|' '
    /^\|/ && !header_seen { for (i = 1; i <= NF; i++) { cell = $i; gsub(/^ +| +$/, "", cell); if (cell == column) pos = i } header_seen = 1 }
    /^## / { header_seen = 0 }
    { cell = $2; gsub(/^ +| +$/, "", cell) }
    /^\|/ && cell == id && pos { $pos = " " }
    { print }
  ' "$3" > "$3.tmp" && mv "$3.tmp" "$3"
}

malformed_row() {
  local name=$1 expected=$2
  shift 2
  fixture_project "$name" src/App net10.0
  local register=$FIXTURE_RUN/$name/register.md
  "$@" "$register"
  dn build "$FIXTURE_RUN/$name/src/App"
  expect_rc 1
  expect_count "error DOMENT013: $register: $expected$" 1
  expect_count 'error DOMENT013' 1
}

remove_platform_heading() { sed -i '/^## Platform packages$/d' "$1"; }
rename_b2() { sed -i 's/^| B2 |/| B1 |/' "$1"; }

CASES+=(register_malformed)
case_register_malformed() {
  malformed_row malformed_heading "table 'Platform packages' is missing" remove_platform_heading
  malformed_row malformed_column "table 'Build-and-test-only tools' has no column 'Licence'" \
    drop_column 'Build-and-test-only tools' Licence
  malformed_row malformed_duplicate "duplicate ID B1" rename_b2
  local column
  for column in Reason Licence Behind Replacement Approved; do
    malformed_row "malformed_empty_$column" "row X1, column '$column' is empty" empty_cell X1 "$column"
  done
}

CASES+=(register_missing_file)
case_register_missing_file() {
  fixture_project register_missing_file src/App net10.0
  rm "$FIXTURE_RUN/register_missing_file/register.md"
  local register=$FIXTURE_RUN/register_missing_file/src/App/register.md
  dn build "$FIXTURE_RUN/register_missing_file/src/App"
  expect_rc 1
  expect_count "error DOMENT013: $register: table 'Exceptions' is missing$" 1
}

# Packs Fx.Listed, Fx.Unlisted, Fx.Tool, Fx.Parent (which depends on Fx.Unlisted), Fx.Wild.Core
# and Fx.Platform into the run feed, once per run.
pack_fixture_packages() {
  [[ -f $TROOT/packed ]] && return 0
  local src=$TROOT/packsrc id dep
  mkdir -p "$src"
  echo '<Project />' > "$src/Directory.Build.props"
  echo '<Project />' > "$src/Directory.Build.targets"
  for id in Fx.Listed Fx.Unlisted Fx.Tool Fx.Parent Fx.Wild.Core Fx.Platform; do
    dep=
    [[ $id == Fx.Parent ]] && dep='<ItemGroup><PackageReference Include="Fx.Unlisted" Version="1.0.0" /></ItemGroup>'
    write_file "$src/$id/$id.csproj" <<XML
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <PackageId>$id</PackageId>
    <Version>1.0.0</Version>
  </PropertyGroup>
  $dep
</Project>
XML
    echo "namespace ${id//./}; public static class Marker { }" > "$src/$id/Marker.cs"
    dn pack "$src/$id" -o "$FEED"
    [[ $RC -eq 0 ]] || fail "packing $id failed: $(tail -n 20 <<<"$OUT")"
  done
  touch "$TROOT/packed"
}

# Adds the X8, X9 and B9 rows the package cases rely on to a case's register.
add_fixture_rows() {
  local register=$FIXTURE_RUN/$1/register.md
  # The backticks are Markdown, not command substitution.
  # shellcheck disable=SC2016
  sed -i '/^| X1 |/a | X8 | Fx listed | `Fx.Listed` | Tests | Fixture | MIT | `IFixture` | None | 2026-11-24 |\n| X9 | Fx parent | `Fx.Parent` | Tests | Fixture | MIT | `IFixture` | None | 2026-11-24 |' "$register"
  # shellcheck disable=SC2016
  sed -i '/^| B2 |/a | B9 | Fx tool | `Fx.Tool` | Tests | MIT | 2026-11-24 |' "$register"
}

# package_case <case> <relative dir> <target framework> [specs...]: a fixture project with the
# packages packed and the extra register rows added.
package_case() {
  pack_fixture_packages
  fixture_project "$@"
  add_fixture_rows "$1"
}

CASES+=(packages_listed)
case_packages_listed() {
  package_case packages_listed src/App net10.0 package=Fx.Listed/1.0.0
  dn build "$FIXTURE_RUN/packages_listed/src/App"
  expect_rc 0
  expect_no_out 'error DOMENT'
  expect_count 'DOMENT-PACKAGES: 1$' 1
}

CASES+=(packages_matching)
case_packages_matching() {
  local root=$FIXTURE_RUN/packages_matching
  package_case packages_matching src/App net10.0 package=Fx.Wild.Core/1.0.0 package=Fx.Platform/1.0.0
  dn build "$root/src/App"
  expect_rc 1
  expect_count "error DOMENT010: .*package Fx.Wild.Core 1.0.0 is in no table" 1
  expect_count "error DOMENT010: .*package Fx.Platform 1.0.0 is in no table" 1
  # A lower-case wildcard row and an upper-case platform row: matching is by prefix and ignores case.
  # shellcheck disable=SC2016
  sed -i '/^| X1 |/a | X6 | Fx wild | `fx.wild.*` | Tests | Fixture | MIT | `IFixture` | None | 2026-11-24 |' "$root/register.md"
  # shellcheck disable=SC2016
  echo '| `FX.PLATFORM` | Fixture | 2026-11-24 |' >> "$root/register.md"
  dn build "$root/src/App"
  expect_rc 0
  expect_no_out 'error DOMENT'
  expect_count 'DOMENT-PACKAGES: 2$' 1
}

CASES+=(package_unlisted_direct)
case_package_unlisted_direct() {
  package_case package_unlisted_direct src/App net10.0 package=Fx.Unlisted/1.0.0
  local root=$FIXTURE_RUN/package_unlisted_direct
  dn build "$root/src/App"
  expect_rc 1
  expect_count "error DOMENT010: $root/src/App/App.csproj: package Fx.Unlisted 1.0.0 is in no table of $root/register.md \(direct reference\)$" 1
}

CASES+=(package_unlisted_transitive)
case_package_unlisted_transitive() {
  local root=$FIXTURE_RUN/package_unlisted_transitive
  package_case package_unlisted_transitive src/App net10.0 package=Fx.Parent/1.0.0
  fixture_project package_unlisted_transitive src/Lib net10.0 package=Fx.Unlisted/1.0.0
  fixture_project package_unlisted_transitive src/App2 net10.0 project=../Lib/Lib.csproj
  dn build "$root/src/App"
  expect_rc 1
  expect_count "error DOMENT010: $root/src/App/App.csproj: package Fx.Unlisted 1.0.0 is in no table of $root/register.md \(through Fx.Parent\)$" 1
  dn build "$root/src/App2"
  expect_rc 1
  expect_count "error DOMENT010: $root/src/App2/App2.csproj: package Fx.Unlisted 1.0.0 is in no table of $root/register.md \(through project Lib\)$" 1
  # App3 -> Mid -> Lib: the direct reference is Mid, although Lib comes first in the assets file.
  fixture_project package_unlisted_transitive src/Mid net10.0 project=../Lib/Lib.csproj
  fixture_project package_unlisted_transitive src/App3 net10.0 project=../Mid/Mid.csproj
  dn build "$root/src/App3"
  expect_rc 1
  expect_count "error DOMENT010: $root/src/App3/App3.csproj: package Fx.Unlisted 1.0.0 is in no table of $root/register.md \(through project Mid\)$" 1
}

CASES+=(buildonly_package)
case_buildonly_package() {
  local root=$FIXTURE_RUN/buildonly_package
  package_case buildonly_package src/App net10.0 package=Fx.Tool/1.0.0
  fixture_project buildonly_package tests/App.Tests net10.0 package=Fx.Tool/1.0.0
  dn build "$root/src/App"
  expect_rc 1
  expect_count "error DOMENT011: $root/src/App/App.csproj ships but resolves build-and-test-only package Fx.Tool 1.0.0, row B9 of $root/register.md \(direct reference\)$" 1
  dn build "$root/tests/App.Tests"
  expect_rc 0
  expect_no_out 'error DOMENT'
  # A shipping project cannot classify itself as build-only.
  fixture_project buildonly_package src/Sneaky net10.0 package=Fx.Tool/1.0.0
  sed -i 's|<TargetFramework>|<DomentBuildOnly>true</DomentBuildOnly><TargetFramework>|' "$root/src/Sneaky/Sneaky.csproj"
  dn build "$root/src/Sneaky"
  expect_rc 1
  expect_count "error DOMENT011: $root/src/Sneaky/Sneaky.csproj ships but resolves build-and-test-only package Fx.Tool 1.0.0" 1
}

CASES+=(buildonly_project_ref)
case_buildonly_project_ref() {
  local root=$FIXTURE_RUN/buildonly_project_ref
  fixture_project buildonly_project_ref tools/Helper net10.0
  fixture_project buildonly_project_ref src/App net10.0 project=../../tools/Helper/Helper.csproj
  dn build "$root/src/App"
  expect_rc 1
  expect_count "error DOMENT011: $root/src/App/App.csproj ships but references build-only project $root/tools/Helper/Helper.csproj$" 1
}

CASES+=(framework_refs)
case_framework_refs() {
  local fw=$DOMENT_FIXTURE_FRAMEWORK root
  fixture_project framework_core src/App net10.0 "project=$fw/src/Darkraise/Darkraise.csproj"
  dn build "$FIXTURE_RUN/framework_core/src/App"
  expect_rc 0

  root=$FIXTURE_RUN/framework_api
  fixture_project framework_api src/App net10.0 "project=$fw/src/Darkraise.Api/Darkraise.Api.csproj"
  dn build "$root/src/App"
  expect_rc 1
  expect_count "error DOMENT012: $root/src/App/App.csproj: project reference $fw/src/Darkraise.Api/Darkraise.Api.csproj is not an allowed darkraise-framework project$" 1

  root=$FIXTURE_RUN/framework_win32_from_net10
  fixture_project framework_win32_from_net10 src/App net10.0 "project=$fw/src/Darkraise.Win32UI/Darkraise.Win32UI.csproj"
  dn build "$root/src/App"
  expect_rc 1
  expect_count "error DOMENT012: $root/src/App/App.csproj: project reference $fw/src/Darkraise.Win32UI/Darkraise.Win32UI.csproj is not an allowed darkraise-framework project$" 1
  expect_no_out 'NU1201'

  root=$FIXTURE_RUN/framework_outside
  mkdir -p "$TROOT/outside/Other"
  printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>\n' \
    > "$TROOT/outside/Other/Other.csproj"
  fixture_project framework_outside src/App net10.0 "project=$TROOT/outside/Other/Other.csproj"
  dn build "$root/src/App"
  expect_rc 1
  expect_count "error DOMENT012: $root/src/App/App.csproj: project reference $TROOT/outside/Other/Other.csproj is not an allowed darkraise-framework project$" 1

  root=$FIXTURE_RUN/framework_windows
  fixture_project framework_windows src/WinApp net10.0-windows \
    "project=$fw/src/Darkraise.Win32UI/Darkraise.Win32UI.csproj" \
    "project=$fw/src/Darkraise.Win32UI.Generators/Darkraise.Win32UI.Generators.csproj"
  dn msbuild "$root/src/WinApp" -t:DomentReferenceCheck
  expect_rc 0
  expect_no_out 'DOMENT012'

  root=$FIXTURE_RUN/framework_windows_api
  fixture_project framework_windows_api src/WinApp net10.0-windows "project=$fw/src/Darkraise.Api/Darkraise.Api.csproj"
  dn msbuild "$root/src/WinApp" -t:DomentReferenceCheck
  expect_rc 1
  expect_count "error DOMENT012: $root/src/WinApp/WinApp.csproj: project reference $fw/src/Darkraise.Api/Darkraise.Api.csproj is not an allowed darkraise-framework project$" 1
}

expect_last() {
  local last
  last=$(tail -n 1 <<<"$OUT")
  [[ $last == "$1" ]] || fail "expected the last line '$1', got '$last'; output: $(tail -n 20 <<<"$OUT")"
}

# A gate tree: a stand-in doment repository synced to a stand-in framework, without src/App, with
# the real register plus row B9 (Fx.Tool), and a nuget.config that restores only from the run feed
# into the run's packages folder.
gate_setup() {
  pack_fixture_packages
  synced_setup
  git rm -rq src/App
  cp "$REPO_ROOT/docs/third-party-exceptions.md" docs/third-party-exceptions.md
  # The backticks are Markdown, not command substitution.
  # shellcheck disable=SC2016
  sed -i '/^| B3 |/a | B9 | Fx tool | `Fx.Tool` | Tests | MIT | 2026-11-24 |' docs/third-party-exceptions.md
  write_file nuget.config <<XML
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <config>
    <add key="globalPackagesFolder" value="$TROOT/pkgs" />
  </config>
  <packageSources>
    <clear />
    <add key="run-feed" value="$FEED" />
  </packageSources>
</configuration>
XML
  git add -A
  git commit -qm "Gate tree"
  REG=$T/doment/docs/third-party-exceptions.md
}

# gate_project <project file> [<package id>...]: a net10.0 library in the gate tree, added to the index.
gate_project() {
  local file=$1 id items=
  shift
  for id in "$@"; do
    items+="    <PackageReference Include=\"$id\" Version=\"1.0.0\" />"$'\n'
  done
  write_file "$file" <<XML
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
$items  </ItemGroup>
</Project>
XML
  git add "$file"
}

run_gate() {
  OUT=$(timeout 1800 bash "$T/doment/build/gate.sh" "$T/doment" 2>&1) && RC=0 || RC=$?
}

CASES+=(gate_reports_all)
case_gate_reports_all() {
  gate_setup
  gate_project src/A/A.csproj Fx.Unlisted
  gate_project src/B/B.csproj Fx.Tool
  gate_project src/C/C.csproj
  gate_project src/D/D.csproj Fx.Unlisted
  git rm -q --cached src/D/D.csproj
  run_gate
  expect_rc 1
  expect_count "^error DOMENT010: $T/doment/src/A/A.csproj: package Fx.Unlisted 1.0.0 is in no table of $REG \(direct reference\)$" 1
  expect_count "^error DOMENT011: $T/doment/src/B/B.csproj ships but resolves build-and-test-only package Fx.Tool 1.0.0, row B9 of $REG \(direct reference\)$" 1
  expect_count 'error DOMENT' 2
  expect_no_out 'src/D'
  expect_last 'gate: 3 projects checked, 2 packages seen, 2 violations'
}

CASES+=(gate_unlisted_project)
case_gate_unlisted_project() {
  gate_setup
  gate_project extra/E/E.csproj Fx.Unlisted
  run_gate
  expect_rc 1
  expect_count "^error DOMENT010: $T/doment/extra/E/E.csproj: package Fx.Unlisted 1.0.0 is in no table of $REG" 1
}

CASES+=(gate_not_importing)
case_gate_not_importing() {
  gate_setup
  gate_project src/F/F.csproj
  echo '<Project />' > src/F/Directory.Build.props
  echo '<Project />' > src/F/Directory.Build.targets
  git add src/F
  run_gate
  expect_rc 1
  expect_count "^error DOMENT020: $T/doment/src/F/F.csproj does not import the root Directory.Build.targets$" 1
  expect_last 'gate: 1 projects checked, 0 packages seen, 1 violations'
}

CASES+=(gate_tool_manifest)
case_gate_tool_manifest() {
  gate_setup
  write_file .config/dotnet-tools.json <<'JSON'
{
  "version": 1,
  "isRoot": true,
  "tools": {
    "csharpier": { "version": "1.0.0", "commands": ["csharpier"], "rollForward": false },
    "dotnet-ef": { "version": "10.0.0", "commands": ["dotnet-ef"], "rollForward": false }
  }
}
JSON
  git add .config
  run_gate
  expect_rc 1
  expect_count "^error DOMENT021: \.config/dotnet-tools\.json: tool dotnet-ef is not a build-and-test-only row of $REG$" 1
  expect_count 'DOMENT021' 1
  expect_no_out 'csharpier'
}

CASES+=(gate_binary)
case_gate_binary() {
  gate_setup
  mkdir -p lib assets
  printf '\177ELF' > lib/native.so
  printf 'MZ' > assets/x.dll
  git add lib assets
  run_gate
  expect_rc 1
  expect_count "^error DOMENT022: lib/native\.so is a tracked binary that no row of $REG lists$" 1
  expect_count "^error DOMENT022: assets/x\.dll is a tracked binary that no row of $REG lists$" 1
  # shellcheck disable=SC2016
  sed -i '/^| X2 |/a | X7 | Native fixture | `lib/native.so` | Tests | Fixture | MIT | `INative` | None | 2026-11-24 |' docs/third-party-exceptions.md
  git add docs
  run_gate
  expect_rc 1
  expect_count 'DOMENT022' 1
  expect_count '^error DOMENT022: assets/x\.dll is a tracked binary' 1
}

CASES+=(gate_main_pin)
case_gate_main_pin() {
  gate_setup
  gate_project src/C/C.csproj
  git commit -qm "Add C"
  local c2
  git -C "$WT" switch -q -c feature
  c2=$(framework_commit "$WT" feature.txt)
  echo "$c2" > build/darkraise-framework.pin
  fw_sh sync
  expect_rc 0
  run_gate
  expect_rc 1
  expect_count "^error DOMENT005: pin $c2 is not an ancestor of the framework's origin/master$" 1
  expect_count 'error DOMENT' 1
  git switch -q -c topic
  run_gate
  expect_rc 0
  expect_no_out 'DOMENT005'
  expect_last 'gate: 1 projects checked, 0 packages seen, 0 violations'
}

CASES+=(gate_off_pin)
case_gate_off_pin() {
  gate_setup
  gate_project src/C/C.csproj
  git -C "$WT" switch -q -c other
  local c2
  c2=$(framework_commit "$WT" other.txt)
  run_gate
  expect_rc 1
  expect_count "^error DOMENT001: darkraise-framework at $WT is at $c2, but the pin is $C1$" 1
  git -C "$WT" switch -q --detach "$C1"
  echo untracked > "$WT/untracked.txt"
  run_gate
  expect_rc 1
  expect_count "^error DOMENT001: darkraise-framework at $WT is at the pin $C1 but not clean, first: untracked.txt$" 1
  # With no tracked project left, the framework check still runs.
  git rm -q --cached src/C/C.csproj
  run_gate
  expect_rc 1
  expect_count "^error DOMENT001: darkraise-framework at $WT is at the pin $C1 but not clean, first: untracked.txt$" 1
  expect_last 'gate: 0 projects checked, 0 packages seen, 1 violations'
}

CASES+=(gate_master_pin_file)
case_gate_master_pin_file() {
  gate_setup
  echo not-a-pin > build/darkraise-framework.pin
  run_gate
  expect_rc 1
  expect_count "^error DOMENT006: $T/doment/build/darkraise-framework.pin must hold one full 40-character commit hash$" 1
  echo "$C1" > build/darkraise-framework.pin
  fw_sh release
  expect_rc 0
  run_gate
  expect_rc 1
  expect_count "^error DOMENT003: darkraise-framework not found at $WT; run tools/framework.sh sync$" 1
  printf '%s\r\n' "$C1" > build/darkraise-framework.pin
  fw_sh sync
  expect_rc 0
  run_gate
  expect_rc 0
}

CASES+=(gate_skips_fixtures)
case_gate_skips_fixtures() {
  gate_setup
  gate_project tests/build/fixtures/x/src/Bad/Bad.csproj Fx.Unlisted
  run_gate
  expect_rc 0
  expect_last 'gate: 0 projects checked, 0 packages seen, 0 violations'
  gate_project tests/build/other/Bad.csproj Fx.Unlisted
  run_gate
  expect_rc 1
  expect_count "^error DOMENT010: $T/doment/tests/build/other/Bad.csproj: package Fx.Unlisted 1.0.0" 1
}

CASES+=(gate_repository)
case_gate_repository() {
  OUT=$(DOMENT_GATE_NO_FETCH=1 timeout 1800 bash "$REPO_ROOT/build/gate.sh" 2>&1) && RC=0 || RC=$?
  expect_rc 0
  expect_out '^gate: [0-9]+ projects checked, [0-9]+ packages seen, 0 violations$'
}

# ---------------------------------------------------------------------------
# Runner

passed=0
failed=0
for name in "${CASES[@]}"; do
  if [[ -n $FILTER ]] && ! [[ $name =~ $FILTER ]]; then
    continue
  fi
  T=$TROOT/case-$name
  mkdir -p "$T"
  : > "$FAIL_FILE"
  set +e
  ( set -e; cd "$T"; "case_$name" )
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "ok $name"
    passed=$((passed + 1))
  else
    reason=$(cat "$FAIL_FILE")
    echo "not ok $name: ${reason:-exited with $rc}"
    failed=$((failed + 1))
  fi
  rm -rf "$T"
done

echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
