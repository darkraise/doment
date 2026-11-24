#!/usr/bin/env bash
# Acceptance tests of the repository, build and NativeAOT spec.
# Usage: bash tests/build/repository-build.acceptance.sh [<extended regex on the test name>]
# Tests run on the real checkout with the user's normal NuGet sources and package folder; temporary trees live
# under artifacts/acceptance/ and are removed on exit.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
FILTER=${1:-}

export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_USE_MSBUILD_SERVER=0
export UseSharedCompilation=false
export DOTNET_NOLOGO=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
unset DARKRAISE_FRAMEWORK_PATH DARKRAISE_FRAMEWORK_REPO FrameworkPinStrict DOMENT_GATE_NO_FETCH

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=acceptance GIT_AUTHOR_EMAIL=acceptance@doment.invalid
export GIT_COMMITTER_NAME=acceptance GIT_COMMITTER_EMAIL=acceptance@doment.invalid
export GIT_LFS_SKIP_SMUDGE=1

mkdir -p "$REPO_ROOT/artifacts/acceptance"
T=$(mktemp -d "$REPO_ROOT/artifacts/acceptance/run.XXXXXX")
trap 'rm -rf "$T"; rmdir "$REPO_ROOT/artifacts/acceptance" "$REPO_ROOT/artifacts" 2>/dev/null' EXIT
trap 'exit 143' TERM INT

OUT=
RC=0
CASE=
FAILS=()
ENVV=()

# ---------------------------------------------------------------------------
# Soft assertions: a failed check is recorded and the test goes on, so one run shows every broken case.

case_() { CASE=$1; }
note() { FAILS+=("[$CASE] $1"); }
tail_out() { tail -n 10 <<<"$OUT" | cut -c1-500; }
rc_is() { [[ $RC -eq $1 ]] || note "expected exit $1, got $RC; output: $(tail_out)"; }
rc_fails() { [[ $RC -ne 0 ]] || note "expected a non-zero exit, got 0; output: $(tail_out)"; }
has() { grep -Eq -- "$1" <<<"$OUT" || note "no output line matches /$1/; output: $(tail_out)"; }
hasi() { grep -Eqi -- "$1" <<<"$OUT" || note "no output line matches /$1/i; output: $(tail_out)"; }
hasnt() {
  if grep -Eq -- "$1" <<<"$OUT"; then note "an output line matches /$1/: $(grep -E -- "$1" <<<"$OUT" | head -n 2 | cut -c1-400)"; fi
}
count_is() {
  local n
  n=$(grep -Ec -- "$1" <<<"$OUT" || true)
  [[ $n -eq $2 ]] || note "expected $2 lines matching /$1/, got $n; output: $(tail_out)"
}
check() { # check <description> <command...>: passes when the command succeeds
  local what=$1
  shift
  "$@" || note "$what"
}
eq() { [[ $1 == "$2" ]] || note "expected '$2', got '$1' ($3)"; }
die() { echo "SETUP ERROR: $1" >&2; exit 99; }

# The message of the diagnostic lines of one kind ("error" or "warning") with one code, without MSBuild's prefix
# and trailing project path.
diag_msgs() { # diag_msgs <kind> <code-regex>
  grep -E ": $1 $2: " <<<"$OUT" | sed -E "s/^.*: $1 $2: //; s/ \[[^]]*\]\$//" || true
}
error_lines() { grep -E '(^|: )error [A-Za-z]+[0-9]+: ' <<<"$OUT" | sed -E 's/ \[[^]]*\]$//' || true; }
error_line_has() { # error_line_has <pattern>...: one error line matches every pattern
  local lines
  lines=$(error_lines)
  local line ok p
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    ok=1
    for p in "$@"; do grep -Eqi -- "$p" <<<"$line" || ok=0; done
    [[ $ok -eq 1 ]] && return 0
  done <<<"$lines"
  note "no single error line matches all of: $* ; errors: $(head -n 6 <<<"$lines" | cut -c1-400)"
}

# ---------------------------------------------------------------------------
# Running tools

# `dotnet build` appends -consoleloggerparameters:Summary after the caller's -clp:NoSummary (SDK 10.0.302 and
# 10.0.404), so the console logger is replaced by one that is told NoSummary itself.
DN_FLAGS=(-nologo -tl:off -clp:NoSummary -noConsoleLogger "-logger:ConsoleLogger,Microsoft.Build;NoSummary;Verbosity=minimal")

dn() { # dn <dir> <dotnet args...>; ENVV holds NAME=value pairs for this call
  local dir=$1
  shift
  OUT=$(cd "$dir" && env "${ENVV[@]}" timeout 600 dotnet "$@" "${DN_FLAGS[@]}" 2>&1) && RC=0 || RC=$?
}
build() { dn "$1" build "${@:2}"; }

# ---------------------------------------------------------------------------
# Tests

version_at_least() { # version_at_least <version> <minimum>: dotted numeric comparison
  local IFS=.
  local -a a=($1) b=($2)
  local i
  for i in 0 1 2; do
    ((${a[i]:-0} > ${b[i]:-0})) && return 0
    ((${a[i]:-0} < ${b[i]:-0})) && return 1
  done
  return 0
}

t_A1() {
  case_ sdk
  OUT=$(cd "$REPO_ROOT" && timeout 60 dotnet --version 2>&1) && RC=0 || RC=$?
  rc_is 0
  local v
  v=$(tail -n 1 <<<"$OUT")
  if grep -Eq '^10\.0\.4[0-9]{2}$' <<<"$v"; then
    check "dotnet --version printed $v, below 10.0.404" version_at_least "$v" 10.0.404
  else
    note "dotnet --version printed '$v', not a 10.0.4xx version"
  fi

  case_ global.json
  local g=$REPO_ROOT/global.json
  if [[ ! -f $g ]]; then
    note "no global.json at the repository root"
    return 0
  fi
  eq "$(jq -r '.sdk.version' "$g" 2>&1)" 10.0.404 "sdk.version"
  eq "$(jq -r '.sdk.rollForward' "$g" 2>&1)" latestPatch "sdk.rollForward"
  eq "$(jq -r '.test.runner' "$g" 2>&1)" Microsoft.Testing.Platform "test.runner"
}

# ---------------------------------------------------------------------------
# Runner

TESTS=(
  "A1: the SDK on PATH is 10.0.404 or a later 10.0.4xx and global.json pins it with the testing platform|t_A1"
)

passed=0
failed=0
for entry in "${TESTS[@]}"; do
  name=${entry%%|*}
  fn=${entry##*|}
  if [[ -n $FILTER ]] && ! grep -Eq -- "$FILTER" <<<"$name"; then continue; fi
  FAILS=()
  ENVV=()
  CASE=
  ( "$fn"; rc=$?; if [[ $rc -eq 99 ]]; then exit 99; fi
    if [[ ${#FAILS[@]} -gt 0 ]]; then
      printf '%s\n' "${FAILS[@]}" > "$T/fails.$fn"
      exit 1
    fi )
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "PASS $name"
    passed=$((passed + 1))
  else
    echo "FAIL $name"
    if [[ -f $T/fails.$fn ]]; then sed 's/^/    /' "$T/fails.$fn"; else echo "    test aborted with exit $rc"; fi
    failed=$((failed + 1))
  fi
done
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
