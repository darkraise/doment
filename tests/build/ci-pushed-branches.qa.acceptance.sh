#!/usr/bin/env bash
# Independent acceptance tests (A1 to A25 except A15) of the "CI for pushed branches" spec, written from the spec text.
# Usage: bash tests/build/ci-pushed-branches.qa.acceptance.sh [<extended regex on the test name>]
# The cases that read GitHub use read-only `gh api` GET calls; without a working `gh` they are skipped.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
FILTER=${1:-}
WF_DIR=$REPO_ROOT/.github/workflows
SLUG=darkraise/doment
FW_SLUG=darkraise/darkraise-framework

export MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_USE_MSBUILD_SERVER=0 UseSharedCompilation=false
export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 GIT_LFS_SKIP_SMUDGE=1
unset DARKRAISE_FRAMEWORK_PATH DARKRAISE_FRAMEWORK_REPO FrameworkPinStrict DOMENT_GATE_NO_FETCH DOMENT_GATE_PIN_ON_MASTER \
  DOMENT_CI_PIN_ON_MASTER DOMENT_CI_FRAMEWORK DOMENT_CI_ZLIB_INCLUDE DOMENT_CI_MIN_FREE_GB GITHUB_ACTIONS
export GIT_AUTHOR_NAME=qa GIT_AUTHOR_EMAIL=qa@doment.invalid GIT_COMMITTER_NAME=qa GIT_COMMITTER_EMAIL=qa@doment.invalid

S=$(mktemp -d "${TMPDIR:-/tmp}/doment-ci-qa.XXXXXX")
trap 'rm -rf "$S"' EXIT
trap 'exit 143' TERM INT

OUT=
RC=0
CASE=
FAILS=()
SKIPS=()

case_() { CASE=$1; }
note() { FAILS+=("[$CASE] $1"); }
skip_case() { SKIPS+=("[$CASE] skipped: $1"); }
tail_out() { tail -n 12 <<<"$OUT" | cut -c1-400; }
rc_is() { [[ $RC -eq $1 ]] || note "expected exit $1, got $RC; output: $(tail_out)"; }
has() { grep -Eq -- "$1" <<<"$OUT" || note "no output line matches /$1/; output: $(tail_out)"; }
hasnt() { ! grep -Eq -- "$1" <<<"$OUT" || note "an output line matches /$1/: $(grep -E -- "$1" <<<"$OUT" | head -n 2 | cut -c1-300)"; }
eq() { [[ $1 == "$2" ]] || note "expected '$2', got '$1' ($3)"; }

run() { # run <seconds> <command...>: sets OUT and RC
  local secs=$1
  shift
  OUT=$(timeout -k 10 "$secs" "$@" 2>&1) && RC=0 || RC=$?
}

# ---------------------------------------------------------------------------
# Workflow analysis (python3 with PyYAML); prints one `FAIL <text>` line per violation.

