---
name: hermes-gateway-monitoring
description: "Auto-restart Hermes Gateway on hosted compute via cronjob."
version: 1.0.0
author: agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, gateway, monitoring, hosted-compute, auto-restart, cronjob]
---

# Hermes Gateway Monitoring on Hosted Compute

## Problem
When Hermes runs on hosted compute platforms (GitHub Actions runners, Azure VMs with `hosted-compute-agent`, etc.), the **parent process manages memory via dynamic ballooning (hv_balloon)** and may **SIGKILL child processes** (including Hermes Gateway) to reclaim memory.

**Symptoms in gateway.log:**
```
exited UNCLEANLY (no exit path ran — SIGKILL / OOM / VM death)
last_heartbeat_at=...
suspected_oom=False
```

**Root cause:** Not actual OOM — the host agent proactively kills processes when memory pressure exceeds thresholds.

## Solution: Cronjob Monitor (5-minute interval)

### Monitor Script (`/home/runner/gateway_monitor.sh`)
```bash
#!/usr/bin/env bash
# Gateway Monitor - Auto restart Hermes Gateway if dead
# Run via cron every 5 minutes

GATEWAY_PID_FILE="$HOME/.hermes/gateway.pid"
HERMES_BIN="$HOME/.hermes/hermes-agent/hermes"
HERMES_HOME="$HOME/.hermes"

check_gateway() {
    if [[ -f "$GATEWAY_PID_FILE" ]]; then
        pid=$(jq -r '.pid' "$GATEWAY_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" && "$pid" != "null" ]]; then
            if kill -0 "$pid" 2>/dev/null; then
                if ps -p "$pid" -o comm= | grep -q "hermes"; then
                    return 0  # Alive
                fi
            fi
        fi
    fi
    return 1  # Dead or no PID file
}

start_gateway() {
    echo "$(date): Starting Hermes Gateway..."
    cd "$HERMES_HOME"
    nohup "$HERMES_BIN" gateway >> "$HOME/.hermes/logs/gateway_monitor.log" 2>&1 &
    sleep 3
    if check_gateway; then
        echo "$(date): Gateway started successfully"
    else
        echo "$(date): ERROR - Failed to start gateway"
    fi
}

if check_gateway; then
    echo "$(date): Gateway is running (PID: $(jq -r '.pid' "$GATEWAY_PID_FILE"))"
else
    echo "$(date): Gateway is DOWN, attempting restart..."
    start_gateway
fi
```

### Cronjob Configuration
```bash
cronjob create \
  --name "Hermes Gateway Monitor (5 menit)" \
  --prompt "Jalankan monitor Hermes Gateway: /home/runner/gateway_monitor.sh. Cek status gateway, restart kalau mati. Log ke ~/.hermes/logs/gateway_monitor.log" \
  --schedule "*/5 * * * *" \
  --workdir "/home/runner"
```

### Enable Linger (persist across SSH logout)
```bash
sudo loginctl enable-linger $USER
```

## Cronjob Model/Provider Configuration Issue

**Problem:** Cronjob `create` with `--model` and `--provider` parameters doesn't persist them — the job runs with default/fallback model (often `ollama-cloud:gemma4:31b-cloud` which has quota limits).

**Workaround:** Recreate job with explicit model/provider, or ensure `config.yaml` default is correct and no fallback triggers.

**config.yaml should have:**
```yaml
model:
  provider: opencode-zen
  default: deepseek-v4-flash-free  # No quota limits
fallback_providers:
  - provider: opencode-zen
    model: deepseek-v4-flash-free
  - provider: opencode-zen
    model: nemotron-3-ultra-free
  # REMOVE or MOVE ollama-cloud to end of fallback list
```

## Gmail Warming: Child Account (Family Link) Limitation

**Child accounts (Google Family Link / managed) CANNOT:**
- Create App Passwords
- Enable "Less Secure Apps"
- Use IMAP/SMTP with password auth

**Workarounds:**
1. **OAuth2/XOAUTH2** — Requires Google Cloud Project + Family Link manager approval
2. **Browser Automation** — Playwright/Puppeteer/Selenium with password + 2FA
3. **Take over account** — If age > 18, request "Take over account" from Family Link manager
4. **Separate warming** — Don't include child accounts in IMAP-based warming systems

## Verification
```bash
# Check gateway status
/home/runner/gateway_monitor.sh

# View monitor logs
tail -f ~/.hermes/logs/gateway_monitor.log

# View gateway logs
tail -f ~/.hermes/logs/gateway.log

# List cronjobs
hermes cron list
```