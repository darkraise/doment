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

# The C4 diagnostic patterns of build/check.sh.
WARNING_RE='(^|[: ])warning [A-Z]+[0-9]+:'

# One item type of a project, as "<Filename><Extension>" lines in sorted order, read with -getItem (no console
# logger output, so the JSON stays parseable).
msb_items() { # msb_items <project> <item type> <dotnet msbuild args...>
  local proj=$1 item=$2
  shift 2
  (cd "$REPO_ROOT" && timeout 600 dotnet msbuild "$proj" -nologo "-getItem:$item" "$@" 2>&1) |
    jq -r --arg i "$item" '(.Items[$i] // [])[] | .Filename + .Extension' 2>&1 | sort
}

solution_projects() { sed -nE 's|^ *<Project Path="([^"]+)" */>$|\1|p' "$REPO_ROOT/doment.slnx"; }

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

t_A2() {
  case_ "release build of the solution"
  [[ -f $REPO_ROOT/doment.slnx ]] || { note "no doment.slnx at the repository root"; return 0; }
  build "$REPO_ROOT" doment.slnx -c Release -p:FrameworkPinStrict=true
  rc_is 0
  hasnt "$WARNING_RE"
}

# Section 3 of the spec: each project's direct ProjectReference file names.
A3_ROWS=(
  "src/Doment.Protocol/Doment.Protocol.csproj|"
  "src/Doment.Core/Doment.Core.csproj|Darkraise.csproj Doment.Protocol.csproj"
  "src/Doment.Simulation/Doment.Simulation.csproj|Doment.Core.csproj"
  "src/Doment.Worker/Doment.Worker.csproj|Doment.Core.csproj"
  "src/Doment.Host/Doment.Host.csproj|Doment.Worker.csproj"
  "src/Doment.Client/Doment.Client.csproj|Doment.Core.csproj"
  "src/Doment.Server/Doment.Server.csproj|Doment.Core.csproj"
  "src/Doment.Cli/Doment.Cli.csproj|Doment.Client.csproj"
  "src/Doment.Agent/Doment.Agent.csproj|Doment.Host.csproj"
  "tests/Doment.Core.Tests/Doment.Core.Tests.csproj|Doment.Core.csproj"
)

