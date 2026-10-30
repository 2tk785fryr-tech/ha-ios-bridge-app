# Home Assistant hand-offs for Bedtime Bridge v0.4.3

These are the Home Assistant changes v0.4.3 needs, for the Home Assistant chat to apply. Nothing
here has been changed in the live instance from this repo. Read every entity id back first.

Integration version: **0.4.3**. Install it from HACS and restart first.

## 1. Winding down helper (item 5)

1. Create a toggle helper: **Settings → Devices & services → Helpers → Create helper → Toggle**,
   named *Winding down*. Read back its entity id (expected `input_boolean.winding_down`; none
   exists today).
2. Integration options (**Settings → Devices & services → Bedtime Bridge → Configure**): set
   **Winding down helper** to it.
3. What the integration does with it: on at wind-down while you're home; off at go to bed, when
   you cancel, when you get into bed early, and on a reset. House automations on it (dim lights,
   quieter TV) are Michael's to write.

## 2. Bedroom door, notifications, phone battery (items 5 and 10)

In the same options:

| Option | Set to | Read back |
| --- | --- | --- |
| Bedroom door sensor | `binary_sensor.aqara_door_and_window_sensor_door_2` | "Master Bedroom Door Door", Master Bedroom (read 29 Oct) |
| Bed sensor | unchanged (`binary_sensor.master_bedroom_bed_presence_bed_occupied_left`) | |
| Wind-down notifications to | empty (uses the notify action), or another `notify.mobile_app_…` | |
| Phone battery level | `sensor.mikes_iphone_battery_level` | read 29 Oct |
| Phone battery state | `sensor.mikes_iphone_battery_state` | read 29 Oct ("Charging", "Not Charging", "Full") |

Door closed (`off`) **and** bed occupied counts as in bed: no go to bed notification, no Still up
reminders, and it records when you went to bed.

The go to bed notification is **critical**: allow Critical Alerts for the Home Assistant app on
the phone (Settings → Notifications → Home Assistant → Critical Alerts), or it arrives as a normal
one. Still up and Plug in your phone are time-sensitive.

## 3. What runs on its own (items 5, 7, 9, 10, 14, 15)

Nothing to build in Home Assistant for these; the integration handles them:

- **Wind-down:** the warning with "15 min later" and "Cancel tonight's wind-down" buttons (it
  listens for `mobile_app_notification_action` itself), RUN_WIND_DOWN, the helper, the note for
  event or moved mornings, go to bed, and Still up every 10 min for an hour. Away overnight: the
  warning and go to bed still reach the phone; no helper, no reminders.
- **Phone commands** (with *Send phone commands* on): `RUN_PLAN_PREVIEW`, `RUN_WIND_DOWN`,
  `RUN_CANCEL_WIND_DOWN`, `RUN_MORNING_UPDATE`. Phone side in `docs/shortcuts.md`.
- **Reset** (new `reset` message from the app's Settings → Reset): clears the alarm state, the
  ladder's delay and weather moves, pending leave checks and phone commands, turns the napping
  and winding-down helpers off, fires a `reset` event, then recalculates the ladder from the
  calendar alone. It never touches the override, Sleep In or Awake For Day.
- **App expiry:** the app reports when it stops opening; a notification at bedtime on the last
  2 days. With the paid account (since 29 Oct) the install lasts a year.
- **Plug in your phone:** at bedtime and at go to bed, under the app's threshold and not
  charging, and once more 10 min later.
- **Weekly summary:** Sunday 6:00 PM by default (the app's setting), as a notification that opens
  the app and the sensor below.

## 4. New entities

| Entity | What |
| --- | --- |
| `sensor.bedtime_bridge_wind_down_status` | scheduled / winding_down / bedtime / cancelled / off; attributes first_alarm, source (alarms, preview, calendar), appointments_checked, reminders |
| `sensor.bedtime_bridge_wind_down` | tonight's wind-down (timestamp) |
| `sensor.bedtime_bridge_go_to_bed` | tonight's go to bed (timestamp) |
| `sensor.bedtime_bridge_went_to_bed` | when you got into bed (door closed + bed occupied) after wind-down |
| `sensor.bedtime_bridge_bedtime_off_target` | minutes after (+) or before (−) go to bed; kept in history |
| `sensor.bedtime_bridge_app_expires` | when this install of the app stops opening |
| `sensor.bedtime_bridge_weekly_summary` | the week in a line; attributes with the numbers |

Read the ids back: the device may have a prefix (e.g. `sensor.master_bedroom_bedtime_bridge_…`,
as `ladder_status` has).

New `bedtime_bridge` event types: `wind_down_started`, `wind_down_cancelled`,
`wind_down_go_to_bed`, `reset`. `cancelled` now carries `sleep_in` and `morning` (No alarms
tomorrow).

## 5. Leave titles (item 12)

The app reads leave from all-day events titled with any of its **Leave titles** (default
*Leave*). Update `current_shift.yaml`'s leave list to the same titles; today it's only "Leave",
which matches the default, so nothing changes unless more titles are added in the app. From v0.6
the integration reads them from a matching option.

## 6. Nothing else

Items 1–4, 6, 8, 11, 13 and 16 are app-only (No alarms tomorrow's Home Assistant side is the
`cancelled` message above).
