# Home Assistant hand-offs for Bedtime Bridge 0.4.8

What 0.4.8 needs on the Home Assistant side. Nothing here has been changed in the live instance
from this repo.

## 1. Install 0.4.8

**HACS → Bedtime Bridge → Update** to 0.4.8, then restart Home Assistant. It includes 0.4.7, so
if 0.4.7 isn't installed yet this does both. Open the app once afterwards (it sends Home
Assistant its push token).

## 2. Bedtime pending, and the Bedtime Nudge blueprint (item 1)

The integration adds **`binary_sensor.bedtime_bridge_bedtime_pending`**. It's on from setting
alarms (a plan or your own time) until bedtime runs, or until 2 hours before the first alarm
(attributes `since` and `until`). The bedtime shortcut's own plan doesn't turn it on.

Your Bedtime Nudge blueprint (`blueprints/automation/bedtime_nudge_v1-02.yaml`, used by
`automation.bedtime_nudge`) only nudges inside its clock windows, so on 31 Oct it stopped at
"Inside the widest bedtime window: false" at 4:04 AM. Three edits make it nudge (and auto-run)
whenever bedtime is pending, at any hour. Keep a copy of the file first (or edit it in the File
editor, which keeps one).

**a. A new input.** Under `blueprint: → input: → core: → input:`, after `bed_sensor:`:

```yaml
        bedtime_pending:
          name: Bedtime pending (Bedtime Bridge)
          description: >-
            On while alarms are set and bedtime hasn't run: nudge at any hour.
            Expected: binary_sensor.bedtime_bridge_bedtime_pending.
          default: binary_sensor.bedtime_bridge_bedtime_pending
          selector:
            entity:
              domain: binary_sensor
```

**b. The variable.** In the top-level `variables:` block, after `bed_sensor: !input bed_sensor`:

```yaml
  bedtime_pending: !input bedtime_pending
```

**c. Both windows.** In the `variables:` step just before "Inside the widest bedtime window",
end `in_shift_window` and `in_wide_window` with "or bedtime is pending":

```yaml
          in_shift_window: >-
            {%- set n = now().strftime('%H:%M:%S') -%}
            {{ ((win_start <= n and n < win_end) if win_start <= win_end
               else (n >= win_start or n < win_end))
               or is_state(bedtime_pending, 'on') }}
          in_wide_window: >-
            {%- set n = now().strftime('%H:%M:%S') -%}
            {{ ((off_window_start <= n and n < off_window_end)
               if off_window_start <= off_window_end
               else (n >= off_window_start or n < off_window_end))
               or is_state(bedtime_pending, 'on') }}
```

The windows themselves stay as they are. Save, then **Tools → YAML → Reload automations** (or
re-save `automation.bedtime_nudge`). Its new input already has the right default.

To check: set alarms in the app, and `binary_sensor.bedtime_bridge_bedtime_pending` turns on.
Run *I'm Ready For Bed - App* (or tap Good night) and it turns off.

## 3. Good night (item 5)

The app's **Good night** (the bar's slide-and-hold, or "Good night in Bedtime Bridge") asks Home
Assistant to send RUN_BEDTIME, the push the nudge sends. That needs *Phone commands* on and the
notify action set (*Configure → Phone*), as I'm awake does. If bedtime already ran tonight, it
sends nothing.

## 4. Testing reports (items 9 and 11)

Reports from the app (Report something, and the automatic ones) are saved in
**`bedtime_bridge_reports/reports.jsonl`** in the config folder (one report per line, the last
200 kept, screenshots next to it). Not in `www`, which anyone can open without signing in. Each
one also writes a line to the log ("Bedtime Bridge report: …").

Home Assistant files automatic reports of its own, at most one of each per night:

- in bed for 10 minutes with bedtime pending and no RUN_BEDTIME;
- RUN_BEDTIME, RUN_GOOD_MORNING or RUN_LEAVE_CHECK sent, and its shortcut not reported as ran
  within 10 minutes.

**For Claude to read them:** once the folder exists (after the first report), add
`bedtime_bridge_reports` as a custom directory in the **ha-mcp settings**. Then ask Claude to
"read my reports".

## 5. Configure goes back to the menu (item 10)

In **Configure**, submitting a page now goes back to the menu, which lists the pages you've
changed. **Save and close** saves them all; closing with ✕ before that drops the changes.

## 6. No alarms tomorrow and your own alarms' backstops (item 7)

*No alarms tomorrow / this morning* now turns off the backstops you'd switched on for your own
alarms too. A shift's backstops still follow the calendar, as before.

## 7. The bedtime health check (item 14)

When the bedtime shortcut reports **Completed** (its last step), the app asks Home Assistant
whether everything is set for the morning: the alarms match, the backstops are armed when they
should be, phone commands are on and it has the push token. Anything off shows on the bar after
bedtime ("⚠ Backstops not armed") and is filed as an automatic report. Nothing to set up; it
uses the *Report Shortcut Ran → Completed* step the shortcut already has.
