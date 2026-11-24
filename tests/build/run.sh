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
