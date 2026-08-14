import os
import json
import time
import logging
import urllib.request

import requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("listener")

TELEGRAM_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
ALLOWED_USERS = {
    u.strip() for u in os.environ.get("TELEGRAM_ALLOWED_USERS", "").split(",") if u.strip()
}
GH_PAT = os.environ.get("GH_PAT", "").strip()
GH_REPO = os.environ.get("GH_REPO", "").strip()  # e.g. owner/repo

TG_API = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}"
LONG_POLL_TIMEOUT = 30
LAST_OFFSET = 0
PROCESSING = set()


def tg(method, **params):
    try:
        r = requests.post(f"{TG_API}/{method}", json=params, timeout=60)
        return r.json()
    except Exception as e:
        log.warning("telegram %s error: %s", method, e)
        return None


def send(chat_id, text, parse_mode=None):
    kwargs = {"chat_id": chat_id, "text": text}
    if parse_mode:
        kwargs["parse_mode"] = parse_mode
    tg("sendMessage", **kwargs)


def trigger_workflow(payload):
    """Trigger the hermes.yml workflow via repository_dispatch."""
    url = f"https://api.github.com/repos/{GH_REPO}/dispatches"
    headers = {
        "Authorization": f"Bearer {GH_PAT}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "hermes-listener",
    }
    body = {"event_type": "hermes-on-demand", "client_payload": payload}
    r = requests.post(url, headers=headers, json=body, timeout=60)
    log.info("dispatch status=%s body=%s", r.status_code, r.text[:300])
    return r.status_code in (204, 202, 201)


def handle(chat_id, text, message_id):
    user_id = str(chat_id)
    if ALLOWED_USERS and user_id not in ALLOWED_USERS:
        send(chat_id, "Unauthorized. Your ID is not allowed.")
        return

    if text == "/status":
        send(chat_id, "Listener online. Trigger GitHub Actions on-demand: send any question.")
        return

    question = text.strip()
    if not question:
        return

    if chat_id in PROCESSING:
        send(chat_id, "Still processing your previous request...")
        return
    PROCESSING.add(chat_id)

    try:
        reply_ok = trigger_workflow(
            {"question": question, "chat_id": chat_id, "message_id": message_id}
        )
        if reply_ok:
            send(chat_id, "Menjalankan Hermes on-demand di GitHub Actions...")
        else:
            send(chat_id, "Gagal trigger workflow. Cek GH_PAT/GH_REPO.")
    finally:
        PROCESSING.discard(chat_id)


def poll_once():
    global LAST_OFFSET
    params = {
        "timeout": LONG_POLL_TIMEOUT,
        "offset": LAST_OFFSET,
        "allowed_updates": ["message"],
    }
    data = tg("getUpdates", **params)
    if not data or not data.get("ok"):
        return
    for update in data["result"]:
        LAST_OFFSET = max(LAST_OFFSET, update.get("update_id", 0) + 1)
        msg = update.get("message") or {}
        chat = msg.get("chat") or {}
        text = msg.get("text") or ""
        chat_id = chat.get("id")
        message_id = msg.get("message_id")
        if chat_id is not None and text:
            handle(chat_id, text, message_id)


def main():
    if not TELEGRAM_TOKEN:
        log.error("TELEGRAM_BOT_TOKEN not set")
        raise SystemExit(1)
    if not GH_PAT or not GH_REPO:
        log.error("GH_PAT and GH_REPO must be set")
        raise SystemExit(1)
    log.info("Listener started. Polling Telegram...")
    while True:
        try:
            poll_once()
        except Exception as e:
            log.warning("poll loop error: %s", e)
            time.sleep(3)


if __name__ == "__main__":
    main()