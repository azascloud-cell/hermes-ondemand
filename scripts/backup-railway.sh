#!/usr/bin/env bash
# Manual Backup Script for Railway
# Run this to manually trigger a backup to GitHub
#
# Usage:
#   railway run bash scripts/backup-railway.sh
#   Or SSH into Railway container and run: bash scripts/backup-railway.sh

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] OK:${NC} $*"; }

# Load environment
if [ -f "$HOME/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$HOME/.env"
    set +a
fi

# Required variables check
check_vars() {
    local missing=()
    
    [ -n "${GH_PAT:-}" ] || missing+=("GH_PAT")
    [ -n "${GH_REPO:-}" ] || missing+=("GH_REPO")
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required environment variables: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Backup data to GitHub
backup_data() {
    local DATA_BRANCH="${DATA_BRANCH:-railway-data}"
    local HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
    local WORK="/tmp/hermes-backup-data"
    local EXCLUDES="hermes-agent bin node uv uvx uv-cache __pycache__ .cache venv .git .env"
    
    log "Backing up Hermes data to GitHub..."
    log "Repo: $GH_REPO"
    log "Branch: $DATA_BRANCH"
    log "Source: $HERMES_HOME"
    
    cd /tmp
    rm -rf "$WORK"; mkdir -p "$WORK"
    
    copy_in() {  # $1=src $2=dst
        mkdir -p "$2"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a \
                $(printf -- '--exclude=%q ' $EXCLUDES) \
                "$1/" "$2/"
        else
            local tar_args=()
            for ex in $EXCLUDES; do tar_args+=(--exclude="$ex"); done
            tar "${tar_args[@]}" -C "$1" -cf - . | tar -C "$2" -xf -
        fi
    }
    
    if git clone -q -b "$DATA_BRANCH" "https://x-access-token:${GH_PAT}@github.com/${GH_REPO}.git" "$WORK" 2>/dev/null; then
        copy_in "$HERMES_HOME" "$WORK"
        cd "$WORK"
        git add -A
        if ! git diff --cached --quiet; then
            git -c user.name="hermes-railway-backup" -c user.email="hermes-railway@users.noreply.github.com" \
                commit -q -m "hermes railway manual backup $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            git push -q origin "$DATA_BRANCH" || { error "Push failed"; return 1; }
            success "Backup pushed to $DATA_BRANCH"
        else
            log "No changes to backup"
        fi
    else
        # First time: create the branch
        git init -q "$WORK"; cd "$WORK"
        git checkout -q -b "$DATA_BRANCH" || true
        copy_in "$HERMES_HOME" "$WORK"
        git add -A
        git -c user.name="hermes-railway-backup" -c user.email="hermes-railway@users.noreply.github.com" \
            commit -q -m "hermes railway initial backup $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        git remote add origin "https://x-access-token:${GH_PAT}@github.com/${GH_REPO}.git"
        git push -q -u origin "$DATA_BRANCH" || { error "Initial push failed"; return 1; }
        success "Created $DATA_BRANCH branch with initial backup"
    fi
    
    return 0
}

# Main
main() {
    echo "=============================================="
    echo "  Hermes Railway Manual Backup"
    echo "=============================================="
    echo
    
    if ! check_vars; then
        exit 1
    fi
    
    echo
    backup_data
    echo
    
    success "Backup complete!"
}

main "$@"