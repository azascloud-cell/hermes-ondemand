# Round-Robin Family Persona Warming System

Advanced automated warming for 2-10+ Gmail accounts using `himalaya` CLI with family personas.

## Overview
This system implements a round-robin email exchange between accounts where each account adopts a family persona (Ayah, Ibu, Kakak 1, Kakak 2, Adik, Nenek, Kakek) to create highly human-like communication patterns.

## Personas (7 Roles)

| Persona | Tone | Style |
|---------|------|-------|
| Ayah | Formal, caring | Sopan, sedikit keras tapi sayang |
| Ibu | Warm, nurturing | Lembut, banyak tanya kabar, doa |
| Kakak 1 | Protective, advisory | Ngasih nasihat, sedikit mengomel tapi sayang |
| Kakak 2 | Casual, storytelling | Banyak cerita kerja/rumah tangga |
| Adik | Needy, confiding | Manja, minta tolong, curhat sekolah |
| Nenek | Religious, wise | Banyak doa, nasehat agama, tanya makan |
| Kakek | Wise, concise | Bijak, ringkas, jarang kirim tapi bermakna |

## Round-Robin Flow
```
Account 1 (Ayah)     → sends to Account 2
Account 2 (Ibu)      → sends to Account 3
Account 3 (Kakak 1)  → sends to Account 4
...
Account N (Persona)  → sends to Account 1 (cycle back)
```

## Per-Cycle Activities
1. **Send email**: Each account sends 1 email to next account using assigned persona
2. **Read inbox**: Each account checks inbox (simulates human checking email)
3. **Random delays**: 5-15s between sends, 2-5s between inbox checks
4. **Template variation**: Placeholders for names, food, problems, etc.

## Scheduling
Cronjob every 3 hours: `0 */3 * * *`

## Implementation Files (in `/home/runner/gmail_warming/`)
- `scripts/warming.py` — Main warming script
- `scripts/email_templates.json` — 7 personas × 3 templates each with placeholders
- `scripts/setup_accounts.py` — Interactive helper to create accounts.txt
- `accounts/TEMPLATE_config.toml` — Himalaya config template
- `accounts/accounts.txt` — User fills: `email app_password` per line
- `logs/warming_YYYYMMDD.log` — Daily logs

## Security Requirements
- ✅ App Passwords only (never main passwords)
- ✅ Mobile data / residential IP only (no datacenter VPN/proxy)
- ✅ Cluster recovery emails: max 5-10 accounts per recovery, non-Google providers
- ✅ New accounts: stay logged in on same device 24-48h before moving
- ✅ YouTube warmup: upload private video, organic likes/subscribes

## Usage
```bash
# 1. Setup accounts interactively
cd /home/runner/gmail_warming
python3 scripts/setup_accounts.py

# 2. Test run
python3 scripts/warming.py

# 3. Cronjob auto-runs every 3 hours (job ID: f8fba9ae738e)
# Check logs:
tail -f logs/warming_$(date +%Y%m%d).log
```