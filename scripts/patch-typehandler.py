#!/usr/bin/env python3
"""Patch Telegram TypeHandler restoration (hermes-agent#85421)"""
import os
import pathlib

p = pathlib.Path("/home/hermes/.hermes/hermes-agent/plugins/platforms/telegram/adapter.py")
if not p.exists():
    print("adapter.py not found, skipping patch")
    raise SystemExit(0)

src = p.read_text()
if "TypeHandler as _TH" in src:
    print("already patched")
    raise SystemExit(0)

old = "            MessageHandler as _MH,\n            ContextTypes as _CT, filters as _filters,\n        )"
new = "            MessageHandler as _MH,\n            ContextTypes as _CT, TypeHandler as _TH, filters as _filters,\n        )"
if old in src:
    src = src.replace(old, new)
else:
    print("WARNING: old pattern not found")

old2 = "    TelegramMessageHandler = _MH\n    ContextTypes = _CT\n    filters = _filters"
new2 = "    TelegramMessageHandler = _MH\n    TypeHandler = _TH\n    ContextTypes = _CT\n    filters = _filters"
if old2 in src:
    src = src.replace(old2, new2)
else:
    print("WARNING: old2 pattern not found")

old3 = "    global CommandHandler, CallbackQueryHandler, TelegramMessageHandler\n    global ContextTypes, filters, ParseMode, ChatType, HTTPXRequest"
new3 = "    global CommandHandler, CallbackQueryHandler, TelegramMessageHandler, TypeHandler\n    global ContextTypes, filters, ParseMode, ChatType, HTTPXRequest"
if old3 in src:
    src = src.replace(old3, new3)
else:
    print("WARNING: old3 pattern not found")

p.write_text(src)
print("patched TypeHandler restoration")