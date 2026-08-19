User prefers a 'Human Touch Analyst' persona for AzzaVision AI: professional, warm, and incorporates Islamic elements (salam, basmalah, hamdalah, daily Quran/Hadith, and prayer alerts for Pasuruan, WIB).
§
Gmail farming: Uses Anti-detect browsers, mobile data/Airplane Mode for IP rotation, and warming (private YT videos, liking/subscribing).
§
Hermes Gateway runs on GitHub Actions runner (hosted-compute-agent) in Azure VM with Dynamic Memory (hv_balloon). Gateway crashes ~every 5-6 hours due to host memory reclaim (SIGKILL/OOM). Fixed with loginctl enable-linger + cronjob monitor every 5 minutes auto-restart.
§
Ollama Cloud (gemma4:31b-cloud) has weekly quota limit (HTTP 429). Removed from fallback_providers in config.yaml. Default provider: opencode-zen with deepseek-v4-flash-free, nemotron-3-ultra-free, north-mini-code-free. Fallback: groq gpt-oss-120b.
§
Gold Alert cronjob (d40f4356873b) requires mandatory live price fetch via web search before analysis. Prompt enforces: fetch live XAUUSD price from gold-api.com/TradingView/Investing.com, then analyze with correct price levels. Model: deepseek-v4-flash-free via opencode-zen. Schedule: 0 22 * * * (05:00 WIB).
§
User wants full Telegram chat-based management for Pterodactyl bots: add/import/delete/set accounts via conversation handlers, with auto-delete of credential messages after successful login verification, and proxy-per-account support via conversation flow. Prefers 'python3 main.py bot' as single deploy command.
§
User deploys to Pterodactyl panels (1GB RAM), uses custom eggs with required variables: TG_BOT_TOKEN, TG_CHAT_ID, TG_ADMIN_USER_ID. Startup command: python3 main.py bot. Expects one-click install via egg's installation script.
§
User is Mas Azza, Indonesian, warm communication with Islamic elements (salam, basmalah, hamdalah). Calls agent 'Neng Lidya' as Human Touch Analyst. Runs AZZAVISION AI trading channel. Advanced Linux (CachyOS/Arch), Termux experienced. Gmail farming business with account warming, clustering recovery emails, anti-detect browsers.