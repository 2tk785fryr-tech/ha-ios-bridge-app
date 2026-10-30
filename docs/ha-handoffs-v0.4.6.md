# Home Assistant hand-offs for Bedtime Bridge 0.4.6

What 0.4.6 needs on the Home Assistant side. Nothing here has been changed in the live instance
from this repo.

## 1. Install 0.4.6

**HACS → Bedtime Bridge → Update** to 0.4.6, then restart Home Assistant. It includes 0.4.5.

## 2. Hallway presence (item 2, mornings with no alarms)

**Settings → Devices & services → Bedtime Bridge → Configure → Hallway presence.** It suggests
these when they exist; keep the ones that see you just outside the bedroom:

- `binary_sensor.hallway_master_presence`
- `binary_sensor.aqara_presence_multisensor_fp300_occupancy`
- `binary_sensor.upstairs_occupancy`

These options must also be set (they are, from earlier versions): **Bed sensor** (your side,
`binary_sensor.master_bedroom_bed_presence_bed_occupied_left`), **Bedroom door sensor**
(`binary_sensor.aqara_door_and_window_sensor_door_2`), **Awake For Day helper**, **Sleep In
helper**, **Phone battery state**, **Send phone commands** on, and **Re-arm after back in bed for**
(the same time a temporary alarm uses).

What it does, only at home, before Awake For Day is on, with no alarm left to ring and no nap:

| When | Home Assistant |
| --- | --- |
| Out of bed → bedroom door → hallway presence (any hour) | `RUN_DISARM` only. Nothing else changes. Letting the dog out the patio door is safe from here. |
| Back in bed for the re-arm time | `RUN_ARM_STAY` |
| From 8:00 AM (app setting): up 15 min, or the phone comes off the charger | Notification **Up for the day?** with *Good morning* / *Back to bed* |
| No answer and still up 10 min later, or *Good morning* | Sleep In off, Awake For Day on, `RUN_GOOD_MORNING` (no re-arm after that) |
| **I'm awake** in the app, Siri or the control | The same, straight away, disarming first if you hadn't left the bedroom |

Times and the on/off switch are in the app: **Settings → Mornings → Mornings with no alarms**.

The pushes use the shortcuts you already have (`RUN_DISARM` → Set Disarm, `RUN_ARM_STAY` → Set
Arm Stay, `RUN_GOOD_MORNING` → Good Morning - App). Good Morning - App has to run fully on a
no-alarm morning; it did when you ran it by hand on 30 Oct. If `MorningState` is `complete` from
a previous morning it stops at step 1 (see `docs/shortcuts.md`).

Events for your own automations: `bedtime_bridge` with type `left_bedroom` (`disarmed`) and
`good_morning` (`by_hand`, `disarmed`, `sent`).

**Not in this version:** a quiet good morning when Seth is still in bed (his side,
`binary_sensor.master_bedroom_bed_presence_bed_occupied_right`): everything except the bedroom
curtains and the Master Bedroom announcement. Still on the open list.

## 3. Weekly summary (item 5)

Nothing to set. Weeks now start at the day and time in the app's **Settings → Weekly summary**
(default Sunday 6:00 PM), and the summary sensor and notification cover the week that just ended.
Home Assistant now keeps 64 days of history (it was 60) so the app can show this week and the 8
before it.
