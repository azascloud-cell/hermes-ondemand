---
name: daily-news-briefing
description: \"Use for recurring news summaries. Timing and sources.\"
version: 1.0.0
author: Neng Lidya
---

# Daily News Briefing

Use this skill when a user requests a recurring news summary (cronjob) with specific language, timing, and source requirements.

## Workflow

1. **Requirements Gathering**:
   - Determine the **time** (e.g., 05:00 WIB).
   - Determine the **language** (e.g., Bahasa Indonesia).
   - Identify **preferred sources** (e.g., Detik, Kompas, BBC Indonesia).
   - Confirm **delivery target** (e.g., current Telegram thread).
   - Determine **format** (e.g., brief summaries with links, not raw lists).

2. **Cronjob Creation**:
   - Use `cronjob(action='create', ...)` with a self-contained prompt.
   - **Prompt Requirements**:
     - Define a persona (if requested, e.g., "Neng Lidya").
     - Explicitly instruct the agent to use `web_search` and `web_extract`.
     - **Critical**: Instruct the agent to find **direct article URLs** (not index/category pages) to avoid 404s or non-specific links. Use `site:domain.com` queries.
     - Define the exact output format (e.g., bold titles, 1-2 sentence summaries, and markdown links `[🔗 Read more](URL)`).

3. **Verification**:
   - Perform a manual `cronjob(action='run')` to verify the output quality and link validity before confirming to the user.

## Pitfalls & Lessons

- **The Index Page Trap**: Search results often return index pages (e.g., `/terbaru`). The prompt must explicitly forbid these and require direct article slugs.
- **Timezone Awareness**: Always confirm the timezone (e.g., WIB) to ensure the cron schedule is accurate.
- **Persona Consistency**: If the user requested a specific role-play persona, the cronjob prompt must include that persona so the automated delivery remains in character.

## Verification
- Verify that each link in the output leads to a specific article.
- Verify the delivery arrives at the correct platform/thread.
