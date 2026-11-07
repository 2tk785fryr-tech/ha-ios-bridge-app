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
- **"15 min later" once per warning (item 9).** A second *later* for the same wind-down warning
  does nothing and is logged. The warning that comes again before the new time says *Wind-down
  moved to 9:05 · bed 9:50*, and isn't sent within the warning time of the press. With the Apple
  push key set up, Home Assistant also sends the app a silent push (`wind_down_changed`) so it
  shows the new time at once.
- **Remote days' backstops (item 10).** A remote plan sends its three backstop times (after the
  last alarm, before the start), and the ladder arms those for that morning instead of the
  calendar's leave-by. With no gap between the last alarm and the start, **Bedtime Bridge →
  Ladder status** reads the new `idle_remote` ("No backstops: the remote shift starts at its last
  alarm"). Your Shift Calendar Watchdog reads that state, so it needs section 2.
- **Remote work days (item 5).** A plan for a shift worked from home carries `remote: true`, no
  `leave_by` and no trip. Home Assistant sends no `RUN_LEAVE_CHECK` for it.
  `sensor.bedtime_bridge_leave_by` stays empty that morning. None of your automations or scripts
  use it (searched 2 Nov), so nothing else needs changing.

## 2. Shift Calendar Watchdog: quiet on a remote day with no backstops (item 10)

`automation.shift_calendar_watchdog` runs on the blueprint `shift_calendar_watchdog_v1-31.yaml`.
It stays quiet only when `sensor.master_bedroom_bedtime_bridge_ladder_status` is one of the idle
states it knows. `idle_remote` isn't one of them, so on a remote day whose shift starts at its last
alarm it would alert that the backstop isn't armed.

In the blueprint's `ladder_idle` variable, add `'idle_remote'` to the list, and call it v1-32:

```yaml
           and states(ladder_status_sensor) in ['idle_override_off', 'idle_leave',
                                                 'idle_uncovered', 'idle_no_shift',
                                                 'idle_own_off', 'idle_remote'] }}
```

Until then, the watchdog alerts only on remote mornings with no gap between the last alarm and the
start: a fixed-time rule at or after the start, or *Get ready on a remote day* set to 0. The usual
remote day (30 min to get ready) has backstops and reads `armed`.

`automation.wake_deadline_backstop` fires on the rung sensors' times and needs nothing.
`script.bedtime_readout` also reads the ladder status. I couldn't open its config from here, so
check that it reads a new status sensibly ("No backstops: the remote shift starts at its last
alarm" is in the status's `reason`).

## 3. Install 0.4.11.1 (items 12, 16 and 20)

**HACS → Bedtime Bridge → Update** to 0.4.11.1, then restart Home Assistant. No settings change,
nothing to edit in your automations or blueprints. What's different:

- **Home late only on arriving (item 12).** Wind-down's *home late* rule now acts only when
  `person.michael_perschy` changes to `home` from something else. A location update while you're
  already home (the attribute updates at 20:49:47 and 20:59:55 on 3 Nov) no longer moves
  wind-down or go to bed. *15 min later* counts from the planned wind-down, and getting home late
  can only push it later, not add on top.
- **A warning after every *later* (item 16).** Replaces item 9's "not within the warning time of
  the press": every *15 min later* gets *Wind-down moved to 9:05 · bed 9:50* before the new start,
  1 min after the press if the warning time has already passed. Once wind-down is up against go to
  bed − the 30-min minimum, the warning offers *Cancel tonight's wind-down* only.
- **On your way (item 20).** With the Apple push key, the morning Live Activity goes stale at Leave
  by, so the Lock Screen reads *Past leave time · 5:43* and counts the minutes late on its own.
  When `person.michael_perschy` changes from `home` to away between the first alarm and the
  shift's start, Home Assistant ends the activity showing *On your way · Days 6:30* (left on the
  Lock Screen until the start) and drops any leave check still to come. Coming back home before
  the start puts *Leave in* / *Past leave time* back. Only the integration's **Presence** option is
  used; nothing new to set up.


## 4. Install 0.4.11.2 and Wake Deadline Backstop v1-40 (item 26)

**Marketplace → Bedtime Bridge → Update** to 0.4.11.2, then restart Home Assistant. It listens for
a new event, `bedtime_bridge_backstop_fired`, keeps this morning's fired backstops until the next
plan (the app shows a red *fired* tag on them), and the weekly summary's *backstops fired* counts
these instead of the rung times that passed. Until the blueprint below is updated nothing fires
the event, so no tag shows and the weekly count reads 0.

### Blueprint: `blueprints/automation/wake_deadline_backstop_v1-30.yaml` → v1-40

**The whole file is in the repo:** `blueprints/automation/wake_deadline_backstop_v1-40.yaml`. Put it
in Home Assistant at `/config/blueprints/automation/wake_deadline_backstop_v1-40.yaml` (File editor
or Studio Code Server: new file, paste it all in), next to v1-30. Keep v1-30 until the new one has
run a morning. It's v1-30 exactly, plus the edits below, so you don't need to make them by hand;
they're listed so you can see what changed. Each escalating branch fires the event as its first
step. Nothing else changes: the triggers, conditions, `mode: parallel` and every choose option's
index stay the same. Inside options 1–5 each step's index moves up by one, as the event is
step 0.

1. **Name:** `name: Wake Deadline Backstop (v1-40)`.
2. **Revision history**, after the v1-30 entry:

   ```yaml
       - v1-40: Each escalating branch (options 1-5) first fires
         `bedtime_bridge_backstop_fired` with `rung` (early, deadline, late) and `level`
         (soft, full, gentle), so Bedtime Bridge 0.4.11.2 can show which backstops went off
         and count them for the weekly summary. Option indexes unchanged; inside options 1-5
         every step index moves up by one. Options 0 and the default fire nothing.
   ```

3. **Option 1 (EARLY, still in bed):** as the first line of its `sequence:`

   ```yaml
          - event: bedtime_bridge_backstop_fired
            event_data:
              rung: early
              level: soft
   ```

4. **Option 2 (DEADLINE, still in bed):** first in its `sequence:`

   ```yaml
          - event: bedtime_bridge_backstop_fired
            event_data:
              rung: deadline
              level: full
   ```

5. **Option 3 (DEADLINE, bed empty, room never left):** first in its `sequence:`

   ```yaml
          - event: bedtime_bridge_backstop_fired
            event_data:
              rung: deadline
              level: soft
   ```

6. **Option 4 (LATE, room never left):** first in its `sequence:`

   ```yaml
          - event: bedtime_bridge_backstop_fired
            event_data:
              rung: late
              level: full
   ```

7. **Option 5 (gentle, own alarm):** first in its `sequence:`

   ```yaml
          - event: bedtime_bridge_backstop_fired
            event_data:
              rung: "{{ rung }}"
              level: gentle
   ```

Then in **Settings → Automations & scenes → Blueprints**, reload, and point the Wake Deadline
Backstop automation at v1-40 (its inputs carry over: same names). To check without waiting for a
morning: **Developer tools → Events**, fire `bedtime_bridge_backstop_fired` with
`{"rung": "deadline", "level": "soft"}`. Open the app: Your morning's Deadline backstop shows a
red *fired* tag until the next plan (it also adds 1 to this week's summary).
