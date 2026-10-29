# Home Assistant hand-offs for Bedtime Bridge v0.4.1

These are the Home Assistant changes v0.4.1 needs, for the Home Assistant chat to apply. Nothing
here has been changed in the live instance from this repo. Read every entity id back before using
it (`ha_search` for `bedtime_bridge`), and read each change back after applying it.

Integration version: **0.4.1**. Install it from HACS and restart before anything below, then tell
the Home Assistant chat that 0.4.1 is installed. Several steps depend on it (see *Watchdog and
Readout*).

## 1. Integration options (Settings → Devices & services → Bedtime Bridge → Configure)

| Option | Set to | Why |
|---|---|---|
| Work calendar | `calendar.calendar` | First day back, "wake up" appointments that replace a shift (item 11), and the next shift once today's is over (item 19) |
| House backstop reads | **Old template (sensor.wake_rung_\*)**, until the cutover (section 6) | The app shows the times the house backstop really fires at (items 6 and 8) |
| Old template's rung sensors | `sensor.wake_rung_early`, `sensor.wake_rung_deadline`, `sensor.wake_rung_late`, in that order | Read back first; they're what the app shows until the cutover |
| Restart when a morning changes | `automation.wake_confirm_still_in_bed_after_alarm`, `automation.wake_deadline_backstop` | Unchanged from v0.4. Edits to single alarms (item 13) and Sleep later (item 12) don't restart them |
| Turn on when I end the alarms before they ring | Unchanged (`input_boolean.wake_mike`, or the gentler instance from the v0.4 hand-offs) | |
| Warn if a phone shortcut doesn't finish within | Default is fine | Also covers `RUN_LEAVE_CHECK` (section 5) |

## 2. What changed in the published state

- **Ladder status:** `done` no longer stays after the morning (item 19). Once today's shift is
  over, the ladder rolls straight on to the next shift from the calendar, or to an `idle_*` status.
  There's one new status, `idle_own_off`: your own alarm on a day off or leave, with its backstops
  switched off (item 14, the default).
- **Your own alarm with backstops on (item 14):** status `armed`, with rungs at fixed times after
  the last alarm (default 15/30/45 min, or the times edited in the app's preview). The rung
  sensors carry a new attribute, `firing`: `gentle` (a push and a light ramp) or `full` (the
  normal Backstop).
- **A "wake up" appointment that replaces the shift (item 11):** the rungs follow the appointment,
  and the new rung attribute `replaces_shift` names the shift it replaced.
- **Ladder status** has a new attribute, `house_backstop`, with which times the house backstop
  reads: `source` (`old` | `bridge`) and the three times.
- **Last event** gains `last_command`, `last_morning_change`, `last_stop` (how each stop was
  decided, for tracing a morning; item 1) and `alarms_missing`.
- **New `bedtime_bridge` event types:** `morning_change_refused` (a change past the late backstop)
  and `alarms_missing` (the phone set fewer alarms than planned; item 1).

## 3. Watchdog and Readout v1-30

Apply these **only once 0.4.1 is installed**. Under 0.4.0 a `done` status stood all day, and these
changes treat a standing `done` as stuck.

- `automation.shift_calendar_watchdog` and `script.bedtime_readout`: stay quiet on any `idle_*`
  status, including the new `idle_own_off`, using the existing two-signal check: rungs
  `unavailable` **and** status `idle_*`. Treat `done` as normal only in the minutes right after a
  morning. A `done` that's still there an hour after the late rung is a fault.
- They read the rung attributes (`leave_by`, `first_day_back`, `replaces_shift`) instead of working
  them out again.
- Check: `dry_run: true` on a night with override `Off` gives no "DISARMED" push and no spoken
  warning.

## 4. Backstop gates and own-alarm firing

On `automation.wake_deadline_backstop` (interim, until v0.5 fires the ladder itself):

- Gate on **ladder status `armed`** (instead of `effective_shift` in `[Days]`), so appointment
  mornings, replaced shifts and own alarms with backstops on all fire, and `idle_own_off` doesn't.
- **Presence gate** before firing: away means nothing fires; unknown counts as home.
  (`person.michael_perschy` includes `device_tracker.macbook`; gate on the iPhone's tracker, or
  drop the MacBook from the person.)
- **`firing: gentle`** (own alarm): send the push and run the light ramp only, with no siren and no
  full Backstop sequence. Missing or `full` means the normal Backstop. Read the attribute from the
  rung sensor that fired.

## 5. Leave checks (item 17), phone side only

Nothing to change in Home Assistant. The integration sends a time-sensitive `RUN_LEAVE_CHECK` push
at each leave reminder the app asks for (default 15 min before and at leave time), while you're
home, until 15 min after leave-by. A morning change, skip or cancel stops them. Each new leave-by
from the phone clears the push and moves the remaining checks. On the phone: one "When I receive a
notification from Home Assistant" automation for `RUN_LEAVE_CHECK` that runs Bedtime Bridge
**Check Drive and Remind** (see `docs/shortcuts.md`).

## 6. Backstop cutover (item 15)

`current_shift.yaml` and `sensor.wake_rung_*` stay as they are throughout, so rolling back needs no
code.

a. **Install 0.4.1** (which has the item 1 fix) and the matching app build.

b. **Work calendar** option → `calendar.calendar` (section 1).

c. **Soak: 3 normal Days mornings.** Each morning, compare the integration's rungs
   (`sensor.bedtime_bridge_ladder_*`, or `sensor.bedtime_bridge_safety_net_*` on an install from
   before 0.4.0; read back which) with `sensor.wake_rung_*`:
   - within a few minutes of each other (the bridge uses the real drive time);
   - 15 min earlier on a first day back, by design;
   - ladder status `armed`.

   A missing rung, a `fault`, or any difference over 10 min that can't be explained restarts the
   soak at zero.

d. **Apply the hand-offs**, in this order: section 3 (Watchdog and Readout) first, then section 4
   (Backstop gates), then point the Backstop's rung inputs (`rung_early_sensor`,
   `rung_deadline_sensor`, `rung_late_sensor`) and the Watchdog's `rung_sensors` at the bridge's
   rung sensors. Read every entity id back first.

e. **House backstop reads** option → **Bedtime Bridge ladder**. The app's "until the cutover"
   notes (confirm screen, Your morning, own alarm, replaced shift) go away on their own.

f. **Watch 3 mornings.** Rollback: point the Backstop and Watchdog inputs back at
   `sensor.wake_rung_*`, restore the previous Readout file, and set House backstop reads back to
   Old template.

There's no manual kill switch for the backstops (decided). Use the override `Off`, or set an own
alarm with backstops off.
