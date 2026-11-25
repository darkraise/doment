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

eq() { [[ $1 == "$2" ]] || note "expected '$2', got '$1' ($3)"; }
line_is() { grep -Fxq -- "$1" <<<"$OUT" || note "no output line is '$1'; output: $(tail_out)"; }

CI_STUBS=(build/check.sh build/gate.sh tests/build/repository-build.acceptance.sh
  tests/build/repository-build-nativeaot.acceptance.sh tests/build/ci-pushed-branches.acceptance.sh)
CI_TOOLS=(clang jq file ps pgrep)

# ci_setup <name>: a stand-in tree $TREE holding a copy of build/ci.sh and stubs of the scripts it runs, a clean
# stand-in framework at $TREE/fw, a directory of the system tools ci.sh may call ($TREE/sys) and one of stub tools
# ($TREE/stub). A stub script prints its name and the gate variables it sees, and exits with the code in $TREE/rc/<name>.
ci_setup() {
  TREE=$OUTSIDE/$1
  mkdir -p "$TREE/build" "$TREE/tests/build" "$TREE/rc" "$TREE/sys" "$TREE/stub" "$TREE/zlib" "$TREE/temp" "$TREE/fw/src"
  cp "$REPO_ROOT/build/ci.sh" "$TREE/build/ci.sh"
  local s q t
  for s in "${CI_STUBS[@]}"; do
    printf -v q '%q' "$TREE/rc/${s##*/}"
    printf '%s\n' '#!/usr/bin/env bash' \
      "echo \"stub $s DOMENT_GATE_PIN_ON_MASTER=\${DOMENT_GATE_PIN_ON_MASTER-unset} DOMENT_GATE_NO_FETCH=\${DOMENT_GATE_NO_FETCH-unset}\"" \
      "rc=0; [[ -f $q ]] && rc=\$(<$q)" 'exit "$rc"' > "$TREE/$s"
  done
  for t in bash env git df find grep sed awk cat dirname basename readlink mktemp rm ls head wc sort tr cut timeout; do
    ln -s "$(command -v "$t")" "$TREE/sys/$t"
  done
  for t in "${CI_TOOLS[@]}"; do
    printf '#!/bin/sh\nexit 0\n' > "$TREE/stub/$t"
    chmod +x "$TREE/stub/$t"
  done
  : > "$TREE/zlib/zlib.h"
  echo a > "$TREE/fw/src/a.txt"
  git -C "$TREE/fw" init -q
  git -C "$TREE/fw" add -A
  git -C "$TREE/fw" commit -qm init
}
stub_rc() { echo "$2" > "$TREE/rc/$1"; } # stub_rc <script name> <exit code>
CI_ENV=()
ci() { # ci <args...>: runs the stand-in's build/ci.sh with only $TREE/sys and $TREE/stub on PATH, plus CI_ENV
  ENVV=(DOMENT_QA=1 "PATH=$TREE/sys:$TREE/stub" "DOMENT_CI_FRAMEWORK=$TREE/fw" "DOMENT_CI_ZLIB_INCLUDE=$TREE/zlib"
    DOMENT_CI_MIN_FREE_GB=0 "RUNNER_TEMP=$TREE/temp" "${CI_ENV[@]}")
  run "$TREE" 120 bash build/ci.sh "$@"
}

t_A4() {
  ci_setup a4
  local want
  want=$(printf 'ci: suite %s\n' tests/build/repository-build.acceptance.sh 'tests/build/repository-build.acceptance.sh exit=1' \
    tests/build/repository-build-nativeaot.acceptance.sh 'tests/build/repository-build-nativeaot.acceptance.sh exit=0' \
    tests/build/ci-pushed-branches.acceptance.sh 'tests/build/ci-pushed-branches.acceptance.sh exit=0')
  case_ "first suite fails"
  stub_rc repository-build.acceptance.sh 1
  ci acceptance
  rc_is 1
  count_is '^stub tests/build/' 3
  eq "$(grep '^ci: suite ' <<<"$OUT")" "$want" "suite lines in order"
  case_ "every suite passes"
  stub_rc repository-build.acceptance.sh 0
  ci acceptance
  rc_is 0
  count_is '^stub tests/build/' 3
  count_is ' exit=0$' 3
}

t_A6() {
  ci_setup a6
  case_ "DOMENT_CI_PIN_ON_MASTER=1"
  CI_ENV=(DOMENT_CI_PIN_ON_MASTER=1)
  ci check
  CI_ENV=()
  rc_is 0
  line_is 'ci: gate DOMENT_GATE_PIN_ON_MASTER=1'
  line_is 'stub build/gate.sh DOMENT_GATE_PIN_ON_MASTER=1 DOMENT_GATE_NO_FETCH=1'
  line_is 'stub build/check.sh DOMENT_GATE_PIN_ON_MASTER=unset DOMENT_GATE_NO_FETCH=unset'
  case_ "DOMENT_CI_PIN_ON_MASTER unset"
  ci check
  rc_is 0
  line_is 'ci: gate DOMENT_GATE_PIN_ON_MASTER=0'
  line_is 'stub build/gate.sh DOMENT_GATE_PIN_ON_MASTER=0 DOMENT_GATE_NO_FETCH=1'
}

