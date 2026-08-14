# Hermes On-Demand via GitHub Actions + Pterodactyl listener

Jalankan **Hermes Agent AI** (Nous Research) secara on-demand. Panel Pterodactyl
berkapasitas kecil hanya menjadi **pendengar (listener)**, workload berat dijalankan
di GitHub Actions hosted runner (gratis, ~7GB RAM) yang hanya menyala saat ada pertanyaan.

## Arsitektur

```
Pterodactyl server (125MB RAM / 500MB disk)
  └─ listener/bot.py  → polling Telegram, tetap online (~60MB)
      │  terima pesanmu → trigger GitHub Actions (repository_dispatch)
GitHub Actions runner (ubuntu-latest, on-demand)
  └─ install Hermes → proses pertanyaan → balas ke Telegram
```

## File

| Path | Fungsi |
|------|--------|
| `listener/bot.py` | Bot polling Telegram ringan untuk server Pterodactyl |
| `listener/requirements.txt` | Dependency bot (`requests`) |
| `listener/.env.example` | Template env |
| `.github/workflows/hermes.yml` | Workflow on-demand yang menjalankan Hermes |

## Setup

### 1. GitHub repo & Secrets

Buat repo di GitHub, lalu tambahkan **Actions secrets** (Settings → Secrets and variables → Actions):

| Secret | Isi |
|--------|-----|
| `OLLAMA_API_KEY` | API key Ollama Cloud dari [ollama.com/settings/keys](https://ollama.com/settings/keys) |
| `TELEGRAM_BOT_TOKEN` | Token bot dari @BotFather |

Upload kode ini ke repo tersebut.

### 2. Server Pterodactyl (listener)

Buat egg Python di panel, lalu pasang file:
- `listener/bot.py`
- `listener/requirements.txt`

Isi environment variables server Pterodactyl:
- `TELEGRAM_BOT_TOKEN` = token bot
- `TELEGRAM_ALLOWED_USERS` = ID Telegram kamu (dari @userinfobot), e.g. `123456789`
- `GH_PAT` = GitHub PAT (scope: `repo`, cukup untuk `dispatches`)
- `GH_REPO` = `owner/repo`

Model yang dipakai: **`gemma4:31b-cloud`** via **Ollama Cloud** (provider `ollama-cloud`, base URL `https://ollama.com/v1`) — cloud sehingga tidak butuh GPU/RAM besar di runner. Butuh akun Ollama + API key dari [ollama.com/settings/keys](https://ollama.com/settings/keys).

Instal dependency: `pip install -r listener/requirements.txt`
Jalankan: `python bot.py`

### 3. Alur kerja

1. Kamu DM bot di Telegram → listener trigger workflow
2. GitHub Actions menjalankan Hermes
3. Jawaban dikirim balik ke Telegram

## Catatan

- **Workflow harus bisa di-trigger via `repository_dispatch`** — PAT yang dipakai `GH_PAT`
  perlu scope `repo` dan harus punya akses ke repo.
- `repository_dispatch` **tidak memerlukan** file workflow dengan `on: workflow_dispatch`;
  event `repository_dispatch` sudah di-listening oleh `hermes.yml`.
- Limit runner free: ~2000 menit/bulan (menyala hanya beberapa menit per pertanyaan → sangat cukup).
- Sesuaikan provider/model di `.github/workflows/hermes.yml` sesuai key yang kamu punya.

## Keamanan

- **Rotasi semua token yang pernah dibagikan** (GitHub PAT, panel key) jika pernah bocor.
- Jangan pernah hardcode secret di file yang masuk repo. Pakai Actions secrets + env panel.
- `TELEGRAM_ALLOWED_USERS` wajib diisi untuk mencegah orang lain memakai bot.