PY=$(
  cat <<'PYEOF'
import glob, json, os, re, sys, yaml

wf_dir, mode = sys.argv[1], sys.argv[2]
extra = sys.argv[3:]
fails = []
def fail(m): fails.append(m)

class N(dict):
    def __getattr__(self, k):
        v = self.get(k, '')
        return N(v) if isinstance(v, dict) else v

def mk(d): return N({k: (mk(v) if isinstance(v, dict) else v) for k, v in d.items()})

SAFE = re.compile(r"^[A-Za-z0-9_.'\-{} ()=!&|,/*:$]*$")
# The expressions come from the repository's own workflow files; the character allowlist and the empty
# builtins keep eval to the comparisons, &&, || and format() those files use.
def ev(expr, env):
    e = expr.strip()
    if not SAFE.match(e): raise ValueError('unsafe expression: ' + e)
    e = e.replace('&&', ' and ').replace('||', ' or ')
    e = re.sub(r'!(?!=)', ' not ', e)
    scope = {'format': lambda f, *a: f.format(*a), 'true': True, 'false': False, 'null': ''}
    scope.update({k: mk(v) for k, v in env.items()})
    return eval(e, {'__builtins__': {}}, scope)

def interp(s, env):
    if not isinstance(s, str): return s
    def sub(m):
        v = ev(m.group(1), env)
        return str(v).lower() if isinstance(v, bool) else str(v)
    return re.sub(r'\$\{\{(.*?)\}\}', sub, s)

def cond(s, env):
    s = str(s).strip()
    m = re.fullmatch(r'\$\{\{(.*)\}\}', s)
    return bool(ev(m.group(1) if m else s, env))

def load():
    out = {}
    for p in sorted(glob.glob(os.path.join(wf_dir, '*.yml')) + glob.glob(os.path.join(wf_dir, '*.yaml'))):
        with open(p) as f: out[os.path.basename(p)] = yaml.safe_load(f)
    return out

def triggers(w):
    t = w.get(True, w.get('on'))
    if t is None: return None
    if isinstance(t, str): return {t: None}
    if isinstance(t, list): return {k: None for k in t}
    return t

def steps_of(w):
    for jn, j in (w.get('jobs') or {}).items():
        for i, s in enumerate(j.get('steps') or []): yield jn, i, s

def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            yield k, v
            yield from walk(v)
    elif isinstance(o, list):
        for v in o: yield from walk(v)

wfs = load()
if not wfs: fail('no workflow file in ' + wf_dir)

if mode == 'on':
    for name, w in wfs.items():
        t = triggers(w)
        if t is None: fail(name + ': no on:'); continue
        extras = set(t) - {'push', 'pull_request', 'workflow_dispatch'}
        if extras: fail(name + ': on: declares ' + ','.join(sorted(extras)))
    ci = wfs.get('ci.yml')
    if ci is None: fail('ci.yml is missing')
    else:
        t = triggers(ci) or {}
        for k in ('push', 'pull_request', 'workflow_dispatch'):
            if k not in t: fail('ci.yml does not declare ' + k)
        push = t.get('push') or {}
        if push.get('branches') != ['**']: fail('ci.yml push branches is %r, not ["**"]' % (push.get('branches'),))
        if 'tags' in push or 'branches-ignore' in push or 'paths' in push or 'paths-ignore' in push:
            fail('ci.yml push is filtered by tags or paths')
        if (t.get('pull_request') or {}).get('branches') != ['master']: fail('ci.yml pull_request branches is not [master]')
    base = {'github': {'repository': 'darkraise/doment', 'event_name': 'pull_request',
                        'event': {'pull_request': {'head': {'repo': {'full_name': 'evil/doment'}}}}}}
    for name, w in wfs.items():
        t = triggers(w) or {}
        for jn, j in (w.get('jobs') or {}).items():
            c = j.get('if')
            if 'pull_request' in t and c is None:
                fail('%s: job %s runs for a pull request with no if:' % (name, jn)); continue
            if c is None: continue
            def at(ev_name, head):
                e = {'github': {'repository': 'darkraise/doment', 'event_name': ev_name,
                                'event': {'pull_request': {'head': {'repo': {'full_name': head}}}}}}
                return cond(c, e)
            try:
                if at('pull_request', 'evil/doment'): fail('%s: job %s is not skipped for a fork pull request' % (name, jn))
                if not at('pull_request', 'darkraise/doment'): fail('%s: job %s is skipped for a same-repository pull request' % (name, jn))
                if not at('push', ''): fail('%s: job %s is skipped for a push' % (name, jn))
                if not at('workflow_dispatch', ''): fail('%s: job %s is skipped for workflow_dispatch' % (name, jn))
            except Exception as ex:
                fail('%s: job %s if: cannot be evaluated: %s' % (name, jn, ex))

elif mode == 'runs-on-uses':
    for name, w in wfs.items():
        for jn, j in (w.get('jobs') or {}).items():
            ro = j.get('runs-on')
            labels = ro if isinstance(ro, list) else [ro]
            for l in labels:
                if not isinstance(l, str): fail('%s: job %s runs-on has a non-string entry %r' % (name, jn, l)); continue
                if re.match(r'^(ubuntu|windows|macos)-', l, re.I): fail('%s: job %s runs on GitHub-hosted %s' % (name, jn, l))
                if '${{' in l: fail('%s: job %s runs-on is an expression: %s' % (name, jn, l))
            if ro is None: fail('%s: job %s has no runs-on' % (name, jn))
            elif 'self-hosted' not in labels or 'doment-linux' not in labels:
                fail('%s: job %s runs-on %r lacks self-hosted or doment-linux' % (name, jn, ro))
        n = 0
        for k, v in walk(w):
            if k != 'uses': continue
            n += 1
            if not re.fullmatch(r'actions/[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)?@[0-9a-f]{40}', str(v)):
                fail('%s: uses %s is not an actions/* action at a 40-character commit SHA' % (name, v))
        if name == 'ci.yml' and n == 0: fail('ci.yml has no uses: at all')

elif mode == 'secrets':
    names = []
    for name in sorted(os.listdir(wf_dir)):
        txt = open(os.path.join(wf_dir, name)).read()
        for m in re.finditer(r'secrets\s*(\.\s*[A-Za-z0-9_]+|\[|\s*:\s*inherit)', txt): names.append((name, m.group(0)))
        if re.search(r'toJSON\(\s*secrets', txt): fail(name + ': toJSON(secrets)')
    if [n for n in names if n[1].replace(' ', '') != 'secrets.DARKRAISE_FRAMEWORK_DEPLOY_KEY']: fail('other secret references: %r' % names)
    if len(names) != 1: fail('expected exactly one secret reference, found %d: %r' % (len(names), names))
    ci = wfs['ci.yml']
    holders = [(jn, i, s) for jn, i, s in steps_of(ci) if re.search(r'secrets\W', json.dumps(s))]
    if len(holders) != 1: fail('the secret is in %d steps' % len(holders))
    else:
        s = holders[0][2]
        if not str(s.get('uses', '')).startswith('actions/checkout@') or (s.get('with') or {}).get('repository') != 'darkraise/darkraise-framework':
            fail('the secret is not in the framework checkout step: %s' % s.get('name'))
        if not isinstance(s.get('with', {}).get('ssh-key'), str) or 'DARKRAISE_FRAMEWORK_DEPLOY_KEY' not in s['with']['ssh-key']:
            fail('the secret is not the checkout step\'s ssh-key')
    for name, w in wfs.items():
        if w.get('permissions') != {'contents': 'read'}: fail('%s: top-level permissions is %r, not {contents: read}' % (name, w.get('permissions')))
        for jn, j in (w.get('jobs') or {}).items():
            if 'permissions' in j and j['permissions'] != {'contents': 'read'}: fail('%s: job %s permissions is %r' % (name, jn, j['permissions']))

elif mode == 'pin-env':
    ci = wfs['ci.yml']
    j = next(iter(ci['jobs'].values()))
    step = [s for s in j['steps'] if 'Run' in str(s.get('name', '')) and 'env' in s]
    if len(step) != 1: fail('expected one run step with env, found %d' % len(step))
    else:
        raw = step[0]['env'].get('DOMENT_CI_PIN_ON_MASTER')
        if raw is None: fail('DOMENT_CI_PIN_ON_MASTER is not set on the run step')
        else:
            def val(suite, event, ref, base):
                e = {'matrix': {'suite': suite}, 'github': {'event_name': event, 'ref': ref, 'base_ref': base}}
                return interp(raw, e)
            for suite in ('check',):
                exp = [('push', 'refs/heads/master', '', '1'), ('pull_request', 'refs/pull/7/merge', 'master', '1'),
                       ('push', 'refs/heads/feature', '', '0'), ('push', 'refs/heads/master-2', '', '0'),
                       ('workflow_dispatch', 'refs/heads/master', '', '0'), ('workflow_dispatch', 'refs/heads/feature', '', '0'),
                       ('pull_request', 'refs/pull/7/merge', 'main', '0'), ('pull_request', 'refs/pull/7/merge', 'feature', '0')]
                for event, ref, base, want in exp:
                    got = val(suite, event, ref, base)
                    if got != want: fail('check entry, %s %s base %r: DOMENT_CI_PIN_ON_MASTER is %r, want %r' % (event, ref, base, got, want))
            for event, ref, base in (('push', 'refs/heads/master', ''), ('pull_request', 'refs/pull/7/merge', 'master')):
                got = val('acceptance', event, ref, base)
                if got == '1': fail('acceptance entry gets DOMENT_CI_PIN_ON_MASTER=1 for %s' % event)
    for jn, j in ci['jobs'].items():
        if 'DOMENT_GATE_PIN_ON_MASTER' in json.dumps(j): fail('job %s names DOMENT_GATE_PIN_ON_MASTER' % jn)
    if 'DOMENT_GATE_PIN_ON_MASTER' in json.dumps({k: v for k, v in ci.items() if k != 'jobs'}): fail('workflow-level env names DOMENT_GATE_PIN_ON_MASTER')

elif mode == 'concurrency':
    ci = wfs['ci.yml']
    c = ci.get('concurrency')
    if not isinstance(c, dict): fail('no concurrency block'); c = {}
    if c.get('cancel-in-progress') is not True: fail('cancel-in-progress is %r' % (c.get('cancel-in-progress'),))
    grp = c.get('group', '')
    def g(event, ref, rid):
        return interp(grp, {'github': {'event_name': event, 'ref': ref, 'run_id': rid, 'run_number': rid}})
    if g('push', 'refs/heads/feat', '1') != g('push', 'refs/heads/feat', '2'): fail('two pushes to one branch are in different groups')
    if g('push', 'refs/heads/feat', '1') == g('push', 'refs/heads/other', '1'): fail('two branches share a group')
    if g('push', 'refs/heads/master', '1') == g('push', 'refs/heads/master', '2'): fail('two master pushes share a group')
    if g('push', 'refs/heads/master', '1') == g('pull_request', 'refs/heads/master', '1'): fail('a master push and a master pull request share a group')
    for rid in ('1', '2', '3'):
        for evn in ('push', 'pull_request', 'workflow_dispatch'):
            gm = g(evn, 'refs/heads/master', rid)
            others = [g(e2, r2, r3) for e2 in ('push', 'pull_request', 'workflow_dispatch') for r2 in ('refs/heads/master', 'refs/heads/feat', 'refs/pull/3/merge') for r3 in ('1', '2', '3') if (e2, r2, r3) != (evn, 'refs/heads/master', rid)]
            if gm in others: fail('master %s run %s shares its group %r with another run' % (evn, rid, gm))

elif mode == 'before-checkout':
    ci = wfs['ci.yml']
    steps = next(iter(ci['jobs'].values()))['steps']
    idx = [i for i, s in enumerate(steps) if s.get('id') == 'framework' or ((s.get('with') or {}).get('repository') == 'darkraise/darkraise-framework')]
    if len(idx) != 1: fail('expected one framework checkout step, found %d' % len(idx))
    else:
        bad = re.compile(r'(\./|(^|[;&|(`]\s*)\.\s+\S|\bsource\b|\bexec\b|\b(bash|sh|zsh|dash|python3?|node|dotnet|make|pwsh|perl|ruby|npm|npx|cargo|go|java)\b|\b(build|tools|tests|src)/[^\s"\']*\.(sh|ps1|py|cs|csproj|targets|props|js|rb|pl)\b|\bbuild/ci\b)')
        for s in steps[:idx[0]]:
            u = str(s.get('uses', ''))
            if u.startswith('./') or u.startswith('docker:'): fail('step %r uses %s from the tree' % (s.get('name'), u))
            r = s.get('run')
            if r:
                for line in r.splitlines():
                    if bad.search(line): fail('step %r runs tree code or a script interpreter: %s' % (s.get('name'), line.strip()))
            if 'script' in (s.get('with') or {}): fail('step %r runs an inline script' % s.get('name'))
            if s.get('shell') and str(s['shell']) not in ('bash',): fail('step %r has an unusual shell' % s.get('name'))
        if idx[0] == 0: fail('no step before the framework checkout')

elif mode == 'shape':
    ci = wfs['ci.yml']
    j = ci['jobs']
    if len(j) != 1: fail('expected one job, found %r' % list(j))
    b = next(iter(j.values()), {})
    if (b.get('strategy') or {}).get('matrix') != {'suite': ['check', 'acceptance']}: fail('matrix is %r' % ((b.get('strategy') or {}).get('matrix'),))
    if b.get('name') != '${{ matrix.suite }}': fail('job name is %r' % (b.get('name'),))
    if ci.get('name') != 'CI': fail('workflow name is %r' % (ci.get('name'),))
    steps = b.get('steps', [])
    for s in steps:
        if 'matrix' in str(s.get('if', '')): fail('step %r runs for one matrix entry only' % s.get('name'))
    fw = [s for s in steps if (s.get('with') or {}).get('repository') == 'darkraise/darkraise-framework']
    if len(fw) != 1: fail('expected one framework checkout step')
    else:
        w = fw[0]['with']
        if w.get('path') != 'external/darkraise-framework': fail('framework path is %r' % w.get('path'))
        if w.get('lfs') is not False: fail('framework checkout has lfs %r' % w.get('lfs'))
        m = re.fullmatch(r'\$\{\{\s*steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)\s*\}\}', str(w.get('ref')))
        if not m: fail('framework ref is %r, not a step output' % w.get('ref'))
        else:
            src = [s for s in steps if s.get('id') == m.group(1)]
            if len(src) != 1 or 'build/darkraise-framework.pin' not in str(src[0].get('run')): fail('the ref step does not read build/darkraise-framework.pin')
            elif 'GITHUB_OUTPUT' not in src[0]['run']: fail('the pin step writes no step output')
        if str((fw[0].get('env') or {}).get('GIT_LFS_SKIP_SMUDGE')) != '1': fail('GIT_LFS_SKIP_SMUDGE is not 1 on the framework checkout')
    names = [str(s.get('run', '')) for s in steps]
    joined = '\n'.join(names)
    if 'dotnet tool restore' not in joined: fail('no dotnet tool restore')
    if 'dotnet --version' not in joined: fail('no dotnet --version')
    if not any('actions/setup-dotnet@' in str(s.get('uses', '')) and (s.get('with') or {}).get('global-json-file') == 'global.json' for s in steps):
        fail('no setup-dotnet with global-json-file: global.json')
    last = steps[-1] if steps else {}
    if not re.search(r'build/ci\.sh\s+\$\{\{\s*matrix\.suite\s*\}\}', str(last.get('run'))): fail('the last step does not run build/ci.sh <suite>: %r' % last.get('run'))
    pos = {k: [i for i, r in enumerate(names) if k in r] for k in ('dotnet tool restore', 'build/ci.sh verify')}
    fwi = steps.index(fw[0]) if fw else 99
    if not pos['build/ci.sh verify'] or pos['build/ci.sh verify'][0] <= fwi: fail('verify does not run after the framework checkout')

print('\n'.join('FAIL ' + f for f in fails))
PYEOF
)

