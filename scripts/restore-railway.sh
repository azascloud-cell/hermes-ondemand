#!/usr/bin/env bash
# Restore Script for New Railway Account
# Run this script to restore Hermes data from GitHub to a new Railway deployment
#
# Usage:
#   1. Deploy this repo to new Railway account
#   2. Set all required environment variables in Railway dashboard
#   3. Run this script via Railway CLI: railway run bash scripts/restore-railway.sh
#   4. Or SSH into Railway container and run: bash scripts/restore-railway.sh

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
        error "Set these in Railway dashboard Variables tab"
        return 1
    fi
    
    success "All required variables present"
    return 0
}

# Restore data from GitHub
restore_data() {
    local DATA_BRANCH="${DATA_BRANCH:-railway-data}"
    local HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
    local WORK="/tmp/hermes-restore-data"
    local EXCLUDES="hermes-agent bin node uv uvx uv-cache __pycache__ .cache venv .git .env"
    
    log "Restoring Hermes data from GitHub..."
    log "Repo: $GH_REPO"
    log "Branch: $DATA_BRANCH"
    log "Target: $HERMES_HOME"
    
    rm -rf "$WORK"; mkdir -p "$WORK"
    
    if git clone -q -b "$DATA_BRANCH" "https://x-access-token:${GH_PAT}@github.com/${GH_REPO}.git" "$WORK" 2>/dev/null; then
        log "Cloned data branch successfully"
        
        # Copy data
        mkdir -p "$HERMES_HOME"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a \
                $(printf -- '--exclude=%q ' $EXCLUDES) \
                "$WORK/" "$HERMES_HOME/"
        else
            local tar_args=()
            for ex in $EXCLUDES; do tar_args+=(--exclude="$ex"); done
            tar "${tar_args[@]}" -C "$WORK" -cf - . | tar -C "$HERMES_HOME" -xf -
        fi
        
        success "Data restored to $HERMES_HOME"
        
        # Show what was restored
        log "Restored files:"
        find "$HERMES_HOME" -type f \( -name "*.db" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | head -20 | while read -r f; do
            echo "  - $f ($(du -h "$f" | cut -f1))"
        done
        
        return 0
    else
        error "Failed to clone data branch '$DATA_BRANCH'"
        error "This is normal for first deployment - no backup exists yet"
        error "The gateway will create the branch on first backup"
        return 1
    fi
}

# Verify restored data
verify_restore() {
    local HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
    
    log "Verifying restored data..."
    
    # Check for state.db (main Hermes database)
    if [ -f "$HERMES_HOME/state.db" ]; then
        success "Found state.db ($(du -h "$HERMES_HOME/state.db" | cut -f1))"
        
        # Quick sanity check
        sqlite3 "$HERMES_HOME/state.db" "SELECT COUNT(*) FROM sessions;" 2>/dev/null | while read -r count; do
            log "Sessions in database: $count"
        done
        sqlite3 "$HERMES_HOME/state.db" "SELECT COUNT(*) FROM gateway_routing;" 2>/dev/null | while read -r count; do
            log "Gateway routing entries: $count"
        done
    else
        warn "state.db not found (fresh start)"
    fi
    
    # Check for memory files
    if [ -d "$HERMES_HOME/memory" ]; then
        local mem_count=$(find "$HERMES_HOME/memory" -name "*.json" | wc -l)
        log "Memory files: $mem_count"
    fi
    
    # Check config
    if [ -f "$HERMES_HOME/config.yaml" ]; then
        success "Found config.yaml"
    else
        warn "config.yaml not found (will be generated on startup)"
    fi
    
    return 0
}

# Reset stale model overrides (same as in entrypoint)
reset_model_overrides() {
    local HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
    
    if [ -f "$HERMES_HOME/state.db" ]; then
        log "Resetting stale model_overrides in state.db..."
        python3 - <<'PY' || true
import json, os, sqlite3, time
db = os.path.expanduser("~/.hermes/state.db")
NEW_DEFAULT = os.environ.get("DEFAULT_MODEL", "gemma4:31b-cloud")
NEW_PROVIDER = os.environ.get("MODEL_PROVIDER", "ollama-cloud")
def is_bad(mo):
    if not isinstance(mo, dict):
        return True
    return mo.get("provider") != NEW_PROVIDER
con = sqlite3.connect(db)
cur = con.cursor()
cur.execute("SELECT rowid, scope, session_key, entry_json FROM gateway_routing")
rows = cur.fetchall()
for rowid, scope, skey, entry in rows:
    try:
        obj = json.loads(entry)
    except Exception:
        continue
    mo = obj.get("model_override")
    if is_bad(mo):
        obj["model_override"] = None
        cur.execute("UPDATE gateway_routing SET entry_json=?, updated_at=? WHERE rowid=?",
                    (json.dumps(obj), time.time(), rowid))
        print("cleared routing override:", skey)
cur.execute("SELECT id, model, model_config FROM sessions")
for sid, model, mcfg in cur.fetchall():
    try:
        cfg = json.loads(mcfg) if mcfg else {}
    except Exception:
        cfg = {}
    if is_bad(cfg) or (model != NEW_DEFAULT):
        cfg = {"provider": NEW_PROVIDER}
        cur.execute("UPDATE sessions SET model=?, model_config=? WHERE id=?",
                    (NEW_DEFAULT, json.dumps(cfg), sid))
        print("cleared session model:", sid)
cur.execute("""UPDATE sessions SET archived=1, hidden=1, ended_at=?,
              end_reason='reset_413_oversize', input_tokens=0, output_tokens=0,
              message_count=0, compression_failure_cooldown_until=NULL,
              compression_failure_error=NULL, compression_fallback_streak=0,
              compression_ineffective_count=0
              WHERE archived=0 AND hidden=0
                AND (compression_failure_error IS NOT NULL OR compression_ineffective_count > 2)""",
            (time.time(),))
print("archived oversized sessions:", cur.rowcount)
con.commit()
con.close()
PY
        success "Model overrides reset"
    fi
}

# Main
main() {
    echo "=============================================="
    echo "  Hermes Railway Restore Script"
    echo "=============================================="
    echo
    
    if ! check_vars; then
        exit 1
    fi
    
    echo
    restore_data
    echo
    verify_restore
    echo
    reset_model_overrides
    echo
    
    success "Restore complete!"
    echo
    log "Next steps:"
    log "1. Deploy/start your Railway service"
    log "2. The gateway will auto-backup every $BACKUP_EVERY_SEC seconds"
    log "3. Check Telegram for '🟢 Hermes Railway Gateway online' notification"
}

main "$@"