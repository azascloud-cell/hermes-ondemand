---
name: pterodactyl-bot-deployment
description: Deploy Python bots to Pterodactyl with egg, startup, zip.
category: devops
tags:
  - pterodactyl
  - python
  - bot
  - deployment
  - egg
  - panel
  - cli
---

# Pterodactyl Bot Deployment Skill

## When to Use
Creating Python bots that run on Pterodactyl game/server panels with:
- Custom egg definitions for panel import
- Startup scripts that handle venv + dependencies
- Config files with environment variable overrides
- Requirements.txt for pip dependencies
- Zip packaging excluding sensitive files (passwords, logs, venv)
- Telegram notifications via env vars (TG_BOT_TOKEN, TG_CHAT_ID)

## Prerequisites
- Pterodactyl panel with admin access to import eggs
- Python 3.9+ (for `_create_socket` in imaplib)
- Docker image: `ghcr.io/pterodactyl-images/python:3.11` or similar

## Standard Project Structure
```
bot-name/
├── main.py                 # CLI entry point
├── config.json             # Default config (token/chat_id empty)
├── requirements.txt        # pip dependencies
├── startup.sh              # Pterodactyl startup (venv + deps)
├── eggs/
│   └── egg-bot-name.json   # Egg definition for panel import
├── module/                 # Package code
│   ├── __init__.py
│   ├── database.py         # Thread-safe JSON storage
│   ├── health.py           # Health checks (IMAP, HTTP, etc.)
│   ├── notifier.py         # Telegram/other notifications
│   ├── exporter.py         # CSV/JSON export
│   └── utils.py            # Shared utilities
├── example.csv             # Import format example
├── README.md               # Deploy + usage docs
└── .gitignore              # Exclude secrets (accounts.json, *.csv, logs, venv)
```

## Egg Definition Template
Key fields for `eggs/egg-*.json`:
- `docker_images`: `{"ghcr.io/pterodactyl-images/python:3.11": "Python 3.11"}`
- `startup`: `"{{STARTUP_CMD}}"` (panel variable)
- `scripts.installation`: Creates venv, installs requirements, chmod +x startup.sh
- `variables`: STARTUP_CMD (default: `./startup.sh auto`), TG_BOT_TOKEN, TG_CHAT_ID
- `config.logs.custom: true`, `location: "logs/app.log"`

## Startup Script Pattern
```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
export TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
export TG_CHAT_ID="${TG_CHAT_ID:-}"
if [ -x "./venv/bin/python" ]; then
    PY="./venv/bin/python"
else
    PY="python3"
    "$PY" -m pip install -q -r requirements.txt >/dev/null 2>&1 || true
fi
exec "$PY" main.py "$@"
```

## Zip Packaging Command
```bash
zip -r bot-name.zip bot-name \
  -x "*/__pycache__/*" "*/*.pyc" "*/.git*" "*/venv/*" \
  "*/logs/*" "*/accounts.json" "*/akun_*.csv" "*/akun_*.json"
```

## Security Rules
- **NEVER** include `accounts.json`, export CSVs/JSONs, or `.env` in zip
- `accounts.json` and exports contain passwords → `chmod 600` on server
- Telegram credentials via env vars only (egg variables), not config.json
- `.gitignore` must exclude all secret files

## Common Pitfalls
| Issue | Fix |
|-------|-----|
| ModuleNotFoundError on panel | Startup script must auto-install requirements if no venv |
| IMAP timeout all accounts | Check panel network / proxy; set `use_proxy: false` in config |
| Telegram notif not working | Verify TG_BOT_TOKEN/TG_CHAT_ID in egg variables; test with `./startup.sh tg-test` |
| Python version error | Egg must use Python 3.9+ (imaplib `_create_socket`) |
| Rate limited by Google | Increase `interval_minutes` to 240+, concurrency to 3-5 max |

## Verification Checklist
- [ ] `python3 -m py_compile main.py module/*.py` passes
- [ ] `python3 main.py --help` shows all subcommands
- [ ] `python3 main.py list` and `stats` work on empty DB
- [ ] Zip extracts cleanly with all 15-20 files
- [ ] Egg imports in Pterodactyl admin panel
- [ ] Server starts, shows "Monitoring X dimulai" in console

## References
- `references/egg-template.json` — Minimal egg definition
- `references/startup-template.sh` — Startup script boilerplate
- `references/zip-excludes.txt` — Standard exclusion patterns