#!/usr/bin/env bash
# Keep-alive: runs hermes gateway, sends Telegram online/offline notifications,
# and self-triggers a new workflow run before the 6h hosted-runner limit.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

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
  # start gateway in background so the keep-alive loop can keep ticking
  hermes gateway start &
  GW_PID=$!
}

main() {
  local wf="${KEEPALIVE_WORKFLOW:-keepalive.yml}"
  notify "🟢 Hermes online (keep-alive start)"

  echo "Starting hermes gateway..."
  run_gateway

  local start_sec run_sec limit_sec restart_at_sec
  start_sec=$(date +%s)
  run_sec=$((RUN_MINUTES * 60))
  limit_sec=$((360 * 60))
  restart_at_sec=$((start_sec + (RUN_MINUTES - RESTART_BUFFER_MIN) * 60))

  while true; do
    local now_sec elapsed
    now_sec=$(date +%s)
    elapsed=$((now_sec - start_sec))

    if [ $now_sec -ge $restart_at_sec ]; then
      echo "Keep-alive: triggering next run at ${elapsed}s"
      notify "🔄 Hermes restarting (keep-alive), bot akan offline sebentar..."
      trigger_next "$wf"
      # give the new run time to boot; the next run sends the online notification
      notify "🔴 Hermes offline sementara (proses restart)"
      kill "$GW_PID" 2>/dev/null || true
      wait "$GW_PID" 2>/dev/null || true
      exit 0
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