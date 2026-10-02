#!/usr/bin/env bash
#
# run.sh — sync helper for the thesis repo.
#
#   ./run.sh pull              fetch and rebase onto origin/<branch>
#   ./run.sh push ["message"]  stage everything, commit, rebase, push
#   ./run.sh sync ["message"]  pull, then push
#   ./run.sh status            working tree + ahead/behind vs origin
#   ./run.sh build             build Thesis.pdf with latexmk
#   ./run.sh clean             remove LaTeX build artifacts
#
# Local edits are never discarded: pulls use --autostash, so uncommitted
# work is stashed, the rebase runs, and the work is reapplied.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; OFF=$'\033[0m'
info() { printf '%s==>%s %s\n' "$BOLD" "$OFF" "$*"; }
ok()   { printf '%s==>%s %s\n' "$GRN" "$OFF" "$*"; }
warn() { printf '%s==>%s %s\n' "$YEL" "$OFF" "$*"; }
die()  { printf '%serror:%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || die "detached HEAD; checkout a branch first"

require_remote() {
  git remote get-url origin >/dev/null 2>&1 \
    || die "no 'origin' remote configured (git remote add origin <url>)"
}

# Report how far ahead/behind origin we are. Safe when there is no upstream yet.
report_position() {
  if git rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
    local counts ahead behind
    counts="$(git rev-list --left-right --count "@{upstream}...HEAD")"
    behind="$(echo "$counts" | cut -f1)"
    ahead="$(echo "$counts" | cut -f2)"
    info "branch ${BOLD}${BRANCH}${OFF}: ${ahead} ahead, ${behind} behind origin/${BRANCH}"
  else
    warn "branch ${BRANCH} has no upstream yet"
  fi
}

do_pull() {
  require_remote
  info "fetching origin"
  git fetch origin --prune
  if git rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
    info "rebasing onto origin/${BRANCH}"
    git pull --rebase --autostash origin "$BRANCH"
  else
    warn "no upstream for ${BRANCH}; nothing to pull"
  fi
  ok "up to date with origin/${BRANCH}"
}

do_push() {
  require_remote
  local msg="${1:-}"
  [ -n "$msg" ] || msg="Update thesis ($(date '+%Y-%m-%d %H:%M'))"

  git add -A
  if git diff --cached --quiet; then
    info "no staged changes"
  else
    info "committing:"
    git diff --cached --name-status | sed 's/^/    /'
    git commit -q -m "$msg"
    ok "committed: ${msg}"
  fi

  # Rebase before pushing so a remote-side commit doesn't reject the push.
  git fetch origin --prune
  if git rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
    git pull --rebase --autostash origin "$BRANCH"
    if git rev-list --left-right --count "@{upstream}...HEAD" | cut -f2 | grep -qx 0; then
      ok "nothing to push"
      return
    fi
    info "pushing to origin/${BRANCH}"
    git push origin "$BRANCH"
  else
    info "pushing and setting upstream to origin/${BRANCH}"
    git push -u origin "$BRANCH"
  fi
  ok "pushed to origin/${BRANCH}"
}

case "${1:-}" in
  pull)
    do_pull
    ;;
  push)
    do_push "${2:-}"
    ;;
  sync)
    do_pull
    do_push "${2:-}"
    ;;
  status)
    report_position
    if [ -n "$(git status --porcelain)" ]; then
      info "working tree changes:"
      git status --short | sed 's/^/    /'
    else
      ok "working tree clean"
    fi
    ;;
  build)
    command -v latexmk >/dev/null 2>&1 \
      || die "latexmk not found. Install TeX Live: sudo apt install texlive-latex-extra latexmk"
    latexmk -pdf -interaction=nonstopmode -halt-on-error Thesis.tex
    ok "built Thesis.pdf"
    ;;
  clean)
    command -v latexmk >/dev/null 2>&1 || die "latexmk not found"
    latexmk -C
    ok "cleaned build artifacts"
    ;;
  *)
    cat <<'USAGE'
run.sh — sync helper for the thesis repo.

  ./run.sh pull              fetch and rebase onto origin/<branch>
  ./run.sh push ["message"]  stage everything, commit, rebase, push
  ./run.sh sync ["message"]  pull, then push
  ./run.sh status            working tree + ahead/behind vs origin
  ./run.sh build             build Thesis.pdf with latexmk
  ./run.sh clean             remove LaTeX build artifacts

Local edits are never discarded: pulls use --autostash, so uncommitted
work is stashed, the rebase runs, and the work is reapplied.
USAGE
    exit 1
    ;;
esac