wf() { # wf <mode> [<workflow dir>]: runs one analysis; each violation becomes a note
  local out
  out=$(python3 -I -c "$PY" "${2:-$WF_DIR}" "$1" 2>&1) || { note "analysis crashed: $out"; return 0; }
  [[ -z $out ]] || while IFS= read -r l; do note "$l"; done <<<"$out"
}

# ---------------------------------------------------------------------------
# GitHub (read-only)

GH_OK=
gh_ok() {
  if [[ -z $GH_OK ]]; then
    if timeout 60 gh api "repos/$SLUG" --jq .full_name > /dev/null 2>&1; then GH_OK=1; else GH_OK=0; fi
  fi
  [[ $GH_OK == 1 ]]
}
gh_get() { timeout 120 gh api "$@" 2>/dev/null; }

RUNS_JSON=
runs_json() {
  [[ -n $RUNS_JSON ]] || RUNS_JSON=$(gh_get "repos/$SLUG/actions/runs?per_page=100" --jq '[.workflow_runs[] | select(.name == "CI") | {id, event, branch: .head_branch, sha: .head_sha, conclusion, status, head_repo: .head_repository.full_name, repo: .repository.full_name, path}]')
  [[ -n $RUNS_JSON ]]
}
jobs_of() { gh_get "repos/$SLUG/actions/runs/$1/jobs" --jq '[.jobs[] | {id, name, conclusion, labels, runner_name, steps: [.steps[] | {name, conclusion}]}]'; }
job_log() { gh_get "repos/$SLUG/actions/jobs/$1/logs"; }
pin_at() { gh_get "repos/$SLUG/contents/build/darkraise-framework.pin?ref=$1" --jq .content | base64 -d | tr -d '\r\n '; }

# ---------------------------------------------------------------------------
# Stand-in trees

mk_tree() { # mk_tree <dir>: a tree holding a copy of build/ci.sh
  mkdir -p "$1/build" "$1/tests/build"
  cp "$REPO_ROOT/build/ci.sh" "$1/build/ci.sh"
}

stand_in() { # stand_in <path> <exit code> [<echo line>]: a script that logs its name and exits
  local path=$1 rc=$2
  cat > "$path" <<EOF
#!/usr/bin/env bash
echo "\$(basename "\$0") rc=$rc gatevar=\${DOMENT_GATE_PIN_ON_MASTER-unset} nofetch=\${DOMENT_GATE_NO_FETCH-unset}" >> "\$QA_LOG"
echo "stand-in \$(basename "\$0") ran"
exit $rc
EOF
}