t_A3() {
  case_ "solution projects"
  [[ -f $REPO_ROOT/doment.slnx ]] || { note "no doment.slnx at the repository root"; return 0; }
  local listed row proj
  listed=$(solution_projects | sort)
  eq "$listed" "$(for row in "${A3_ROWS[@]}"; do echo "${row%%|*}"; done | sort)" "projects of doment.slnx"

  case_ "direct references"
  for row in "${A3_ROWS[@]}"; do
    proj=${row%%|*}
    eq "$(msb_items "$proj" ProjectReference | paste -sd ' ')" "${row#*|}" "ProjectReference of $proj"
  done

  case_ "simulation reaches no other project"
  build "$REPO_ROOT" doment.slnx -c Release
  rc_is 0
  local refs
  while IFS= read -r proj; do
    [[ $proj == src/Doment.Simulation/* ]] && continue
    refs=$(msb_items "$proj" ReferencePath -p:Configuration=Release -t:ResolveReferences -p:BuildProjectReferences=false)
    grep -Eq '^[A-Za-z]' <<<"$refs" || note "no ReferencePath read for $proj: $(head -n 3 <<<"$refs")"
    if grep -qx 'Doment.Simulation.dll' <<<"$refs"; then note "$proj has Doment.Simulation in its ReferencePath"; fi
  done < <(solution_projects)
}

EXECUTABLES=(
  "src/Doment.Server/Doment.Server.csproj|doment-server"
  "src/Doment.Cli/Doment.Cli.csproj|doment"
  "src/Doment.Agent/Doment.Agent.csproj|doment-agent"
)

t_A4() {
  case_ "check.sh aot"
  [[ -f $CHECK ]] || { note "no build/check.sh"; return 0; }
  check_sh aot
  rc_is 0
  has '^check: aot ok$'
  hasnt "$WARNING_RE"

  local row name bin stdout
  for row in "${EXECUTABLES[@]}"; do
    name=${row#*|}
    bin=$REPO_ROOT/artifacts/publish/$name/linux-x64/$name
    case_ "$name --version"
    if [[ ! -x $bin ]]; then
      note "no executable $bin"
      continue
    fi
    stdout=$(timeout 60 "$bin" --version 2>"$T/a4.err") && RC=0 || RC=$?
    OUT=$stdout$'\n'$(cat "$T/a4.err")
    rc_is 0
    eq "$(head -n 1 <<<"$stdout" | grep -Ec "^${name} 0\\.1\\.0([+-]|\$)")" 1 "first line of $name --version: $(head -n 1 <<<"$stdout")"

    case_ "$name --bogus"
    stdout=$(timeout 60 "$bin" --bogus 2>"$T/a4.err") && RC=0 || RC=$?
    OUT=$stdout$'\n'$(cat "$T/a4.err")
    rc_is 2
    OUT=$(cat "$T/a4.err")
    has "^usage: ${name} \\[--version \\| --help\\]\$"
    OUT=$stdout
    hasnt '^usage:'
  done
}

t_A5() {
  local row proj assets
  for row in "${EXECUTABLES[@]}"; do
    proj=${row%%|*}
    assets=$REPO_ROOT/$(dirname "$proj")/obj/project.assets.json
    case_ "$(basename "$proj" .csproj) assets"
    if [[ ! -f $assets ]]; then
      note "no $assets; A4 publishes first"
      continue
    fi
    local id version
    for id in Microsoft.DotNet.ILCompiler runtime.linux-x64.Microsoft.DotNet.ILCompiler; do
      version=$(jq -r --arg id "$id" '.libraries | keys[] | select(startswith($id + "/")) | sub("^[^/]*/"; "")' "$assets")
      if [[ -z $version ]]; then note "no $id in $assets"; continue; fi
      check "$id is $version, below 10.0.14" version_at_least "$version" 10.0.14
    done
    local packs
    # A download dependency's version is a range such as "[10.0.15, 10.0.15]"; its lower bound is checked.
    packs=$(jq -r '.project.frameworks[].downloadDependencies[]? | select(.name | test("linux-x64"))
      | "\(.name) \(.version | gsub("[\\[\\]() ]"; "") | split(",")[0])"' "$assets")
    [[ -n $packs ]] || note "no linux-x64 runtime pack among the download dependencies of $assets"
    local pack
    while IFS=' ' read -r pack version; do
      [[ -n $pack ]] || continue
      check "$pack is $version, below 10.0.14" version_at_least "$version" 10.0.14
    done <<<"$packs"
  done

  case_ "audit"
  dn "$REPO_ROOT" restore doment.slnx -p:DomentAuditStrict=true
  rc_is 0
  hasnt 'NU190'
}

# standin <name>: a stand-in tree at $T/<name> (under artifacts/acceptance/) with the checkout's build files and a
# copy of its register; prints its path. The real framework worktree is reached through DARKRAISE_FRAMEWORK_PATH.
standin() {
  local d=$T/$1 f
  mkdir -p "$d/docs"
  for f in Directory.Build.props Directory.Build.targets global.json .editorconfig .csharpierrc .csharpierignore; do
    cp "$REPO_ROOT/$f" "$d/$f"
  done
  cp -r "$REPO_ROOT/build" "$REPO_ROOT/.config" "$d/"
  cp "$REPO_ROOT/docs/third-party-exceptions.md" "$d/docs/third-party-exceptions.md"
  printf '<Solution>\n  <Folder Name="/src/">\n    <Project Path="src/Fx/Fx.csproj" />\n  </Folder>\n</Solution>\n' > "$d/doment.slnx"
  echo "$d"
}

standin_check() { # standin_check <tree> <args...>
  local tree=$1
  shift
  OUT=$(cd "$tree" && env "DARKRAISE_FRAMEWORK_PATH=$REPO_ROOT/external/darkraise-framework" timeout 3000 bash build/check.sh "$@" 2>&1) &&
    RC=0 || RC=$?
}

t_A6() {
  case_ "trim warning fails the aot step"
  local d
  d=$(standin a6)
  mkdir -p "$d/src/Fx"
  printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <OutputType>Exe</OutputType>\n    <TargetFramework>net10.0</TargetFramework>\n    <AssemblyName>fx</AssemblyName>\n    <PublishAot>true</PublishAot>\n    <TrimmerSingleWarn>false</TrimmerSingleWarn>\n  </PropertyGroup>\n</Project>\n' \
    > "$d/src/Fx/Fx.csproj"
  printf 'System.Console.WriteLine(System.Type.GetType(System.Console.ReadLine()!)!.GetMethods().Length);\n' > "$d/src/Fx/Program.cs"
  standin_check "$d" aot
  rc_is 1
  has '^check: aot failed$'
  has '^    .*(IL2|IL3)[0-9]{3}'

  case_ "the warning pattern matches the ILC form"
  local re
  re=$(sed -nE "s/^WARNING_RE='(.*)'\$/\\1/p" "$CHECK")
  [[ -n $re ]] || note "no WARNING_RE in $CHECK"
  grep -Eq -- "$re" <<<'ILC : Trim analysis warning IL2026: Foo.Bar(): message' || note "/$re/ does not match the ILC warning form"
}

t_A7() {
  case_ "check.sh portable"
  [[ -f $CHECK ]] || { note "no build/check.sh"; return 0; }
  check_sh portable
  rc_is 0
  has '^check: portable ok$'
  local p rid
  for p in Doment.Protocol Doment.Core Doment.Simulation Doment.Worker Doment.Host Doment.Client Doment.Server Doment.Cli Doment.Core.Tests; do
    for rid in linux-x64 win-x64; do
      count_is "^check: portable ${p//./\\.} $rid\$" 1
    done
  done
  hasnt '^check: portable Doment\.Agent '
}

t_A27() {
  local d
  d=$(standin a27)
  mkdir -p "$d/src/Fx"
  printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>net10.0</TargetFramework>\n  </PropertyGroup>\n  <ItemGroup>\n    <PackageReference Include="Newtonsoft.Json" Version="12.0.1" />\n  </ItemGroup>\n</Project>\n' \
    > "$d/src/Fx/Fx.csproj"
  # The backticks are Markdown.
  # shellcheck disable=SC2016
  sed -i '/^| X2 |/a | X9 | Newtonsoft.Json | `Newtonsoft.Json` | Acceptance A27 | Known-vulnerable stand-in | MIT | - | - | 2026-11-24 |' \
    "$d/docs/third-party-exceptions.md"

  case_ "plain build warns"
  ENVV=("DARKRAISE_FRAMEWORK_PATH=$REPO_ROOT/external/darkraise-framework")
  build "$d" doment.slnx
  ENVV=()
  rc_is 0
  has 'warning NU1903'

  case_ "check.sh build fails"
  standin_check "$d" build
  rc_is 1
  has '^check: build failed$'
  error_line_has 'NU1903' 'GHSA-5crp-9r3c-p9vr'
}

SIMULATION_HOSTS=(src/Doment.Cli/Doment.Cli.csproj src/Doment.Agent/Doment.Agent.csproj)

t_A15() {
  local proj refs defines
  for proj in "${SIMULATION_HOSTS[@]}"; do
    case_ "$proj with DomentSimulation=true"
    refs=$(msb_items "$proj" ProjectReference -p:DomentSimulation=true)
    grep -qx 'Doment.Simulation.csproj' <<<"$refs" || note "no Doment.Simulation.csproj among the references: $(paste -sd ' ' <<<"$refs")"
    defines=$(cd "$REPO_ROOT" && timeout 600 dotnet msbuild "$proj" -nologo -getProperty:DefineConstants -p:DomentSimulation=true 2>&1)
    grep -Eq '(^|;)DOMENT_SIMULATION(;|$)' <<<"$defines" || note "DefineConstants lacks DOMENT_SIMULATION: $defines"

    case_ "$proj without the property"
    refs=$(msb_items "$proj" ProjectReference)
    if grep -qx 'Doment.Simulation.csproj' <<<"$refs"; then note "Doment.Simulation.csproj is referenced"; fi
    defines=$(cd "$REPO_ROOT" && timeout 600 dotnet msbuild "$proj" -nologo -getProperty:DefineConstants 2>&1)
    if grep -q 'DOMENT_SIMULATION' <<<"$defines"; then note "DefineConstants holds DOMENT_SIMULATION: $defines"; fi
  done
}

t_A16() {
  local proj name
  for proj in "${SIMULATION_HOSTS[@]}"; do
    name=$(basename "$proj" .csproj)
    case_ "$name release publish"
    dn "$REPO_ROOT" publish "$proj" -c Release -r linux-x64 -p:DomentSimulation=true
    rc_fails
    has 'error DOMENT030: a release publish cannot include Doment\.Simulation; build simulation binaries in Debug'

    case_ "$name debug publish"
    dn "$REPO_ROOT" publish "$proj" -c Debug -r linux-x64 -p:DomentSimulation=true -o "artifacts/acceptance/a16/$name"
    rc_is 0
    hasnt 'DOMENT030'
  done
  rm -rf "$REPO_ROOT/artifacts/acceptance/a16"
}

CHECK=$REPO_ROOT/build/check.sh

check_sh() { # check_sh <args...>; ENVV holds NAME=value pairs for this call
  OUT=$(cd "$REPO_ROOT" && env "${ENVV[@]}" timeout 3000 bash "$CHECK" "$@" 2>&1) && RC=0 || RC=$?
}

t_A17() {
  case_ "check.sh test"
  [[ -f $CHECK ]] || { note "no build/check.sh"; return 0; }
  check_sh test
  rc_is 0
  local first root
  first=$(head -n 1 <<<"$OUT")
  grep -Eq '^check: dotnet 10\.0\.4[0-9]{2} at /' <<<"$first" || note "first line is not 'check: dotnet 10.0.4nn at <dir>': $first"
  root=${first#* at }
  has '^check: test ok$'
  eq "$(tail -n 1 <<<"$OUT")" "check: 1 steps run, 0 failed" "last line"

  case_ "test host runtime"
  local probe=$T/probe
  mkdir -p "$probe"
  printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <OutputType>Exe</OutputType>\n    <TargetFramework>net10.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n' \
    > "$probe/Probe.csproj"
  printf 'System.Console.WriteLine(System.Environment.Version);\n' > "$probe/Program.cs"
  build "$probe" Probe.csproj -o "$probe/out"
  rc_is 0
  local v
  v=$(DOTNET_ROOT=$root timeout 60 "$probe/out/Probe" 2>&1) || note "the probe apphost failed under DOTNET_ROOT=$root: $v"
  check "the probe ran on runtime $v under DOTNET_ROOT=$root, below 10.0.14" version_at_least "$v" 10.0.14
}

t_A18() {
  [[ -f $CHECK ]] || { note "no build/check.sh"; return 0; }
  case_ "build and test"
  check_sh build test
  rc_is 0
  eq "$(grep -E '^check: (build|test) |^check: [0-9]+ steps' <<<"$OUT" | paste -sd '|')" \
    "check: build ok|check: test ok|check: 2 steps run, 0 failed" "step lines"

  case_ "failed build"
  # Not /nonexistent: some hosts create it as a home directory.
  ENVV=("DARKRAISE_FRAMEWORK_PATH=$T/no-framework")
  check_sh
  ENVV=()
  rc_is 1
  has '^check: build failed$'
  has '^    .*DOMENT003'
  hasnt '^check: portable'
  eq "$(tail -n 1 <<<"$OUT")" "check: 1 steps run, 1 failed" "last line"

  case_ "every step"
  check_sh
  rc_is 0
  eq "$(grep -E '^check: [a-z]+ (ok|failed)$|^check: [0-9]+ steps' <<<"$OUT" | paste -sd '|')" \
    "check: build ok|check: portable ok|check: aot ok|check: test ok|check: 4 steps run, 0 failed" "step lines"

  case_ "unknown step"
  check_sh bogus
  rc_is 2
  has "^check: unknown step 'bogus'; steps: build, portable, aot, test$"
}

# Processes started by a check.sh run carry A19_MARK in their environment, so processes of other sessions on the
# machine do not count.
A19_NAMES='(^|/)(dotnet|MSBuild|VBCSCompiler|ilc|Doment\.Core\.Tests)(\.dll)?$'
a19_leftovers() { # prints "<pid> <command>" for each marked process of those names
  local pid exe
  for pid in $(ls /proc | grep -E '^[0-9]+$'); do
    [[ $pid -eq $$ || $pid -eq $BASHPID ]] && continue
    grep -qz "^A19_MARK=$A19_MARK\$" "/proc/$pid/environ" 2>/dev/null || continue
    exe=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    local word
    for word in $(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | head -n 2); do
      if grep -Eq "$A19_NAMES" <<<"$word"; then
        echo "$pid $exe"
        break
      fi
    done
  done
}
a19_none_left() { # a19_none_left <when>
  local i left
  for i in $(seq 1 20); do
    left=$(a19_leftovers)
    [[ -z $left ]] && return 0
    sleep 0.5
  done
  note "processes left after $1: $(head -n 5 <<<"$left" | cut -c1-200)"
}

t_A19() {
  [[ -f $CHECK ]] || { note "no build/check.sh"; return 0; }
  A19_MARK=$$-$RANDOM
  case_ "after build and test"
  ENVV=("A19_MARK=$A19_MARK")
  check_sh build test
  rc_is 0
  a19_none_left "build/check.sh build test"

  case_ "after a timeout"
  ENVV=("A19_MARK=$A19_MARK" DOMENT_CHECK_TIMEOUT=1)
  check_sh build
  rc_is 1
  has '^    timed out after 1 s: '
  a19_none_left "a timed-out build"

  case_ "after SIGTERM"
  (cd "$REPO_ROOT" && exec env "A19_MARK=$A19_MARK" timeout 900 bash "$CHECK" build > "$T/a19.out" 2>&1) &
  local pid=$!
  sleep 2
  kill -TERM "$pid"
  wait "$pid"
  RC=$?
  OUT=$(cat "$T/a19.out")
  rc_fails
  a19_none_left "SIGTERM two seconds into build/check.sh build"
  ENVV=()
}

t_A20() {
  case_ gate
  OUT=$(cd "$REPO_ROOT" && DOMENT_GATE_NO_FETCH=1 timeout 900 bash build/gate.sh 2>&1) && RC=0 || RC=$?
  rc_is 0
  has '^gate: [0-9]+ projects checked, [0-9]+ packages seen, 0 violations$'

  case_ "platform rows"
  local rows
  rows=$(awk '/^## /{ t = ($0 == "## Platform packages") } t && /^\| `/' "$REPO_ROOT/docs/third-party-exceptions.md")
  [[ -n $rows ]] || note "the register has no Platform packages row"
  local line added
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    added=$(awk -F'|' '{ gsub(/^ +| +$/, "", $3); print $3 }' <<<"$line")
    [[ $added == ".NET SDK"* ]] || note "platform row not added by the .NET SDK: $line"
  done <<<"$rows"
}

# The Kind column of the module map in docs/architecture.md, as "<project> <DomentPlatform value>" lines.
module_map_platforms() {
  awk -F'|' '
    /^## / { t = ($0 == "## Module map") }
    t && /^\| `/ {
      p = $2; k = $5
      gsub(/[ `]/, "", p); gsub(/^ +| +$/, "", k)
      v = k == "portable" ? "portable" : k == "Linux-bound" ? "linux" : k == "Windows-bound" ? "windows" : "unknown:" k
      print p, v
    }
  ' "$REPO_ROOT/docs/architecture.md"
}

t_A28() {
  case_ "module map"
  [[ -f $REPO_ROOT/doment.slnx ]] || { note "no doment.slnx at the repository root"; return 0; }
  local map proj name expected actual linux=
  map=$(module_map_platforms)
  [[ -n $map ]] || note "no module map rows read from docs/architecture.md"
  while IFS= read -r proj; do
    name=$(basename "$proj" .csproj)
    expected=$(awk -v n="$name" '$1 == n { print $2 }' <<<"$map")
    if [[ -z $expected ]]; then
      if [[ $name == Doment.Core.Tests ]]; then
        expected=portable
      else
        note "$name has no module map row"
        continue
      fi
    fi
    actual=$(cd "$REPO_ROOT" && timeout 600 dotnet msbuild "$proj" -nologo -getProperty:DomentPlatform 2>&1)
    eq "$actual" "$expected" "DomentPlatform of $name"
    [[ $actual == linux ]] && linux+="$name "
  done < <(solution_projects)
  eq "$linux" "Doment.Agent " "the linux projects"
}

# The framework's .editorconfig as doment adopts it: without the DRUI020 line and the comment block directly above
# it, and with LF line endings.
framework_editorconfig() {
  awk '
    /^#/ { held = held $0 "\n"; next }
    /^dotnet_diagnostic\.DRUI020\.severity/ { held = ""; next }
    { printf "%s", held; held = ""; print }
    END { printf "%s", held }
  ' "$1" | sed 's/^end_of_line = crlf$/end_of_line = lf/'
}

t_A10() {
  case_ editorconfig
  local fw=$REPO_ROOT/external/darkraise-framework/.editorconfig ours=$REPO_ROOT/.editorconfig
  [[ -f $fw ]] || die "no framework .editorconfig at $fw; run tools/framework.sh sync"
  if [[ ! -f $ours ]]; then
    note "no .editorconfig at the repository root"
    return 0
  fi
  local d
  d=$(diff <(framework_editorconfig "$fw") \
    <(grep -v -E '^# doment:|^dotnet_diagnostic\.(IDE0161|IDE0028|IDE030[0-5])\.severity' "$ours") 2>&1)
  [[ -z $d ]] || note "the root .editorconfig differs from the framework's beyond the doment changes: $(head -n 12 <<<"$d")"

  case_ csharpierrc
  if [[ ! -f $REPO_ROOT/.csharpierrc ]]; then
    note "no .csharpierrc at the repository root"
    return 0
  fi
  eq "$(jq -S . "$REPO_ROOT/.csharpierrc" 2>&1)" "$(jq -S . "$REPO_ROOT/external/darkraise-framework/.csharpierrc" 2>&1)" ".csharpierrc"
}

t_A21() {
  case_ index
  OUT=$(git -C "$REPO_ROOT" ls-files --eol 2>&1) && RC=0 || RC=$?
  rc_is 0
  hasnt '^i/(crlf|mixed) '

  case_ eol
  local p
  # check-attr resolves a path whether or not the file exists.
  for p in build/gate.sh tests/build/run.sh build/Doment.BuildChecks.cs Directory.Build.props \
    src/Doment.Core/Doment.Core.csproj README.md build/darkraise-framework.pin; do
    eq "$(git -C "$REPO_ROOT" check-attr eol -- "$p" 2>&1)" "$p: eol: lf" "eol of $p"
  done

  case_ binary
  for p in x.dll x.exe x.so x.dylib x.a x.lib x.sys x.nupkg x.snupkg x.png x.jpg x.ico; do
    eq "$(git -C "$REPO_ROOT" check-attr text -- "$p" 2>&1)" "$p: text: unset" "text of $p"
  done
}

# ---------------------------------------------------------------------------
# Runner

TESTS=(
  "A1: the SDK on PATH is 10.0.404 or a later 10.0.4xx and global.json pins it with the testing platform|t_A1"
  "A2: the solution builds in Release with no warning|t_A2"
  "A3: each project references exactly its section 3 row and only Doment.Simulation holds Doment.Simulation|t_A3"
  "A4: build/check.sh aot publishes the three executables, which print their name and version|t_A4"
  "A5: the executables restore NativeAOT packages of 10.0.14 or later and the restore has no audit finding|t_A5"
  "A6: a trim warning fails the aot step, and the warning pattern matches ILC's form|t_A6"
  "A7: build/check.sh portable builds every portable project for linux-x64 and win-x64|t_A7"
  "A10: the root .editorconfig is the framework's with only the recorded doment changes|t_A10"
  "A15: DomentSimulation=true gives Doment.Cli and Doment.Agent the simulation reference and constant|t_A15"
  "A16: a release publish with simulation fails with DOMENT030; a debug publish succeeds|t_A16"
  "A17: build/check.sh test passes and its DOTNET_ROOT runs apphosts on runtime 10.0.14 or later|t_A17"
  "A18: build/check.sh runs the named steps in order, stops at the first failure and refuses an unknown step|t_A18"
  "A19: build/check.sh leaves no build or test process behind, after success, a timeout or SIGTERM|t_A19"
  "A20: the gate passes on this tree and every platform row is added by the .NET SDK|t_A20"
  "A21: every tracked text file is LF in the index and attributes force LF; binaries are not text|t_A21"
  "A27: a known-vulnerable package warns in a plain build and fails build/check.sh build|t_A27"
  "A28: each solution project's DomentPlatform matches its module map Kind and only Doment.Agent is linux|t_A28"
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
