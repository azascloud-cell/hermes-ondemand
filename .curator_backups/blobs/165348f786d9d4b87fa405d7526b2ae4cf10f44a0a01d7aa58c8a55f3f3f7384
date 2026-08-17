---
name: whatsapp-bot-automation
description: Use when automating WhatsApp bots via Baileys.
---

# WhatsApp Bot Automation

Strategies for deploying and maintaining WhatsApp bots while minimizing ban risks and maximizing durability.

## Setup Workflow
1. **Environment**: Use a dedicated VPS (Ubuntu) to ensure 24/7 uptime.
2. **Dependencies**: Install Node.js (LTS) and essential libraries (e.g., `@whiskeysockets/baileys`, `qrcode-terminal`, `pino`).
3. **Persistence**: Use `pm2` to manage the process in the background.
4. **Integration**: For remote control, implement a simple Express.js API bridge to allow external triggers (e.g., from a Telegram bot or Cron job) to send messages.

## Anti-Ban & Durability Strategies
- **Human-like Behavior**: Implement random delays between messages to avoid trigger-happy spam filters.
- **Session Management**: Store authentication state in a persistent directory to avoid frequent re-scanning of QR codes.
- **Avoid Mass-Spamming**: Do not use new accounts for bulk messaging without a warming-up period.

## Pitfalls
- **Losing Session**: If the `auth_info` folder is deleted or corrupted, the bot must re-scan the QR code.
- **Device Disconnection**: Ensure the linked mobile device remains active or the session is kept alive via heartbeat.
- **API Rate Limits**: Be mindful of the number of requests sent to the WhatsApp socket to avoid temporary IP blocks.