mk_fw() { # mk_fw <dir>: a clean stand-in framework repository
  git init -q "$1"
  echo content > "$1/a.txt"
  git -C "$1" add a.txt
  git -C "$1" commit -qm first
}

VERIFY_ENV=()
verify_run() { # verify_run <tree> <framework> [VAR=value...]
  local tree=$1 fw=$2
  shift 2
  mkdir -p "$S/zlib" "$S/rt"
  : > "$S/zlib/zlib.h"
  OUT=$(cd "$tree" && env DOMENT_CI_FRAMEWORK="$fw" DOMENT_CI_ZLIB_INCLUDE="$S/zlib" DOMENT_CI_MIN_FREE_GB=0 RUNNER_TEMP="$S/rt" "$@" \
    timeout -k 10 120 bash build/ci.sh verify 2>&1) && RC=0 || RC=$?
}

# ---------------------------------------------------------------------------
# The cases

t_A1() {
  case_ "workflow triggers and labels"
  wf on
  wf runs-on-uses
  wf shape
  [[ $(sed -n '1p' "$WF_DIR/ci.yml") == 'name: CI' ]] || note "ci.yml does not start with name: CI"
  case_ "pushed runs"
  gh_ok || { skip_case "no GitHub access"; return 0; }
  runs_json || { skip_case "cannot list runs"; return 0; }
  local ids branches id
  ids=$(jq -r '[.[] | select(.event == "push" and .branch != "master" and .repo == "'"$SLUG"'")] | .[].id' <<<"$RUNS_JSON")
  branches=$(jq -r '[.[] | select(.event == "push" and .branch != "master")] | map(.branch) | unique | length' <<<"$RUNS_JSON")
  [[ $branches -ge 2 ]] || note "pushes to $branches distinct non-master branches started CI, expected at least 2"
  local checked=0 jobs
  for id in $ids; do
    jobs=$(jobs_of "$id")
    [[ -n $jobs ]] || continue
    [[ $(jq -r 'map(select(.name == "check" or .name == "acceptance")) | length' <<<"$jobs") -gt 0 ]] || continue
    checked=$((checked + 1))
    eq "$(jq -r 'map(.name) | sort | join(",")' <<<"$jobs")" "acceptance,check" "jobs of push run $id"
    eq "$(jq -r 'map(select((.labels | index("self-hosted")) and (.labels | index("doment-linux")))) | length' <<<"$jobs")" 2 "jobs of run $id on self-hosted and doment-linux"
    eq "$(jq -r 'map(select(.runner_name != null and .runner_name != "")) | length' <<<"$jobs")" 2 "jobs of run $id that a runner took"
  done
  [[ $checked -ge 2 ]] || note "only $checked push runs on non-master branches had readable jobs"
}

t_A2() {
  case_ "workflow steps"
  wf shape
  case_ "check.sh steps and gate by stand-in"
  grep -Eq '^ALL_STEPS=\(build portable aot test\)$' "$REPO_ROOT/build/check.sh" || note "build/check.sh does not list the four steps build portable aot test"
  grep -Eq '^10\.0\.404$|"version": "10\.0\.404"' "$REPO_ROOT/global.json" || note "global.json does not name SDK 10.0.404"
  local t=$S/a2 combo rc_check rc_gate want
  mk_tree "$t"
  export QA_LOG=$S/a2.log
  for combo in "0 0 0" "1 0 1" "0 1 1" "1 1 1"; do
    read -r rc_check rc_gate want <<<"$combo"
    : > "$QA_LOG"
    stand_in "$t/build/check.sh" "$rc_check"
    stand_in "$t/build/gate.sh" "$rc_gate"
    run 60 bash "$t/build/ci.sh" check
    rc_is "$want"
    eq "$(grep -c '^gate.sh ' "$QA_LOG")" 1 "gate runs once (check rc $rc_check, gate rc $rc_gate)"
    eq "$(grep -c '^check.sh ' "$QA_LOG")" 1 "check.sh runs once (check rc $rc_check, gate rc $rc_gate)"
  done
  case_ "pushed run logs"
  gh_ok && runs_json || { skip_case "no GitHub access"; return 0; }
  local id jobs jid log n
  id=$(jq -r '[.[] | select(.event == "push" and .branch != "master" and .conclusion == "success")][0].id // empty' <<<"$RUNS_JSON")
  [[ -n $id ]] || { note "no successful push run on a non-master branch"; return 0; }
  jobs=$(jobs_of "$id")
  jid=$(jq -r '.[] | select(.name == "check") | .id' <<<"$jobs")
  log=$(job_log "$jid")
  OUT=$log
  has 'check: dotnet 10\.0\.404 at '
  has 'Installed version is 10\.0\.404'
  has 'check: build ok$'
  has 'check: portable ok$'
  has 'check: aot ok$'
  has 'check: test ok$'
  has 'check: 4 steps run, 0 failed$'
  has 'gate: [0-9]+ projects checked, [0-9]+ packages seen, 0 violations$'
  n=$(grep -nE 'check: 4 steps run' <<<"$log" | head -n 1 | cut -d: -f1)
  [[ -n $n && $(grep -nE '^[^ ]+ gate: [0-9]+ projects checked' <<<"$log" | head -n 1 | cut -d: -f1) -gt $n ]] || note "the gate result does not follow the check.sh result"
  [[ $(jq -r '.[] | select(.name == "check") | .steps[] | select(.name == "Restore the local tools") | .conclusion' <<<"$jobs") == success ]] || note "the tool restore step did not succeed"
}

t_A3() {
  case_ "framework checkout in the workflow"
  wf shape
  case_ "strict pin build"
  grep -Fq 'FrameworkPinStrict=true' "$REPO_ROOT/build/check.sh" || note "build/check.sh does not build with FrameworkPinStrict=true"
  grep -Fq 'FrameworkPinStrict=true' "$REPO_ROOT/build/gate.sh" || note "build/gate.sh does not run with FrameworkPinStrict=true"
  case_ "pushed run logs"
  gh_ok && runs_json || { skip_case "no GitHub access"; return 0; }
  local id sha pin jobs jid log
  id=$(jq -r '[.[] | select(.event == "push" and .branch != "master" and .conclusion == "success")][0].id // empty' <<<"$RUNS_JSON")
  sha=$(jq -r '[.[] | select(.id == '"${id:-0}"')][0].sha // empty' <<<"$RUNS_JSON")
  [[ -n $id && -n $sha ]] || { note "no successful push run on a non-master branch"; return 0; }
  pin=$(pin_at "$sha")
  [[ $pin =~ ^[0-9a-f]{40}$ ]] || { note "cannot read the pin at $sha"; return 0; }
  jobs=$(jobs_of "$id")
  for jid in $(jq -r '.[].id' <<<"$jobs"); do
    log=$(job_log "$jid")
    OUT=$log
    has "darkraise/darkraise-framework"
    has "$pin"
    has 'external/darkraise-framework'
    has 'ci: verify ok$'
    hasnt 'LFS objects were downloaded'
  done
  eq "$(jq -r 'length' <<<"$jobs")" 2 "jobs of run $id"
}

