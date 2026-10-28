# Home Assistant hand-offs for Bedtime Bridge v0.4

Changes on the Home Assistant side that v0.4 needs, for the Home Assistant chat to apply. Nothing
here has been changed in the live instance from this repo. Read each item back after applying it.

Integration version: **0.4.0**. Install it from HACS (and restart) before the item 6 steps.

## Item 7: Sleep In has one owner

The integration sets `input_boolean.sleep_in` on every plan, on a skipped morning, on *Not going to
sleep yet*, and (item 3) when the morning changes. The Bedtime Readout stops setting it.

1. In the Bedtime Readout (`script.bedtime_readout`, the YAML file in `/config/scripts/`), set
   `auto_set_sleep_in: false`. The readout still reads Sleep In for what it says; it just doesn't
   write it.
2. Reload scripts.
3. Read back: `auto_set_sleep_in` is `false`, and the readout's spoken text still mentions Sleep In
   correctly after a bedtime run (`dry_run: true` is enough).

Still writing Sleep In after this, outside Home Assistant: the bedtime shortcut's "No alarms →
enable Sleep In? → Yes" HomeKit scene (see `docs/shortcuts.md`). That's a phone-side decision for
Mike, not a hand-off.

## Item 6: leave-by backstop ladder

The integration now publishes the ladder; it doesn't fire anything (the Backstop blueprint still
does until v0.5). Nothing below should be applied until 0.4.0 is installed and the soak (step 6)
has passed. `current_shift.yaml` and `sensor.wake_rung_*` stay as they are throughout, so rollback
needs no code.

### 1. Integration options (Settings → Devices & services → Bedtime Bridge → Configure)

- **Backstop ladder for these shift types:** `Days`.
- **Work calendar:** `calendar.calendar` (used to tell a first day back when the phone hasn't
  planned; if it can't be read, the 15-minute extra is applied).
- The old *Safety-net times for* and *Safety-net margin* options are gone.

### 2. Read back the entity ids (never assume them)

Use `ha_search` for `bedtime_bridge` and record:
- The three rung sensors. On an install that existed before 0.4.0 they keep their old ids
  (`sensor.bedtime_bridge_safety_net_early` / `_deadline` / `_late`) under the new names *Ladder
  early / deadline / late*. A fresh install gets `sensor.bedtime_bridge_ladder_early` etc.
- `sensor.bedtime_bridge_ladder_status` (new).
- The five ladder settings (number entities, minutes): *Ladder early* (50), *Ladder deadline*
  (35), *Ladder late* (20), *First day back extra* (15), *Fallback drive time* (35).

What "not armed" looks like: the rung sensors read `unavailable`, and ladder status is one of
`idle_override_off`, `idle_leave`, `idle_uncovered`, `idle_no_shift` (attribute `reason` says
which), or `done` after the morning, or `fault`. Rung attributes: `leave_by`, `leave_by_source`
(`plan` | `calendar`), `first_day_back`, `shift_start`, `appointment`, `appointment_start`,
`delay_minutes`, `changed_by`, `reason`, `weather_extra_minutes`, `condition` (and
`effective_shift: Days`, kept for the Backstop's shift gate until step 4).

### 3. Watchdog v1-30 and Readout v1-30

- `automation.shift_calendar_watchdog` (input `rung_sensors`) and `script.bedtime_readout`
  (hardcoded in `/config/scripts/`) stay quiet on any `idle_*` ladder status, with the same
  two-positive-values pattern they use for leave: rungs `unavailable` **and** ladder status
  `idle_*`. Only that pair counts as a deliberate "off"; anything else unexpected is still a fault.
- They read the rung attributes above instead of re-deriving leave-by or first day back.
- Check the Readout with `dry_run: true` on a night with override `Off`: no "DISARMED" push, no
  spoken warning.

### 4. Backstop instance gates (interim, until v0.5)

On `automation.wake_deadline_backstop`:
- Gate on **ladder status `armed`** instead of `current_shift`'s `effective_shift` in `[Days]`, so
  appointment mornings fire.
- Add a **presence gate** before firing: away means nothing fires; unknown counts as home.
  `person.michael_perschy` includes `device_tracker.macbook`, so a MacBook left at home reads
  home: drop it from the person, or gate on the iPhone's tracker. The integration's "only when
  you're home" option has the same issue.

### 5. Dry run

Move a rung to now + 60 s and check the Backstop fires it. (The integration publishes any rung
that would land in the past as now + 60 s; this proves that lead is enough.) One way: on a Days
night, set *Ladder early* so the early rung lands a couple of minutes ahead, watch it fire, then
set it back to 50.

### 6. Soak, then cut over

- Soak: the bridge rungs and `sensor.wake_rung_*` show the same times on at least three Days
  mornings, including one first day back (bridge 15 minutes earlier there, by design).
- Cutover: point the Backstop (`rung_early_sensor`, `rung_deadline_sensor`, `rung_late_sensor`),
  the Watchdog (`rung_sensors`) and the Readout at the bridge's rung sensors, all at once.
- Rollback: point those inputs back at `sensor.wake_rung_*` and restore the previous Readout file.

## Items 3, 8 and 9: changing a morning, ending early, routines once

### Integration options (Configure)

- **Restart when a morning changes:** `automation.wake_confirm_still_in_bed_after_alarm` and
  `automation.wake_deadline_backstop` (suggested when they exist). Item 3 turns them off, which
  cancels anything they're running, and straight back on, and clears the `wake_backstop` and
  `wake_confirm` notifications. Retired in v0.5.
- **Turn on when I end the alarms before they ring:** leave empty to use `input_boolean.wake_mike`,
  or point it at a gentler wake (below).

### A gentler early wake (optional)

For ending the alarms from the app before they ring (item 8): a second **Wake Sequence** instance
with its own trigger helper, for example a new `input_boolean.wake_mike_early`, the same lights
and Day Mode helper as the existing instance, and a longer **Wake Transition** (60–120 s instead
of 1). Then set the option above to `input_boolean.wake_mike_early`. Wake Sequence resets its
helper itself, so nothing else is needed. If you'd rather keep it simple, leave the option empty.

### Nothing else to change

- Item 9 (Wake Mike and Good Morning once per wake-up) is all in the integration. Snooze Fade
  already ignores a repeat; Wake Sequence no longer gets one.
- Item 3's house steps after a stop are, in order: Sleep In from the new alarms, then
  `input_boolean.bedtime_routine` on (Bedtime Routine: Awake For Day off, Night Mode re-armed,
  lights swept, bedroom curtain closed), then the `RUN_BACK_TO_BED` push. While snoozing it only
  turns `input_boolean.wake_fade` off (Snooze Fade's cancel branch fades the nightstands down).
- The change's reason and note show in the `morning_changed` event and in Last event's
  `last_morning_change` attribute.
