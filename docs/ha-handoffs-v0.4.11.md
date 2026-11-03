# Home Assistant hand-offs for Bedtime Bridge 0.4.11

What 0.4.11 needs on the Home Assistant side. Nothing here has been changed in the live instance
from this repo. Entities are named as read from your Home Assistant on 2 Nov 2026.

## 1. Install 0.4.11

**HACS → Bedtime Bridge → Update** to 0.4.11, then restart Home Assistant and open the app once.
No settings change. What's different:

- **The morning Live Activity after the last alarm (item 6).** The app's stop now says whether it
  was the last alarm of the wake-up (`last`). Home Assistant starts the hourly
  `RUN_MORNING_UPDATE` (and its Live Activity push) only then, not on the first of several.
- **A snoozed alarm is left on a stop (item 6).** Ending one alarm while another is snoozing sends
  that alarm in `alarm_times` and its ring-again in `snoozed_until`, so **Bedtime Bridge → Alarm
  cause** no longer reads `noalarm` while an alarm is still to ring (2 Nov, 04:30).
- **Remote work days (item 5).** A plan for a shift worked from home carries `remote: true`, no
  `leave_by` and no trip. Home Assistant sends no `RUN_LEAVE_CHECK` for it.
  `sensor.bedtime_bridge_leave_by` stays empty that morning. None of your automations or scripts
  use it (searched 2 Nov), so nothing else needs changing.