t_A4() {
  local t=$S/a4 combo a b c
  mk_tree "$t"
  export QA_LOG=$S/a4.log
  stand_in "$t/tests/build/architecture-decisions.acceptance.sh" 0
  stand_in "$t/tests/build/run.sh" 0
  for combo in "0 0 0" "3 0 0" "0 4 0" "0 0 5" "3 4 5" "0 4 5"; do
    read -r a b c <<<"$combo"
    case_ "suites exit $a $b $c"
    : > "$QA_LOG"
    stand_in "$t/tests/build/repository-build.acceptance.sh" "$a"
    stand_in "$t/tests/build/repository-build-nativeaot.acceptance.sh" "$b"
    stand_in "$t/tests/build/ci-pushed-branches.acceptance.sh" "$c"
    (cd / && OUT=$(timeout -k 10 60 bash "$t/build/ci.sh" acceptance 2>&1) && RC=0 || RC=$?; echo "$RC" > "$S/a4.rc"; echo "$OUT" > "$S/a4.out")
    RC=$(<"$S/a4.rc")
    OUT=$(<"$S/a4.out")
    if [[ $a == 0 && $b == 0 && $c == 0 ]]; then rc_is 0; else rc_is 1; fi
    eq "$(cut -d' ' -f1 "$QA_LOG" | paste -sd,)" "repository-build.acceptance.sh,repository-build-nativeaot.acceptance.sh,ci-pushed-branches.acceptance.sh" "suites run, in order"
  done
  case_ "usage"
  run 30 bash "$t/build/ci.sh"
  rc_is 2
  run 30 bash "$t/build/ci.sh" bogus
  rc_is 2
}

# A clone of the repository at HEAD with its framework as a separate clone, for the cases that run the real gate.
CLONE=$S/clone
clone_ready=
make_clone() {
  [[ -n $clone_ready ]] && return 0
  local fw_src pin
  fw_src=$(dirname "$(git -C "$REPO_ROOT/external/darkraise-framework" rev-parse --path-format=absolute --git-common-dir)")
  pin=$(tr -d '\r\n ' < "$REPO_ROOT/build/darkraise-framework.pin")
  git clone -q --local --no-hardlinks "$REPO_ROOT" "$CLONE" || return 1
  git -C "$CLONE" checkout -q --detach "$(git -C "$REPO_ROOT" rev-parse HEAD)" || return 1
  git clone -q --local --no-hardlinks --no-checkout "$fw_src" "$CLONE/external/darkraise-framework" || return 1
  git -C "$CLONE/external/darkraise-framework" checkout -q --detach "$pin" || return 1
  git -C "$CLONE/external/darkraise-framework" merge-base --is-ancestor "$pin" refs/remotes/origin/master || return 1
  clone_ready=1
}

gate_in_clone() { # gate_in_clone [VAR=value...]: the gate on the clone, offline
  OUT=$(cd "$CLONE" && env DOMENT_GATE_NO_FETCH=1 "$@" timeout -k 10 1500 bash build/gate.sh "$CLONE" 2>&1) && RC=0 || RC=$?
}

t_A5() {
  case_ "stand-in clone"
  make_clone || { note "cannot build the stand-in clone"; return 0; }
  local fw=$CLONE/external/darkraise-framework old new
  old=$(git -C "$fw" rev-parse HEAD)
  git -C "$fw" checkout -q --detach
  git -C "$fw" commit -q --allow-empty -m "qa: a framework commit that is on no origin branch"
  new=$(git -C "$fw" rev-parse HEAD)
  git -C "$fw" merge-base --is-ancestor "$new" refs/remotes/origin/master && note "the stand-in pin is an ancestor of origin/master"
  echo "$new" > "$CLONE/build/darkraise-framework.pin"
  git -C "$CLONE" commit -q -am "qa: pin a framework commit that is on no origin branch"
  local re="^error DOMENT005: pin $new is not an ancestor of the framework's origin/master\$"
  case_ "valid pin passes with the variable on"
  git -C "$fw" checkout -q --detach "$old"
  echo "$old" > "$CLONE/build/darkraise-framework.pin"
  git -C "$CLONE" commit -q -am "qa: valid pin"
  git -C "$CLONE" switch -q -c qa-feature
  gate_in_clone DOMENT_GATE_PIN_ON_MASTER=1
  rc_is 0
  hasnt 'DOMENT005'
  git -C "$fw" checkout -q --detach "$new"
  echo "$new" > "$CLONE/build/darkraise-framework.pin"
  git -C "$CLONE" commit -q -am "qa: bad pin"
  case_ "feature branch, variable on"
  gate_in_clone DOMENT_GATE_PIN_ON_MASTER=1
  rc_is 1
  has "$re"
  case_ "detached HEAD, variable on"
  git -C "$CLONE" checkout -q --detach
  gate_in_clone DOMENT_GATE_PIN_ON_MASTER=1
  rc_is 1
  has "$re"
  case_ "feature branch, variable off or unset"
  git -C "$CLONE" switch -q qa-feature
  gate_in_clone
  rc_is 0
  hasnt 'DOMENT005'
  gate_in_clone DOMENT_GATE_PIN_ON_MASTER=0
  rc_is 0
  hasnt 'DOMENT005'
}

