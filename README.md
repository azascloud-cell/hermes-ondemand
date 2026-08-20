# Hermes On-Demand — Multi-Platform Deployment

> **Run Hermes Agent anywhere: Railway (recommended), GitHub Actions, Pterodactyl, or locally.**

This repository contains everything needed to deploy Hermes Agent with **automatic backup/restore** so your conversations, memory, and settings survive platform migrations, trial expiries, and container restarts.

---

## 🎯 Platforms Supported

| Platform | Use Case | Persistence | Cost |
|----------|----------|-------------|------|
| **Railway** ⭐ | Primary deployment, trial-proof | GitHub data branch (auto) | Free tier + paid |
| **GitHub Actions** | 24/7 keep-alive, on-demand | GitHub data branch (auto) | Free (2000 min/mo) |
| **Pterodactyl** | Game panel hosting, persistent | Local disk + GitHub backup | Self-hosted |
| **Local** | Development, testing | Local `~/.hermes` | Free |

---

## 🚀 Quick Start: Railway (Recommended)

**Best for:** Trial-proof deployment with automatic backup/restore.

```bash
# 1. Fork this repo to your GitHub
# 2. Create GitHub PAT with 'repo' scope
# 3. Deploy to Railway
```

👉 **Full guide:** [README-RAILWAY.md](README-RAILWAY.md)

---

## ⚡ Quick Start: GitHub Actions (24/7 Free)

**Best for:** Always-on bot without paying for hosting.

### 1. Fork & Configure Secrets
Go to your fork → **Settings → Secrets and variables → Actions** → Add:

| Secret | Value |
|--------|-------|
| `TELEGRAM_BOT_TOKEN` | From @BotFather |
| `TELEGRAM_ALLOWED_USERS` | Your user ID(s) |
| `TELEGRAM_CHAT_ID` | Chat ID for notifications |
| `OLLAMA_API_KEY` | From ollama.com/settings/keys |
| `GROQ_API_KEY` | From console.groq.com (fallback) |
| `OPENCODE_ZEN_API_KEY` | From opencode.ai/auth (optional) |
| `GH_PAT` | GitHub PAT with `repo` scope |
| `SIGNAL_CHAT_ID` | Optional: channel for AzzaVision signals |

### 2. Enable Workflows
- **Actions tab** → Enable workflows
- **keepalive.yml** runs 24/7 (auto-restarts every 6h)
- **hermes.yml** triggers on-demand via repository_dispatch

### 3. Trigger Manually
```bash
# Via GitHub CLI
gh workflow run hermes.yml -f question="Hello Hermes!"

# Or via Telegram (if listener deployed)
# Send any message to your bot
```

---

## 🐳 Quick Start: Pterodactyl

**Best for:** Persistent hosting on your own panel.

### 1. Import Eggs
Upload `eggs/hermes-gateway.json` or `eggs/hermes-listener.json` to your Pterodactyl panel.

### 2. Create Server
- **Egg:** Hermes Agent Gateway (full) or Listener (lite)
- **Variables:** Fill in all required fields (same as Railway env vars)
- **Startup:** `bash start.sh` (gateway) or `python bot.py` (listener)

### 3. Install & Start
Console → `npm install` → Start server.

---

## 💻 Local Development

```bash
# Clone
git clone https://github.com/yourusername/hermes-ondemand.git
cd hermes-ondemand

# Install Hermes
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup

# Configure
cp .env.example .env
# Edit .env with your keys

# Run gateway
hermes gateway

# Or run listener
cd listener && pip install -r requirements.txt && python bot.py
```

---

## 🔄 Backup/Restore System

All platforms use the **same backup format** — a GitHub branch named `data` (GitHub Actions) or `railway-data` (Railway).

### What's Backed Up
```
~/.hermes/
├── state.db              # Sessions, routing, memory (SQLite)
├── config.yaml           # Model/provider configuration
├── memory/               # Long-term memory files
├── sessions/             # Session exports
└── .env                  # (regenerated from secrets each run)
```

