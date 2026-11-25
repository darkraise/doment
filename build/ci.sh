#!/usr/bin/env bash
# CI entry points: build/ci.sh verify|check|acceptance. The workflow runs every step after the framework checkout here.
set -uo pipefail

# The tree that holds this script, found without git, as build/check.sh finds it.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

usage() {
  echo "usage: build/ci.sh verify|check|acceptance" >&2
  exit 2
}
[[ $# -eq 1 ]] || usage

verify() {
  local fw=${DOMENT_CI_FRAMEWORK:-$ROOT/external/darkraise-framework}
  local zlib=${DOMENT_CI_ZLIB_INCLUDE:-/usr/include}
  local min_gb=${DOMENT_CI_MIN_FREE_GB:-20}
  local failed=0 path

  if [[ -n $(git -C "$fw" config --get core.sshCommand 2>/dev/null) ]]; then
    echo "::error::the deploy key is still configured in the framework checkout (core.sshCommand)"
    failed=1
  fi

  if [[ -n ${RUNNER_TEMP:-} ]]; then
    while IFS= read -r path; do
      [[ -f $path && ! -L $path ]] || continue
      echo "::error::a private key is still present under RUNNER_TEMP: $path"
      failed=1
    done < <(grep -rlF -D skip -- 'PRIVATE KEY-----' "$RUNNER_TEMP" 2>/dev/null)
  fi

  if [[ -d $fw/.git/lfs/objects && -n $(find "$fw/.git/lfs/objects" -type f -print -quit) ]]; then
    echo "::error::LFS objects were downloaded into the framework checkout"
    failed=1
  fi

  local records=()
  mapfile -d '' records < <(git -C "$fw" status --porcelain=v1 -z --ignored=matching --untracked-files=all 2>/dev/null)
  if ! wait "$!"; then
    echo "::error::cannot read the framework checkout's status at $fw"
    failed=1
  else
    # Build output and IDE folders are allowed, as in build/Doment.BuildChecks.cs. A rename's or copy's second record
    # (its source path) carries no status code and is skipped.
    local record code skip_next=0 part parts allowed dirty=
    for record in "${records[@]}"; do
      if [[ $skip_next == 1 ]]; then
        skip_next=0
        continue
      fi
      code=${record:0:2}
      path=${record:3}
      [[ $code == R* || $code == C* ]] && skip_next=1
      allowed=0
      IFS=/ read -ra parts <<<"$path"
      for part in "${parts[@]}"; do
        case $part in bin | obj | .vs | .idea) allowed=1 ;; esac
      done
      if [[ $allowed == 0 ]]; then
        dirty=$path
        break
      fi
    done
    if [[ -n $dirty ]]; then
      echo "::error::the framework checkout is not clean: $dirty"
      failed=1
    fi
  fi

  local tool pkg
  for tool in clang:clang jq:jq file:file ps:procps pgrep:procps; do
    pkg=${tool#*:}
    tool=${tool%%:*}
    if ! command -v "$tool" > /dev/null 2>&1; then
      echo "::error::$pkg is missing on the runner; add it to the ghr pool's managed packages"
      failed=1
    fi
  done
  if [[ ! -f $zlib/zlib.h ]]; then
    echo "::error::zlib1g-dev is missing on the runner; add it to the ghr pool's managed packages"
    failed=1
  fi

  local free_gb
  free_gb=$(df -Pk "$ROOT" | awk 'NR == 2 { print int($4 / 1048576) }')
  if [[ ! $free_gb =~ ^[0-9]+$ ]]; then
    echo "::error::cannot read the free space at $ROOT"
    failed=1
  elif ((free_gb < min_gb)); then
    echo "::error::workspace has $free_gb GB free at $ROOT, needs $min_gb GB"
    failed=1
  fi

  [[ $failed == 0 ]] || return 1
  echo "ci: verify ok"
}

check() {
  local rc=0 pin=0
  bash "$ROOT/build/check.sh" || rc=1
  [[ ${DOMENT_CI_PIN_ON_MASTER:-} == 1 ]] && pin=1
  echo "ci: gate DOMENT_GATE_PIN_ON_MASTER=$pin"
  DOMENT_GATE_NO_FETCH=1 DOMENT_GATE_PIN_ON_MASTER=$pin bash "$ROOT/build/gate.sh" || rc=1
  return "$rc"
}

acceptance() {
  local rc=0 suite suite_rc
  for suite in tests/build/repository-build.acceptance.sh tests/build/repository-build-nativeaot.acceptance.sh \
    tests/build/ci-pushed-branches.acceptance.sh; do
    echo "ci: suite $suite"
    bash "$ROOT/$suite" && suite_rc=0 || suite_rc=$?
    echo "ci: suite $suite exit=$suite_rc"
    [[ $suite_rc == 0 ]] || rc=1
  done
  return "$rc"
}

case $1 in
  verify) verify ;;
  check) check ;;
  acceptance) acceptance ;;
  *) usage ;;
esac
