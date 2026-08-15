#!/usr/bin/env bash
# Persist ~/.hermes data to a dedicated git branch ("data") in the same repo,
# and restore it on startup. This survives ephemeral GitHub Actions runners.
#
# Usage:
#   persist.sh restore   # pull latest data into ~/.hermes (before gateway)
#   persist.sh backup    # commit ~/.hermes data -> origin/data (after/parallel)
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
DATA_BRANCH="${DATA_BRANCH:-data}"
GH_PAT="${GH_PAT:-}"
GH_REPO="${GH_REPO:-}"
GH_REF="${GH_REF:-main}"
WORK="${WORK:-/tmp/hermes-data}"
# exclude heavy tooling/code that we reinstall fresh every run
EXCLUDES="hermes-agent bin node uv uvx uv-cache __pycache__ .cache venv"

copy_in() {  # $1=src $2=dst
  rm -rf "$2"; mkdir -p "$2"
  # use tar for excludes
  tar --exclude-from=<(printf '%s\n' $EXCLUDES) -C "$1" -cf - . | tar -C "$2" -xf -
}

restore() {
  [ -n "$GH_PAT" ] && [ -n "$GH_REPO" ] || { echo "restore: missing GH_PAT/GH_REPO"; return 1; }
  rm -rf "$WORK"; mkdir -p "$WORK"
  git clone -q -b "$DATA_BRANCH" "https://x-access-token:${GH_PAT}@github.com/${GH_REPO}.git" "$WORK" 2>/dev/null \
    || { echo "restore: no data branch yet; starting fresh"; return 0; }
  copy_in "$WORK" "$HERMES_HOME"
  echo "restore: data loaded from $DATA_BRANCH"
}

backup() {
  [ -n "$GH_PAT" ] && [ -n "$GH_REPO" ] || { echo "backup: missing GH_PAT/GH_REPO"; return 1; }
  rm -rf "$WORK"; mkdir -p "$WORK"
  if git clone -q -b "$DATA_BRANCH" "https://x-access-token:${GH_PAT}@github.com/${GH_REPO}.git" "$WORK" 2>/dev/null; then
    copy_in "$HERMES_HOME" "$WORK"
    cd "$WORK"
    git add -A
    if ! git diff --cached --quiet; then
      git -c user.name="hermes-backup" -c user.email="hermes-backup@users.noreply.github.com" \
        commit -q -m "hermes data backup $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      git push -q origin "$DATA_BRANCH" || echo "backup: push failed"
      echo "backup: pushed changes"
    else
      echo "backup: no changes"
    fi
  else
    # first time: create the branch
    git init -q "$WORK"; cd "$WORK"
    git checkout -q -b "$DATA_BRANCH" || true
    copy_in "$HERMES_HOME" "$WORK"
    git add -A
    git -c user.name="hermes-backup" -c user.email="hermes-backup@users.noreply.github.com" \
      commit -q -m "hermes data backup $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    git remote add origin "https://x-access-token:${GH_PAT}@github.com/${GH_REPO}.git"
    git push -q -u origin "$DATA_BRANCH" || echo "backup: initial push failed"
    echo "backup: created $DATA_BRANCH"
  fi
}

case "${1:-}" in
  restore) restore ;;
  backup)  backup ;;
  *) echo "usage: $0 restore|backup"; exit 2 ;;
esac