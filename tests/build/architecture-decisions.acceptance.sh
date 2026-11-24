#!/usr/bin/env bash
# Acceptance tests A10-A26 of the architecture-decisions spec.
# Usage: bash tests/build/architecture-decisions.acceptance.sh [<extended regex on the test name>]
# Every test builds stand-in framework and doment repositories under one temporary directory and restores only
# from a folder feed of tiny packages packed here, so nothing touches a real framework checkout or the network.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
FILTER=${1:-}

export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_USE_MSBUILD_SERVER=0
export UseSharedCompilation=false
export DOTNET_NOLOGO=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export NuGetAudit=false
unset DARKRAISE_FRAMEWORK_PATH DARKRAISE_FRAMEWORK_REPO FrameworkPinStrict DOMENT_GATE_NO_FETCH

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=acceptance GIT_AUTHOR_EMAIL=acceptance@doment.invalid
export GIT_COMMITTER_NAME=acceptance GIT_COMMITTER_EMAIL=acceptance@doment.invalid
export GIT_LFS_SKIP_SMUDGE=1

T=$(mktemp -d "${TMPDIR:-/tmp}/doment-acceptance.XXXXXX")
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
trap 'exit 143' TERM INT
FEED=$T/feed
PKGS=$T/pkgs
SRC=$T/packsrc
mkdir -p "$FEED" "$PKGS" "$SRC"
export NUGET_PACKAGES=$PKGS NUGET_HTTP_CACHE_PATH=$T/httpcache

OUT=
RC=0
CASE=
FAILS=()
ENVV=()
SEQ=0

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
# A line with a message of any code, for the tests that do not pin the code.
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
DN_FLAGS=(-nologo -tl:off -clp:NoSummary -noConsoleLogger "-logger:ConsoleLogger,Microsoft.Build;NoSummary;Verbosity=minimal"
  "-p:RestoreSources=$FEED" "-p:RestorePackagesPath=$PKGS")

dn() { # dn <dir> <dotnet args...>; ENVV holds NAME=value pairs for this call
  local dir=$1
  shift
  OUT=$(cd "$dir" && env "${ENVV[@]}" timeout 600 dotnet "$@" "${DN_FLAGS[@]}" 2>&1) && RC=0 || RC=$?
}
build() { dn "$1" build "${@:2}"; }

fw() { # fw <doment-dir> <framework-clone> <verb>
  OUT=$(cd "$1" && env "${ENVV[@]}" DARKRAISE_FRAMEWORK_REPO="$2" timeout 300 bash tools/framework.sh "${@:3}" 2>&1) && RC=0 || RC=$?
}
fw_noenv() { # fw_noenv <doment-dir> <verb> : no DARKRAISE_FRAMEWORK_REPO
  OUT=$(cd "$1" && env "${ENVV[@]}" timeout 300 bash tools/framework.sh "${@:2}" 2>&1) && RC=0 || RC=$?
}

gate() { # gate <tree>
  OUT=$(cd "$T" && env "${ENVV[@]}" DOMENT_GATE_NO_FETCH=1 timeout 900 bash "$REPO_ROOT/build/gate.sh" "$1" 2>&1) && RC=0 || RC=$?
}

# ---------------------------------------------------------------------------
# Stand-in repositories

write_file() {
  mkdir -p "$(dirname "$1")"
  cat > "$1"
}

new_dir() { SEQ=$((SEQ + 1)); local d=$T/t$SEQ-$1; mkdir -p "$d"; echo "$d"; }

# mk_framework <dir> [extra csproj content for Darkraise.csproj]: a stand-in framework clone with an origin; prints nothing.
mk_framework() {
  local dir=$1 extra=${2:-}
  git init -q --bare "$dir.origin.git" || die "bare"
  git init -q -b master "$dir" || die "init framework"
  echo '<Project />' > "$dir/Directory.Build.props"
  printf '%s\n' '*.user' 'bin/' 'obj/' '.vs/' '.idea/' > "$dir/.gitignore"
  local name tf
  for name in Darkraise Darkraise.Api Darkraise.Win32UI Darkraise.Win32UI.Generators; do
    tf=net10.0
    [[ $name == Darkraise.Win32UI ]] && tf=net10.0-windows
    [[ $name == Darkraise.Win32UI.Generators ]] && tf=netstandard2.0
    write_file "$dir/src/$name/$name.csproj" <<XML
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>$tf</TargetFramework>
$([[ $tf == net10.0-windows ]] && echo '    <EnableWindowsTargeting>true</EnableWindowsTargeting>')
  </PropertyGroup>
  $([[ $name == Darkraise ]] && echo "$extra")
</Project>
XML
  done
  write_file "$dir/src/Darkraise/Class1.cs" <<'CS'
namespace Darkraise;

public static class Class1
{
    public static string Name => "one";
}
CS
  git -C "$dir" add -A && git -C "$dir" commit -qm "framework one" || die "commit framework"
  git -C "$dir" remote add origin "$dir.origin.git"
  git -C "$dir" push -q origin master || die "push framework"
  git -C "$dir" fetch -q origin
}

# fw_commit <clone> <tag> [push]: a new framework commit that changes Class1.cs; prints its hash.
fw_commit() {
  sed -i "s/\"[a-z0-9]*\"/\"$2\"/" "$1/src/Darkraise/Class1.cs"
  git -C "$1" commit -qam "framework $2" || die "fw_commit"
  [[ ${3:-} == push ]] && git -C "$1" push -q origin master
  git -C "$1" rev-parse HEAD
}
head_of() { git -C "$1" rev-parse HEAD; }

# fw_worktree <clone> <path> <commit>
fw_worktree() { git -C "$1" worktree add -q --detach "$2" "$3" >/dev/null 2>&1 || die "worktree add $2"; }

# register_text: the fixture register in the register's own layout.
register_text() {
  cat <<'MD'
# Third-party exception register (acceptance fixture)

## Exceptions

| ID | Component | Packages or files | Used for | Reason | Licence | Behind | Replacement | Approved |
|---|---|---|---|---|---|---|---|---|
| X1 | Fixture codec | `Fx.Codec`, `Fx.Codec.*`, `Fx.Outer`, `vendor/listed.sys` | Decoding test media | No first-party codec yet | MIT | `IVideoDecoder` | First-party codec | 2026-11-24 |
| X2 | Fixture driver | - | Virtual displays | No first-party driver | BSD-3-Clause | `IVirtualDisplay` | Own driver | 2026-11-24 |

## Build-and-test-only tools

| ID | Component | Packages or tool | Used for | Licence | Approved |
|---|---|---|---|---|---|
| B1 | Fixture test kit | `Fx.TestKit`, `Fx.TestKit.*` | Unit tests | MIT | 2026-11-24 |
| B2 | Fixture formatter | `fx-format` | Formatting | MIT | 2026-11-24 |

## Platform packages

| Package | Added by | First seen |
|---|---|---|
| `Microsoft.DotNet.ILCompiler` | .NET SDK | 2026-11-24 |
| `runtime.linux-x64.Microsoft.DotNet.ILCompiler` | .NET SDK | 2026-11-24 |
| `Microsoft.NET.ILLink.Tasks` | .NET SDK | 2026-11-24 |
MD
}

