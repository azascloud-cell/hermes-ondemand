#!/usr/bin/env bash
# Startup untuk Pterodactyl — otomatis pakai venv kalau ada, install deps jika perlu.
# Replace BOT_NAME with your bot name.
set -e
cd "$(dirname "$0")"

export TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
export TG_CHAT_ID="${TG_CHAT_ID:-}"

if [ -x "./venv/bin/python" ]; then
    PY="./venv/bin/python"
else
    PY="python3"
    # Aman diulang: kalau sudah terpasang, operasi ini cepat selesai.
    "$PY" -m pip install -q -r requirements.txt >/dev/null 2>&1 || true
fi

exec "$PY" main.py "$@"