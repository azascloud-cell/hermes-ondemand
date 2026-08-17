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
| `SIGNAL_CHAT_ID` | chat_id channel/topic sinyal XAUUSD (contoh `-1004310936137`) untuk orchestrator AzzaVision |
| `GH_PAT` | GitHub PAT (scope: `repo` + `workflow`) untuk auto re-trigger, self-heal, dan trigger repo Azza-Vision-AI |

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

Groq didaftarkan sebagai **named custom provider** `groq` di `config.yaml` (`providers.groq`,
base URL `https://api.groq.com/openai/v1`, key dari `${GROQ_API_KEY}`). Isi secret `GROQ_API_KEY`
(awalan `gsk_`). Untuk beralih, gunakan **sintaks titik dua**:

```
/model custom:groq:llama-3.3-70b-versatile
```

> Catatan: syntax `/model` Hermes memakai `provider:model` (titik dua), bukan garis miring.
> Provider custom dipanggil `custom:<nama>:<model>`. Groq tidak dipakai sebagai default — itu
> tetap Ollama Cloud `gemma4:31b-cloud`.

## Self-Heal (Hermes memperbaiki diri sendiri)

Hermes dapat memperbaiki dirinya sendiri dan memicu ulang workflow memakai **PAT**,
via helper script `scripts/selfheal.sh` (guardrail aman):

| Perintah | Fungsi |
|----------|--------|
| `selfheal.sh status` | Cek akses PAT & repo |
| `selfheal.sh dispatch <event> [json]` | Self-trigger `repository_dispatch` (memicu `hermes-on-demand`) |
| `selfheal.sh trigger <workflow> [ref]` | Trigger `workflow_dispatch` |
| `selfheal.sh retry <workflow> <fp> [max]` | Trigger dengan **batas retry** per fingerprint (default 3) |
| `selfheal.sh fix <branch> <title> [body]` | Commit + push ke **branch baru** & buka **PR** ke main |
| `selfheal.sh merge <pr> [fp]` | Merge PR (dan reset retry counter) |

### Guardrail (keamanan)
- **`fix` selalu lewat branch + PR**, tidak pernah push langsung ke `main`.
  Hermes tidak punya kunci untuk menyabotase produksi.
- **`retry` punya max counter** per fingerprint → mencegah infinite-loop jika
  Hermes mendeteksi "masalah" yang bukan bug asli.
- Semua akses memakai `GH_PAT` (scope `repo` + `workflow`); token **tidak pernah
  di-hardcode** di file — selalu dari Actions secret.

### Contoh alur self-heal
1. Hermes mendeteksi error di log (mis. provider timeout).
2. Ia memanggil `selfheal.sh retry keepalive.yml "provider-timeout" 3` untuk memicu ulang run (dibatasi 3x).
3. Kalau masalah butuh perbaikan kode, Hermes ubah file lalu
   `selfheal.sh fix fix/provider-timeout "fix: ganti provider fallback"`.
4. PR dibuka → (CI/manusia) review → `selfheal.sh merge <pr> "provider-timeout"` (reset counter).

## Orkestrator AzzaVision-AI (`orchestrate-azzavision.yml`)

Hermes-ondemand bertindak sebagai **orchestrator pusat** yang:

- Men-trigger repo **`azascloud-cell/Azza-Vision-AI`** (workflow `deploy-pterodactyl.yml`,
  Pterodactyl panel keep-alive) via `GH_PAT`.
- Mengirim notifikasi ke channel sinyal (`SIGNAL_CHAT_ID`) bahwa panel & bot aktif.
- Menjaga channel "hidup" — **tidak menggantikan** logika AzzaVision, hanya melengkapi.

> Catatan: concurrency di repo Azza-Vision-AI (group `pterodactyl-panel`) memastikan
> panel tidak berjalan dobel meski di-trigger dari sini maupun cron-nya sendiri.

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