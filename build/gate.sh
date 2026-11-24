#!/usr/bin/env bash
# Third-party gate: build/gate.sh [<tree>]
set -euo pipefail

# Keep the gate from leaving MSBuild nodes, the MSBuild server or the compiler server behind.
export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_USE_MSBUILD_SERVER=0
export UseSharedCompilation=false

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# `dotnet build` appends -consoleloggerparameters:Summary after the caller's -clp:NoSummary
# (SDK 10.0.302), so the console logger is replaced by one that is told NoSummary itself.
DN_FLAGS=(-nologo -tl:off -clp:NoSummary -noConsoleLogger "-logger:ConsoleLogger,Microsoft.Build;NoSummary;Verbosity=minimal")

if [[ $# -gt 1 ]]; then
  echo "usage: build/gate.sh [<tree>]" >&2
  exit 2
fi
TREE_ARG=${1:-$SCRIPT_DIR}
TREE=$(git -C "$TREE_ARG" rev-parse --show-toplevel 2>/dev/null) || {
  echo "gate: $TREE_ARG is not a git work tree" >&2
  exit 2
}
# The tree's global.json, if any, selects the SDK.
cd "$TREE"
REGISTER=$TREE/docs/third-party-exceptions.md

TMP=$(mktemp -d "${TMPDIR:-/tmp}/doment-gate.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
VIOLATIONS=$TMP/violations
: > "$VIOLATIONS"

OUT=
RC=0
dn() {
  OUT=$(timeout 600 dotnet "$@" "${DN_FLAGS[@]}" 2>&1) && RC=0 || RC=$?
}

violation() {
  printf '%s\n' "$1" >> "$VIOLATIONS"
}

# Adds the `error DOMENT` lines of the last dn call, cut to start at `error` and without MSBuild's
# trailing ` [<project path>]`, so the same error from several projects is one line. A call that
# failed without one is a violation of its own, and its error lines go to stderr.
collect() {
  local what=$1 lines
  lines=$(grep -oE 'error DOMENT[0-9]+: .*' <<<"$OUT" | sed -E 's/ \[[^]]*\]$//' || true)
  if [[ -n $lines ]]; then
    printf '%s\n' "$lines" >> "$VIOLATIONS"
  elif [[ $RC -ne 0 ]]; then
    violation "gate: $what failed with exit code $RC"
    grep -E 'error' <<<"$OUT" | head -n 20 >&2 || true
  fi
}

PROJECTS=()
while IFS= read -r -d '' path; do
  [[ $path == tests/build/fixtures/* ]] && continue
  PROJECTS+=("$path")
done < <(git -C "$TREE" ls-files -z -- '*.csproj' '*.fsproj' '*.vbproj')

packages=0
first_importing=
for path in "${PROJECTS[@]}"; do
  project=$TREE/$path
  dn msbuild "$project" -getProperty:DomentRootTargetsImported
  if [[ $RC -ne 0 ]]; then
    collect "evaluating $project"
    continue
  fi
  if [[ $(tr -d '[:space:]' <<<"$OUT") != true ]]; then
    violation "error DOMENT020: $project does not import the root Directory.Build.targets"
    continue
  fi
  [[ -n $first_importing ]] || first_importing=$project
  dn msbuild "$project" -restore -t:DomentThirdPartyCheck -p:FrameworkPinStrict=true
  collect "checking the packages of $project"
  count=$(grep -oE 'DOMENT-PACKAGES: [0-9]+' <<<"$OUT" | head -n 1 | grep -oE '[0-9]+$' || true)
  packages=$((packages + ${count:-0}))
done

if [[ -n $first_importing ]]; then
  dn msbuild "$first_importing" -t:DomentFrameworkCheck -p:FrameworkPinStrict=true
  collect "checking the framework from $first_importing"
fi

BINARIES=$TMP/binaries
: > "$BINARIES"
while IFS= read -r -d '' path; do
  case ${path,,} in
    *.dll | *.exe | *.so | *.dylib | *.a | *.lib | *.sys | *.nupkg | *.snupkg) printf '%s\0' "$path" >> "$BINARIES" ;;
  esac
done < <(git -C "$TREE" ls-files -z)
manifest=
[[ -n $(git -C "$TREE" ls-files -- .config/dotnet-tools.json) ]] && manifest=.config/dotnet-tools.json
dn msbuild "$SCRIPT_DIR/Gate.proj" -t:DomentGateFiles "-p:DomentGateTree=$TREE" "-p:DomentGateRegister=$REGISTER" \
  "-p:DomentGateBinaryList=$BINARIES" "-p:DomentGateToolManifest=$manifest"
collect "checking the tracked files"

branch=$(git -C "$TREE" branch --show-current)
if [[ $branch == master || $branch == main ]]; then
  framework=${DARKRAISE_FRAMEWORK_PATH:-$TREE/external/darkraise-framework}
  framework=${framework%/}
  pin_file=$TREE/build/darkraise-framework.pin
  pin=
  [[ -f $pin_file ]] && pin=$(<"$pin_file")
  # These two lines match the build's own DOMENT006 and DOMENT003 text, so they merge with them.
  if [[ ! $pin =~ ^[0-9a-f]{40}$ ]]; then
    violation "error DOMENT006: $pin_file must hold one full 40-character commit hash"
  elif [[ ! -d $framework ]]; then
    violation "error DOMENT003: darkraise-framework not found at $framework; run tools/framework.sh sync"
  else
    if [[ ${DOMENT_GATE_NO_FETCH:-} != 1 ]]; then
      timeout 120 git -C "$framework" fetch --quiet origin ||
        echo "gate: warning: could not fetch the framework's remote" >&2
    fi
    git -C "$framework" merge-base --is-ancestor "$pin" refs/remotes/origin/master 2>/dev/null ||
      violation "error DOMENT005: pin $pin is not an ancestor of the framework's origin/master"
  fi
fi

awk '!seen[$0]++' "$VIOLATIONS" > "$TMP/unique"
count=$(wc -l < "$TMP/unique")
cat "$TMP/unique"
echo "gate: ${#PROJECTS[@]} projects checked, $packages packages seen, $count violations"
[[ $count -eq 0 ]]