t_A6() {
  case_ "workflow passes the variable for master only"
  wf pin-env
  case_ "check prints the value it passes"
  local t=$S/a6 v want
  mk_tree "$t"
  export QA_LOG=$S/a6.log
  stand_in "$t/build/check.sh" 0
  stand_in "$t/build/gate.sh" 0
  for v in "1:1" "0:0" "unset:0"; do
    : > "$QA_LOG"
    if [[ ${v%%:*} == unset ]]; then
      OUT=$(env -u DOMENT_CI_PIN_ON_MASTER timeout -k 10 60 bash "$t/build/ci.sh" check 2>&1) && RC=0 || RC=$?
    else
      OUT=$(env DOMENT_CI_PIN_ON_MASTER="${v%%:*}" timeout -k 10 60 bash "$t/build/ci.sh" check 2>&1) && RC=0 || RC=$?
    fi
    want=${v##*:}
    rc_is 0
    has "^ci: gate DOMENT_GATE_PIN_ON_MASTER=$want\$"
    grep -q "^gate.sh rc=0 gatevar=$want " "$QA_LOG" || note "the gate saw DOMENT_GATE_PIN_ON_MASTER other than $want ($(cat "$QA_LOG"))"
  done
  case_ "pushed run logs"
  gh_ok && runs_json || { skip_case "no GitHub access"; return 0; }
  local id jid
  id=$(jq -r '[.[] | select(.event == "push" and .branch != "master" and .conclusion == "success")][0].id // empty' <<<"$RUNS_JSON")
  [[ -n $id ]] || { note "no successful push run on a non-master branch"; return 0; }
  jid=$(jobs_of "$id" | jq -r '.[] | select(.name == "check") | .id')
  OUT=$(job_log "$jid")
  has 'ci: gate DOMENT_GATE_PIN_ON_MASTER=0$'
}

t_A7() {
  case_ "on: allowlist and fork skip"
  wf on
}

t_A8() {
  case_ "runs-on and uses"
  wf runs-on-uses
}

t_A9() {
  case_ "workflow secret and permissions"
  wf secrets
  local t=$S/a9 fw=$S/a9fw
  mk_tree "$t"
  mk_fw "$fw"
  case_ "verify passes on a clean stand-in"
  verify_run "$t" "$fw"
  rc_is 0
  has '^ci: verify ok$'
  case_ "verify fails on core.sshCommand"
  git -C "$fw" config core.sshCommand 'ssh -i /tmp/key'
  verify_run "$t" "$fw"
  rc_is 1
  has '^::error::.*sshCommand'
  git -C "$fw" config --unset core.sshCommand
  case_ "verify fails on a private key under RUNNER_TEMP"
  mkdir -p "$S/rt/x"
  printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----\n' > "$S/rt/x/key"
  verify_run "$t" "$fw"
  rc_is 1
  has '^::error::.*private key.*'"$S/rt/x/key"
  rm -rf "$S/rt"
  verify_run "$t" "$fw"
  rc_is 0
}

t_A10() {
  case_ "failed framework checkout of the bad-pin branch"
  gh_ok && runs_json || { skip_case "no GitHub access"; return 0; }
  local id sha pin jobs jid msg found=0
  for id in $(jq -r '[.[] | select(.event == "push" and .conclusion == "failure")] | .[].id' <<<"$RUNS_JSON"); do
    sha=$(jq -r '.[] | select(.id == '"$id"') | .sha' <<<"$RUNS_JSON")
    pin=$(pin_at "$sha")
    [[ $pin =~ ^[0-9a-f]{40}$ ]] || continue
    jobs=$(jobs_of "$id")
    for jid in $(jq -r '.[].id' <<<"$jobs"); do
      [[ $(jq -r '.[] | select(.id == '"$jid"') | .steps[] | select(.name == "Check out darkraise-framework") | .conclusion' <<<"$jobs") == failure ]] || continue
      found=1
      msg=$(gh_get "repos/$SLUG/check-runs/$jid/annotations" --jq '.[] | select(.annotation_level == "failure") | .message')
      OUT=$msg
      has "cannot check out darkraise-framework at $pin: "
      has 'push that framework commit to its origin'
      has 'DARKRAISE_FRAMEWORK_DEPLOY_KEY'
      has 'outbound SSH'
      [[ $(jq -r '.[] | select(.id == '"$jid"') | .steps[] | select(.name | startswith("Run ")) | .conclusion' <<<"$jobs") != success ]] || note "the build step succeeded after the failed checkout"
    done
    [[ $found == 1 ]] && break
  done
  [[ $found == 1 ]] || note "no failed push run failed at the framework checkout"
}

t_A11() {
  local t=$S/a11 bin=$S/a11bin c pkg
  mk_tree "$t"
  mk_fw "$S/a11fw"
  mkdir -p "$bin" "$S/a11zlib"
  : > "$S/a11zlib/zlib.h"
  for c in git grep find df awk dirname sed cat tr head sort mktemp uname; do ln -sf "$(command -v "$c")" "$bin/$c"; done
  for c in clang jq file ps pgrep; do printf '#!/bin/sh\nexit 0\n' > "$bin/$c"; chmod +x "$bin/$c"; done
  local bash_bin timeout_bin
  bash_bin=$(command -v bash)
  timeout_bin=$(command -v timeout)
  vrun() { # vrun <zlib include dir>
    OUT=$(cd "$t" && env -i PATH="$bin" HOME="$S" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DOMENT_CI_FRAMEWORK="$S/a11fw" \
      DOMENT_CI_ZLIB_INCLUDE="$1" DOMENT_CI_MIN_FREE_GB=0 RUNNER_TEMP="$S/a11rt" "$timeout_bin" -k 10 60 "$bash_bin" build/ci.sh verify 2>&1) && RC=0 || RC=$?
  }
  mkdir -p "$S/a11rt"
  case_ "all tools present"
  vrun "$S/a11zlib"
  rc_is 0
  for pkg in clang:clang jq:jq file:file ps:procps pgrep:procps; do
    case_ "${pkg%%:*} missing"
    mv "$bin/${pkg%%:*}" "$bin/${pkg%%:*}.off"
    vrun "$S/a11zlib"
    mv "$bin/${pkg%%:*}.off" "$bin/${pkg%%:*}"
    rc_is 1
    has "^::error::.*${pkg##*:}"
    hasnt 'dotnet|check: '
  done
  case_ "zlib.h missing"
  mkdir -p "$S/a11nozlib"
  vrun "$S/a11nozlib"
  rc_is 1
  has '^::error::.*zlib1g-dev'
}

t_A12() {
  case_ "concurrency group"
  wf concurrency
}

t_A13() {
  case_ "A17 and A20 from master"
  make_clone || { note "cannot build the stand-in clone"; return 0; }
  git -C "$CLONE" checkout -q -B master "$(git -C "$REPO_ROOT" rev-parse HEAD)"
  [[ $(git -C "$CLONE" branch --show-current) == master ]] || note "the clone is not on master"
  local fw=$CLONE/external/darkraise-framework pin
  pin=$(tr -d '\r\n ' < "$CLONE/build/darkraise-framework.pin")
  git -C "$fw" checkout -q --detach "$pin"
  [[ $(git -C "$CLONE" status --porcelain | head -n 1) == '' ]] || note "the clone is not clean: $(git -C "$CLONE" status --porcelain | head -n 3)"
  run 3000 bash "$CLONE/tests/build/repository-build-nativeaot.acceptance.sh" '^(A17|A20)$'
  has '^ok +A17: '
  has '^ok +A20: '
  has '^2 passed, 0 failed$'
  case_ "A17 with an SDK outside /usr/local/share/dotnet"
  local sdk=$S/sdk-copy/dotnet-root
  mkdir -p "$S/sdk-copy"
  cp -a /usr/local/share/dotnet "$sdk" || { note "cannot copy the SDK"; return 0; }
  eq "$(dirname "$(readlink -f "$sdk/dotnet")")" "$sdk" "the stand-in SDK location"
  [[ $sdk != /usr/local/share/dotnet* ]] || note "the stand-in SDK is under /usr/local/share/dotnet"
  OUT=$(cd "$CLONE" && env PATH="$sdk:$PATH" timeout -k 10 3000 bash tests/build/repository-build-nativeaot.acceptance.sh '^A17$' 2>&1) && RC=0 || RC=$?
  has '^ok +A17: '
  has '^1 passed, 0 failed$'
  eq "$(env PATH="$sdk:$PATH" bash -c 'dirname "$(readlink -f "$(command -v dotnet)")"')" "$sdk" "dotnet on the PATH of that run"
}

t_A14() {
  case_ "CI run of the finishing master push"
  gh_ok && runs_json || { skip_case "no GitHub access"; return 0; }
  local id jobs
  id=$(jq -r '[.[] | select(.event == "push" and .branch == "master")][0].id // empty' <<<"$RUNS_JSON")
  [[ -n $id ]] || { skip_case "no CI run of a master push exists yet; the finishing push has not been made"; return 0; }
  eq "$(jq -r '[.[] | select(.id == '"$id"')][0].conclusion' <<<"$RUNS_JSON")" success "master push run $id"
  jobs=$(jobs_of "$id")
  eq "$(jq -r 'map(select(.conclusion == "success")) | map(.name) | sort | join(",")' <<<"$jobs")" "acceptance,check" "successful jobs of run $id"
}

t_A16() {
  case_ "the workflow never sets the gate variable"
  wf pin-env
  case_ "only the gate call sees it"
  local t=$S/a16
  mk_tree "$t"
  export QA_LOG=$S/a16.log
  stand_in "$t/build/check.sh" 0
  stand_in "$t/build/gate.sh" 0
  : > "$QA_LOG"
  OUT=$(env DOMENT_CI_PIN_ON_MASTER=1 timeout -k 10 60 bash "$t/build/ci.sh" check 2>&1) && RC=0 || RC=$?
  rc_is 0
  grep -q '^check.sh rc=0 gatevar=unset ' "$QA_LOG" || note "check.sh saw DOMENT_GATE_PIN_ON_MASTER: $(cat "$QA_LOG")"
  grep -q '^gate.sh rc=0 gatevar=1 nofetch=1$' "$QA_LOG" || note "the gate did not see DOMENT_GATE_PIN_ON_MASTER=1 and DOMENT_GATE_NO_FETCH=1: $(cat "$QA_LOG")"
  case_ "acceptance suites run without it"
  mkdir -p "$t/tests/build"
  local f
  for f in repository-build.acceptance.sh repository-build-nativeaot.acceptance.sh ci-pushed-branches.acceptance.sh; do stand_in "$t/tests/build/$f" 0; done
  : > "$QA_LOG"
  OUT=$(env DOMENT_CI_PIN_ON_MASTER=1 timeout -k 10 60 bash "$t/build/ci.sh" acceptance 2>&1) && RC=0 || RC=$?
  rc_is 0
  [[ $(grep -c 'gatevar=unset' "$QA_LOG") -eq 3 ]] || note "an acceptance suite saw DOMENT_GATE_PIN_ON_MASTER: $(cat "$QA_LOG")"
  case_ "every tests/build runner unsets it"
  for f in run.sh architecture-decisions.acceptance.sh repository-build.acceptance.sh repository-build-nativeaot.acceptance.sh; do
    grep -Eq '^[[:space:]]*unset([[:space:]]+[A-Za-z_]+)*[[:space:]]+DOMENT_GATE_PIN_ON_MASTER([[:space:]]|$)' "$REPO_ROOT/tests/build/$f" ||
      note "tests/build/$f does not unset DOMENT_GATE_PIN_ON_MASTER"
  done
  case_ "run.sh gate_main_pin with the variable set in the caller's environment"
  OUT=$(cd "$REPO_ROOT" && env DOMENT_GATE_PIN_ON_MASTER=1 timeout -k 10 1800 bash tests/build/run.sh '^gate_main_pin$' 2>&1) && RC=0 || RC=$?
  rc_is 0
}

t_A17() {
  case_ "workflow_dispatch run after the finishing master push"
  gh_ok && runs_json || { skip_case "no GitHub access"; return 0; }
  local id jobs
  jq -e '[.[] | select(.event == "push" and .branch == "master")] | length > 0' <<<"$RUNS_JSON" > /dev/null || { skip_case "the finishing master push has not been made"; return 0; }
  id=$(jq -r '[.[] | select(.event == "workflow_dispatch")][0].id // empty' <<<"$RUNS_JSON")
  [[ -n $id ]] || { note "no workflow_dispatch run exists after the master push"; return 0; }
  jobs=$(jobs_of "$id")
  eq "$(jq -r 'map(.name) | sort | join(",")' <<<"$jobs")" "acceptance,check" "jobs of workflow_dispatch run $id"
}

t_A18() {
  local t=$S/a18 fw=$S/a18fw
  mk_tree "$t"
  mk_fw "$fw"
  printf '*.log\n' > "$fw/.gitignore"
  git -C "$fw" add .gitignore
  git -C "$fw" commit -qm ignore
  case_ "clean with allowed build folders"
  mkdir -p "$fw/bin" "$fw/obj" "$fw/.vs" "$fw/.idea" "$fw/sub/bin" "$fw/.git/lfs/objects"
  for f in bin/o.dll obj/x .vs/y .idea/z sub/bin/w; do echo x > "$fw/$f"; done
  verify_run "$t" "$fw"
  rc_is 0
  rm -rf "$fw/bin" "$fw/obj" "$fw/.vs" "$fw/.idea" "$fw/sub"
  case_ "untracked path named"
  mkdir -p "$fw/stray"
  echo x > "$fw/stray/new.txt"
  verify_run "$t" "$fw"
  rc_is 1
  has '^::error::.*stray/new\.txt'
  rm -rf "$fw/stray"
  case_ "modified tracked path named"
  echo changed > "$fw/a.txt"
  verify_run "$t" "$fw"
  rc_is 1
  has '^::error::.*a\.txt'
  git -C "$fw" checkout -q -- a.txt
  case_ "ignored path named"
  echo x > "$fw/x.log"
  verify_run "$t" "$fw"
  rc_is 1
  has '^::error::.*x\.log'
  rm -f "$fw/x.log"
  case_ "LFS objects named"
  mkdir -p "$fw/.git/lfs/objects/ab/cd"
  echo obj > "$fw/.git/lfs/objects/ab/cd/abcdef"
  verify_run "$t" "$fw"
  rc_is 1
  has '^::error::.*LFS'
  rm -rf "$fw/.git/lfs"
  verify_run "$t" "$fw"
  rc_is 0
  case_ "free space"
  verify_run "$t" "$fw" DOMENT_CI_MIN_FREE_GB=99999999
  rc_is 1
  has '^::error::workspace has [0-9]+ GB free at .*, needs 99999999 GB$'
  local free found
  free=$(df -Pk "$t" | awk 'NR == 2 { print int($4 / 1048576) }')
  found=$(grep -oE 'workspace has [0-9]+ GB' <<<"$OUT" | grep -oE '[0-9]+' | head -n 1)
  [[ -n $found && $((found - free)) -ge -1 && $((found - free)) -le 1 ]] || note "the error names $found GB free, df shows $free GB"
}

t_A19() {
  local t=$S/a19 combo rc_check rc_gate want
  mk_tree "$t"
  export QA_LOG=$S/a19.log
  for combo in "1 0 1" "0 1 1" "1 1 1" "0 0 0"; do
    read -r rc_check rc_gate want <<<"$combo"
    case_ "check.sh rc $rc_check, gate rc $rc_gate"
    : > "$QA_LOG"
    stand_in "$t/build/check.sh" "$rc_check"
    stand_in "$t/build/gate.sh" "$rc_gate"
    run 60 bash "$t/build/ci.sh" check
    rc_is "$want"
    eq "$(cut -d' ' -f1 "$QA_LOG" | paste -sd,)" "check.sh,gate.sh" "calls, in order"
    has '^ci: gate DOMENT_GATE_PIN_ON_MASTER=[01]$'
  done
}

t_A20() {
  case_ "same-repository pull request run"
  gh_ok && runs_json || { skip_case "no GitHub access"; return 0; }
  local id jobs jid
  id=$(jq -r '[.[] | select(.event == "pull_request" and .head_repo == .repo)][0].id // empty' <<<"$RUNS_JSON")
  [[ -n $id ]] || { note "no CI run of a same-repository pull request"; return 0; }
  jobs=$(jobs_of "$id")
  eq "$(jq -r 'map(select(.conclusion == "success")) | map(.name) | sort | join(",")' <<<"$jobs")" "acceptance,check" "successful jobs of pull request run $id"
  jid=$(jq -r '.[] | select(.name == "check") | .id' <<<"$jobs")
  OUT=$(job_log "$jid")
  has 'ci: gate DOMENT_GATE_PIN_ON_MASTER=1$'
}

t_A21() {
  case_ "deploy key is read only"
  gh_ok || { skip_case "no GitHub access"; return 0; }
  local keys
  keys=$(gh_get "repos/$FW_SLUG/keys" --jq '[.[] | {title, read_only}]')
  [[ -n $keys ]] || { note "cannot read the keys of $FW_SLUG"; return 0; }
  [[ $(jq 'length' <<<"$keys") -ge 1 ]] || note "the framework has no deploy key"
  [[ $(jq '[.[] | select(.read_only != true)] | length' <<<"$keys") -eq 0 ]] || note "a deploy key is not read-only: $keys"
}

t_A22() {
  case_ "fork approval and SHA pinning"
  gh_ok || { skip_case "no GitHub access"; return 0; }
  eq "$(gh_get "repos/$SLUG/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy)" all_external_contributors "fork pull request approval policy"
  eq "$(gh_get "repos/$SLUG/actions/permissions" --jq .sha_pinning_required)" true "sha_pinning_required"
}

