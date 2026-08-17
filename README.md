# Hermes 24/7 via GitHub Actions Keep-Alive

Jalankan **Hermes Agent AI** (Nous Research) secara terus-menerus (24 jam) memakai
**GitHub Actions hosted runner** dengan mekanisme **keep-alive**. Tidak perlu panel
Pterodactyl.

GitHub Actions hosted runner punya limit **6 jam per job**, jadi job dijalankan
~5 jam 50 menit, lalu **auto-trigger run baru** sebelum limit habis. Bot Telegram
memberi notifikasi saat **online** dan **offline sementara** saat restart.

## Arsitektur

```
GitHub Actions runner (ubuntu-latest, ~7GB RAM)
  └─ scripts/keepalive.sh
      ├─ jalankan `hermes gateway` (bot Telegram online)
      ├─ notif "🟢 online" saat mulai
      ├─ ~5j50m → notif "🔄 restarting" + trigger run baru (workflow_dispatch)
      ├─ kill gateway → notif "🔴 offline sementara" → exit
      └─ run baru mulai → notif "🟢 online" lagi  → loop 24/7
```

## File

| Path | Fungsi |
|------|--------|
| `.github/workflows/keepalive.yml` | Workflow utama 24/7 (dispatch + cron fallback) |
| `scripts/keepalive.sh` | Menjalankan gateway + keep-alive + notifikasi |
| `.github/workflows/hermes.yml` | (opsional) Workflow on-demand lama |
| `listener/bot.py` | (opsional) Listener Pterodactyl lama |

## Setup

### 1. GitHub Secrets

Tambahkan di Settings → Secrets and variables → Actions:

| Secret | Isi |
|--------|-----|
| `OLLAMA_API_KEY` | API key Ollama Cloud dari [ollama.com/settings/keys](https://ollama.com/settings/keys) (dipakai untuk `OLLAMA_API_KEY` dan `OLLAMA_CLOUD_API_KEY`) |
| `GROQ_API_KEY` | (opsional) API key Groq dari [console.groq.com/keys](https://console.groq.com/keys) untuk fallback, diawali `gsk_` |
| `TELEGRAM_BOT_TOKEN` | Token bot dari @BotFather |
| `TELEGRAM_CHAT_ID` | Numeric chat/user ID Telegram (contoh `6874843931`) |
| `TELEGRAM_ALLOWED_USERS` | ID Telegram yang diizinkan (koma untuk banyak) |
| `GH_PAT` | GitHub PAT (scope: `repo` + `workflow`) untuk auto re-trigger |

### 2. Jalankan

- **Manual sekali**: Actions → `Hermes Keep-Alive 24/7` → Run workflow (input `minutes`, default 350).
- **Otomatis**: workflow sudah punya `schedule` cron tiap 6 jam sebagai fallback, dan
  keep-alive meng-dispatch run baru sebelum limit — jadi berjalan terus.

### Model

`gemma4:31b-cloud` via **Ollama Cloud** (provider `ollama-cloud`, base URL `https://ollama.com/v1`).
Cloud → tidak butuh GPU/RAM besar di runner.

> Catatan: provider `ollama-cloud` membaca API key dari env var `OLLAMA_CLOUD_API_KEY`
> (bukan `OLLAMA_API_KEY`). Keduanya diset dari secret `OLLAMA_API_KEY` agar otentikasi selalu sukses.

### Fallback Groq

Jika ingin beralih ke Groq (cepat, ada free tier), isi secret `GROQ_API_KEY` lalu di chat
Telegram gunakan `/model groq/llama-3.3-70b-versatile` (atau model Groq lain). Groq tidak
dipakai sebagai default, hanya cadangan.

## Catatan penting

- **6 jam limit**: `keepalive.sh` default `RUN_MINUTES=350` (5j50m) dan memicu run baru
  ~3 menit sebelum limit. Jangan set >355.
- **Concurrency**: grup `hermes-gateway` mencegah dua run bertabrakan (dua gateway polling
  token bot yang sama). `cancel-in-progress: false` agar run lama tidak dibatalkan mendadak.
- **Cron fallback**: jika dispatch keep-alive gagal, cron tiap 6 jam memastikan bot tetap
  aktif.
- **Runner free limit**: ~2000 menit/bulan. 24/7 = ~1440 menit/bulan, masih muat untuk
  pemakaian pribadi (jika pakai repo privat, pakai plan apa pun; hosted runner gratis
  untuk repo publik, dan menit juga berlaku untuk privat sesuai kuota akun).

## Keamanan

- **Rotasi semua token yang pernah dibagikan** (GitHub PAT, panel key, token bot, Ollama key).
- Jangan pernah hardcode secret di file yang masuk repo. Pakai Actions secrets.
- `TELEGRAM_ALLOWED_USERS` wajib diisi untuk mencegah orang lain memakai bot.