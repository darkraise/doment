#!/usr/bin/env bash
# Acceptance tests (A1 to A25, A27, A28) of the repository, build and NativeAOT spec, written from the spec text.
# Usage: bash tests/build/repository-build-nativeaot.acceptance.sh [<extended regex on the test name>]
# ACCEPT_CHECK_LOG=<file>: a recorded run of `build/check.sh` (its output, then a last line `exit=<n>`), reused by
# A4, A7 and A18 instead of a fresh full run.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
FILTER=${1:-}
FRAMEWORK=$REPO_ROOT/external/darkraise-framework

export MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_USE_MSBUILD_SERVER=0 UseSharedCompilation=false
export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
unset DARKRAISE_FRAMEWORK_PATH DARKRAISE_FRAMEWORK_REPO FrameworkPinStrict DOMENT_GATE_NO_FETCH
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_LFS_SKIP_SMUDGE=1
export GIT_AUTHOR_NAME=acceptance GIT_AUTHOR_EMAIL=acceptance@doment.invalid
export GIT_COMMITTER_NAME=acceptance GIT_COMMITTER_EMAIL=acceptance@doment.invalid

mkdir -p "$REPO_ROOT/artifacts/acceptance-qa"
IN=$(mktemp -d "$REPO_ROOT/artifacts/acceptance-qa/run.XXXXXX") # stand-in trees that must sit under artifacts/
OUTSIDE=$(mktemp -d "${TMPDIR:-/tmp}/doment-qa.XXXXXX")         # stand-in trees outside the checkout
trap 'rm -rf "$IN" "$OUTSIDE"; rmdir "$REPO_ROOT/artifacts/acceptance-qa" 2>/dev/null' EXIT
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
eq() { [[ $1 == "$2" ]] || note "expected '$2', got '$1' ($3)"; }
version_at_least() { [[ $(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1) == "$2" ]]; }

DN_FLAGS=(-nologo -tl:off -clp:NoSummary -noConsoleLogger "-logger:ConsoleLogger,Microsoft.Build;NoSummary;Verbosity=minimal")

run() { # run <dir> <seconds> <command...>: sets OUT and RC; ENVV holds NAME=value pairs
  local dir=$1 secs=$2
  shift 2
  OUT=$(cd "$dir" && env "${ENVV[@]}" timeout -k 10 "$secs" "$@" 2>&1) && RC=0 || RC=$?
}
ENVV=(DOMENT_QA=1)
dn() { local dir=$1; shift; run "$dir" 900 dotnet "$@" "${DN_FLAGS[@]}"; }

projects_all=(Protocol Core Simulation Worker Host Client Server Cli Agent)
proj_path() { # proj_path <short name>: path relative to the root
  [[ $1 == Core.Tests ]] && echo "tests/Doment.Core.Tests/Doment.Core.Tests.csproj" || echo "src/Doment.$1/Doment.$1.csproj"
}
msb() { # msb <root> <project> <msbuild args...>: evaluation only, output is JSON
  local root=$1 proj=$2
  shift 2
  (cd "$root" && env "${ENVV[@]}" timeout 300 dotnet msbuild "$proj" -nologo "$@" 2>&1)
}

# The output and exit code of `build/check.sh` with no argument, from ACCEPT_CHECK_LOG or one fresh run.
FULL_OUT=
FULL_RC=
full_check() {
  [[ -n $FULL_RC ]] && return 0
  if [[ -n ${ACCEPT_CHECK_LOG:-} && -f ${ACCEPT_CHECK_LOG:-} ]]; then
    FULL_RC=$(tail -n 1 "$ACCEPT_CHECK_LOG" | sed -nE 's/^exit=([0-9]+)$/\1/p')
    FULL_OUT=$(sed '$d' "$ACCEPT_CHECK_LOG")
  else
    FULL_OUT=$(cd "$REPO_ROOT" && timeout -k 30 2400 bash build/check.sh 2>&1) && FULL_RC=0 || FULL_RC=$?
  fi
}

# standin <name> <inside|outside>: a tree with the checkout's build files and register; prints its path.
standin() {
  local base=$OUTSIDE f d
  [[ $2 == inside ]] && base=$IN
  d=$base/$1
  mkdir -p "$d/docs"
  for f in Directory.Build.props Directory.Build.targets global.json .editorconfig .csharpierrc .csharpierignore; do
    cp "$REPO_ROOT/$f" "$d/$f"
  done
  cp -r "$REPO_ROOT/build" "$REPO_ROOT/.config" "$d/"
  cp "$REPO_ROOT/docs/third-party-exceptions.md" "$d/docs/third-party-exceptions.md"
  echo "$d"
}

# fx <tree> <name> <csproj properties> <csproj items> <source>: a formatted library project src/<name>.
fx() {
  local d=$1/src/$2
  mkdir -p "$d"
  printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>net10.0</TargetFramework>\n    %s\n  </PropertyGroup>\n  %s\n</Project>\n' \
    "$3" "$4" > "$d/$2.csproj"
  printf '%s\n' "$5" > "$d/Probe.cs"
}
CLEAN_SRC='namespace Fx;

public static class Probe
{
    public static int Value() => 1;
}'
REG_SRC='namespace Fx;

public static class Probe
{
    public static object? Read() => Microsoft.Win32.Registry.CurrentUser;
}'
fx_env() { ENVV=(DOMENT_QA=1 "DARKRAISE_FRAMEWORK_PATH=$FRAMEWORK"); }

# ---------------------------------------------------------------------------

