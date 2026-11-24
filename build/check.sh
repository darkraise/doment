#!/usr/bin/env bash
# Repository check: build/check.sh [<step>...]; steps: build, portable, aot, test (default: all four, in this order).
set -uo pipefail

# The tree that holds this script, found without git: a copy of the script in a stand-in tree under artifacts/
# must check the stand-in, which git would resolve to the enclosing checkout.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SOLUTION=$ROOT/doment.slnx
ALL_STEPS=(build portable aot test)

export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_USE_MSBUILD_SERVER=0
export UseSharedCompilation=false
export DOTNET_NOLOGO=1

PROPS=(-c Release -p:FrameworkPinStrict=true -p:DomentFormatCheck=true -p:DomentAuditStrict=true)
# `dotnet build` appends -consoleloggerparameters:Summary after the caller's -clp:NoSummary
# (SDK 10.0.302 and 10.0.404), so the console logger is replaced by one that is told NoSummary itself.
DN_FLAGS=(-nologo -tl:off -clp:NoSummary -noConsoleLogger "-logger:ConsoleLogger,Microsoft.Build;NoSummary;Verbosity=minimal")
# The testing platform's handshake fails under -tl:off or -clp:NoSummary
# (docs/dforge/research/2026-11-24-build-probes.md, P6).
TEST_FLAGS=(-nologo)

ERROR_RE='(^|[: ])error [A-Z]+[0-9]+:'
WARNING_RE='(^|[: ])warning [A-Z]+[0-9]+:'

STEPS=("$@")
[[ ${#STEPS[@]} -gt 0 ]] || STEPS=("${ALL_STEPS[@]}")
for step in "${STEPS[@]}"; do
  case $step in
    build | portable | aot | test) ;;
    *)
      echo "check: unknown step '$step'; steps: build, portable, aot, test" >&2
      exit 2
      ;;
  esac
done
if [[ -n ${DOMENT_CHECK_TIMEOUT:-} && ! ${DOMENT_CHECK_TIMEOUT} =~ ^[1-9][0-9]*$ ]]; then
  echo "check: DOMENT_CHECK_TIMEOUT must be a whole number of seconds, got '$DOMENT_CHECK_TIMEOUT'" >&2
  exit 2
fi

DOTNET=$(command -v dotnet) || {
  echo "check: no dotnet on PATH" >&2
  exit 1
}
# The test executable's apphost reads DOTNET_ROOT, so it runs on this SDK's runtime and not on another install's.
DOTNET_ROOT=$(dirname "$(readlink -f "$DOTNET")")
export DOTNET_ROOT

TMP=$(mktemp -d "${TMPDIR:-/tmp}/doment-check.XXXXXX")
OUTPUT=$TMP/output
CAUSE=$TMP/cause
CHILD=
RC=0
TIMED_OUT=0
LIMIT=0
COMMAND=

# Kills the process group of the running call; `timeout` signals only the group it started in, and a node or
# test host may outlive its parent.
kill_child() {
  if [[ -n $CHILD ]]; then
    kill -TERM -- "-$CHILD" 2>/dev/null
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 -- "-$CHILD" 2>/dev/null || break
      sleep 0.5
    done
    kill -KILL -- "-$CHILD" 2>/dev/null
    CHILD=
  fi
}

finish() {
  kill_child
  # Under the same bounds as a call, so the shutdown itself leaves nothing behind.
  setsid timeout -k 10 120 dotnet build-server shutdown > /dev/null 2>&1 &
  CHILD=$!
  wait "$CHILD" 2>/dev/null
  kill -KILL -- "-$CHILD" 2>/dev/null
  CHILD=
  rm -rf "$TMP"
}
trap finish EXIT
trap 'kill_child; exit 130' INT
trap 'kill_child; exit 143' TERM

# call <seconds> <command...>: runs the command in a process group of its own under a timeout, waiting in the
# background so that a trapped signal interrupts the wait; sets RC and TIMED_OUT and leaves the output in OUTPUT.
call() {
  LIMIT=${DOMENT_CHECK_TIMEOUT:-$1}
  shift
  COMMAND="$*"
  (cd "$ROOT" && exec setsid timeout -k 10 "$LIMIT" "$@") > "$OUTPUT" 2>&1 &
  CHILD=$!
  wait "$CHILD"
  RC=$?
  # Anything the call left in its group goes now.
  kill -KILL -- "-$CHILD" 2>/dev/null
  CHILD=
  TIMED_OUT=0
  [[ $RC -eq 124 || $RC -eq 137 ]] && TIMED_OUT=1
  return 0
}

# Writes the cause of the last call's failure: the timeout, else its deduplicated error lines, else its last
# 20 output lines.
call_cause() {
  if [[ $TIMED_OUT -eq 1 ]]; then
    echo "timed out after $LIMIT s: $COMMAND" > "$CAUSE"
    return
  fi
  grep -E "$ERROR_RE" "$OUTPUT" | sed -E 's/ \[[^]]*\]$//' | awk '!seen[$0]++' > "$CAUSE"
  [[ -s $CAUSE ]] || tail -n 20 "$OUTPUT" > "$CAUSE"
}

# call_ok <seconds> <command...>: a call that must exit 0; on failure the cause is written and it returns 1.
call_ok() {
  call "$@"
  if [[ $RC -ne 0 ]]; then
    call_cause
    return 1
  fi
}

step_build() {
  call_ok 600 dotnet build "$SOLUTION" "${PROPS[@]}" "${DN_FLAGS[@]}"
}

step_portable() {
  echo "not implemented" > "$CAUSE"
  return 1
}

step_aot() {
  echo "not implemented" > "$CAUSE"
  return 1
}

step_test() {
  call_ok 600 dotnet test --solution "$SOLUTION" "${PROPS[@]}" "${TEST_FLAGS[@]}"
}

version=$(cd "$ROOT" && timeout 60 dotnet --version 2>/dev/null) || version=unknown
echo "check: dotnet $version at $DOTNET_ROOT"

run=0
failed=0
for step in "${STEPS[@]}"; do
  run=$((run + 1))
  : > "$CAUSE"
  if "step_$step"; then
    echo "check: $step ok"
  else
    echo "check: $step failed"
    sed 's/^/    /' "$CAUSE"
    failed=1
    break
  fi
done
echo "check: $run steps run, $failed failed"
[[ $failed -eq 0 ]] || exit 1
