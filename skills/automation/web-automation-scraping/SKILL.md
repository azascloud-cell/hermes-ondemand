---
name: web-automation-scraping
description: "Use when scraping web data and forwarding via APIs."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [scraping, automation, telegram-bot, requests, beautifulsoup, pterodactyl]
---

# Web Automation & Scraping

Guidelines for building scripts that interact with web services, extract data, and forward it to other platforms (like Telegram).

## General Workflow

1. **Analysis:** Inspect target site (Developer Tools $\rightarrow$ Network/Elements) to identify request patterns, required headers, and HTML structure.
2. **Session Management:** Use `requests.Session()` to maintain cookies and login states across multiple requests.
3. **Parsing:** Use `BeautifulSoup` for HTML extraction. Focus on stable selectors (IDs or unique classes).
4. **Forwarding:** Integrate API calls (e.g., Telegram Bot API) to push extracted data to the user.
5. **Stability:** Implement `time.sleep()` and `try-except` blocks to prevent crashes and avoid being flagged as a bot.

## Deployment Targets

### Pterodactyl (Generic Python)
When deploying to a Pterodactyl panel:
- **Dependencies:** Always provide a `requirements.txt` file. The panel installs these on startup.
- **Entry Point:** Name the main script `main.py` unless configured otherwise in the Startup tab.
- **Resources:** For lightweight scrapers, RAM 128MB-512MB is sufficient. If a headless browser (Selenium/Playwright) is required, RAM must be $\ge$ 1GB.

## Pitfalls & Lessons

- **API-Based Uploads:** Be aware that many Pterodactyl hosts disable file uploads via the Client API (Error 404/403). In these cases, manual upload via File Manager or SFTP is the only reliable path.
- **Bot Detection:** High-frequency scraping leads to IP bans. Use reasonable intervals (e.g., 30s+).
- **Dynamic Content:** If data is loaded via JavaScript after the page loads, `requests` + `BeautifulSoup` will not see it. Transition to a browser-based automation tool.
- **Security:** Never hardcode secrets in shared skills; use environment variables or configuration files.

## Templates
- See `templates/basic-scraper-forwarder.py` for a boilerplate implementation.
