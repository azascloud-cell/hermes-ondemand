# Telegram Bot Conversation Handler Pattern

## Overview
This pattern implements a full Telegram bot with conversation handlers for account management, running alongside background monitoring in a Pterodactyl deployment.

## Key Components

### 1. Conversation States (in telegram_bot.py)
```python
ADD_EMAIL, ADD_PASSWORD, ADD_RECOVERY, ADD_PROXY, ADD_CONFIRM = range(5)
IMPORT_FILE = range(5, 6)[0]
DELETE_CONFIRM = range(6, 7)[0]
SET_FIELD, SET_VALUE = range(7, 9)
```

### 2. Authorization Guard
```python
def is_authorized(update: Update, cfg) -> bool:
    admin_id = str(cfg.get("telegram", {}).get("admin_user_id", ""))
    if not admin_id:
        return True  # Allow all if not set (dev mode)
    return str(update.effective_user.id) == admin_id
```

### 3. Auto-Delete Credential Messages
```python
async def safe_delete_message(context, chat_id, message_id):
    try:
        await context.bot.delete_message(chat_id=chat_id, message_id=message_id)
    except Exception:
        pass

# In password handler:
await safe_delete_message(context, update.effective_chat.id, update.message.message_id)
```

### 4. Conversation Handlers Structure
```python
add_conv = ConversationHandler(
    entry_points=[CommandHandler("add", add_start)],
    states={
        ADD_EMAIL: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_email)],
        ADD_PASSWORD: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_password)],
        ADD_RECOVERY: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_recovery)],
        ADD_PROXY: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_proxy)],
        ADD_CONFIRM: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_confirm)],
    },
    fallbacks=[CommandHandler("cancel", cancel)],
    per_user=True, per_chat=True,
)
```

### 5. Background Monitor + Bot Polling (main.py)
```python
def cmd_bot(cfg, db, args):
    notifier = Notifier(cfg)
    if not notifier.enabled:
        return 1
    
    bot_thread = start_bot_thread(cfg, db, notifier)  # Thread + asyncio
    
    try:
        while bot_thread.is_alive():
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    return 0
```

## Required Dependencies
```
requests>=2.28
PySocks>=1.7
python-dotenv>=1.0
python-telegram-bot>=21.0
```

## Egg Variables (Required)
| Variable | Description | Required |
|----------|-------------|----------|
| TG_BOT_TOKEN | From @BotFather | Yes |
| TG_CHAT_ID | Notification target (from @userinfobot) | Yes |
| TG_ADMIN_USER_ID | Admin user ID for command auth (from @userinfobot) | Recommended |

## Startup Command
`python3 main.py bot` — runs both Telegram polling and background monitor

## Security Features
- Password/proxy messages auto-deleted after processing
- Only TG_ADMIN_USER_ID can execute management commands
- Credentials never logged or stored in chat history
- User can manually delete chat messages anytime

## Commands Implemented
| Command | Description |
|---------|-------------|
| /start, /help | Main menu with keyboard |
| /list | Masked account list |
| /check | Manual health check all |
| /export | Send CSV+JSON of healthy accounts |
| /stats | Database statistics |
| /tgtest | Test notification |
| /add | Full conversation: email → pwd → recovery → proxy → confirm |
| /import | Reply CSV file → bulk import |
| /delete <email> | Delete with confirmation |
| /set <email> | Change: status/paused/note/proxy/password |