t_A23() {
  case_ "no tree code before the framework checkout"
  wf before-checkout
}

t_A24() {
  case_ "probe job run"
  gh_ok && runs_json || { skip_case "no GitHub access"; return 0; }
  local id jobs jid sha wf_text
  for id in $(jq -r '.[].id' <<<"$RUNS_JSON"); do
    jobs=$(jobs_of "$id")
    jid=$(jq -r '[.[] | select(.name == "probe")][0].id // empty' <<<"$jobs")
    [[ -n $jid ]] && break
  done
  [[ -n ${jid:-} ]] || { note "no CI run has a probe job"; return 0; }
  sha=$(jq -r '.[] | select(.id == '"$id"') | .sha' <<<"$RUNS_JSON")
  OUT=$(job_log "$jid")
  has 'hook: /.*job-started\.sh'
  has 'fork refusal: installed at /.*job-started\.sh'
  hasnt '##\[error\]'
  eq "$(jq -r '.[] | select(.id == '"$jid"') | .conclusion' <<<"$jobs")" success "probe job"
  wf_text=$(gh_get "repos/$SLUG/contents/.github/workflows/ci.yml?ref=$sha" --jq .content | base64 -d)
  OUT=$wf_text
  has 'ACTIONS_RUNNER_HOOK_JOB_STARTED'
  has "grep -q 'refusing a job started from another repository' \"\\\$hook\""
  has '::error::.*fork refusal is not installed'
  has 'exit 1'
}