t_A9() {
  ci_setup a9
  case_ "clean framework, every tool present"
  ci verify
  rc_is 0
  line_is 'ci: verify ok'
  case_ "core.sshCommand left in the framework"
  git -C "$TREE/fw" config core.sshCommand 'ssh -i x'
  ci verify
  rc_is 1
  line_is '::error::the deploy key is still configured in the framework checkout (core.sshCommand)'
  hasnt '^ci: verify ok$'
  git -C "$TREE/fw" config --unset core.sshCommand
  case_ "private key under RUNNER_TEMP"
  mkdir -p "$TREE/temp/sub"
  printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nx\n' > "$TREE/temp/sub/key"
  ci verify
  rc_is 1
  line_is "::error::a private key is still present under RUNNER_TEMP: $TREE/temp/sub/key"
}

t_A11() {
  ci_setup a11
  local t pkg
  for t in "${CI_TOOLS[@]}" zlib.h; do
    case $t in ps | pgrep) pkg=procps ;; zlib.h) pkg=zlib1g-dev ;; *) pkg=$t ;; esac
    case_ "$t missing"
    if [[ $t == zlib.h ]]; then rm "$TREE/zlib/zlib.h"; else mv "$TREE/stub/$t" "$TREE/$t.off"; fi
    ci verify
    rc_is 1
    line_is "::error::$pkg is missing on the runner; add it to the ghr pool's managed packages"
    count_is '^::error::' 1
    if [[ $t == zlib.h ]]; then : > "$TREE/zlib/zlib.h"; else mv "$TREE/$t.off" "$TREE/stub/$t"; fi
  done
}

t_A18() {
  ci_setup a18
  case_ "untracked file in the framework"
  echo x > "$TREE/fw/src/new.txt"
  ci verify
  rc_is 1
  line_is '::error::the framework checkout is not clean: src/new.txt'
  rm "$TREE/fw/src/new.txt"
  case_ "untracked file under obj only"
  mkdir -p "$TREE/fw/src/obj"
  echo x > "$TREE/fw/src/obj/x.txt"
  ci verify
  rc_is 0
  line_is 'ci: verify ok'
  case_ "too little free space"
  CI_ENV=(DOMENT_CI_MIN_FREE_GB=100000)
  ci verify
  CI_ENV=()
  rc_is 1
  has '^::error::workspace has [0-9]+ GB free at .*, needs 100000 GB$'
  case_ "LFS objects downloaded"
  mkdir -p "$TREE/fw/.git/lfs/objects/aa/bb"
  echo x > "$TREE/fw/.git/lfs/objects/aa/bb/x"
  ci verify
  rc_is 1
  line_is '::error::LFS objects were downloaded into the framework checkout'
  rm -rf "$TREE/fw/.git/lfs"
  case_ "framework checkout missing"
  CI_ENV=("DOMENT_CI_FRAMEWORK=$TREE/absent")
  ci verify
  CI_ENV=()
  rc_is 1
  line_is "::error::cannot read the framework checkout's status at $TREE/absent"
}

t_A19() {
  ci_setup a19
  case_ "check.sh fails"
  stub_rc check.sh 1
  ci check
  rc_is 1
  count_is '^stub build/gate.sh ' 1
  case_ "gate fails"
  stub_rc check.sh 0
  stub_rc gate.sh 1
  ci check
  rc_is 1
  case_ "both pass"
  stub_rc gate.sh 0
  ci check
  rc_is 0
}

t_usage() {
  ci_setup usage
  local args
  for args in '' nope 'check extra'; do
    case_ "arguments '$args'"
    ENVV=(DOMENT_QA=1)
    # shellcheck disable=SC2086 # each row is a word list
    run "$TREE" 60 bash -c 'bash build/ci.sh "$@" 2>&1 > /dev/null' _ $args
    rc_is 2
    line_is 'usage: build/ci.sh verify|check|acceptance'
  done
}

# ---------------------------------------------------------------------------

declare -A DESC=(
  [A4]="acceptance runs every suite and fails on any" [A6]="check passes the pin switch to the gate only"
  [A9]="verify finds a leftover deploy key" [A11]="verify names a missing runner package"
  [A18]="verify checks framework cleanliness, free space and LFS" [A19]="check runs the gate after a failed check.sh"
  [A25]="check.sh skips the build-server shutdown on CI" [usage]="ci.sh usage errors"
)

RESULT_FAIL=0
RESULT_PASS=0
for fn in $(declare -F | awk '{print $3}' | grep -E '^t_A[0-9]+$' | sort -t A -k2 -n) t_usage; do
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
