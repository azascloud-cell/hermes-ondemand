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
OPENCODE_ZEN_API_KEY=${OPENCODE_ZEN_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}
EOF
  cat > "$HOME/.hermes/config.yaml" <<EOF
model:
  provider: "ollama-cloud"
  default: "gemma4:31b-cloud"
  base_url: "https://ollama.com/v1"
providers:
  groq:
    api: "https://api.groq.com/openai/v1"
    api_key: "\${GROQ_API_KEY}"
    models:
      llama-3.3-70b-versatile:
        context_length: 131072
      llama-3.1-8b-instant:
        context_length: 131072
      qwen/qwen3-32b:
        context_length: 131072
      openai/gpt-oss-120b:
        context_length: 131072
      moonshotai/kimi-k2-instruct:
        context_length: 131072
EOF
}

main() {
  local wf="${KEEPALIVE_WORKFLOW:-keepalive.yml}"

  # restore persisted data before starting the gateway (survives ephemeral runners)
  echo "Restoring ~/.hermes data..."
  "$(dirname "$0")/persist.sh" restore 2>&1 | tail -5 || true

  # re-apply secrets + provider config so the fresh config always wins
  write_config

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

    sleep 20
  done
}

main "$@"