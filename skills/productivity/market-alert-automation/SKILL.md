---
name: market-alert-automation
description: Use when setting up recurring market alerts via cronjobs.
---

# Market Alert Automation

This skill governs the creation and maintenance of recurring market analysis alerts delivered via cronjobs.

## Trigger
Use when the user requests automated, scheduled market reports, sentiment analysis, or "morning alerts" for specific assets (e.g., Gold/XAUUSD).

## Workflow
1. **Define Persona & Tone**: Ensure the cronjob prompt embeds the specific persona (e.g., Neng Lidya) and the user's relationship (e.g., Mas Azza) to maintain consistency across isolated cron sessions.
2. **Define User Constraints**: Explicitly include the user's trading style (e.g., ultra-scalper, specific SL/TP points) in the prompt so the analysis is actionable.
3. **Structure the Report**: Use a consistent, high-visibility format:
   - 🚩 **SENTIMEN HARI INI**: [BULLISH/BEARISH/SIDEWAYS]
   - 📰 **BERITA KUNCI**: Top 1-2 catalysts.
   - 🎯 **AREA PANTAUAN**: Key levels (Support/Resistance).
   - 💡 **CATATAN**: Personal reminder/discipline check based on user's constraints.
4. **Cron Configuration**:
   - `schedule`: Use standard cron syntax (e.g., `0 5 * * *` for 5 AM).
   - `enabled_toolsets`: Always include `["web", "terminal"]` to allow real-time data fetching.
   - `model`: Ensure a compatible model is explicitly set or a default is configured in `config.yaml` to avoid `RuntimeError: no model configured`.

## Pitfalls & Lessons
- **Model Configuration**: Cron jobs run in fresh sessions. If they fail with `no model configured` or `model not supported`, verify `model.default` in `config.yaml` or update the job specifically using `cronjob(action='update', job_id=..., model=...)`.
- **Persona Drift**: Since cron sessions lack chat history, the prompt MUST be self-contained with all identity and tone instructions.
- **Data Freshness**: Instruct the agent in the prompt to use real-time web searches rather than relying on internal knowledge.

## Verification
- Trigger a manual run using `cronjob(action='run', job_id=...)` immediately after creation to verify the prompt, toolsets, and model configuration work as expected.