t_A1() {
  case_ "dotnet --version"
  run "$REPO_ROOT" 60 dotnet --version
  rc_is 0
  [[ $OUT =~ ^10\.0\.4[0-9]{2}$ ]] && version_at_least "$OUT" 10.0.404 || note "dotnet --version is '$OUT', not 10.0.404 or a later 10.0.4xx"
  case_ "global.json"
  eq "$(jq -r '.sdk.version' "$REPO_ROOT/global.json")" 10.0.404 "sdk.version"
  eq "$(jq -r '.sdk.rollForward' "$REPO_ROOT/global.json")" latestPatch "sdk.rollForward"
  eq "$(jq -r '.test.runner' "$REPO_ROOT/global.json")" Microsoft.Testing.Platform "test.runner"
}

t_A2() {
  case_ "solution lists the ten projects"
  run "$REPO_ROOT" 120 dotnet sln doment.slnx list
  local want got

  got=$(tr '\\' '/' <<<"$OUT" | grep -E '\.csproj$' | sort)
  local p n=0
  for p in "${projects_all[@]}" Core.Tests; do
    grep -Fxq "$(proj_path "$p")" <<<"$got" || note "doment.slnx does not list $(proj_path "$p")"
    n=$((n + 1))
  done
  eq "$(wc -l <<<"$got" | tr -d ' ')" 10 "project count in doment.slnx"
  case_ "build"
  run "$REPO_ROOT" 900 dotnet build doment.slnx -c Release -p:FrameworkPinStrict=true --no-incremental -nologo
  rc_is 0
  has '^ *0 Warning\(s\)'
  has '^ *0 Error\(s\)'
  hasnt '(^|[: ])(warning|error) [A-Z]+[0-9]+:'
}

# direct project references of <proj>, as sorted file names
direct_refs() { msb "$REPO_ROOT" "$(proj_path "$1")" -getItem:ProjectReference | jq -r '(.Items.ProjectReference // [])[] | .Filename' | sort | paste -sd' '; }