# Register edits, all on the file given.
blank_cell() { # blank_cell <file> <row id> <1-based column>
  awk -F'|' -v OFS='|' -v id="$2" -v col="$3" '$2 ~ "^ *" id " *$" { $(col + 1) = "  " } { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}
drop_column() { # drop_column <file> <section heading> <1-based column>
  awk -F'|' -v OFS='|' -v sec="$2" -v col="$3" '
    /^## / { insec = ($0 == "## " sec) }
    insec && /^\|/ { out = ""; for (i = 2; i < NF; i++) if (i != col + 1) out = out OFS $i; print out OFS; next }
    { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}
drop_section() { # drop_section <file> <section heading>
  awk -v sec="$2" '/^## / { skip = ($0 == "## " sec) } !skip { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}
dup_row() { # dup_row <file> <row id>: the row appears twice
  awk -F'|' -v id="$2" '{ print } $2 ~ "^ *" id " *$" { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}

# mk_doment <dir> <framework-clone> <pin> [real]: a stand-in doment repository built from this repository's own build
# files, with the fixture register (or the real one with "real"), one project src/App and a nuget.config.
mk_doment() {
  local dir=$1 fwclone=$2 pin=$3 mode=${4:-fixture} path
  git init -q -b master "$dir" || die "init doment"
  while IFS= read -r path; do
    [[ -f $REPO_ROOT/$path ]] || continue
    mkdir -p "$dir/$(dirname "$path")"
    cp "$REPO_ROOT/$path" "$dir/$path"
  done < <(git -C "$REPO_ROOT" ls-files -- Directory.Build.props Directory.Build.targets .gitignore build external tools docs/third-party-exceptions.md)
  rm -f "$dir/build/darkraise-framework.pin"
  echo "$pin" > "$dir/build/darkraise-framework.pin"
  if [[ $mode == fixture ]]; then register_text > "$dir/docs/third-party-exceptions.md"; fi
  write_file "$dir/nuget.config" <<XML
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="feed" value="$FEED" />
  </packageSources>
  <config>
    <add key="globalPackagesFolder" value="$PKGS" />
  </config>
</configuration>
XML
  mk_project "$dir" src/App net10.0 "" '<ProjectReference Include="$(DarkraiseFrameworkPath)/src/Darkraise/Darkraise.csproj" />'
  git -C "$dir" add -A && git -C "$dir" commit -qm "doment stand-in" || die "commit doment"
}

# mk_project <doment-dir> <relative dir> <target framework> [<package spec>...|""] <item lines>: writes a project.
# Package spec "Id:Version" per word in the 4th argument.
mk_project() {
  local dir=$1 rel=$2 tf=$3 pkgs=$4 items=$5 name p
  name=$(basename "$rel")
  {
    echo '<Project Sdk="Microsoft.NET.Sdk">'
    echo "  <PropertyGroup><TargetFramework>$tf</TargetFramework>$([[ $tf == net10.0-windows ]] && echo '<EnableWindowsTargeting>true</EnableWindowsTargeting>')</PropertyGroup>"
    echo '  <ItemGroup>'
    for p in $pkgs; do echo "    <PackageReference Include=\"${p%%:*}\" Version=\"${p##*:}\" />"; done
    [[ -n $items ]] && echo "    $items"
    echo '  </ItemGroup>'
    echo '</Project>'
  } | write_file "$dir/$rel/$name.csproj"
  printf 'namespace %s;\npublic static class Marker { public static int Value => 1; }\n' "$name" > "$dir/$rel/Marker.cs"
}

commit_all() { git -C "$1" add -A && git -C "$1" commit -qm "${2:-change}" || die "commit_all $1"; }

FRAMEWORK_REF='<ProjectReference Include="$(DarkraiseFrameworkPath)/src/Darkraise/Darkraise.csproj" />'

# new_world <name> [framework extra] [real]: a framework clone with commit one, a doment stand-in pinned to it
# and a clean framework worktree at the pin in the doment checkout. Sets FW, D, C1, W.
new_world() {
  local base
  base=$(new_dir "$1")
  FW=$base/framework
  D=$base/doment
  mk_framework "$FW" "${2:-}"
  C1=$(head_of "$FW")
  mk_doment "$D" "$FW" "$C1" "${3:-fixture}"
  W=$D/external/darkraise-framework
  fw_worktree "$FW" "$W" "$C1"
}

# ensure_feed: packs the tiny fixture packages once.
FEED_READY=0
pack_pkg() { # pack_pkg <id> <version> [dep id:version]
  local id=$1 ver=$2 dep=${3:-} dir=$SRC/$1 out
  mkdir -p "$dir"
  {
    echo '<Project Sdk="Microsoft.NET.Sdk">'
    echo "  <PropertyGroup><TargetFramework>net10.0</TargetFramework><PackageId>$id</PackageId><Version>$ver</Version></PropertyGroup>"
    [[ -n $dep ]] && echo "  <ItemGroup><PackageReference Include=\"${dep%%:*}\" Version=\"${dep##*:}\" /></ItemGroup>"
    echo '</Project>'
  } > "$dir/$id.csproj"
  printf 'namespace %s;\npublic static class Marker { public static int Value => 1; }\n' "${id//./_}" > "$dir/Marker.cs"
  out=$(cd "$dir" && timeout 600 dotnet pack -c Release -o "$FEED" "-p:RestoreSources=$FEED" "-p:RestorePackagesPath=$PKGS" -nologo -tl:off 2>&1) || {
    echo "$out" | tail -n 15 >&2
    die "pack $id"
  }
}
ensure_feed() {
  [[ $FEED_READY -eq 0 ]] || return 0
  pack_pkg Fx.Unlisted 2.5.0
  pack_pkg Fx.Unlisted2 1.1.0
  pack_pkg Fx.Codec.Inner 1.0.0
  pack_pkg Fx.Codec 1.2.3 Fx.Codec.Inner:1.0.0
  pack_pkg Fx.Outer 1.0.0 Fx.Unlisted:2.5.0
  pack_pkg Fx.TestKit 3.1.0
  FEED_READY=1
}

# ---------------------------------------------------------------------------
# A10

t_A10() {
  ensure_feed
  new_world a10
  local d1=$D w1=$W c1=$C1 c2 d2 w2
  c2=$(fw_commit "$FW" two push)
  d2=$(dirname "$d1")/doment-linked
  git -C "$d1" worktree add -q -b linked "$d2" HEAD || die "linked doment worktree"
  echo "$c2" > "$d2/build/darkraise-framework.pin"
  commit_all "$d2" "pin two"
  w2=$d2/external/darkraise-framework
  fw_worktree "$FW" "$w2" "$c2"

  case_ "primary checkout, no property"
  build "$d1" src/App/App.csproj
  rc_is 0
  hasnt '(warning|error) DOMENT'
  case_ "linked worktree, no property"
  build "$d2" src/App/App.csproj
  rc_is 0
  hasnt '(warning|error) DOMENT'

  case_ "each checkout resolves its own framework worktree"
  dn "$d1" msbuild src/App/App.csproj -getProperty:DarkraiseFrameworkPath
  eq "$(tr -d '[:space:]' <<<"$OUT" | sed 's#/$##')" "$w1" "primary checkout's framework path"
  dn "$d2" msbuild src/App/App.csproj -getProperty:DarkraiseFrameworkPath
  eq "$(tr -d '[:space:]' <<<"$OUT" | sed 's#/$##')" "$w2" "linked worktree's framework path"

  case_ "each build used its own framework sources"
  local l1 l2 a1 a2
  l1=$(find "$w1/src/Darkraise/bin" -name Darkraise.dll 2>/dev/null | head -n 1)
  l2=$(find "$w2/src/Darkraise/bin" -name Darkraise.dll 2>/dev/null | head -n 1)
  a1=$(find "$d1/src/App/bin" -name Darkraise.dll 2>/dev/null | head -n 1)
  a2=$(find "$d2/src/App/bin" -name Darkraise.dll 2>/dev/null | head -n 1)
  [[ -n $l1 && -n $l2 && -n $a1 && -n $a2 ]] || note "a Darkraise.dll is missing: $l1 | $l2 | $a1 | $a2"
  if [[ -n $l1 && -n $a1 ]]; then cmp -s "$l1" "$a1" || note "the primary build did not use its own framework worktree"; fi
  if [[ -n $l2 && -n $a2 ]]; then cmp -s "$l2" "$a2" || note "the linked build did not use its own framework worktree"; fi
  if [[ -n $l1 && -n $l2 ]]; then cmp -s "$l1" "$l2" && note "the two framework builds are identical, so the pins did not differ"; fi

  case_ "two checkouts with different pins build strict (primary)"
  build "$d1" src/App/App.csproj -p:FrameworkPinStrict=true
  rc_is 0
  hasnt 'DOMENT00[12]'
  case_ "two checkouts with different pins build strict (linked)"
  build "$d2" src/App/App.csproj -p:FrameworkPinStrict=true
  rc_is 0
  hasnt 'DOMENT00[12]'
}

# ---------------------------------------------------------------------------
# A11

t_A11() {
  new_world a11
  git -C "$FW" worktree remove --force "$W"
  local expected=$W
  case_ "default location missing"
  build "$D" src/App/App.csproj
  rc_fails
  count_is ': error ' 1
  error_line_has "$expected" 'tools/framework\.sh sync'
  check "App compiled although the framework is missing" bash -c "! find '$D/src/App/bin' '$D/src/App/obj' -name App.dll 2>/dev/null | grep -q ."

  case_ "override path missing"
  local missing=$T/does-not-exist/darkraise
  ENVV=("DARKRAISE_FRAMEWORK_PATH=$missing")
  build "$D" src/App/App.csproj
  ENVV=()
  rc_fails
  count_is ': error ' 1
  error_line_has "$missing" 'tools/framework\.sh sync'
}

# ---------------------------------------------------------------------------
# A12

t_A12() {
  new_world a12
  local c2 c3 before after
  git -C "$FW" worktree remove --force "$W"
  c2=$(fw_commit "$FW" two push)
  c3=$(fw_commit "$FW" three push)
  git -C "$FW" checkout -q master
  before=$(git -C "$FW" for-each-ref --format='%(refname) %(objectname)')

  case_ "sync creates the worktree at the pin"
  fw "$D" "$FW" sync
  rc_is 0
  [[ -d $W ]] || note "no worktree at $W"
  eq "$(head_of "$W")" "$C1" "worktree HEAD after create"
  check "worktree is not listed by the framework repository" bash -c "git -C '$FW' worktree list --porcelain | grep -Fxq 'worktree $W'"
  case_ "build strict after create"
  build "$D" src/App/App.csproj -p:FrameworkPinStrict=true
  rc_is 0
  hasnt '(warning|error) DOMENT'

  case_ "sync moves a clean worktree to a new pin"
  echo "$c2" > "$D/build/darkraise-framework.pin"
  fw "$D" "$FW" sync
  rc_is 0
  eq "$(head_of "$W")" "$c2" "worktree HEAD after move"
  build "$D" src/App/App.csproj -p:FrameworkPinStrict=true
  rc_is 0
  hasnt '(warning|error) DOMENT'

  case_ "sync moves a clean worktree that holds build output"
  echo "$c3" > "$D/build/darkraise-framework.pin"
  fw "$D" "$FW" sync
  rc_is 0
  eq "$(head_of "$W")" "$c3" "worktree HEAD after second move"
  build "$D" src/App/App.csproj -p:FrameworkPinStrict=true
  rc_is 0
  hasnt '(warning|error) DOMENT'

  case_ "no branch of the framework repository moved"
  after=$(git -C "$FW" for-each-ref --format='%(refname) %(objectname)')
  eq "$after" "$before" "refs of the framework repository"
}

# ---------------------------------------------------------------------------
# A13

# A13 case runner: <label> <setup command> ; the worktree is reset first and the pin is C1.
reset_fw() {
  git -C "$W" reset -q --hard "$C1" 2>/dev/null
  git -C "$W" checkout -q --detach "$C1" 2>/dev/null
  git -C "$W" clean -fdq
  find "$W" -name '*.user' -not -path '*/obj/*' -delete 2>/dev/null
  rm -rf "$W/.vs" "$W/.idea" "$W/src/Darkraise/.vs" "$W/src/Darkraise/.idea"
}

dirty_case() { # dirty_case <label> <expected path regex or ""> <setup function>
  case_ "$1"
  reset_fw
  "$3"
  build "$D" src/App/App.csproj
  rc_is 0
  count_is 'warning DOMENT001' 1
  local msg
  msg=$(diag_msgs warning DOMENT001 | head -n 1)
  grep -Fq "${C1:0:7}" <<<"$msg" || note "message does not name the pinned commit ${C1:0:7}: $msg"
  if [[ -n $2 ]]; then grep -Eq -- "$2" <<<"$msg" || note "message does not name the path /$2/: $msg"; fi
  if [[ -n ${EXPECT_ACTUAL:-} ]]; then grep -Fq "${EXPECT_ACTUAL:0:7}" <<<"$msg" || note "message does not name the actual commit ${EXPECT_ACTUAL:0:7}: $msg"; fi
  local ordinary_msg=$msg
  build "$D" src/App/App.csproj -p:FrameworkPinStrict=true
  rc_fails
  count_is 'error DOMENT001' 1
  msg=$(diag_msgs error DOMENT001 | head -n 1)
  eq "$msg" "$ordinary_msg" "the strict error carries the message of the warning"
}

a13_head_moved() { git -C "$W" checkout -q --detach "$C2"; EXPECT_ACTUAL=$C2; }
a13_modified() { echo '// changed' >> "$W/src/Darkraise/Class1.cs"; }
a13_staged() { echo 'staged' > "$W/staged-file.txt"; git -C "$W" add staged-file.txt; }
a13_staged_change() { echo '// staged change' >> "$W/src/Darkraise/Class1.cs"; git -C "$W" add src/Darkraise/Class1.cs; }
a13_untracked_src() { echo '// new' > "$W/src/Darkraise/Extra.cs"; }
a13_untracked_deep() { mkdir -p "$W/docs/deeper/still"; echo x > "$W/docs/deeper/still/notes.txt"; }
a13_untracked_root() { echo x > "$W/scratch-note.txt"; }
a13_ignored_user() { echo '<Project />' > "$W/src/Darkraise/Darkraise.csproj.user"; }
a13_ignored_other() { mkdir -p "$W/plans"; echo x > "$W/plans/scratch.user"; }

t_A13() {
  new_world a13
  C2=$(fw_commit "$FW" two push)
  git -C "$FW" checkout -q master
  # A first build leaves bin and obj in the worktree: they must not count.
  build "$D" src/App/App.csproj -p:FrameworkPinStrict=true
  case_ "bin and obj output are not offences"
  rc_is 0
  hasnt '(warning|error) DOMENT'
  case_ "files in .vs and .idea directories are not offences"
  mkdir -p "$W/.vs" "$W/.idea" "$W/src/Darkraise/.vs" "$W/src/Darkraise/obj/Debug/inner"
  echo x > "$W/.vs/state"; echo x > "$W/.idea/workspace.xml"; echo x > "$W/src/Darkraise/.vs/state"; echo x > "$W/src/Darkraise/obj/Debug/inner/x"
  build "$D" src/App/App.csproj -p:FrameworkPinStrict=true
  rc_is 0
  hasnt '(warning|error) DOMENT'

  EXPECT_ACTUAL=
  dirty_case "commit differs from the pin" "" a13_head_moved
  EXPECT_ACTUAL=
  dirty_case "modified tracked file" 'src/Darkraise/Class1\.cs' a13_modified
  dirty_case "staged new file" 'staged-file\.txt' a13_staged
  dirty_case "staged change" 'src/Darkraise/Class1\.cs' a13_staged_change
  dirty_case "untracked source file" 'src/Darkraise/Extra\.cs' a13_untracked_src
  dirty_case "untracked file in a deep directory" 'docs/deeper' a13_untracked_deep
  dirty_case "untracked file at the root" 'scratch-note\.txt' a13_untracked_root
  dirty_case "ignored csproj.user next to a project" 'Darkraise\.csproj\.user' a13_ignored_user
  dirty_case "ignored file in an ordinary directory" 'plans/scratch\.user|scratch\.user' a13_ignored_other
  reset_fw
}

# ---------------------------------------------------------------------------
# A14

t_A14() {
  new_world a14
  local alt=$(dirname "$D")/alt-framework
  fw_worktree "$FW" "$alt" "$C1"

  case_ "relative property, path does not exist"
  build "$D" src/App/App.csproj -p:DarkraiseFrameworkPath=rel/fw
  rc_fails
  error_line_has 'absolute'
  case_ "relative property, path exists relative to the working directory"
  build "$D" src/App/App.csproj -p:DarkraiseFrameworkPath=external/darkraise-framework
  rc_fails
  error_line_has 'absolute'
  case_ "relative property with a trailing slash"
  build "$D" src/App/App.csproj -p:DarkraiseFrameworkPath=external/darkraise-framework/
  rc_fails
  error_line_has 'absolute'
  case_ "relative environment variable, path does not exist"
  ENVV=("DARKRAISE_FRAMEWORK_PATH=rel/fw")
  build "$D" src/App/App.csproj
  ENVV=()
  rc_fails
  error_line_has 'absolute'
  case_ "relative environment variable, path exists relative to the working directory"
  ENVV=("DARKRAISE_FRAMEWORK_PATH=external/darkraise-framework")
  build "$D" src/App/App.csproj
  ENVV=()
  rc_fails
  error_line_has 'absolute'
  case_ "dot-relative environment variable"
  ENVV=("DARKRAISE_FRAMEWORK_PATH=./external/darkraise-framework")
  build "$D" src/App/App.csproj
  ENVV=()
  rc_fails
  error_line_has 'absolute'

  case_ "control: absolute environment variable builds against that path"
  ENVV=("DARKRAISE_FRAMEWORK_PATH=$alt")
  build "$D" src/App/App.csproj -p:FrameworkPinStrict=true
  ENVV=()
  rc_is 0
  check "the override path was not built" bash -c "find '$alt/src/Darkraise/bin' -name Darkraise.dll | grep -q ."
  case_ "control: absolute property wins over a relative environment variable"
  ENVV=("DARKRAISE_FRAMEWORK_PATH=rel/fw")
  build "$D" src/App/App.csproj "-p:DarkraiseFrameworkPath=$alt"
  ENVV=()
  rc_is 0
  hasnt 'error '
}

# ---------------------------------------------------------------------------
# A15

t_A15() {
  ensure_feed
  new_world a15
  mk_project "$D" src/App net10.0 "Fx.Codec:1.2.3" "$FRAMEWORK_REF"
  mk_project "$D" tests/App.Tests net10.0 "Fx.TestKit:3.1.0" '<ProjectReference Include="../../src/App/App.csproj" />'
  commit_all "$D"
  case_ "shipping project with listed packages (one transitive by wildcard)"
  build "$D" src/App/App.csproj
  rc_is 0
  hasnt 'DOMENT0(10|11|12|13)'
  hasnt ': error '
  case_ "build-only project with a build-and-test-only package"
  build "$D" tests/App.Tests/App.Tests.csproj
  rc_is 0
  hasnt ': error '
  case_ "real register, project without packages"
  new_world a15real "" real
  build "$D" src/App/App.csproj -p:FrameworkPinStrict=true
  rc_is 0
  hasnt ': error '
  case_ "gate reports no violation for the fixture tree"
  new_world a15gate
  mk_project "$D" src/App net10.0 "Fx.Codec:1.2.3" "$FRAMEWORK_REF"
  commit_all "$D"
  gate "$D"
  rc_is 0
  has '^gate: 1 projects checked, [0-9]+ packages seen, 0 violations$'
}

# ---------------------------------------------------------------------------
# A16

t_A16() {
  ensure_feed
  new_world a16
  mk_project "$D" src/App net10.0 "Fx.Unlisted:2.5.0" "$FRAMEWORK_REF"
  commit_all "$D"
  case_ "directly referenced package in no table"
  build "$D" src/App/App.csproj
  rc_fails
  error_line_has 'Fx\.Unlisted' '2\.5\.0' 'App' 'third-party-exceptions\.md'
  check "App compiled" bash -c "! find '$D/src/App/bin' -name App.dll 2>/dev/null | grep -q ."
  case_ "same package, strict build"
  build "$D" src/App/App.csproj -p:FrameworkPinStrict=true
  rc_fails
  error_line_has 'Fx\.Unlisted' '2\.5\.0' 'App' 'third-party-exceptions\.md'
}

# ---------------------------------------------------------------------------
# A17

t_A17() {
  ensure_feed
  case_ "through a package"
  new_world a17pkg
  mk_project "$D" src/App net10.0 "Fx.Outer:1.0.0" "$FRAMEWORK_REF"
  commit_all "$D"
  build "$D" src/App/App.csproj
  rc_fails
  error_line_has 'Fx\.Unlisted' 'Fx\.Outer'

  case_ "through the framework project"
  new_world a17fw '<ItemGroup><PackageReference Include="Fx.Unlisted" Version="2.5.0" /></ItemGroup>'
  build "$D" src/App/App.csproj
  rc_fails
  error_line_has 'Fx\.Unlisted' 'Darkraise'

  case_ "through a referenced doment project"
  new_world a17proj
  mk_project "$D" src/Lib net10.0 "Fx.Unlisted:2.5.0" ""
  mk_project "$D" src/App net10.0 "" "$FRAMEWORK_REF"$'\n    <ProjectReference Include="../Lib/Lib.csproj" />'
  commit_all "$D"
  build "$D" src/App/App.csproj
  rc_fails
  error_line_has 'Fx\.Unlisted' 'Lib' 'App'
}

# ---------------------------------------------------------------------------
# A18

t_A18() {
  ensure_feed
  new_world a18
  mk_project "$D" src/App net10.0 "Fx.TestKit:3.1.0" "$FRAMEWORK_REF"
  mk_project "$D" tools/Helper net10.0 "" ""
  mk_project "$D" src/Ships net10.0 "" '<ProjectReference Include="../../tools/Helper/Helper.csproj" />'
  mk_project "$D" src/Clean net10.0 "" ""
  mk_project "$D" tests/Ships.Tests net10.0 "Fx.TestKit:3.1.0" '<ProjectReference Include="../../src/Clean/Clean.csproj" />'$'\n    <ProjectReference Include="../../tools/Helper/Helper.csproj" />'
  mk_project "$D" tools/Tooling net10.0 "Fx.TestKit:3.1.0" ""
  commit_all "$D"

  case_ "shipping project resolves a build-and-test-only package"
  build "$D" src/App/App.csproj
  rc_fails
  error_line_has 'Fx\.TestKit'
  case_ "shipping project references a build-only project"
  build "$D" src/Ships/Ships.csproj
  rc_fails
  error_line_has 'Helper'
  case_ "project under tests/ builds with the package and a build-only reference"
  build "$D" tests/Ships.Tests/Ships.Tests.csproj
  rc_is 0
  hasnt ': error '
  case_ "project under tools/ builds with the package"
  build "$D" tools/Tooling/Tooling.csproj
  rc_is 0
  hasnt ': error '
}

# ---------------------------------------------------------------------------
# A19

ref_check() { dn "$D" msbuild "$1" -t:DomentReferenceCheck; }

t_A19() {
  new_world a19
  local fwp='$(DarkraiseFrameworkPath)'
  mk_project "$D" src/RefCore net10.0 "" "<ProjectReference Include=\"$fwp/src/Darkraise/Darkraise.csproj\" />"
  mk_project "$D" src/RefApi net10.0 "" "<ProjectReference Include=\"$fwp/src/Darkraise.Api/Darkraise.Api.csproj\" />"
  mk_project "$D" src/RefUiOnNet net10.0 "" "<ProjectReference Include=\"$fwp/src/Darkraise.Win32UI/Darkraise.Win32UI.csproj\" />"
  mk_project "$D" src/RefGenOnNet net10.0 "" "<ProjectReference Include=\"$fwp/src/Darkraise.Win32UI.Generators/Darkraise.Win32UI.Generators.csproj\" />"
  mk_project "$D" src/WinCore net10.0-windows "" "<ProjectReference Include=\"$fwp/src/Darkraise/Darkraise.csproj\" />"
  mk_project "$D" src/WinUi net10.0-windows "" "<ProjectReference Include=\"$fwp/src/Darkraise.Win32UI/Darkraise.Win32UI.csproj\" />"
  mk_project "$D" src/WinGen net10.0-windows "" "<ProjectReference Include=\"$fwp/src/Darkraise.Win32UI.Generators/Darkraise.Win32UI.Generators.csproj\" />"
  mk_project "$D" src/WinApi net10.0-windows "" "<ProjectReference Include=\"$fwp/src/Darkraise.Api/Darkraise.Api.csproj\" />"
  local outside
  outside=$(dirname "$D")/outside
  mk_project "$outside" Out net10.0 "" ""
  mk_project "$D" src/RefOutAbs net10.0 "" "<ProjectReference Include=\"$outside/Out/Out.csproj\" />"
  mk_project "$D" src/RefOutRel net10.0 "" '<ProjectReference Include="../../../outside/Out/Out.csproj" />'
  commit_all "$D"

  local ok
  for ok in RefCore WinCore WinUi WinGen; do
    case_ "allowed: $ok"
    ref_check "src/$ok/$ok.csproj"
    rc_is 0
    hasnt ': error '
  done
  case_ "refused: framework Api project from net10.0"
  ref_check src/RefApi/RefApi.csproj
  rc_fails
  error_line_has 'Darkraise\.Api'
  case_ "refused: Win32UI from net10.0"
  ref_check src/RefUiOnNet/RefUiOnNet.csproj
  rc_fails
  error_line_has 'Win32UI'
  case_ "refused: Win32UI generator from net10.0"
  ref_check src/RefGenOnNet/RefGenOnNet.csproj
  rc_fails
  error_line_has 'Generators'
  case_ "refused: Api project from net10.0-windows"
  ref_check src/WinApi/WinApi.csproj
  rc_fails
  error_line_has 'Darkraise\.Api'
  case_ "refused: project outside the checkout, absolute path"
  ref_check src/RefOutAbs/RefOutAbs.csproj
  rc_fails
  error_line_has 'Out\.csproj|outside'
  case_ "refused: project outside the checkout, relative path"
  ref_check src/RefOutRel/RefOutRel.csproj
  rc_fails
  error_line_has 'Out\.csproj|outside'
  case_ "a real build refuses the Api reference"
  build "$D" src/RefApi/RefApi.csproj
  rc_fails
  error_line_has 'Darkraise\.Api'
  check "RefApi compiled" bash -c "! find '$D/src/RefApi/bin' -name RefApi.dll 2>/dev/null | grep -q ."
}

# ---------------------------------------------------------------------------
# A20

register_case() { # register_case <label> <edit function> <error patterns...>
  local label=$1 edit=$2
  shift 2
  case_ "$label"
  new_world "a20-${label// /-}"
  "$edit" "$D/docs/third-party-exceptions.md"
  commit_all "$D"
  build "$D" src/App/App.csproj
  rc_fails
  error_line_has "$@"
}

e_no_exceptions() { drop_section "$1" "Exceptions"; }
e_no_tools() { drop_section "$1" "Build-and-test-only tools"; }
e_no_platform() { drop_section "$1" "Platform packages"; }
e_no_licence() { drop_column "$1" "Exceptions" 6; }
e_no_approved_b() { drop_column "$1" "Build-and-test-only tools" 6; }
e_no_package_col() { drop_column "$1" "Platform packages" 1; }
e_dup_x1() { dup_row "$1" X1; }
e_dup_b1() { dup_row "$1" B1; }
e_blank_reason() { blank_cell "$1" X1 5; }
e_blank_licence() { blank_cell "$1" X1 6; }
e_blank_behind() { blank_cell "$1" X1 7; }
e_blank_replacement() { blank_cell "$1" X2 8; }
e_blank_approved() { blank_cell "$1" X1 9; }
e_blank_b_licence() { blank_cell "$1" B1 5; }
e_blank_b_approved() { blank_cell "$1" B2 6; }

t_A20() {
  register_case "missing Exceptions table" e_no_exceptions 'Exceptions'
  register_case "missing tools table" e_no_tools 'Build-and-test-only'
  register_case "missing Platform packages table" e_no_platform 'Platform packages'
  register_case "missing Licence column" e_no_licence 'Licence'
  register_case "missing Approved column of the tools table" e_no_approved_b 'Approved'
  register_case "missing Package column" e_no_package_col 'Package'
  register_case "duplicate X1" e_dup_x1 'X1'
  register_case "duplicate B1" e_dup_b1 'B1'
  register_case "empty reason" e_blank_reason 'X1' 'Reason'
  register_case "empty licence" e_blank_licence 'X1' 'Licence'
  register_case "empty interface" e_blank_behind 'X1' 'Behind|interface'
  register_case "empty replacement" e_blank_replacement 'X2' 'Replacement'
  register_case "empty approval" e_blank_approved 'X1' 'Approved'
  register_case "empty licence of a tool" e_blank_b_licence 'B1' 'Licence'
  register_case "empty approval of a tool" e_blank_b_approved 'B2' 'Approved'
}

# ---------------------------------------------------------------------------
# A21

t_A21() {
  ensure_feed
  new_world a21
  mk_project "$D" src/App net10.0 "Fx.Codec:1.2.3" "$FRAMEWORK_REF"
  mk_project "$D" src/OrphanOne net10.0 "Fx.Unlisted:2.5.0" ""
  mk_project "$D" src/OrphanTwo net10.0 "Fx.Unlisted2:1.1.0" ""
  mk_project "$D" tests/build/fixtures/FxSkipped net10.0 "Fx.Unlisted:2.5.0" ""
  mk_project "$D" tests/build/other/FxOther net10.0 "Fx.Unlisted:2.5.0" ""
  mk_project "$D" tests/fixtures/FxFixturesLike net10.0 "Fx.Unlisted:2.5.0" ""
  echo '<Solution><Project Path="src/App/App.csproj" /></Solution>' > "$D/Doment.slnx"
  commit_all "$D"
  mk_project "$D" src/FxUntracked net10.0 "Fx.Unlisted:2.5.0" ""

  case_ "tree with violations in projects the solution does not list"
  gate "$D"
  rc_fails
  has 'OrphanOne'
  has 'OrphanTwo'
  has 'FxOther'
  has 'FxFixturesLike'
  hasnt 'FxSkipped'
  hasnt 'FxUntracked'
  has '^gate: 5 projects checked, [0-9]+ packages seen, [0-9]+ violations$'
  local last v
  last=$(tail -n 1 <<<"$OUT")
  eq "$(grep -cE '^gate: [0-9]+ projects checked, [0-9]+ packages seen, [0-9]+ violations$' <<<"$last")" 1 "the last line is the summary"
  v=$(sed -nE 's/^gate: [0-9]+ projects checked, [0-9]+ packages seen, ([0-9]+) violations$/\1/p' <<<"$last")
  [[ -n $v && $v -ge 4 ]] || note "expected at least 4 violations in the summary, got '$v'"

  case_ "the gate takes the tree as its argument, from any directory"
  gate "$D"
  rc_fails

  case_ "this repository passes and skips only tests/build/fixtures/"
  if [[ -d $REPO_ROOT/external/darkraise-framework ]]; then
    OUT=$(cd "$T" && DOMENT_GATE_NO_FETCH=1 timeout 900 bash "$REPO_ROOT/build/gate.sh" 2>&1) && RC=0 || RC=$?
    rc_is 0
    local expected
    expected=$(git -C "$REPO_ROOT" ls-files -- '*.csproj' '*.fsproj' '*.vbproj' | grep -vc '^tests/build/fixtures/' || true)
    has "^gate: $expected projects checked, [0-9]+ packages seen, 0 violations\$"
  else
    note "no framework worktree at $REPO_ROOT/external/darkraise-framework, so the repository's own gate run cannot be proven here"
  fi
}

# ---------------------------------------------------------------------------
# A22

t_A22() {
  new_world a22
  mkdir -p "$D/vendor" "$D/lib"
  printf 'MZ listed' > "$D/vendor/listed.sys"
  commit_all "$D" "listed binary"
  case_ "baseline: only a listed binary"
  gate "$D"
  rc_is 0
  has ', 0 violations$'

  local ext
  for ext in dll exe so dylib a lib sys nupkg snupkg; do printf 'binary %s' "$ext" > "$D/lib/unlisted.$ext"; done
  commit_all "$D" "unlisted binaries"
  printf 'x' > "$D/lib/untracked.dll"
  case_ "tracked unlisted binaries of every listed extension"
  gate "$D"
  rc_fails
  for ext in dll exe so dylib a lib sys nupkg snupkg; do has "lib/unlisted\\.$ext"; done
  hasnt 'vendor/listed\.sys'
  hasnt 'untracked\.dll'
  has '^gate: [0-9]+ projects checked, [0-9]+ packages seen, [0-9]+ violations$'
}

# ---------------------------------------------------------------------------
# A23

t_A23() {
  new_world a23
  case_ "baseline: tool manifest with a build-and-test-only tool"
  write_file "$D/.config/dotnet-tools.json" <<'JSON'
{ "version": 1, "isRoot": true, "tools": { "fx-format": { "version": "1.0.0", "commands": [ "fx-format" ] } } }
JSON
  commit_all "$D"
  gate "$D"
  rc_is 0
  has ', 0 violations$'

  case_ "project that does not import the root build targets"
  mk_project "$D" src/Legacy net10.0 "" ""
  echo '<Project />' > "$D/src/Legacy/Directory.Build.targets"
  commit_all "$D" "legacy"
  gate "$D"
  rc_fails
  has 'Legacy'

  case_ "tool in no table"
  git -C "$D" rm -rq src/Legacy && git -C "$D" commit -qm "drop legacy" || die "drop legacy"
  write_file "$D/.config/dotnet-tools.json" <<'JSON'
{ "version": 1, "isRoot": true, "tools": { "fx-format": { "version": "1.0.0", "commands": [ "fx-format" ] }, "fx-unlisted": { "version": "2.0.0", "commands": [ "fx-unlisted" ] } } }
JSON
  commit_all "$D" "unlisted tool"
  gate "$D"
  rc_fails
  has 'fx-unlisted'

  case_ "tool that is an exception row, not a build-and-test-only row"
  write_file "$D/.config/dotnet-tools.json" <<'JSON'
{ "version": 1, "isRoot": true, "tools": { "Fx.Codec": { "version": "1.0.0", "commands": [ "fxcodec" ] } } }
JSON
  commit_all "$D" "exception tool"
  gate "$D"
  rc_fails
  has 'Fx\.Codec'
}

# ---------------------------------------------------------------------------
# A25

snapshot_refs() { git -C "$1" for-each-ref --format='%(refname) %(objectname)'; }

t_A25() {
  new_world a25
  local c2 c3 refs_before
  c2=$(fw_commit "$FW" two push)
  git -C "$FW" checkout -q master
  echo "$c2" > "$D/build/darkraise-framework.pin"

  case_ "sync refuses a worktree with a modified file"
  echo '// work' >> "$W/src/Darkraise/Class1.cs"
  fw "$D" "$FW" sync
  rc_fails
  hasi 'Class1\.cs|modified|changes|not clean'
  eq "$(head_of "$W")" "$C1" "worktree HEAD after refused sync"
  check "the modified file was lost" grep -q '// work' "$W/src/Darkraise/Class1.cs"
  git -C "$W" checkout -q -- src/Darkraise/Class1.cs

  case_ "sync refuses a worktree with an untracked file"
  echo x > "$W/untracked-note.txt"
  fw "$D" "$FW" sync
  rc_fails
  hasi 'untracked-note\.txt|untracked|changes|not clean'
  eq "$(head_of "$W")" "$C1" "worktree HEAD after refused sync"
  check "the untracked file was lost" test -f "$W/untracked-note.txt"
  rm -f "$W/untracked-note.txt"

  case_ "sync refuses a worktree with a staged file"
  echo x > "$W/staged-note.txt"
  git -C "$W" add staged-note.txt
  fw "$D" "$FW" sync
  rc_fails
  hasi 'staged-note\.txt|staged|changes|not clean'
  eq "$(head_of "$W")" "$C1" "worktree HEAD after refused sync"
  git -C "$W" rm -qf staged-note.txt

  case_ "sync refuses a HEAD on no branch and no remote-tracking ref"
  git -C "$W" checkout -q --detach "$C1"
  git -C "$W" commit -q --allow-empty -m "orphan work"
  local orphan
  orphan=$(head_of "$W")
  refs_before=$(snapshot_refs "$FW")
  fw "$D" "$FW" sync
  rc_fails
  hasi "${orphan:0:7}|branch|remote-tracking|reachable"
  eq "$(head_of "$W")" "$orphan" "worktree HEAD after refused sync"
  eq "$(snapshot_refs "$FW")" "$refs_before" "refs after refused sync"

  case_ "sync moves a HEAD that only a remote-tracking ref reaches, and leaves it detached"
  git -C "$FW" update-ref refs/remotes/origin/side "$orphan"
  refs_before=$(snapshot_refs "$FW")
  fw "$D" "$FW" sync
  rc_is 0
  eq "$(head_of "$W")" "$c2" "worktree HEAD after sync"
  check "HEAD is not detached" bash -c "! git -C '$W' symbolic-ref -q HEAD >/dev/null"
  eq "$(snapshot_refs "$FW")" "$refs_before" "refs after sync"
  git -C "$FW" update-ref -d refs/remotes/origin/side

  case_ "sync moves a worktree on a local branch and leaves the branch alone"
  git -C "$W" checkout -q -b fw-work "$C1"
  git -C "$W" commit -q --allow-empty -m "branch work"
  local branch_tip
  branch_tip=$(head_of "$W")
  refs_before=$(snapshot_refs "$FW")
  fw "$D" "$FW" sync
  rc_is 0
  eq "$(head_of "$W")" "$c2" "worktree HEAD after sync"
  check "HEAD is not detached" bash -c "! git -C '$W' symbolic-ref -q HEAD >/dev/null"
  eq "$(git -C "$FW" rev-parse refs/heads/fw-work)" "$branch_tip" "the branch fw-work"
  eq "$(snapshot_refs "$FW")" "$refs_before" "refs after sync"

  case_ "pin refuses a worktree with changes"
  git -C "$W" checkout -q --detach "$c2"
  echo "$C1" > "$D/build/darkraise-framework.pin"
  echo '// work' >> "$W/src/Darkraise/Class1.cs"
  fw "$D" "$FW" pin
  rc_fails
  hasi 'Class1\.cs|modified|changes|not clean'
  eq "$(tr -d '[:space:]' < "$D/build/darkraise-framework.pin")" "$C1" "pin file after refused pin"
  git -C "$W" checkout -q -- src/Darkraise/Class1.cs
  echo x > "$W/untracked-note.txt"
  fw "$D" "$FW" pin
  rc_fails
  hasi 'untracked|changes|not clean'
  eq "$(tr -d '[:space:]' < "$D/build/darkraise-framework.pin")" "$C1" "pin file after refused pin (untracked)"
  rm -f "$W/untracked-note.txt"

  case_ "pin records a pushed commit without a warning"
  fw "$D" "$FW" pin
  rc_is 0
  eq "$(tr -d '[:space:]' < "$D/build/darkraise-framework.pin")" "$c2" "pin file after pin"
  hasnt '[Ww]arn'

  case_ "pin records a commit that is not on the remote, with a warning"
  c3=$(fw_commit "$FW" three)
  git -C "$FW" checkout -q master
  git -C "$W" checkout -q --detach "$c3"
  fw "$D" "$FW" pin
  rc_is 0
  eq "$(tr -d '[:space:]' < "$D/build/darkraise-framework.pin")" "$c3" "pin file after pin of an unpushed commit"
  hasi 'warn'
  hasi 'remote|push|origin'
}

# ---------------------------------------------------------------------------
# A26

release_refusal() { # release_refusal <label> <setup> <name pattern>
  case_ "$1"
  new_world "a26-${1// /-}"
  "$2"
  fw "$D" "$FW" release
  rc_fails
  hasi "$3"
  [[ -d $W ]] || note "the worktree directory was removed"
  check "the framework repository no longer lists the worktree" bash -c "git -C '$FW' worktree list --porcelain | grep -Fxq 'worktree $W'"
  [[ -f $W/src/Darkraise/Class1.cs ]] || note "the worktree files are gone"
}

r_modified() { echo '// work' >> "$W/src/Darkraise/Class1.cs"; }
r_staged() { echo x > "$W/staged-note.txt"; git -C "$W" add staged-note.txt; }
r_untracked() { echo x > "$W/untracked-note.txt"; }
r_ignored() { echo '<Project />' > "$W/src/Darkraise/Darkraise.csproj.user"; }
r_orphan() { git -C "$W" commit -q --allow-empty -m "orphan work"; ORPHAN=$(head_of "$W"); }

t_A26() {
  release_refusal "modified file" r_modified 'Class1\.cs'
  release_refusal "staged file" r_staged 'staged-note\.txt'
  release_refusal "untracked file" r_untracked 'untracked-note\.txt'
  release_refusal "ignored file outside bin and obj" r_ignored 'Darkraise\.csproj\.user'
  release_refusal "HEAD on no branch" r_orphan 'branch|remote-tracking|reachable|commit'
  case_ "HEAD on no branch names the commit"
  new_world a26-orphan-commit
  r_orphan
  fw "$D" "$FW" release
  rc_fails
  has "${ORPHAN:0:7}"

  case_ "clean worktree with bin, obj, .vs and .idea content is removed"
  new_world a26-clean
  mkdir -p "$W/src/Darkraise/bin/Debug" "$W/src/Darkraise/obj" "$W/.vs" "$W/.idea"
  echo x > "$W/src/Darkraise/bin/Debug/x.dll"; echo x > "$W/src/Darkraise/obj/y"; echo x > "$W/.vs/z"; echo x > "$W/.idea/w"
  fw "$D" "$FW" release
  rc_is 0
  [[ ! -e $W ]] || note "the worktree directory is still there"
  check "the framework repository still lists the worktree" bash -c "! git -C '$FW' worktree list --porcelain | grep -Fq '$W'"

  case_ "HEAD reachable only through a remote-tracking ref is removed"
  new_world a26-remote-only
  git -C "$W" commit -q --allow-empty -m "remote only work"
  git -C "$FW" update-ref refs/remotes/origin/side "$(head_of "$W")"
  fw "$D" "$FW" release
  rc_is 0
  [[ ! -e $W ]] || note "the worktree directory is still there"
  check "the framework repository still lists the worktree" bash -c "! git -C '$FW' worktree list --porcelain | grep -Fq '$W'"
}

# ---------------------------------------------------------------------------
# Runner

TESTS=(
  "A10: builds from a checkout and a linked worktree, each against its own framework worktree|t_A10"
  "A11: a missing framework directory fails once, before compilation, naming the path and sync|t_A11"
  "A12: sync creates and moves the framework worktree, then a strict build succeeds|t_A12"
  "A13: a moved, modified, staged, untracked or ignored-file worktree warns, and errors when strict|t_A13"
  "A14: a relative framework path fails the build and asks for an absolute path|t_A14"
  "A15: a project whose packages are all in the register builds without a violation|t_A15"
  "A16: a directly referenced package in no table fails naming project, package, version and register|t_A16"
  "A17: a transitive package in no table fails naming it and the direct reference|t_A17"
  "A18: a shipping project cannot use build-only packages or projects; tests can|t_A18"
  "A19: only allowed framework projects may be referenced from outside the checkout|t_A19"
  "A20: a malformed register fails naming the row and the column|t_A20"
  "A21: the gate command checks every tracked project, reports all violations and summarises|t_A21"
  "A22: the gate command fails on an unlisted tracked binary|t_A22"
  "A23: the gate command fails on a project without the root targets and on an unlisted tool|t_A23"
  "A25: sync and pin refuse unsafe worktrees, leave branches alone and say why|t_A25"
  "A26: release refuses unsafe worktrees and removes a clean one|t_A26"
)

passed=0
failed=0
for entry in "${TESTS[@]}"; do
  if grep -Eq -- 'A1[5-9]:|A2[01]:' <<<"${entry%%|*}" && { [[ -z $FILTER ]] || grep -Eq -- "$FILTER" <<<"${entry%%|*}"; }; then ensure_feed; break; fi
done
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
