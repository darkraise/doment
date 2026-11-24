#!/usr/bin/env bash
# Manages this checkout's darkraise-framework worktree: framework.sh sync | pin | release
set -euo pipefail

export GIT_LFS_SKIP_SMUDGE=1

die() {
  echo "framework.sh: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage: framework.sh <verb>
  sync     create the framework worktree at the pin, or move a clean one to it
  pin      write the framework worktree's commit into the pin file
  release  remove the framework worktree through the framework repository
EOF
  exit 2
}

real_dir() {
  (cd "$1" && pwd -P)
}

TMP_FILES=()
cleanup() {
  if ((${#TMP_FILES[@]})); then
    rm -f "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

resolve_paths() {
  TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a doment git checkout"
  local common primary
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  primary=$(dirname "$common")

  if [[ -n ${DARKRAISE_FRAMEWORK_PATH:-} ]]; then
    [[ $DARKRAISE_FRAMEWORK_PATH == /* ]] ||
      die "DARKRAISE_FRAMEWORK_PATH must be an absolute path, got '$DARKRAISE_FRAMEWORK_PATH'"
    WORKTREE=${DARKRAISE_FRAMEWORK_PATH%/}
  else
    WORKTREE=$TOPLEVEL/external/darkraise-framework
  fi

  local default_clone
  default_clone=$(dirname "$primary")/darkraise-framework
  CLONE=
  if [[ -n ${DARKRAISE_FRAMEWORK_REPO:-} ]] && is_repo "$DARKRAISE_FRAMEWORK_REPO"; then
    CLONE=$DARKRAISE_FRAMEWORK_REPO
  elif is_repo "$default_clone"; then
    if [[ -n ${DARKRAISE_FRAMEWORK_REPO:-} ]]; then
      echo "framework.sh: no darkraise-framework clone at $DARKRAISE_FRAMEWORK_REPO; using $default_clone" >&2
    fi
    CLONE=$default_clone
  else
    die "no darkraise-framework clone at ${DARKRAISE_FRAMEWORK_REPO:-(unset)} or $default_clone"
  fi
  CLONE=$(real_dir "$CLONE")
  PIN_FILE=$TOPLEVEL/build/darkraise-framework.pin
}

is_repo() {
  [[ -d $1 ]] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

read_pin() {
  [[ -f $PIN_FILE ]] || die "$PIN_FILE must hold one full 40-character commit hash"
  local content
  content=$(<"$PIN_FILE")
  [[ $content =~ ^[0-9a-f]{40}$ ]] || die "$PIN_FILE must hold one full 40-character commit hash"
  PIN=$content
}

# The worktree must be a worktree of $CLONE's repository, so git never runs against the
# enclosing doment repository, another repository, or the framework's primary checkout.
check_is_framework_worktree() {
  local top wt_common clone_common
  top=$(git -C "$WORKTREE" rev-parse --show-toplevel 2>/dev/null) || top=
  if [[ -z $top || $(real_dir "$top") != "$(real_dir "$WORKTREE")" ]]; then
    die "$WORKTREE exists but is not a git worktree"
  fi
  wt_common=$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-common-dir)
  clone_common=$(git -C "$CLONE" rev-parse --path-format=absolute --git-common-dir)
  [[ $(real_dir "$wt_common") == "$(real_dir "$clone_common")" ]] ||
    die "$WORKTREE is not a worktree of the framework clone $CLONE"
  [[ $(real_dir "$WORKTREE") != "$(real_dir "$(dirname "$wt_common")")" ]] ||
    die "$WORKTREE is the framework's primary checkout, not a worktree of it"
}

# Prints the first path that makes the worktree not clean (Global Constraints), or nothing.
first_unclean_path() {
  local status_file entry code path segment skip_next=0
  status_file=$(mktemp)
  TMP_FILES+=("$status_file")
  git -C "$WORKTREE" status --porcelain=v1 -z --ignored=matching --untracked-files=all > "$status_file"
  while IFS= read -r -d '' entry; do
    if ((skip_next)); then
      skip_next=0
      continue
    fi
    code=${entry:0:2}
    path=${entry:3}
    [[ $code == R* || $code == C* ]] && skip_next=1
    if [[ $code == '!!' ]]; then
      local allowed=0
      IFS=/ read -r -a segments <<<"${path%/}"
      for segment in "${segments[@]}"; do
        case $segment in
          bin | obj | .vs | .idea) allowed=1 ;;
        esac
      done
      ((allowed)) && continue
    fi
    printf '%s\n' "$path"
    return 0
  done < "$status_file"
}

check_clean() {
  local first
  first=$(first_unclean_path)
  [[ -z $first ]] || die "$WORKTREE is not clean (first: $first)"
}

check_reachable() {
  local head refs
  head=$(git -C "$WORKTREE" rev-parse HEAD)
  refs=$(git -C "$WORKTREE" for-each-ref --contains HEAD refs/heads refs/remotes)
  [[ -n $refs ]] || die "$WORKTREE HEAD $head is on no framework branch or remote-tracking ref"
}

ensure_pin_commit() {
  git -C "$CLONE" cat-file -e "$PIN^{commit}" 2>/dev/null && return 0
  timeout 120 git -C "$CLONE" fetch --quiet origin ||
    echo "framework.sh: warning: fetching origin in $CLONE failed" >&2
  git -C "$CLONE" cat-file -e "$PIN^{commit}" 2>/dev/null ||
    die "commit $PIN is not in $CLONE or its remote"
}

cmd_sync() {
  resolve_paths
  read_pin
  git -C "$CLONE" worktree prune
  if [[ -e $WORKTREE ]]; then
    check_is_framework_worktree
    check_clean
    check_reachable
    ensure_pin_commit
    git -C "$WORKTREE" switch --quiet --detach "$PIN"
  else
    ensure_pin_commit
    mkdir -p "$(dirname "$WORKTREE")"
    git -C "$CLONE" worktree add --quiet --detach "$WORKTREE" "$PIN"
  fi
  echo "framework.sh: $WORKTREE is at $PIN" >&2
}

[[ $# -eq 1 ]] || usage
case $1 in
  sync) cmd_sync ;;
  pin | release)
    echo "framework.sh: $1 is not implemented yet" >&2
    exit 2
    ;;
  *) usage ;;
esac
