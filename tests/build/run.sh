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
trap 'rm -rf "$TROOT"' EXIT
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
  expect_no_out 'DOMENT'
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
