# Home Assistant hand-offs for Bedtime Bridge 0.4.10

What 0.4.10 needs on the Home Assistant side. Nothing here has been changed in the live instance
from this repo. Entities are named by what they are, with the id as read from your Home Assistant
on 1 Nov 2026.

## 1. Install 0.4.10

**HACS → Bedtime Bridge → Update** to 0.4.10, then restart Home Assistant and open the app once.
No settings change, and nothing in the blueprints or automations. What's different:

- **Good morning (item 2).** As before, `RUN_GOOD_MORNING` goes out on the first alarm stopped.
  New: a later stop in the same wake-up sends it again, but only when the shortcut never reported
  it ran (its *Report Shortcut Ran* step). Once it has reported, later stops send nothing.
- **Stop on the banner is a snooze (items 1–3).** Home Assistant now gets `snoozed` (Wake Snooze
  Fade), not `stopped`, when Stop is pressed on the banner or Lock Screen. Only the app's Stop
  screen sends `stopped`: the slide for one alarm (`alarm_times` still listing the rest), the hold
  for all (`all: true`). `stop_behavior` and `up` are no longer in the stop, so **Bedtime Bridge →
  Last event**'s `last_stop` shows them empty.
- **Why 1 Nov 08:18 ended everything:** Michael's side of the bed
  (`binary_sensor.master_bedroom_bed_presence_bed_occupied_left`) read empty from 08:17:14, 66 s
  before the Stop, so the app took him for up. From 0.4.10 a reading like that can't end alarms.
  The bed sensor still needs adjusting and calibrating (Michael).
- **No alarms Sunday (item 10)** now sends `skipped` (with the shift, if one is on the calendar,
  so the shift override goes to Off until it's passed) instead of `cancelled`. Like `cancelled`,
  it ends bedtime pending and turns your own alarms' backstops off. Undo is the skipped-morning
  card, which sends `unskipped`.
- **Reports (item 13)** you sent from the phone can be edited or deleted. The line in
  `bedtime_bridge_reports/reports.jsonl` is replaced (with `edited`) or removed with its
  screenshot. Automatic reports stay.

## 2. To check

- After a morning: **Bedtime Bridge → Last event** says `stopped` only after the Stop screen's
  slide or hold, and good morning ran once (or twice if the first push wasn't reported).
- Edit a report on the phone (Settings → About → Testing reports → Reports sent), then read the
  file: the same line, with the new note and `edited`.
