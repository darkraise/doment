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
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export TESTINGPLATFORM_TELEMETRY_OPTOUT=1

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
  # Every CI runner is the same user, so a shutdown there would stop other jobs' build servers.
  if [[ ${GITHUB_ACTIONS:-} != true ]]; then
    # Under the same bounds as a call, so the shutdown itself leaves nothing behind.
    setsid timeout -k 10 120 dotnet build-server shutdown > /dev/null 2>&1 &
    CHILD=$!
    wait "$CHILD" 2>/dev/null
    kill -KILL -- "-$CHILD" 2>/dev/null
    CHILD=
  fi
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
  local start=$SECONDS
  (cd "$ROOT" && exec setsid timeout -k 10 "$LIMIT" "$@") > "$OUTPUT" 2>&1 &
  CHILD=$!
  wait "$CHILD"
  RC=$?
  # Anything the call left in its group goes now.
  kill -KILL -- "-$CHILD" 2>/dev/null
  CHILD=
  TIMED_OUT=0
  # 137 is also a SIGKILL from outside, such as the out-of-memory killer, before the limit.
  [[ $RC -eq 124 || ($RC -eq 137 && $((SECONDS - start)) -ge $LIMIT) ]] && TIMED_OUT=1
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

# Sets PROJECTS to the solution's project paths, relative to the root.
projects() {
  call_ok 600 dotnet sln "$SOLUTION" list || return 1
  mapfile -t PROJECTS < <(tr '\\' '/' < "$OUTPUT" | grep -E '\.(cs|fs|vb)proj$')
  if [[ ${#PROJECTS[@]} -eq 0 ]]; then
    echo "dotnet sln list named no project in $SOLUTION" > "$CAUSE"
    return 1
  fi
}

# property <project> <name>: sets VALUE to the project's evaluated property.
property() {
  call_ok 600 dotnet msbuild "$ROOT/$1" -nologo "-getProperty:$2" -p:Configuration=Release || return 1
  VALUE=$(tail -n 1 "$OUTPUT")
}

step_portable() {
  projects || return 1
  local proj rid flags built=0
  for proj in "${PROJECTS[@]}"; do
    property "$proj" DomentPlatform || return 1
    [[ ${VALUE,,} == portable ]] || continue
    built=$((built + 1))
    for rid in linux-x64 win-x64; do
      echo "check: portable $(basename "$proj" .csproj) $rid"
      # A NativeAOT executable built for win-x64 would restore runtime.win-x64.Microsoft.DotNet.ILCompiler
      # (docs/dforge/research/2026-11-24-build-probes.md, P5); without it the project still compiles for win-x64.
      flags=()
      [[ $rid == win-x64 ]] && flags=(-p:PublishAot=false)
      call_ok 600 dotnet build "$ROOT/$proj" "${PROPS[@]}" -r "$rid" "${flags[@]}" "${DN_FLAGS[@]}" || return 1
    done
  done
  if [[ $built -eq 0 ]]; then
    echo "no project in $SOLUTION is portable" > "$CAUSE"
    return 1
  fi
}

step_aot() {
  projects || return 1
  local proj name version dir first published=0
  for proj in "${PROJECTS[@]}"; do
    property "$proj" PublishAot || return 1
    [[ ${VALUE,,} == true ]] || continue
    published=$((published + 1))
    property "$proj" AssemblyName || return 1
    name=$VALUE
    property "$proj" VersionPrefix || return 1
    version=$VALUE
    dir=$ROOT/artifacts/publish/$name/linux-x64
    call_ok 1200 dotnet publish "$ROOT/$proj" "${PROPS[@]}" -r linux-x64 -o "$dir" "${DN_FLAGS[@]}" || return 1
    grep -E "$WARNING_RE" "$OUTPUT" | sed -E 's/ \[[^]]*\]$//' | awk '!seen[$0]++' > "$CAUSE"
    [[ -s $CAUSE ]] && return 1

    call 60 "$dir/$name" --version
    if [[ $TIMED_OUT -eq 1 ]]; then
      call_cause
      return 1
    fi
    first=$(head -n 1 "$OUTPUT")
    if [[ $RC -ne 0 ]] || ! grep -Eq "^${name//./\\.} ${version//./\\.}([+-]|\$)" <<<"$first"; then
      echo "$dir/$name --version exited $RC with first line '$first'; expected '$name $version'" > "$CAUSE"
      return 1
    fi
  done
  if [[ $published -eq 0 ]]; then
    echo "no project in $SOLUTION sets PublishAot" > "$CAUSE"
    return 1
  fi
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
