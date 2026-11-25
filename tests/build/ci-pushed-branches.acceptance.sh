#!/usr/bin/env bash
# Acceptance tests of the CI for pushed branches spec, named by its acceptance numbers.
# Usage: bash tests/build/ci-pushed-branches.acceptance.sh [<extended regex on the test name>]
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
FILTER=${1:-}

export MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_USE_MSBUILD_SERVER=0 UseSharedCompilation=false
export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
# The CI job's own values must never reach a case: each case sets the inputs it relies on.
unset DARKRAISE_FRAMEWORK_PATH DARKRAISE_FRAMEWORK_REPO FrameworkPinStrict DOMENT_GATE_NO_FETCH DOMENT_GATE_PIN_ON_MASTER \
  GITHUB_ACTIONS DOMENT_CI_PIN_ON_MASTER DOMENT_CI_ZLIB_INCLUDE DOMENT_CI_MIN_FREE_GB DOMENT_CI_FRAMEWORK RUNNER_TEMP
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_LFS_SKIP_SMUDGE=1
export GIT_AUTHOR_NAME=acceptance GIT_AUTHOR_EMAIL=acceptance@doment.invalid
export GIT_COMMITTER_NAME=acceptance GIT_COMMITTER_EMAIL=acceptance@doment.invalid

OUTSIDE=$(mktemp -d "${TMPDIR:-/tmp}/doment-ci-qa.XXXXXX")
trap 'rm -rf "$OUTSIDE"' EXIT
trap 'exit 143' TERM INT

OUT=
RC=0
CASE=
FAILS=()

case_() { CASE=$1; }
note() { FAILS+=("[$CASE] $1"); }
tail_out() { tail -n 12 <<<"$OUT" | cut -c1-400; }
rc_is() { [[ $RC -eq $1 ]] || note "expected exit $1, got $RC; output: $(tail_out)"; }
has() { grep -Eq -- "$1" <<<"$OUT" || note "no output line matches /$1/; output: $(tail_out)"; }
hasnt() { ! grep -Eq -- "$1" <<<"$OUT" || note "an output line matches /$1/: $(grep -E -- "$1" <<<"$OUT" | head -n 2 | cut -c1-300)"; }
count_is() {
  local n
  n=$(grep -Ec -- "$1" <<<"$OUT" || true)
  [[ $n -eq $2 ]] || note "expected $2 lines matching /$1/, got $n; output: $(tail_out)"
}

run() { # run <dir> <seconds> <command...>: sets OUT and RC; ENVV holds NAME=value pairs
  local dir=$1 secs=$2
  shift 2
  OUT=$(cd "$dir" && env "${ENVV[@]}" timeout -k 10 "$secs" "$@" 2>&1) && RC=0 || RC=$?
}
ENVV=(DOMENT_QA=1)

# stub_dotnet <dir> <log>: a `dotnet` in <dir> that appends its arguments to <log> and exits 0.
stub_dotnet() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n' "$2" > "$1/dotnet"
  chmod +x "$1/dotnet"
}

t_A25() {
  local bin=$OUTSIDE/a25/bin log
  case_ "GITHUB_ACTIONS=true"
  log=$OUTSIDE/a25/ci.log
  stub_dotnet "$bin" "$log"
  : > "$log"
  ENVV=(DOMENT_QA=1 "PATH=$bin:$PATH" GITHUB_ACTIONS=true)
  run "$REPO_ROOT" 300 bash build/check.sh build
  OUT=$(<"$log")
  count_is 'build-server shutdown' 0
  case_ "GITHUB_ACTIONS unset"
  log=$OUTSIDE/a25/local.log
  stub_dotnet "$bin" "$log"
  : > "$log"
  ENVV=(DOMENT_QA=1 "PATH=$bin:$PATH")
  run "$REPO_ROOT" 300 bash build/check.sh build
  OUT=$(<"$log")
  count_is 'build-server shutdown' 1
}

# ---------------------------------------------------------------------------

declare -A DESC=(
  [A25]="check.sh skips the build-server shutdown on CI"
)

RESULT_FAIL=0
RESULT_PASS=0
for fn in $(declare -F | awk '{print $3}' | grep -E '^t_A[0-9]+$' | sort -t A -k2 -n); do
  n=${fn#t_}
  [[ -z $FILTER || $n =~ $FILTER ]] || continue
  FAILS=()
  ENVV=(DOMENT_QA=1)
  CASE=
  "$fn"
  if [[ ${#FAILS[@]} -eq 0 ]]; then
    echo "ok   $n: ${DESC[$n]}"
    RESULT_PASS=$((RESULT_PASS + 1))
  else
    echo "FAIL $n: ${DESC[$n]}"
    printf '       %s\n' "${FAILS[@]}"
    RESULT_FAIL=$((RESULT_FAIL + 1))
  fi
done
echo "$RESULT_PASS passed, $RESULT_FAIL failed"
[[ $RESULT_FAIL -eq 0 ]]