### What's Excluded (reinstalled fresh)
```
hermes-agent/    # Hermes installation
bin/             # Binaries
node/ uv/ uvx/   # Package managers
__pycache__/     # Python cache
.cache/ venv/    # Virtual environments
.git/            # Git metadata
```

### Manual Backup/Restore (Any Platform)
```bash
# Backup now
bash scripts/persist.sh backup    # GitHub Actions
bash scripts/backup-railway.sh    # Railway

# Restore
bash scripts/persist.sh restore   # GitHub Actions
bash scripts/restore-railway.sh   # Railway
```

---

## 📁 Repository Structure

```
hermes-ondemand/
├── Dockerfile                    # Railway multi-stage build
├── railway.json                  # Railway config
├── nixpacks.toml                 # Nixpacks alternative
├── .env.example                  # Environment template
├── README.md                     # This file
├── README-RAILWAY.md             # Railway detailed guide
├── scripts/
│   ├── railway-entrypoint.sh     # Railway main entrypoint
│   ├── restore-railway.sh        # Railway manual restore
│   ├── backup-railway.sh         # Railway manual backup
│   ├── patch-typehandler.py      # Telegram bug fix
│   ├── keepalive.sh              # GH Actions: gateway + keepalive
│   ├── persist.sh                # GH Actions: backup/restore
│   └── selfheal.sh               # GH Actions: self-healing
├── listener/                     # Lightweight trigger bot
│   ├── bot.py                    # Telegram polling
│   ├── requirements.txt
│   └── .env.example
├── .github/workflows/
│   ├── hermes.yml                # On-demand workflow
│   ├── keepalive.yml             # 24/7 keep-alive
│   └── orchestrate-azzavision.yml
├── eggs/                         # Pterodactyl eggs
│   ├── hermes-gateway.json
│   └── hermes-listener.json
└── archive-*.tar.gz              # Legacy Node.js bot archive
```

---

## 🔧 Configuration Reference

### Model Providers

| Provider | Env Var | Models | Free Tier |
|----------|---------|--------|-----------|
| Ollama Cloud | `OLLAMA_API_KEY` | gemma4:31b-cloud, llama3.3:70b | ✅ Generous |
| Groq | `GROQ_API_KEY` | llama-3.3-70b, qwen-2.5-72b | ✅ Fast |
| OpenCode Zen | `OPENCODE_ZEN_API_KEY` | deepseek-v4-flash-free, big-pickle | ✅ Free |

### Memory Settings (in config.yaml)
```yaml
memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 5000    # Conversation memory
  user_char_limit: 4000      # User profile memory
```

---

## 🐛 Common Issues

| Issue | Solution |
|-------|----------|
| `TypeHandler` / `Any cannot be instantiated` | Auto-fixed by `patch-typehandler.py` |
| Gateway won't start | Check API keys, Telegram token, Railway logs |
| Restore fails | First deploy = no backup yet (normal) |
| OOM (out of memory) | Use `MODE=listener` or upgrade plan |
| Bot not responding | Check `TELEGRAM_ALLOWED_USERS` includes your ID |

---

## 🔒 Security

- **All secrets** → Railway Variables / GitHub Secrets (encrypted)
- **Conversations** → Private GitHub repo data branch
- **Keep fork private** if storing sensitive chats
- **GH_PAT** needs only `repo` scope

---

## 📚 Related Projects

- **Hermes Agent**: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)
- **Original Template**: [azascloud-cell/hermes-ondemand](https://github.com/azascloud-cell/hermes-ondemand)
- **AzzaVision AI**: [azascloud-cell/Azza-Vision-AI](https://github.com/azascloud-cell/Azza-Vision-AI)

---

## 📄 License

MIT — Use freely, deploy anywhere.

---

**Deploy once, run forever. 🚂✨**