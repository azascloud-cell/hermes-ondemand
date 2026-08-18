---
name: hermes-gateway-resilience
description: "Auto-restart Hermes Gateway in hosted compute via cron."
version: 1.0.0
author: agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, gateway, resilience, hosted-compute, monitoring, auto-restart, cronjob]
---

# Hermes Gateway Resilience for Hosted Compute Environments

When Hermes Gateway runs inside a hosted compute agent (GitHub Actions, Azure VMs, AWS CodeBuild, etc.), the parent process may kill child processes to reclaim memory. This skill provides patterns to detect and recover from such crashes automatically.

## Problem Signature

Gateway logs show:
```
exited UNCLEANLY (no exit path ran — SIGKILL / OOM / VM death)
last_heartbeat_at=... last_mem={...} suspected_oom=False
```

The `suspected_oom=False` with `SIGKILL` indicates **external process kill** (host agent reclaiming memory), not actual OOM.

## Root Cause

Hosted compute agents (e.g., `hosted-compute-agent` on Azure) use dynamic memory ballooning (`hv_balloon`) and enforce memory limits via cgroups. When the agent needs memory, it sends `SIGKILL` to child processes — including Hermes Gateway.

## Solution: Gateway Monitor Cronjob

### 1. Monitor Script (`scripts/gateway_monitor.sh`)

Checks gateway PID file, verifies process is alive, restarts if dead.

```bash
#!/usr/bin/env bash
GATEWAY_PID_FILE="$HOME/.hermes/gateway.pid"
HERMES_BIN="$HOME/.hermes/hermes-agent/hermes"
HERMES_HOME="$HOME/.hermes"

check_gateway() {
    if [[ -f "$GATEWAY_PID_FILE" ]]; then
        pid=$(jq -r '.pid' "$GATEWAY_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" && "$pid" != "null" ]]; then
            if kill -0 "$pid" 2>/dev/null; then
                if ps -p "$pid" -o comm= | grep -q "hermes"; then
                    return 0
                fi
            fi
        fi
    fi
    return 1
}

start_gateway() {
    cd "$HERMES_HOME"
    nohup "$HERMES_BIN" gateway >> "$HOME/.hermes/logs/gateway_monitor.log" 2>&1 &
    sleep 3
    check_gateway && return 0 || return 1
}

if check_gateway; then
    echo "$(date): Gateway running (PID: $(jq -r '.pid' "$GATEWAY_PID_FILE"))"
else
    echo "$(date): Gateway DOWN, restarting..."
    start_gateway
fi
```

### 2. Cronjob (every 5 minutes)

```bash
hermes cron create \
  --name "Hermes Gateway Monitor" \
  --schedule "*/5 * * * *" \
  --prompt "Run gateway monitor: /home/runner/gateway_monitor.sh" \
  --workdir "/home/runner"
```

Job ID: `3a44145b87ad` (example)

### 3. Prerequisites

```bash
# Enable linger so user services survive logout
sudo loginctl enable-linger $USER

# Ensure swap exists (helps avoid OOM pressure)
free -h  # Verify swap > 0
```

## Verification

- Gateway restarts within 5 minutes of crash
- Sessions & memory preserved in `state.db` (SQLite + FTS5)
- Telegram connection re-established automatically

## Pitfalls

- **Don't use systemd service** — hosted compute agent manages processes; systemd may conflict
- **Monitor script must be lightweight** — runs every 5 min, no heavy deps
- **PID file location** — `$HERMES_HOME/gateway.pid` (JSON with `pid` field)
- **False positives** — verify process name is `hermes`, not just any python process

## Related Skills

- `hermes-agent` (configuration, backgrounds-systems.md for cronjob details)
- `gmail-account-management` (warming workloads that run on gateway)