#!/usr/bin/env bash
# Third-party gate: build/gate.sh [<tree>]
set -euo pipefail

# Keep the gate from leaving MSBuild nodes, the MSBuild server or the compiler server behind.
export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_USE_MSBUILD_SERVER=0
export UseSharedCompilation=false

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# `dotnet build` appends -consoleloggerparameters:Summary after the caller's -clp:NoSummary
# (SDK 10.0.302 and 10.0.404), so the console logger is replaced by one that is told NoSummary itself.
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
# MSBuild gives these characters a meaning of its own in paths; `&` and `<` also break the inline
# tasks, whose RoslynCodeTaskFactory body is re-parsed as XML after the path is expanded into it.
for c in ';' '%' '$' '@' '"' ',' '&' '<'; do
  if [[ $TREE == *"$c"* ]]; then
    echo "gate: $TREE contains '$c', which MSBuild cannot take in a path" >&2
    exit 2
  fi
done
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

die() {
  echo "gate: $*" >&2
  exit 1
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

git -C "$TREE" ls-files -z -- '*.csproj' '*.fsproj' '*.vbproj' > "$TMP/projects" || die "git ls-files failed in $TREE"
PROJECTS=()
while IFS= read -r -d '' path; do
  [[ $path == tests/build/fixtures/* ]] && continue
  PROJECTS+=("$path")
done < "$TMP/projects"

packages=0
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
  # The register is passed globally so that a project cannot point its check at another file.
  dn msbuild "$project" -restore -t:DomentThirdPartyCheck -p:FrameworkPinStrict=true "-p:DomentRegisterFile=$REGISTER"
  collect "checking the packages of $project"
  count=$(grep -oE 'DOMENT-PACKAGES: [0-9]+' <<<"$OUT" | head -n 1 | grep -oE '[0-9]+$' || true)
  packages=$((packages + ${count:-0}))
done

# The framework check is the same for the whole tree, and runs even when the tree has no project.
FRAMEWORK_PROJECT=$TMP/framework-check.proj
# The quoted replacements keep bash 5.2's patsub_replacement from reading `&` as the match.
tree_xml=${TREE//'&'/'&amp;'}
tree_xml=${tree_xml//'<'/'&lt;'}
tree_xml=${tree_xml//'>'/'&gt;'}
tree_xml=${tree_xml//'"'/'&quot;'}
tree_xml=${tree_xml//\'/'&apos;'}
printf '<Project>\n  <Import Project="%s/Directory.Build.props" />\n  <Import Project="%s/Directory.Build.targets" />\n</Project>\n' \
  "$tree_xml" "$tree_xml" > "$FRAMEWORK_PROJECT"
dn msbuild "$FRAMEWORK_PROJECT" -t:DomentFrameworkCheck -p:FrameworkPinStrict=true
collect "checking the framework"

git -C "$TREE" ls-files -z > "$TMP/files" || die "git ls-files failed in $TREE"
BINARIES=$TMP/binaries
: > "$BINARIES"
while IFS= read -r -d '' path; do
  case ${path,,} in
    *.dll | *.exe | *.so | *.dylib | *.a | *.lib | *.sys | *.nupkg | *.snupkg) printf '%s\0' "$path" >> "$BINARIES" ;;
  esac
done < "$TMP/files"
git -C "$TREE" ls-files -- .config/dotnet-tools.json > "$TMP/manifest" || die "git ls-files failed in $TREE"
manifest=
[[ -s $TMP/manifest ]] && manifest=.config/dotnet-tools.json
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
  pin=${pin%$'\r'}
  if [[ ! $pin =~ ^[0-9a-f]{40}$ || ! -d $framework ]]; then
    : # The framework check above reports the malformed pin or the missing directory.
  elif ! prefix=$(git -C "$framework" rev-parse --show-prefix 2>/dev/null) || [[ -n $prefix ]]; then
    : # Not a git checkout of its own: the framework check reports DOMENT002, and git here would read the enclosing repository.
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
