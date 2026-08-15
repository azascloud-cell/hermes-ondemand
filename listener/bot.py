import os
import json
import time
import logging
import urllib.request
import urllib.parse

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("listener")


def load_dotenv(path=".env"):
    if not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip()
            if k and os.environ.get(k, "") == "":
                os.environ[k] = v


load_dotenv()

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


def http_post_json(url, body=None, headers=None, timeout=60):
    data = None
    hdrs = {"User-Agent": "hermes-listener"}
    if headers:
        hdrs.update(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            try:
                return resp.status, json.loads(raw.decode("utf-8"))
            except Exception:
                return resp.status, raw.decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw.decode("utf-8"))
        except Exception:
            return e.code, raw.decode("utf-8", "replace")
    except Exception as e:
        log.warning("http error: %s", e)
        return None, None


def tg(method, **params):
    code, data = http_post_json(f"{TG_API}/{method}", body=params)
    return data


def send(chat_id, text, parse_mode=None):
    params = {"chat_id": chat_id, "text": text}
    if parse_mode:
        params["parse_mode"] = parse_mode
    tg("sendMessage", **params)


def trigger_workflow(payload):
    url = f"https://api.github.com/repos/{GH_REPO}/dispatches"
    headers = {
        "Authorization": f"Bearer {GH_PAT}",
        "Accept": "application/vnd.github+json",
    }
    code, body = http_post_json(url, body=payload, headers=headers)
    log.info("dispatch status=%s body=%s", code, str(body)[:300])
    return code in (204, 202, 201)


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