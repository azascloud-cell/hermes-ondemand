# Timezone Conversion Reference

For scheduling cronjobs in WIB (Western Indonesian Time, UTC+7):

## WIB to UTC Conversion
- WIB is UTC+7, so subtract 7 hours from WIB time to get UTC
- Example: 5:00 AM WIB = 22:00 UTC (previous day)
- Therefore, a daily 5 AM WIB cron would be: `0 22 * * *`

## Cron Schedule Formats
- Standard 5-field: `minute hour day month weekday` (e.g., `0 22 * * *`)
- Hermes supports additional formats:
  - `'30m'` - every 30 minutes
  - `'every 2h'` - every 2 hours
  - ISO timestamp for one-shot jobs

## Important Notes
1. Always verify the actual timezone setting of the Hermes instance
2. The server may be running in UTC - confirm before setting schedules
3. Daylight saving changes may affect some regions but not WIB
4. For user-specified local times, always convert to the server's timezone

## Session Example
In this session, the user requested 5 AM WIB delivery. The equivalent
cron schedule in UTC would be `0 22 * * *` (10 PM UTC on previous day).