t_A25() {
  local t=$S/a25 stub=$S/a25stub
  mkdir -p "$t/build" "$stub"
  cp "$REPO_ROOT/build/check.sh" "$t/build/check.sh"
  cat > "$stub/dotnet" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$QA_DN_LOG"
[[ ${1:-} == --version ]] && echo 10.0.404
exit 0
EOF
  chmod +x "$stub/dotnet"
  export QA_DN_LOG=$S/a25.log
  local mode n
  for mode in true unset false; do
    case_ "GITHUB_ACTIONS=$mode"
    : > "$QA_DN_LOG"
    if [[ $mode == unset ]]; then
      OUT=$(env -u GITHUB_ACTIONS PATH="$stub:$PATH" timeout -k 10 120 bash "$t/build/check.sh" build 2>&1) && RC=0 || RC=$?
    else
      OUT=$(env GITHUB_ACTIONS=$mode PATH="$stub:$PATH" timeout -k 10 120 bash "$t/build/check.sh" build 2>&1) && RC=0 || RC=$?
    fi
    rc_is 0
    has '^check: build ok$'
    grep -q '^build ' "$QA_DN_LOG" || note "the stand-in dotnet saw no build call"
    n=$(grep -c '^build-server shutdown' "$QA_DN_LOG")
    if [[ $mode == true ]]; then eq "$n" 0 "dotnet build-server shutdown calls under GITHUB_ACTIONS=true"; else eq "$n" 1 "dotnet build-server shutdown calls under GITHUB_ACTIONS=$mode"; fi
  done
}

# ---------------------------------------------------------------------------

declare -A DESC=(
  [A1]="a push of any branch runs both jobs on self-hosted doment-linux" [A2]="the check job restores tools, runs check.sh then the gate, fails on either"
  [A3]="framework checked out at the pin without LFS objects, strict pin" [A4]="ci.sh acceptance runs the three suites, each, and fails when any failed"
  [A5]="DOMENT_GATE_PIN_ON_MASTER=1 makes the gate check ancestry on any branch or detached HEAD" [A6]="DOMENT_CI_PIN_ON_MASTER for master pushes and pull requests only"
  [A7]="on: allowlist and the fork pull request condition" [A8]="no GitHub-hosted runner, every action at a full SHA"
  [A9]="the secret in the framework checkout only, verify finds no key, contents: read" [A10]="a pin absent from the framework's remote fails at the checkout with an annotation"
  [A11]="verify names the missing package before any build" [A12]="concurrency cancels on a feature branch, never on master"
  [A13]="A17 and A20 of the native AOT suite pass from master and with another SDK" [A14]="the master push run passes both jobs"
  [A16]="only the gate sees DOMENT_GATE_PIN_ON_MASTER, every runner unsets it" [A17]="a workflow_dispatch run starts both entries"
  [A18]="verify names the dirty path, the free space or the LFS objects" [A19]="check runs the gate after a failed check.sh and fails when either failed"
  [A20]="a same-repository pull request passes both entries with the gate value 1" [A21]="the deploy key is read only"
  [A22]="fork approval for all external contributors, SHA pinning required" [A23]="no step before the framework checkout runs tree code"
  [A24]="the probe job prints the hook path and fails unless it holds the fork refusal" [A25]="check.sh skips build-server shutdown only under GITHUB_ACTIONS=true"
)

PASS=0
FAIL=0
SKIP=0
for fn in $(declare -F | awk '{print $3}' | grep -E '^t_A[0-9]+$' | sort -t A -k2 -n); do
  n=${fn#t_}
  [[ -z $FILTER || $n =~ $FILTER ]] || continue
  FAILS=()
  SKIPS=()
  CASE=
  "$fn"
  if [[ ${#FAILS[@]} -gt 0 ]]; then
    echo "FAIL $n: ${DESC[$n]}"
    printf '       %s\n' "${FAILS[@]}"
    FAIL=$((FAIL + 1))
  elif [[ ${#SKIPS[@]} -gt 0 ]]; then
    echo "SKIP $n: ${DESC[$n]}"
    printf '       %s\n' "${SKIPS[@]}"
    SKIP=$((SKIP + 1))
  else
    echo "ok   $n: ${DESC[$n]}"
    PASS=$((PASS + 1))
  fi
done
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[[ $FAIL -eq 0 ]]
