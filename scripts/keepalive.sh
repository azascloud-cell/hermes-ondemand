#!/usr/bin/env bash
# Keep-alive: runs hermes gateway, sends Telegram online/offline notifications,
# and self-triggers a new workflow run before the 6h hosted-runner limit.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

# Ensure any config written to ~/.hermes/.env is applied to the gateway process,
# even if a workflow step set the env var to empty (which would otherwise
# override the real value). Only set vars not already explicitly provided.
if [ -f "$HOME/.hermes/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$HOME/.hermes/.env"
  set +a
fi

RUN_MINUTES="${RUN_MINUTES:-350}"        # job length (5h50m) — must be < 360
RESTART_BUFFER_MIN="${RESTART_BUFFER_MIN:-3}"  # trigger new run this many min before limit
TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
GH_PAT="${GH_PAT:-}"
GH_REPO="${GH_REPO:-}"
GH_REF="${GH_REF:-main}"

TG="https://api.telegram.org/bot${TOKEN}"

notify() {
  local text="$1"
  [ -n "$TOKEN" ] && [ -n "$CHAT_ID" ] || return 0
  curl -s -X POST "$TG/sendMessage" \
    --data-urlencode "chat_id=$CHAT_ID" \
    --data-urlencode "text=$text" >/dev/null 2>&1 || true
}

trigger_next() {
  local wf="$1"
  [ -n "$GH_PAT" ] && [ -n "$GH_REPO" ] || { echo "missing GH_PAT/GH_REPO"; return 1; }
  curl -s -X POST \
    -H "Authorization: Bearer $GH_PAT" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$GH_REPO/actions/workflows/$wf/dispatches" \
    -d "{\"ref\":\"$GH_REF\"}" >/dev/null 2>&1 || true
  echo "dispatched next run of $wf"
}

run_gateway() {
  # Foreground gateway (no systemd service needed) running in background so the
  # keep-alive loop can keep ticking. `hermes gateway start` needs a user service,
  # which doesn't work on ephemeral CI runners.
  hermes gateway >/tmp/gateway.log 2>&1 &
  GW_PID=$!
}

write_config() {
  # Write fresh secrets + provider config. Runs AFTER persist.sh restore so the
  # freshly-generated config always wins over whatever was restored from the
  # data branch (restore would otherwise overwrite config.yaml/.env).
  mkdir -p "$HOME/.hermes"
  cat > "$HOME/.hermes/.env" <<EOF
OLLAMA_API_KEY=${OLLAMA_API_KEY}
OLLAMA_CLOUD_API_KEY=${OLLAMA_CLOUD_API_KEY}
GROQ_API_KEY=${GROQ_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}
EOF
  cat > "$HOME/.hermes/config.yaml" <<EOF
model:
  provider: "ollama-cloud"
  default: "gemma4:31b-cloud"
providers:
  groq:
    base_url: "https://api.groq.com/openai/v1"
    api_key: "\${GROQ_API_KEY}"
memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 5000
  user_char_limit: 4000
EOF
}

main() {
  local wf="${KEEPALIVE_WORKFLOW:-keepalive.yml}"

  # restore persisted data before starting the gateway (survives ephemeral runners)
  echo "Restoring ~/.hermes data..."
  "$(dirname "$0")/persist.sh" restore 2>&1 | tail -5 || true

  # re-apply secrets + provider config so the fresh config always wins
  write_config

  # Clear stale per-session model_override rows pointing at providers that need
  # paid credentials (e.g. opencode/OpenCode Zen → HTTP 401) or at unavailable
  # endpoints. The override lives in ~/.hermes/state.db (gateway_routing
  # entry_json + sessions.model) and survives persist restore, rehydrating on
  # every gateway start. We scrub it directly so the gateway falls back to the
  # configured default (ollama-cloud, with groq as a real fallback).
  if [ -f "$HOME/.hermes/state.db" ]; then
    echo "Resetting stale model_overrides to paid/unavailable providers..."
    python3 - <<'PY' || true
import json, os, sqlite3, time
db = os.path.expanduser("~/.hermes/state.db")
NEW_DEFAULT = "gemma4:31b-cloud"
NEW_PROVIDER = "ollama-cloud"
def is_bad(mo):
    if not isinstance(mo, dict):
        return True
    # Force everything back to the single configured provider. Persisted
    # overrides (opencode-zen, opencode-go, paid models, deprecated groq ids)
    # all reference providers we no longer configure, so reset them all.
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
# scrub sessions.model / model_config pointing at bad providers or deprecated models
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
# archive sessions that ballooned (413 payload too large / compression failures)
# so they never rehydrate with an oversized context that exceeds provider TPM limits.
cur.execute("""UPDATE sessions SET archived=1, hidden=1, ended_at=?, end_reason='reset_413_oversize',
               input_tokens=0, output_tokens=0, message_count=0,
               compression_failure_cooldown_until=NULL, compression_failure_error=NULL,
               compression_fallback_streak=0, compression_ineffective_count=0
               WHERE archived=0 AND hidden=0
                 AND (compression_failure_error IS NOT NULL OR compression_ineffective_count > 2)""",
            (time.time(),))
print("archived oversized sessions:", cur.rowcount)
con.commit()
con.close()
# scrub legacy sessions.json mirror (gateway_routing echo) if present
sj = os.path.expanduser("~/.hermes/sessions/sessions.json")
if os.path.exists(sj):
    try:
        with open(sj, "r") as f:
            data = json.load(f)
        changed = False
        for key, obj in (data.items() if isinstance(data, dict) else []):
            if not isinstance(obj, dict):
                continue
            mo = obj.get("model_override")
            if isinstance(mo, dict) and mo.get("provider") != NEW_PROVIDER:
                obj["model_override"] = None
                changed = True
        if changed:
            with open(sj, "w") as f:
                json.dump(data, f, indent=2)
            print("scrubbed sessions.json overrides")
    except Exception as e:
        print("sessions.json scrub skipped:", e)
PY
  fi

  notify "🟢 Hermes online (keep-alive start)"

  echo "Starting hermes gateway..."
  run_gateway

  # give the gateway a moment to come online before the keep-alive loop checks it
  sleep 8
  if ! kill -0 "$GW_PID" 2>/dev/null; then
    echo "Gateway exited immediately. Log:"
    cat /tmp/gateway.log 2>/dev/null || true
    notify "⚠️ Hermes gateway gagal start, cek log"
    exit 1
  fi
  echo "Gateway up (pid $GW_PID). Log tail:"
  tail -n 20 /tmp/gateway.log 2>/dev/null || true

  local start_sec run_sec limit_sec restart_at_sec
  start_sec=$(date +%s)
  run_sec=$((RUN_MINUTES * 60))
  limit_sec=$((360 * 60))
  restart_at_sec=$((start_sec + (RUN_MINUTES - RESTART_BUFFER_MIN) * 60))
  BACKUP_EVERY_SEC="${BACKUP_EVERY_SEC:-300}"
  local last_backup=$start_sec
  local last_log_offset=0
  local last_err_report=0

  while true; do
    local now_sec elapsed
    now_sec=$(date +%s)
    elapsed=$((now_sec - start_sec))

    if [ $now_sec -ge $restart_at_sec ]; then
      echo "Keep-alive: triggering next run at ${elapsed}s"
      # final backup before handing over to the next run
      "$(dirname "$0")/persist.sh" backup 2>&1 | tail -3 || true
      notify "🔄 Hermes restarting (keep-alive), bot akan offline sebentar..."
      trigger_next "$wf"
      # give the new run time to boot; the next run sends the online notification
      notify "🔴 Hermes offline sementara (proses restart)"
      kill "$GW_PID" 2>/dev/null || true
      wait "$GW_PID" 2>/dev/null || true
      exit 0
    fi

    # periodic backup so recent sessions/memory are never lost
    if [ $((now_sec - last_backup)) -ge $BACKUP_EVERY_SEC ]; then
      last_backup=$now_sec
      "$(dirname "$0")/persist.sh" backup 2>&1 | tail -2 || true
    fi

    # if the gateway process died unexpectedly, restart it
    if ! kill -0 "$GW_PID" 2>/dev/null; then
      echo "Gateway died; restarting..."
      notify "⚠️ Hermes gateway crash, restarting..."
      run_gateway
    fi

    # surface real provider/gateway errors to Telegram so they're visible
    # immediately instead of waiting for the run to finish
    if [ -f /tmp/gateway.log ]; then
      local size
      size=$(wc -c < /tmp/gateway.log 2>/dev/null || echo 0)
      if [ "$size" -gt "$last_log_offset" ]; then
        local errlines
        errlines=$(tail -c "+$last_log_offset" /tmp/gateway.log 2>/dev/null \
          | grep -iE "backoff|401|403|404|429|5[0-9][0-9]|auth|provider|timeout|not found|error|fail" \
          | tail -5 || true)
        if [ -n "$errlines" ]; then
          if [ $((now_sec - last_err_report)) -ge 30 ]; then
            last_err_report=$now_sec
            notify "⚠️ Hermes error:
${errlines}"
          fi
        fi
        last_log_offset=$size
      fi
    fi

    sleep 20
  done
}

main "$@"