t_A3() {
  case_ "direct references"
  declare -A want=([Protocol]="" [Core]="Darkraise Doment.Protocol" [Simulation]="Doment.Core" [Worker]="Doment.Core"
    [Host]="Doment.Worker" [Client]="Doment.Core" [Server]="Doment.Core" [Cli]="Doment.Client" [Agent]="Doment.Host"
    [Core.Tests]="Doment.Core")
  local p got
  declare -A refs
  for p in "${projects_all[@]}" Core.Tests; do
    got=$(direct_refs "$p")
    refs[$p]=$got
    eq "$got" "${want[$p]}" "direct references of Doment.$p"
  done
  case_ "no Doment.Simulation outside the simulation library"
  local queue seen cur r
  for p in "${projects_all[@]}" Core.Tests; do
    [[ $p == Simulation ]] && continue
    queue=("${refs[$p]}")
    seen=" "
    # shellcheck disable=SC2206
    queue=(${refs[$p]})
    while [[ ${#queue[@]} -gt 0 ]]; do
      cur=${queue[0]}
      queue=("${queue[@]:1}")
      [[ $seen == *" $cur "* ]] && continue
      seen+="$cur "
      [[ $cur == Doment.* ]] || continue
      r=${cur#Doment.}
      # shellcheck disable=SC2206
      [[ -n ${refs[$r]+x} ]] && queue+=(${refs[$r]})
    done
    [[ $seen != *" Doment.Simulation "* ]] || note "Doment.$p reaches Doment.Simulation"
  done
}

t_A4() {
  full_check
  case_ "aot step of the full check"
  OUT=$FULL_OUT
  has '^check: aot ok$'
  local name v
  for name in doment doment-agent doment-server; do
    case_ "$name --version"
    local bin=$REPO_ROOT/artifacts/publish/$name/linux-x64/$name
    [[ -x $bin ]] || { note "no executable $bin"; continue; }
    file "$bin" | grep -q ELF || note "$bin is not an ELF executable"
    OUT=$("$bin" --version 2>&1) && RC=0 || RC=$?
    rc_is 0
    v=$(head -n 1 <<<"$OUT")
    [[ $v =~ ^${name//./\\.}\ 0\.1\.0([+-].*)?$ ]] || note "first line '$v' is not '$name 0.1.0'"
    # NativeAOT: no managed runtime assemblies beside the binary
    [[ ! -e $REPO_ROOT/artifacts/publish/$name/linux-x64/System.Private.CoreLib.dll ]] || note "$name publish holds System.Private.CoreLib.dll"
  done
}

t_A5() {
  local p f
  for p in Cli Agent Server; do
    case_ "package versions of Doment.$p"
    f=$REPO_ROOT/src/Doment.$p/obj/project.assets.json
    [[ -f $f ]] || { note "no $f; run the aot step first"; continue; }
    local libs
    libs=$(jq -r '.libraries | keys[]' "$f")
    local pack
    for pack in Microsoft.DotNet.ILCompiler runtime.linux-x64.Microsoft.DotNet.ILCompiler; do
      grep -q "^$pack/" <<<"$libs" || note "$pack is not in the restore output of Doment.$p"
    done
    local line ver
    while IFS= read -r line; do
      ver=${line#*/}
      version_at_least "$ver" 10.0.14 || note "${line%%/*} is $ver, below 10.0.14"
    done < <(grep -E '^(Microsoft\.DotNet\.ILCompiler|runtime\.linux-x64\.Microsoft\.DotNet\.ILCompiler|Microsoft\.NETCore\.App\.Runtime(\.NativeAOT)?\.linux-x64)/' <<<"$libs")
  done
  case_ "NuGet audit reports nothing"
  run "$REPO_ROOT" 600 dotnet list doment.slnx package --vulnerable --include-transitive
  rc_is 0
  hasnt 'has the following vulnerable packages'
  has 'no vulnerable packages|no vulnerable'
}

# A6 and A27 fixture trees
t_A6() {
  case_ "trim-unsafe fixture fails the aot step"
  local d
  d=$(standin a6 inside)
  printf '<Solution>\n  <Folder Name="/src/">\n    <Project Path="src/Fx/Fx.csproj" />\n  </Folder>\n</Solution>\n' > "$d/doment.slnx"
  fx "$d" Fx '<OutputType>Exe</OutputType>
    <AssemblyName>fx</AssemblyName>
    <PublishAot>true</PublishAot>
    <TrimmerSingleWarn>false</TrimmerSingleWarn>' '' 'System.Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new object()));'
  mv "$d/src/Fx/Probe.cs" "$d/src/Fx/Program.cs"
  ENVV=(DOMENT_QA=1 "DARKRAISE_FRAMEWORK_PATH=$FRAMEWORK")
  run "$d" 3000 bash build/check.sh aot
  rc_is 1
  has '^check: aot failed$'
  has 'IL[0-9]{4}'
  case_ "the warning filter matches the recorded trim warning"
  local re
  re=$(sed -nE "s/^WARNING_RE='(.*)'\$/\\1/p" "$REPO_ROOT/build/check.sh")
  [[ -n $re ]] || note "no WARNING_RE in build/check.sh"
  grep -Eq -- "$re" <<<'ILC : Trim analysis warning IL2026: Foo.Bar(): message' || note "/$re/ does not match a Trim analysis warning IL2026 line"
}

t_A7() {
  full_check
  case_ "portable step of the full check"
  OUT=$FULL_OUT
  has '^check: portable ok$'
  local p rid
  for p in Doment.Protocol Doment.Core Doment.Simulation Doment.Worker Doment.Host Doment.Client Doment.Server Doment.Cli Doment.Core.Tests; do
    for rid in linux-x64 win-x64; do
      count_is "^check: portable ${p//./\\.} $rid\$" 1
    done
  done
  hasnt '^check: portable Doment\.Agent '
  count_is '^check: portable Doment\.[A-Za-z.]+ (linux|win)-x64$' 18
}

portable_tree() { # portable_tree <name>: a stand-in for the portable-rule cases
  standin "$1" outside
}

t_A8() {
  local d
  d=$(portable_tree a8)
  fx "$d" Clean '' '' "$CLEAN_SRC"
  fx "$d" Reg '' '' "$REG_SRC"
  fx_env
  case_ "control builds"
  dn "$d/src/Clean" build -p:DomentFormatCheck=false
  rc_is 0
  case_ "Registry.CurrentUser fails with CA1416"
  dn "$d/src/Reg" build -p:DomentFormatCheck=false
  [[ $RC -ne 0 ]] || note "a portable project calling Registry.CurrentUser built"
  has 'error CA1416'
}

# Writes a fixture for each A9 finding into <tree>/src/<name>
a9_fixtures() {
  local d=$1
  fx "$d" DllImport '' '' 'using System.Runtime.InteropServices;

namespace Fx;

public static class Probe
{
    [DllImport("libc", EntryPoint = "getpid")]
    public static extern int GetPid();
}'
  fx "$d" LibImport '<AllowUnsafeBlocks>true</AllowUnsafeBlocks>' '' 'using System.Runtime.InteropServices;

namespace Fx;

public static partial class Probe
{
    [LibraryImport("libc", EntryPoint = "getpid")]
    public static partial int GetPid();
}'
  fx "$d" NativeLib '' '' 'using System.Runtime.InteropServices;

namespace Fx;

public static class Probe
{
    public static bool Load() => NativeLibrary.TryLoad("libc", out _);
}'
  fx "$d" OsAttr '' '' '[assembly: System.Runtime.Versioning.SupportedOSPlatform("windows")]

namespace Fx;

public static class Probe
{
    public static int Value() => 1;
}'
  fx "$d" Net9 '' '' "$CLEAN_SRC"
  sed -i 's|<TargetFramework>net10.0</TargetFramework>|<TargetFramework>net9.0</TargetFramework>|' "$d/src/Net9/Net9.csproj"
}

t_A9() {
  local d f
  d=$(portable_tree a9)
  a9_fixtures "$d"
  fx_env
  declare -A finding=([DllImport]='DllImport|P/Invoke|native import|GetPid' [LibImport]='LibraryImport|P/Invoke|native import|GetPid'
    [NativeLib]='NativeLibrary' [OsAttr]='SupportedOSPlatform' [Net9]='net9.0|net10.0|target')
  for f in DllImport LibImport NativeLib OsAttr Net9; do
    case_ "$f fails with DOMENT033"
    dn "$d/src/$f" build -p:DomentFormatCheck=false
    [[ $RC -ne 0 ]] || note "$f built"
    has "error DOMENT033"
    local l
    l=$(grep -E 'error DOMENT033' <<<"$OUT" | head -n 1)
    grep -Eq "$f" <<<"$l" || note "the DOMENT033 line does not name the project $f: $l"
    grep -Eqi "${finding[$f]}" <<<"$l" || note "the DOMENT033 line does not name the finding (${finding[$f]}): $l"
    if [[ $f != Net9 ]]; then
      case_ "$f builds with -p:DomentPlatform=linux"
      dn "$d/src/$f" build -p:DomentFormatCheck=false -p:DomentPlatform=linux
      rc_is 0
    fi
  done
}

t_A10() {
  local pin norm fw
  pin=$(tr -d '[:space:]' < "$REPO_ROOT/build/darkraise-framework.pin")
  fw=$OUTSIDE/fw-editorconfig
  case_ ".editorconfig"
  git -C "$FRAMEWORK" show "$pin:.editorconfig" > "$fw" 2> "$OUTSIDE/fw.err" || { note "cannot read the framework's .editorconfig at $pin: $(cat "$OUTSIDE/fw.err")"; return 0; }
  norm=$OUTSIDE/fw-norm
  tr -d '\r' < "$fw" | sed -E 's/^(end_of_line *= *)crlf/\1lf/' | grep -Ev 'DRUI020' > "$norm"
  tr -d '\r' < "$REPO_ROOT/.editorconfig" > "$OUTSIDE/root-norm"
  local extra missing allowed='^(#.*|dotnet_diagnostic\.(IDE0161|IDE0028|IDE0300|IDE0301|IDE0302|IDE0303|IDE0304|IDE0305)\.severity *= *warning)?$'
  extra=$(diff <(sort "$norm") <(sort "$OUTSIDE/root-norm") | grep -E '^>' | sed 's/^> //' | grep -Ev "$allowed" || true)
  missing=$(diff <(sort "$norm") <(sort "$OUTSIDE/root-norm") | grep -E '^<' | sed 's/^< //' | grep -Ev '^(#.*)?$' || true)
  [[ -z $extra ]] || note "lines in the root .editorconfig beyond the documented changes: $(head -n 5 <<<"$extra")"
  [[ -z $missing ]] || note "framework lines missing from the root .editorconfig: $(head -n 5 <<<"$missing")"
  grep -Eq '^end_of_line *= *lf' "$REPO_ROOT/.editorconfig" || note "no end_of_line = lf"
  ! grep -qi 'crlf' <(grep -Ev '^ *#' "$REPO_ROOT/.editorconfig") || note "the root .editorconfig still says crlf"
  ! grep -q 'DRUI020' <(grep -Ev '^ *#' "$REPO_ROOT/.editorconfig") || note "DRUI020 is still configured"
  local id
  for id in IDE0161 IDE0028 IDE0300 IDE0301 IDE0302 IDE0303 IDE0304 IDE0305; do
    grep -Eq "^dotnet_diagnostic\.$id\.severity *= *warning" "$REPO_ROOT/.editorconfig" || note "no dotnet_diagnostic.$id.severity = warning"
  done
  case_ ".csharpierrc"
  git -C "$FRAMEWORK" show "$pin:.csharpierrc" 2>/dev/null | tr -d '\r' > "$OUTSIDE/fw-rc"
  tr -d '\r' < "$REPO_ROOT/.csharpierrc" | cmp -s - "$OUTSIDE/fw-rc" || note ".csharpierrc differs from the framework's at $pin"
}

t_A11() {
  local d
  d=$(portable_tree a11)
  fx "$d" Clean '' '' "$CLEAN_SRC"
  fx "$d" Block '' '' 'namespace Fx
{
    public static class Probe
    {
        public static int Value() => 1;
    }
}'
  fx "$d" Arr '' '' 'namespace Fx;

public static class Probe
{
    public static int[] Values() => new int[] { 1, 2, 3 };
}'
  fx "$d" Ca '' '' 'namespace Fx;

public static class Probe
{
    public static int Bad_Name() => 1;
}'
  fx_env
  case_ "control builds"
  dn "$d/src/Clean" build -p:DomentFormatCheck=false
  rc_is 0
  local f
  for f in Block:IDE0161 Arr:IDE0300 Ca:CA1707; do
    case_ "${f%%:*} fails the build"
    dn "$d/src/${f%%:*}" build -p:DomentFormatCheck=false
    [[ $RC -ne 0 ]] || note "${f%%:*} built"
    has "error ${f##*:}"
  done
}

fmt_ran() { grep -Eq 'Checked [0-9]+ file|csharpier check|csharpier' <<<"$OUT"; }

t_A12() {
  local d
  d=$(standin a12 outside)
  fx "$d" Fx '' '' 'namespace Fx;   public static class Probe{public static int Value()=>1;}'
  fx_env
  (cd "$d" && env "${ENVV[@]}" timeout 120 dotnet tool restore > /dev/null 2>&1) || note "dotnet tool restore failed in the stand-in"
  local p=$d/src/Fx
  case_ "unformatted file fails with DOMENT031"
  run "$p" 600 dotnet build -nologo -v:n -tl:off
  [[ $RC -ne 0 ]] || note "an unformatted file built"
  has 'error DOMENT031'
  has 'Probe\.cs'
  case_ "formatted file builds"
  run "$p" 300 dotnet csharpier format .
  run "$p" 600 dotnet build -nologo -v:n -tl:off
  rc_is 0
  fmt_ran || note "the first passing build did not run CSharpier; output: $(tail_out)"
  case_ "second build does not run CSharpier"
  run "$p" 600 dotnet build -nologo -v:n -tl:off
  rc_is 0
  ! fmt_ran || note "CSharpier ran again with no change: $(grep -E 'Checked|csharpier' <<<"$OUT" | head -n 3)"
  case_ ".csharpierrc change runs it again"
  sed -i 's/130/120/' "$d/.csharpierrc"
  run "$p" 600 dotnet build -nologo -v:n -tl:off
  rc_is 0
  fmt_ran || note "CSharpier did not run after .csharpierrc changed"
  case_ "design-time build does not run it"
  sed -i 's/120/110/' "$d/.csharpierrc"
  run "$p" 600 dotnet build -nologo -v:n -tl:off -p:DesignTimeBuild=true
  ! fmt_ran || note "CSharpier ran in a design-time build"
  run "$p" 600 dotnet build -nologo -v:n -tl:off
  rc_is 0
  fmt_ran || note "the build after the design-time build did not run CSharpier although its input changed"
}

t_A13() {
  local d
  d=$(standin a13 outside)
  fx "$d" Fx '' '' "$CLEAN_SRC"
  mkdir -p "$OUTSIDE/empty-packages"
  ENVV=(DOMENT_QA=1 "DARKRAISE_FRAMEWORK_PATH=$FRAMEWORK" "NUGET_PACKAGES=$OUTSIDE/empty-packages")
  case_ "tool not restored"
  run "$d/src/Fx" 600 dotnet build -nologo -tl:off
  [[ $RC -ne 0 ]] || note "the build passed with the tool not restored"
  has 'error DOMENT032'
  has 'run dotnet tool restore'
}

t_A14() {
  local d
  d=$(standin a14 outside)
  fx_env
  (cd "$d" && env "${ENVV[@]}" timeout 120 dotnet tool restore > /dev/null 2>&1) || note "dotnet tool restore failed in the stand-in"
  fx "$d" Own '<DomentFormatCheck>false</DomentFormatCheck>
    <DomentPlatform>linux</DomentPlatform>' '' 'using System.Runtime.InteropServices;

namespace Fx;   public static class Probe
{
    [DllImport("libc", EntryPoint = "getpid")]
    public static extern int GetPid();
}'
  case_ "own-file properties change nothing"
  run "$d/src/Own" 600 dotnet build -nologo -tl:off
  [[ $RC -ne 0 ]] || note "built"
  has 'error DOMENT031'
  has 'error DOMENT033'
  case_ "-p:DomentFormatCheck=false skips only the format check"
  run "$d/src/Own" 600 dotnet build -nologo -tl:off -p:DomentFormatCheck=false
  [[ $RC -ne 0 ]] || note "built"
  hasnt 'error DOMENT031'
  has 'error DOMENT033'
  fx "$d" NoWarn '<NoWarn>$(NoWarn);CA1416</NoWarn>' '' "$REG_SRC"
  case_ "NoWarn CA1416 in the project file still fails"
  run "$d/src/NoWarn" 600 dotnet build -nologo -tl:off -p:DomentFormatCheck=false
  [[ $RC -ne 0 ]] || note "built"
  has 'error CA1416'
}

t_A15() {
  local p sim=Doment.Simulation
  for p in Cli Agent; do
    case_ "Doment.$p without the property"
    local json
    json=$(msb "$REPO_ROOT" "$(proj_path "$p")" -getItem:ProjectReference -getProperty:DefineConstants)
    jq -r '(.Items.ProjectReference // [])[].Filename' <<<"$json" | grep -qx "$sim" && note "$sim is referenced without the property"
    jq -r '.Properties.DefineConstants' <<<"$json" | tr ';' '\n' | grep -qx DOMENT_SIMULATION && note "DOMENT_SIMULATION defined without the property"
    case_ "Doment.$p with -p:DomentSimulation=true"
    json=$(msb "$REPO_ROOT" "$(proj_path "$p")" -getItem:ProjectReference -getProperty:DefineConstants -p:DomentSimulation=true)
    jq -r '(.Items.ProjectReference // [])[].Filename' <<<"$json" | grep -qx "$sim" || note "$sim is not referenced with the property"
    jq -r '.Properties.DefineConstants' <<<"$json" | tr ';' '\n' | grep -qx DOMENT_SIMULATION || note "DOMENT_SIMULATION is not defined with the property"
  done
}

t_A16() {
  local p
  fx_env
  for p in Cli Agent; do
    case_ "release publish of Doment.$p with the property"
    run "$REPO_ROOT" 1500 dotnet publish "$(proj_path "$p")" -c Release -p:DomentSimulation=true -o "$OUTSIDE/pub-$p" "${DN_FLAGS[@]}"
    [[ $RC -ne 0 ]] || note "the publish succeeded"
    has 'error DOMENT030'
    has 'cannot include Doment\.Simulation'
    case_ "debug publish of Doment.$p with the property"
    run "$REPO_ROOT" 1500 dotnet publish "$(proj_path "$p")" -c Debug -p:DomentSimulation=true -o "$OUTSIDE/pubd-$p" "${DN_FLAGS[@]}"
    rc_is 0
    hasnt 'DOMENT030'
  done
  case_ "release publish of a fixture that references Doment.Simulation"
  local d
  d=$(standin a16 outside)
  fx "$d" Doment.Simulation '' '' "$CLEAN_SRC"
  fx "$d" Fx '<OutputType>Exe</OutputType>' '<ItemGroup><ProjectReference Include="../Doment.Simulation/Doment.Simulation.csproj" /></ItemGroup>' 'System.Console.WriteLine(1);'
  mv "$d/src/Fx/Probe.cs" "$d/src/Fx/Program.cs"
  run "$d/src/Fx" 900 dotnet publish -c Release -p:DomentFormatCheck=false -o "$OUTSIDE/pub-fx" "${DN_FLAGS[@]}"
  [[ $RC -ne 0 ]] || note "the publish succeeded"
  has 'error DOMENT030'
}

t_A17() {
  case_ "check.sh test"
  run "$REPO_ROOT" 900 bash build/check.sh test
  rc_is 0
  has '^check: test ok$'
  case_ "test executable"
  local exe=$REPO_ROOT/tests/Doment.Core.Tests/bin/Release/net10.0/Doment.Core.Tests
  [[ -x $exe ]] || { note "no test executable at $exe"; return 0; }
  ENVV=(DOMENT_QA=1 "DOTNET_ROOT=/usr/local/share/dotnet")
  run "$REPO_ROOT" 300 "$exe" --list-tests
  rc_is 0
  has -i 'Version'
  run "$REPO_ROOT" 300 "$exe"
  rc_is 0
  has 'Microsoft\.Testing\.Platform|xUnit\.net v3'
  has 'failed: 0|0 failed'
  local rt
  rt=$(grep -Eo '\.NET 10\.0\.[0-9]+|\.NET [0-9]+\.[0-9]+\.[0-9]+' <<<"$OUT" | head -n 1 | sed 's/^\.NET //')
  [[ -n $rt ]] && version_at_least "$rt" 10.0.14 || note "the test executable does not report a runtime of 10.0.14 or later (reported '$rt'): $(head -n 4 <<<"$OUT")"
}

t_A18() {
  full_check
  case_ "full check"
  OUT=$FULL_OUT RC=$FULL_RC
  rc_is 0
  local s order
  for s in build portable aot test; do count_is "^check: $s ok\$" 1; done
  order=$(grep -E '^check: (build|portable|aot|test) ok$' <<<"$OUT" | sed -E 's/^check: ([a-z]+) ok$/\1/' | paste -sd' ')
  eq "$order" "build portable aot test" "step order"
  has '^check: 4 steps run, 0 failed$'
  case_ "absent framework"
  # /nonexistent exists on some hosts, so the absent path is one under this test's own temporary directory.
  ENVV=(DOMENT_QA=1 "DARKRAISE_FRAMEWORK_PATH=$OUTSIDE/no-such-framework")
  run "$REPO_ROOT" 900 bash build/check.sh
  rc_is 1
  has '^check: build failed$'
  has 'DOMENT003'
  hasnt '^check: (portable|aot|test)'
  hasnt '^check: (portable|aot|test) ok$'
  case_ "unknown step"
  ENVV=(DOMENT_QA=1)
  run "$REPO_ROOT" 120 bash build/check.sh bogus
  rc_is 2
}

qa_procs() { # PIDs whose environment holds the marker $1
  local e p
  for e in /proc/[0-9]*/environ; do
    p=${e#/proc/}
    p=${p%/environ}
    [[ $p == "$$" || $p == "$BASHPID" ]] && continue
    tr '\0' '\n' < "$e" 2>/dev/null | grep -qx "QA_MARK=$1" && echo "$p"
  done
}

t_A19() {
  local d mark pids
  d=$(standin a19 outside)
  fx "$d" Fx '' '' "$CLEAN_SRC"
  printf '<Solution>\n  <Folder Name="/src/">\n    <Project Path="src/Fx/Fx.csproj" />\n  </Folder>\n</Solution>\n' > "$d/doment.slnx"
  mark=a19-timeout-$$
  case_ "after a timeout"
  ENVV=(DOMENT_QA=1 "QA_MARK=$mark" "DARKRAISE_FRAMEWORK_PATH=$FRAMEWORK" DOMENT_CHECK_TIMEOUT=1)
  run "$d" 300 bash build/check.sh build
  rc_is 1
  has 'timed out after 1 s'
  sleep 3
  pids=$(qa_procs "$mark" | paste -sd' ')
  [[ -z $pids ]] || note "processes left after the timeout: $(ps -o pid,args -p "${pids// /,}" | cut -c1-200)"
  case_ "after SIGTERM during the build step"
  mark=a19-term-$$
  mkdir -p "$d/obj-clean"
  rm -rf "$d/src/Fx/obj" "$d/src/Fx/bin"
  (cd "$d" && env DOMENT_QA=1 "QA_MARK=$mark" "DARKRAISE_FRAMEWORK_PATH=$FRAMEWORK" bash build/check.sh build > "$OUTSIDE/a19-term.out" 2>&1) &
  local sub=$! i seen=0
  for i in $(seq 1 60); do
    [[ $(qa_procs "$mark" | wc -l) -ge 3 ]] && { seen=1; break; }
    sleep 0.25
  done
  [[ $seen -eq 1 ]] || note "the build step never started helper processes"
  local cs
  cs=$(pgrep -P "$sub" -f 'check.sh' | head -n 1)
  [[ -n $cs ]] || cs=$(qa_procs "$mark" | while read -r q; do tr '\0' ' ' < "/proc/$q/cmdline" | grep -q 'build/check.sh' && echo "$q"; done | head -n 1)
  [[ -n $cs ]] && kill -TERM "$cs" 2>/dev/null
  wait "$sub" 2>/dev/null
  sleep 5
  pids=$(qa_procs "$mark" | paste -sd' ')
  [[ -z $pids ]] || note "processes left after SIGTERM: $(ps -o pid,args -p "${pids// /,}" | cut -c1-200)"
  case_ "after the full check"
  if [[ -n ${ACCEPT_CHECK_MARK:-} ]]; then
    pids=$(qa_procs "$ACCEPT_CHECK_MARK" | paste -sd' ')
    [[ -z $pids ]] || note "processes left after the full check: $pids"
  fi
}

t_A20() {
  case_ "gate on the repository"
  run "$REPO_ROOT" 900 bash build/gate.sh
  rc_is 0
  has ' 0 violations$'
  case_ "platform-packages rows added by this epic"
  local base rows row id n=0
  base=$(git -C "$REPO_ROOT" merge-base HEAD master) || { note "no merge base with master"; return 0; }
  rows=$(git -C "$REPO_ROOT" diff "$base" HEAD -- docs/third-party-exceptions.md | grep -E '^\+\| *`' || true)
  while IFS= read -r row; do
    [[ -n $row ]] || continue
    n=$((n + 1))
    id=$(sed -E 's/^\+\| *`([^`]+)`.*/\1/' <<<"$row")
    grep -Eqi '\.NET SDK' <<<"$row" || note "row for $id does not say the .NET SDK adds it"
    if grep -rqE "<PackageReference[^>]*Include=\"$id\"" "$REPO_ROOT/src" "$REPO_ROOT/tests/Doment.Core.Tests" --include='*.csproj'; then
      note "$id is a PackageReference of a doment project, not added by the SDK"
    fi
    grep -lq "\"$id/" "$REPO_ROOT"/src/*/obj/project.assets.json "$REPO_ROOT"/tests/Doment.Core.Tests/obj/project.assets.json 2>/dev/null ||
      note "$id is in no project's restore output"
  done <<<"$rows"
  [[ $n -ge 1 ]] || note "no platform-packages row was added by this epic"
}

t_A21() {
  case_ "tracked text files are LF in the index"
  OUT=$(git -C "$REPO_ROOT" ls-files --eol)
  hasnt '^i/(crlf|mixed) '
  count_is '^i/lf ' "$(grep -Ec '^i/lf ' <<<"$OUT")"
  case_ "eol attribute"
  OUT=$(git -C "$REPO_ROOT" check-attr eol -- x.sh x.cs x.csproj x.md build/darkraise-framework.pin)
  count_is ': eol: lf$' 5
  case_ "text attribute of the binary types"
  OUT=$(git -C "$REPO_ROOT" check-attr text -- x.dll x.exe x.so x.dylib x.a x.lib x.sys x.nupkg x.snupkg x.png x.jpg x.ico)
  count_is ': text: unset$' 12
}

# mkrepo <dir> [<branch>]: a git repository with one project, the checkout's build files and register, committed.
mkrepo() {
  local d=$1 f
  mkdir -p "$d/docs" "$d/src/Fx"
  for f in Directory.Build.props Directory.Build.targets global.json .editorconfig .csharpierrc .csharpierignore; do
    cp "$REPO_ROOT/$f" "$d/$f"
  done
  cp -r "$REPO_ROOT/build" "$REPO_ROOT/.config" "$d/"
  rm -rf "$d/build/obj" "$d/build/bin"
  cp "$REPO_ROOT/docs/third-party-exceptions.md" "$d/docs/"
  fx "$d" Fx '' '' "$CLEAN_SRC"
  git -C "$d" init -q -b "${2:-master}" || return 1
  git -C "$d" add -A && git -C "$d" commit -q -m init
}

t_A22() {
  local d
  d=$OUTSIDE/a22
  mkrepo "$d" master || die_setup "mkrepo"
  case_ "gate.sh has no DOMENT006 or DOMENT003 text of its own"
  OUT=$(grep -n 'DOMENT00[36]' "$REPO_ROOT/build/gate.sh" || true)
  [[ -z $OUT ]] || note "build/gate.sh mentions: $OUT"
  case_ "malformed pin"
  printf 'not-a-commit\n' > "$d/build/darkraise-framework.pin"
  git -C "$d" commit -q -am pin
  ENVV=(DOMENT_QA=1 "DARKRAISE_FRAMEWORK_PATH=$FRAMEWORK")
  run "$d" 900 bash build/gate.sh
  count_is 'DOMENT006' 1
  case_ "missing framework directory"
  cp "$REPO_ROOT/build/darkraise-framework.pin" "$d/build/darkraise-framework.pin"
  git -C "$d" commit -q -am pin
  ENVV=(DOMENT_QA=1 "DARKRAISE_FRAMEWORK_PATH=$OUTSIDE/missing-framework")
  run "$d" 900 bash build/gate.sh
  count_is 'DOMENT003' 1
}
die_setup() { echo "SETUP ERROR: $1" >&2; exit 99; }

t_A23() {
  local d
  d="$OUTSIDE/p&<' x"
  mkrepo "$d" master || die_setup "mkrepo"
  case_ "path with & < ' and a space"
  ENVV=(DOMENT_QA=1 "DARKRAISE_FRAMEWORK_PATH=$FRAMEWORK")
  run "$REPO_ROOT" 900 bash build/gate.sh "$d"
  [[ $RC -eq 0 ]] || note "the gate exited $RC; output: $(tail_out)"
  has ' 0 violations$'
  local c b
  for c in ';' '%' '$' '@' '"' ','; do
    case_ "path with $c"
    b="$OUTSIDE/bad${c}tree"
    mkdir -p "$b"
    git -C "$b" init -q
    run "$REPO_ROOT" 120 bash build/gate.sh "$b"
    rc_is 2
    has "'${c//\\/\\\\}'"
    has 'MSBuild cannot take'
  done
}

t_A24() {
  local d outer bin real log
  d=$OUTSIDE/a24
  mkrepo "$d" master || die_setup "mkrepo"
  outer=$OUTSIDE/outer
  mkdir -p "$outer/fw"
  git -C "$outer" init -q -b master
  printf 'x\n' > "$outer/fw/file.txt"
  git -C "$outer" add -A && git -C "$outer" commit -q -m init
  bin=$OUTSIDE/gitwrap
  mkdir -p "$bin"
  real=$(command -v git)
  log=$OUTSIDE/git-calls.log
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nif [[ " $* " == *" ls-files "* && -n ${FAIL_LSFILES:-} ]]; then\n  n=$(cat "%s.n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "%s.n"\n  [[ $n -eq $FAIL_LSFILES ]] && { echo "git: injected failure" >&2; exit 1; }\nfi\nexec "%s" "$@"\n' \
    "$log" "$log" "$log" "$real" > "$bin/git"
  chmod +x "$bin/git"
  case_ "framework path is a plain directory in another repository"
  : > "$log"
  ENVV=(DOMENT_QA=1 "PATH=$bin:$PATH" "DARKRAISE_FRAMEWORK_PATH=$outer/fw")
  run "$d" 900 bash build/gate.sh
  has 'DOMENT002'
  hasnt 'DOMENT005'
  ! grep -Eq ' fetch( |$)' "$log" || note "the gate ran git fetch: $(grep -E ' fetch' "$log" | head -n 2)"
  local n
  for n in 1 2 3; do
    case_ "ls-files call $n fails"
    rm -f "$log.n"
    ENVV=(DOMENT_QA=1 "PATH=$bin:$PATH" "FAIL_LSFILES=$n" "DARKRAISE_FRAMEWORK_PATH=$FRAMEWORK")
    run "$d" 900 bash build/gate.sh
    rc_is 1
    has "gate: git ls-files failed in .*a24"
  done
}

t_A25() {
  case_ "tests/build/run.sh"
  run "$REPO_ROOT" 2400 bash tests/build/run.sh
  rc_is 0
  case_ "tests/build/architecture-decisions.acceptance.sh"
  run "$REPO_ROOT" 2400 bash tests/build/architecture-decisions.acceptance.sh
  rc_is 0
}

t_A27() {
  local d
  d=$(standin a27 inside)
  printf '<Solution>\n  <Folder Name="/src/">\n    <Project Path="src/Fx/Fx.csproj" />\n  </Folder>\n</Solution>\n' > "$d/doment.slnx"
  fx "$d" Fx '' '<ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="12.0.1" />
  </ItemGroup>' "$CLEAN_SRC"
  local row
  row='| X9 | Newtonsoft.Json | `Newtonsoft.Json` | Acceptance A27 | Known-vulnerable stand-in | MIT | - | - | 2026-11-24 |'
  sed -i "/^| X2 |/a $row" "$d/docs/third-party-exceptions.md"
  fx_env
  case_ "plain build warns"
  dn "$d" build doment.slnx
  rc_is 0
  has 'warning NU190[1-4]'
  case_ "check.sh build fails naming the advisory"
  run "$d" 1500 bash build/check.sh build
  rc_is 1
  has '^check: build failed$'
  has 'NU190[1-4].*GHSA-|GHSA-.*NU190[1-4]'
}

t_A28() {
  case_ "DomentPlatform equals the module map's Kind"
  local name kind val short
  while IFS='|' read -r _ name _ _ kind _; do
    name=$(tr -d '` ' <<<"$name")
    kind=$(tr -d ' ' <<<"$kind")
    [[ $name == Doment.* ]] || continue
    short=${name#Doment.}
    [[ -f $REPO_ROOT/src/$name/$name.csproj ]] || continue
    val=$(msb "$REPO_ROOT" "src/$name/$name.csproj" -getProperty:DomentPlatform | tail -n 1)
    local want
    case $kind in Linux-bound) want=linux ;; Windows-bound) want=windows ;; portable) want=portable ;; *) want=? ;; esac
    eq "$val" "$want" "DomentPlatform of $name (Kind $kind)"
  done < <(sed -n '/^| Project | Holds/,/^$/p' "$REPO_ROOT/docs/architecture.md" | tail -n +3)
  val=$(msb "$REPO_ROOT" "$(proj_path Core.Tests)" -getProperty:DomentPlatform | tail -n 1)
  eq "$val" portable "DomentPlatform of Doment.Core.Tests"
  local linux=0 p
  for p in "${projects_all[@]}" Core.Tests; do
    [[ $(msb "$REPO_ROOT" "$(proj_path "$p")" -getProperty:DomentPlatform | tail -n 1) == linux ]] && linux=$((linux + 1)) && [[ $p != Agent ]] && note "Doment.$p is linux"
  done
  eq "$linux" 1 "number of linux projects"
}

# ---------------------------------------------------------------------------

RESULT_FAIL=0
RESULT_PASS=0
for fn in $(declare -F | awk '{print $3}' | grep -E '^t_A[0-9]+$' | sort -t A -k2 -n); do
  n=${fn#t_}
  [[ -z $FILTER || $n =~ $FILTER ]] || continue
  FAILS=()
  CASE=
  "$fn"
  if [[ ${#FAILS[@]} -eq 0 ]]; then
    echo "ok   $n"
    RESULT_PASS=$((RESULT_PASS + 1))
  else
    echo "FAIL $n"
    printf '       %s\n' "${FAILS[@]}"
    RESULT_FAIL=$((RESULT_FAIL + 1))
  fi
done
echo "$RESULT_PASS passed, $RESULT_FAIL failed"
[[ $RESULT_FAIL -eq 0 ]]
