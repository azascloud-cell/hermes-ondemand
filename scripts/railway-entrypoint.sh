#!/usr/bin/env bash
# Railway Entrypoint for Hermes Agent
# Handles backup/restore from GitHub, runs gateway or listener mode

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

# Load .env if exists
if [ -f "$HOME/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$HOME/.env"
    set +a
fi

# Railway provides these automatically
RAILWAY_SERVICE_NAME="${RAILWAY_SERVICE_NAME:-hermes}"
RAILWAY_ENVIRONMENT="${RAILWAY_ENVIRONMENT:-production}"

# Required secrets (set in Railway dashboard)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS:-}"
OLLAMA_API_KEY="${OLLAMA_API_KEY:-}"
OLLAMA_CLOUD_API_KEY="${OLLAMA_CLOUD_API_KEY:-${OLLAMA_API_KEY}}"
GROQ_API_KEY="${GROQ_API_KEY:-}"
OPENCODE_ZEN_API_KEY="${OPENCODE_ZEN_API_KEY:-}"

# GitHub backup config
GH_PAT="${GH_PAT:-}"
GH_REPO="${GH_REPO:-}"
GH_REF="${GH_REF:-main}"
DATA_BRANCH="${DATA_BRANCH:-railway-data}"
BACKUP_EVERY_SEC="${BACKUP_EVERY_SEC:-300}"

# Mode: gateway (full agent) or listener (lightweight trigger)
MODE="${MODE:-gateway}"

WORK="/tmp/hermes-railway-data"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

# URL-encode a credential component so special characters in GH_PAT never
# break the clone/push URL (and never leak raw into git output).
urlencode() {
    local s="${1// /%20}"
    s="${s//\#/%23}"; s="${s//\&/%26}"; s="${s//\?/%3F}"
    s="${s//\//%2F}"; s="${s//\+/%2B}"; s="${s//\@/%40}"
    s="${s//\:/%3A}"; s="${s//\=/%3D}"
    printf '%s' "$s"
}

# Normalize GH_REPO to "owner/name" — accepts "owner/name", a full
# "https://github.com/owner/name" URL, and optional ".git" suffix.
normalize_repo() {
    local r="${1#https://github.com/}"
    r="${r#http://github.com/}"
    r="${r#git@github.com:}"
    r="${r%.git}"
    printf '%s' "$r"
}

# Build a git remote URL using an auth token, URL-encoded for safety.
auth_url() {  # $1=repo (any common format)
    local enc repo
    enc="$(urlencode "$GH_PAT")"
    repo="$(normalize_repo "$1")"
    printf 'https://x-access-token:%s@github.com/%s.git' "$enc" "$repo"
}

# Exclude heavy tooling/code that we reinstall fresh every run
# config.yaml is excluded because it embeds API keys (generated fresh every
# run from Railway env vars); never back it up to GitHub.
EXCLUDES="hermes-agent bin node uv uvx uv-cache __pycache__ .cache venv .git .env config.yaml"

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

# Telegram notification
notify() {
    local text="$1"
    [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ] || return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$text" >/dev/null 2>&1 || true
}

# Restore data from GitHub data branch
restore_data() {
    [ -n "$GH_PAT" ] && [ -n "$GH_REPO" ] || { log "No GH_PAT/GH_REPO, skipping restore"; return 0; }
    
    log "Restoring ~/.hermes data from GitHub branch '$DATA_BRANCH'..."
    rm -rf "$WORK"; mkdir -p "$WORK"
    
    if git clone -q -b "$DATA_BRANCH" "$(auth_url "$GH_REPO")" "$WORK" 2>/dev/null; then
        copy_in "$WORK" "$HERMES_HOME"
        success "Data restored from $DATA_BRANCH"
    else
        log "No data branch yet; starting fresh"
        return 0
    fi
}

# Backup data to GitHub data branch
backup_data() {
    [ -n "$GH_PAT" ] && [ -n "$GH_REPO" ] || { log "No GH_PAT/GH_REPO, skipping backup"; return 0; }
    
    log "Backing up ~/.hermes data to GitHub branch '$DATA_BRANCH'..."
    cd /tmp
    rm -rf "$WORK"; mkdir -p "$WORK"
    
    if git clone -q -b "$DATA_BRANCH" "$(auth_url "$GH_REPO")" "$WORK" 2>/dev/null; then
        copy_in "$HERMES_HOME" "$WORK"
        cd "$WORK"
        git add -A
        if ! git diff --cached --quiet; then
            git -c user.name="hermes-railway-backup" -c user.email="hermes-railway@users.noreply.github.com" \
                commit -q -m "hermes railway backup $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            if ! git push -q origin "$DATA_BRANCH" 2>/tmp/push-err.log; then
                sed -i "s/${GH_PAT}/***/g" /tmp/push-err.log 2>/dev/null || true
                error "backup: push failed: $(tail -1 /tmp/push-err.log)"
            else
                success "Backup pushed to $DATA_BRANCH"
            fi
        else
            log "Backup: no changes"
        fi
    else
        # First time: create the branch
        git init -q "$WORK"; cd "$WORK"
        git checkout -q -b "$DATA_BRANCH" || true
        copy_in "$HERMES_HOME" "$WORK"
        git add -A
        # --allow-empty guarantees a ref exists so the first push never fails
        # with "src refspec ... does not match any".
        git -c user.name="hermes-railway-backup" -c user.email="hermes-railway@users.noreply.github.com" \
            commit -q --allow-empty -m "hermes railway backup $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        git remote add origin "$(auth_url "$GH_REPO")"
        if ! git push -q -u origin "$DATA_BRANCH" 2>/tmp/push-err.log; then
            # Mask any token that may leak into git's error output.
            sed -i "s/${GH_PAT}/***/g" /tmp/push-err.log 2>/dev/null || true
            error "backup: initial push failed: $(tail -1 /tmp/push-err.log)"
        else
            success "Created $DATA_BRANCH branch with initial backup"
        fi
    fi
}

# Write fresh config (secrets + provider config)
write_config() {
    log "Writing Hermes config..."
    mkdir -p "$HERMES_HOME"
    
    # .env file
    cat > "$HERMES_HOME/.env" <<EOF
OLLAMA_API_KEY=${OLLAMA_API_KEY}
OLLAMA_CLOUD_API_KEY=${OLLAMA_CLOUD_API_KEY}
GROQ_API_KEY=${GROQ_API_KEY}
OPENCODE_ZEN_API_KEY=${OPENCODE_ZEN_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}
EOF

    # Determine provider from env.
    # Auto-detect: if OPENCODE_ZEN_API_KEY is set, prefer opencode-zen
    # (built-in Hermes provider reading OPENCODE_ZEN_API_KEY from env);
    # otherwise fall back to OLLAMA_CLOUD_API_KEY / GROQ_API_KEY.
    if [ -n "${OPENCODE_ZEN_API_KEY:-}" ]; then
        MODEL_PROVIDER="${MODEL_PROVIDER:-opencode-zen}"
        DEFAULT_MODEL="${DEFAULT_MODEL:-laguna-s-2.1-free}"
        BASE_URL="${BASE_URL:-https://opencode.ai/zen/v1}"
    elif [ -n "${OLLAMA_CLOUD_API_KEY:-}" ]; then
        MODEL_PROVIDER="${MODEL_PROVIDER:-ollama-cloud}"
        DEFAULT_MODEL="${DEFAULT_MODEL:-gemma4:31b-cloud}"
        BASE_URL="${BASE_URL:-https://ollama.com/v1}"
    else
        MODEL_PROVIDER="${MODEL_PROVIDER:-groq}"
        DEFAULT_MODEL="${DEFAULT_MODEL:-llama-3.3-70b-versatile}"
        BASE_URL="${BASE_URL:-https://api.groq.com/openai/v1}"
    fi
    
    # config.yaml
    # NOTE: api_key values are written directly (not as ${ENV} refs) because
    # Hermes does not reliably expand env references inside config.yaml. The
    # real secret values come from Railway env vars.
    cat > "$HERMES_HOME/config.yaml" <<EOF
model:
  provider: "${MODEL_PROVIDER}"
  default: "${DEFAULT_MODEL}"
  base_url: "${BASE_URL}"
providers:
  groq:
    base_url: "https://api.groq.com/openai/v1"
    api_key: "${GROQ_API_KEY}"
  opencode-zen:
    base_url: "https://opencode.ai/zen/v1"
    api_key: "${OPENCODE_ZEN_API_KEY}"
  ollama-cloud:
    base_url: "https://ollama.com/v1"
    api_key: "${OLLAMA_CLOUD_API_KEY}"
memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 5000
  user_char_limit: 4000
EOF
    success "Config written"
    
    # Export the resolved provider/model so the python reset step below
    # (reset_model_overrides) uses the SAME values as config.yaml.
    export MODEL_PROVIDER DEFAULT_MODEL BASE_URL
}

# Reset stale model overrides in state.db
reset_model_overrides() {
    if [ -f "$HERMES_HOME/state.db" ]; then
        log "Resetting stale model_overrides..."
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
# scrub gateway_routing entry_json model_override
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
# scrub sessions.model / model_config
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
# archive oversized sessions
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
    fi
}

# Run gateway mode
run_gateway() {
    log "Starting Hermes Gateway..."
    notify "🟢 Hermes Railway Gateway online"
    
    # Run gateway in background
    hermes gateway >/tmp/gateway.log 2>&1 &
    GW_PID=$!
    
    # Wait for gateway to start
    sleep 8
    if ! kill -0 "$GW_PID" 2>/dev/null; then
        error "Gateway exited immediately. Log:"
        cat /tmp/gateway.log 2>/dev/null || true
        notify "⚠️ Hermes gateway gagal start, cek log"
        exit 1
    fi
    success "Gateway up (pid $GW_PID)"
    
    # Periodic backup loop
    local last_backup=$(date +%s)
    
    while true; do
        local now=$(date +%s)
        
        # Periodic backup
        if [ $((now - last_backup)) -ge $BACKUP_EVERY_SEC ]; then
            last_backup=$now
            backup_data 2>&1 | tail -2 || true
        fi
        
        # Check if gateway died
        if ! kill -0 "$GW_PID" 2>/dev/null; then
            warn "Gateway died; restarting..."
            notify "⚠️ Hermes gateway crash, restarting..."
            hermes gateway >/tmp/gateway.log 2>&1 &
            GW_PID=$!
            sleep 5
        fi
        
        sleep 20
    done
}

# Run listener mode (lightweight trigger bot)
run_listener() {
    log "Starting Hermes Listener..."
    notify "🟢 Hermes Railway Listener online"
    
    cd "$HOME/listener"
    python3 bot.py
}

# Signal handler
cleanup() {
    log "Shutting down..."
    backup_data 2>&1 | tail -2 || true
    notify "🔴 Hermes Railway offline"
    if [ -n "${GW_PID:-}" ]; then
        kill "$GW_PID" 2>/dev/null || true
        wait "$GW_PID" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup SIGTERM SIGINT

# Main
main() {
    log "=== Hermes Railway Entrypoint ==="
    log "Mode: $MODE"
    log "Railway Service: $RAILWAY_SERVICE_NAME"
    log "Environment: $RAILWAY_ENVIRONMENT"
    
    # Restore data first
    restore_data
    
    # Write fresh config (secrets take priority over restored config)
    write_config
    
    # Reset stale model overrides
    reset_model_overrides
    
    # Initial baseline backup — guarantees a restore point exists even if the
    # container is killed (OOM/trial expiry) before the first periodic backup.
    backup_data 2>&1 | tail -2 || true
    
    # Run selected mode
    case "$MODE" in
        gateway)
            run_gateway
            ;;
        listener)
            run_listener
            ;;
        *)
            error "Unknown mode: $MODE (use 'gateway' or 'listener')"
            exit 1
            ;;
    esac
}

main "$@"