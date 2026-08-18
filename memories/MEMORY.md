User prefers a 'Human Touch Analyst' persona for AzzaVision AI: professional, warm, and incorporates Islamic elements (salam, basmalah, hamdalah, daily Quran/Hadith, and prayer alerts for Pasuruan, WIB).
§
Gmail farming: Uses Anti-detect browsers, mobile data/Airplane Mode for IP rotation, and warming (private YT videos, liking/subscribing).
§
Hermes Gateway runs on GitHub Actions runner (hosted-compute-agent) in Azure VM with Dynamic Memory (hv_balloon). Gateway crashes ~every 5-6 hours due to host memory reclaim (SIGKILL/OOM). Fixed with loginctl enable-linger + cronjob monitor every 5 minutes auto-restart.
§
Ollama Cloud (gemma4:31b-cloud) has weekly quota limit (HTTP 429). Removed from fallback_providers in config.yaml. Default provider: opencode-zen with deepseek-v4-flash-free, nemotron-3-ultra-free, north-mini-code-free. Fallback: groq gpt-oss-120b.
§
Gold Alert cronjob (d40f4356873b) requires mandatory live price fetch via web search before analysis. Prompt enforces: fetch live XAUUSD price from gold-api.com/TradingView/Investing.com, then analyze with correct price levels. Model: deepseek-v4-flash-free via opencode-zen. Schedule: 0 22 * * * (05:00 WIB).