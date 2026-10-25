# Bedtime Bridge

An iOS app that takes over the parts of the bedtime shortcut that Shortcuts does badly:
reading the calendar, working out drive time, and setting the alarms. Your shortcut still
runs the routine and still talks to Home Assistant. It just calls this app's actions
instead of a long chain of calendar, maps and alarm actions.

## What it does

1. **Next shift.** Finds the first event within the look-ahead window (24 h by default) whose
   title contains one of your shift words (`Days`, `Swings`, …). The first alarm goes off a
   set number of minutes before that shift starts. Each shift word has its own lead time.
2. **Appointments.** Finds events whose notes contain `wake up` and that have a location. It
   gets the driving time **for arriving 10 minutes before the start**, using the traffic
   expected at that hour (see [Drive time](#drive-time)).
   Wake time = start − 10 min buffer − drive − get-ready time.
3. **Picks the earlier one.** The appointment only wins if its wake time is earlier than the
   shift's.
4. **Checks Home Assistant** (optional). It applies `input_select.select_shift_override`
   (Off = no work alarm, Days/Swings = use that shift's lead time). It warns if
   `sensor.current_shift` disagrees with the calendar, and adds extra time when the hourly
   forecast looks bad between waking and arriving.
5. **Sets the alarms.** 3 alarms 10 minutes apart (you can change this). The worked-out
   wake-up time is the **last** alarm by default, so the others go off earlier (up at 5:30 →
   5:10, 5:20, 5:30). Settings → Alarms → *Wake-up time is the* can make it the first alarm
   instead (5:30, 5:40, 5:50). The day-off *Set Wake-Up Alarms* action follows the same
   setting. Alarms are set either as the app's own
   alarms or as times for your shortcut to make Clock alarms with (see [Alarms and snooze](#alarms-and-snooze)).
6. **Nothing found.** It returns `Has Alarm = false` so your shortcut can ask about a
   day-off alarm and the Sleep In helper, as it does now.
7. **Keeps HA updated.** `sensor.bedtime_bridge_next_alarm` holds the next alarm time and cause.
   It's updated on plan, snooze, stop and cancel.

## Alarms and snooze

Settings → Alarms chooses one of two styles:

| | **Bedtime Bridge alarms** (default) | **Clock app (via shortcut)** |
|---|---|---|
| Who makes the alarms | The app (AlarmKit). Rings through Silent and Focus. | Your shortcut, with *Create Alarm* for each item in `Wake Plan › Alarm Dates`. |
| Snooze | Snooze button. **Length is adjustable** (default 9 min). The countdown shows on the Lock Screen and in the Dynamic Island. | Apple's fixed 9 minutes. |
| Morning routines | **Snooze** turns on `input_boolean.wake_fade` (Wake Snooze Fade). **Stop** turns on `input_boolean.wake_mike` (Wake Sequence). The app tells HA directly and retries if HA doesn't answer. | Your existing "Alarm is snoozed / stopped" Shortcuts automations, unchanged. |
| After Stop | Cancels the rest of the series (setting), rechecks traffic for the leave-by reminder. | Whatever your shortcut does. |

Why two styles: the Shortcuts "Alarm is snoozed / stopped" triggers only fire for **Clock app**
alarms. They never see app alarms, so in app-alarm mode the app has to tell HA itself.
**Turn off those Shortcuts automations when you use app alarms,** or a Clock alarm and an app
alarm could both fire. Also delete the Clock alarms the old shortcut toggled.

## Home Assistant integration (recommended)

`custom_components/bedtime_bridge` is a companion integration. With it, the app pairs through
a private webhook instead of an admin token, and everything shows up in Home Assistant as a
**Bedtime Bridge** device.

**Install:** HACS → ⋮ → Custom repositories → add this repo as an *Integration* → install
**Bedtime Bridge** → restart HA. Then go to Settings → Devices & services → Add integration →
Bedtime Bridge. Or copy `custom_components/bedtime_bridge` into your config folder.

**Setup screen:**

| Option | Default |
|---|---|
| When you snooze or stop an alarm | **Turn on helpers and fire events** (both), helpers only, or events only |
| Turn on when snoozed / stopped | `input_boolean.wake_fade` / `input_boolean.wake_mike` (any input_boolean, script, automation, switch or scene) |
| Shift override, shift sensor, weather | `input_select.select_shift_override`, `sensor.current_shift`, `weather.forecast_home` |
| Shift types | `Days, Swings` |

The last step shows a **pairing address**. Paste it into the app under Settings → Home Assistant →
Integration address and tap **Test connection**. You can see it again later under the
integration's **Configure**. Keep it private.

**Entities** (all keep their values through HA restarts):

| Entity | |
|---|---|
| `sensor.bedtime_bridge_next_alarm` | Next alarm (timestamp). Attributes: all alarm times, cause, label, style |
| `sensor.bedtime_bridge_wake_up_time` | When you need to be up (the last alarm by default, or the first) |
| `sensor.bedtime_bridge_alarm_cause` | `Days` / `Swings` / `calendar` / `automade` / `noalarm` |
| `sensor.bedtime_bridge_reason` | "Dentist at 7:00 AM. Leave by 6:26 AM (…)". Attribute: warnings |
| `sensor.bedtime_bridge_leave_by`, `_drive_time`, `_bad_weather_extra_time` | Appointment and weather details |
| `sensor.bedtime_bridge_snooze_count`, `_last_event` | This morning's snoozes. Last event: planned/snoozed/stopped/cancelled/leave_by |
| `binary_sensor.bedtime_bridge_snoozing` | On from a snooze until the alarm rings again |
| `binary_sensor.bedtime_bridge_plan_out_of_date` | The shift override or next shift changed after you planned. Attribute: reason |
| `sensor.bedtime_bridge_last_plan` | When the phone last planned. Attribute: error, if the last attempt failed |
| `sensor.bedtime_bridge_safety_net_early` / `_deadline` / `_late` | Wake-up time −15 / 0 / +15 min for the chosen causes, for Wake Deadline Backstop |
| `number.bedtime_bridge_get_ready_time`, `_arrive_early`, `_snooze_length`, `_bad_weather_extra_time_setting`, `_leave_by_reminder_lead`, `_days_lead_time`, `_swings_lead_time` | **Settings you can change in HA.** They start out matching the app after its first plan. After that, HA's value wins each time the app runs. |

**Events:** `bedtime_bridge` with `type` (`planned`, `snoozed`, `stopped`, `cancelled`,
`leave_by`) plus `alarm_cause`, `alarm_time`, `alarm_times`, `label`, `leave_by` and
`snooze_count`. Also fired: `bedtime`, `plan_failed` (with `error`) and `plan_outdated`
(with `reason`). Test alarms add `test: true`. With *helpers only*, or while you're away,
snoozed/stopped aren't fired.

**Helpers or blueprints, your choice:**
- *Helpers:* your existing Wake Snooze Fade and Wake Sequence blueprints keep watching
  `wake_fade` / `wake_mike`. Nothing to change. They also no longer need to be in the HomeKit
  Bridge for this.
- *Events:* import `blueprints/automation/bedtime_bridge/bedtime_bridge_alarm_event.yaml`
  (Settings → Blueprints → Import, using the raw GitHub URL). Pick an event (for example
  "Alarm snoozed"), optionally limit it to causes like `Days`, and add your actions.
- *Both* is the default, so you can move routines over one at a time. Don't let a helper-driven
  automation and an event-driven automation do the same thing, or it will run twice.

What it can't do: HA can't push commands to the phone. Settings changed in HA reach the app
the next time it runs (bedtime, snooze or stop).

The integration has its own tests (`pytest`, with `pytest-homeassistant-custom-component`).

## Only when you're home

Wake-up and bedtime routines only run in Home Assistant while you're home, so a hotel night
doesn't light up an empty house.

- **Wake side:** when you snooze or stop, the integration checks your person entity. If you're
  away, it doesn't turn on `wake_fade` / `wake_mike` and doesn't fire the snoozed/stopped
  events. The state still updates, and `sensor.bedtime_bridge_last_event` shows
  `skipped_away: true`.
- **Bedtime side:** replace the shortcut's HomeKit "turn on Bedtime Routine" step with the app's
  **Start Bedtime Routine** action. It asks the integration, which turns on
  `input_boolean.bedtime_routine` only if you're home, and returns *Started* (true/false) so the
  shortcut can skip or change later steps.
- **Clock app mode:** in the Shortcuts "Alarm is snoozed" and "Alarm is stopped" personal
  automations, replace the HomeKit helper steps with **Report Alarm Event** (Snoozed / Stopped),
  so the same check applies.
- **Wake Plan › At Home** is false when you're away, and the Tonight screen shows "away".

Set it up in the integration's options: **You** (defaults to your person entity), **Only run
routines when you're home** (on), and **Turn on to start the bedtime routine**
(`input_boolean.bedtime_routine`). Unknown or unavailable presence counts as home, so a tracker
glitch never skips your morning while you're in bed. Without the integration, the same three
settings are in the app (token mode).

Anything that still flips those helpers directly (an old HomeKit step, a dashboard button)
bypasses the check. Route it through the app's actions instead.

## Safety nets

- **Test alarm.** Settings → Alarms → **Test alarm in 2 minutes** (app alarms). It rings once.
  Snooze it, then stop it, and your real routines run (if you're home). HA marks those events
  `test: true` and leaves tonight's plan alone.
- **If planning fails.** If the calendar can't be read, *Plan Wake-Up Alarms* falls back to Home
  Assistant's next shift (`sensor.current_shift`) and sets your usual alarms with a warning.
  Appointments aren't checked in that case. If HA can't help either, the action fails visibly
  in the shortcut and tells HA the plan failed.
- **No plan by bedtime.** `sensor.bedtime_bridge_last_plan` records every plan (its `error`
  attribute shows a failure). The **Bedtime Bridge missing plan** blueprint checks at a time you
  pick (default 11:30 PM). If a shift starts within 14 h and there's no fresh plan, or the last
  one failed, it sends a time-sensitive notification with a **Plan now** button.
- **Appointment mornings in Wake Deadline Backstop.** For the causes you choose (default:
  `calendar`), the integration publishes `sensor.bedtime_bridge_safety_net_early` /
  `_deadline` / `_late` (wake-up time −15 / 0 / +15 min). Only when you're home. Make a second
  Backstop instance with those three as its rung sensors. Set its **Shift sensor** to
  `sensor.bedtime_bridge_safety_net_deadline` and keep *Applies to shifts* = Days: that sensor
  reports `effective_shift: Days` whenever a deadline is set, which satisfies the blueprint's
  shift check without editing it. Your shift instance stays as it is.
- **Plan out of date.** If the shift override or HA's next shift changes after you planned (and
  before you wake), `binary_sensor.bedtime_bridge_plan_out_of_date` turns on and a
  `plan_outdated` event fires. If you set a notify action in the integration, you get a
  notification with **Re-plan now** (opens `bedtimebridge://replan`, and the app plans again).
  Routine refreshes with the same shift time don't count. Calendar edits on the phone itself
  can't be seen by HA; the app picks those up the next time it plans.
- **Appointments without a location.** A "wake up" appointment with no location still gets an
  alarm. Until you answer, it's planned with the fallback drive time (30 min), so an unanswered
  question errs toward waking early. You get a quiet notification, *"Dentist has no location.
  Should it have a location?"*, that you can answer from the Lock Screen:
  - **Add location:** type the place right in the notification. It's saved to the calendar
    event and the app re-plans in the background with the real drive time.
  - **No location needed:** remembered for that event. The app re-plans with no drive.
  - **Ignore it:** the safe plan stands. The Tonight screen shows the same question as a card.

  The shortcut never waits on this (see below).

## Hands-free bedtime

The bedtime flow runs with nobody tapping: the bed sensor → HA's notification → the shortcut.
So **Plan Wake-Up Alarms**, **Start Bedtime Routine** and **Set Wake-Up Alarms** never ask
questions or wait for input. Anything that needs you (a missing location, an out-of-date
plan, a missing plan) comes as a notification you can answer later or ignore, with a safe
default. The shortcut's own day-off questions are unchanged: no answer still means no alarm
and Sleep In.

## Lock Screen widget

Add **Next Alarm** from the Lock Screen widget gallery (Bedtime Bridge). It shows the next
alarm time, why it's set ("Days shift", "Dentist", "Day off"), and leave-by on appointment
mornings. While snoozing it shows the snooze time instead. Sizes: rectangular (time, reason,
leave-by), circular (time) and the inline line above the clock. There's also a small
Home Screen widget.

The app updates it whenever alarms change (plan, snooze, stop, cancel). It moves on to the next
alarm by itself as each one passes. In Clock app mode it shows the planned times but can't
see Clock snoozes. The app and widget share data through the App Group
`group.com.example.BedtimeBridge`. If you change the bundle ID, change the group in
`project.yml` and `Shared/NextAlarmSnapshot.swift` to match.

## Leave-by reminder and bad weather

- **Leave-by reminder.** On appointment mornings you get a notification 15 min (adjustable)
  before leave-by. When you stop an app alarm, the app re-asks the drive-time service with that
  morning's traffic and moves the reminder ("Traffic is 8 min worse than planned"). In Clock
  mode it stays at the bedtime estimate.
- **Bad weather.** Uses `weather.forecast_home`'s hourly forecast from your first alarm until
  you need to be there. If a ticked condition shows up (default: pouring, lightning-rainy,
  snowy, snowy-rainy, hail, or rain/snow at freezing), it adds 15 min. Shift alarms go off
  earlier. Appointment drives get the time added, so leave-by moves too. The Wake Plan reason
  says why ("+15 min for pouring at 6 AM").

## Look: Nightfall

The app uses a dark-only theme called **Nightfall**: midnight blue backgrounds (`#0B1026`, with
cards in `#141B3A`), violet buttons (`#6D4AFF`) and violet text (`#DDD6FE`). Accent colors:
mint for connected, sky blue for leave-by, amber for weather warnings. Colors live in
`Shared/Theme.swift`, so the widgets and the snooze Live Activity match. Times and titles use
**Sora** (light for the big alarm time); body text is SF Pro. The five Sora weights in
`Shared/Fonts` are static cuts of Google Fonts' variable Sora, made with fontTools. They're
used under the SIL Open Font License (`Shared/Fonts/OFL.txt`, shipped inside the app).

## Shortcuts actions

| Action | Use |
|---|---|
| **Plan Wake-Up Alarms** | The main step. Returns a *Wake Plan*: `Has Alarm`, `Wake-Up Time`, `First Alarm`, `Alarm Times`, `Alarm Dates`, `Needs Clock Alarms`, `Alarm Cause`, `Reason`, `Warnings`, `Home Assistant JSON`. Turn off *Set Alarms* to preview only. If nothing needs an alarm, it also clears the app's old alarms. |
| **Set Wake-Up Alarms** | The day-off path. Give it your wake-up time and it sets the usual alarm series around it (ending at it by default). A time already past today rolls to tomorrow. |
| **Cancel Wake-Up Alarms** | Clears every alarm the app has set and the leave-by reminder. |
| **Get Drive Time** | Drive minutes from home to a place, arriving by a given time. Useful in other shortcuts. |

## Alarm cause

Every Wake Plan carries an **Alarm Cause** (`alarm_cause` in the JSON) telling Home Assistant why
the alarm exists:

| Value | Meaning |
|---|---|
| `Days`, `Swings` | Work shift. The value is the shift word from Settings, so spell it the way HA expects (these match `input_select.select_shift_override`). |
| `calendar` | A calendar appointment noted "wake up" |
| `automade` | You picked the time (Set Wake-Up Alarms) |
| `noalarm` | No alarm was set |

If you skip the day-off alarm, send the Wake Plan from *Plan Wake-Up Alarms*. It already says `noalarm`.

## Drive time

Pick the service in Settings → Drive time. All three plan for arriving by *start − buffer*
(10 min by default).

| Service | How arrive-by works | Needs |
|---|---|---|
| **Apple Maps** (default) | Takes an arrival time directly and uses the traffic it predicts for that hour. | Nothing. Free. |
| **TomTom** | Takes an arrival time directly (`arriveAt`) and uses its historical traffic for that time and day. One request per appointment. | API key from developer.tomtom.com (the free tier is plenty), home address |
| **Google** (Routes API) | Driving routes only take a **departure** time, so the app works backwards. It tries leaving 30 min early, sees when you'd arrive, moves the departure by the difference and repeats (at most 4 requests). It keeps the latest departure that still arrives on time. Optional *Plan for heavy traffic* uses Google's pessimistic traffic model. | Routes API key, home address |

API keys are stored in the iOS Keychain. If a service fails (no signal, bad key), the app uses
the fallback drive time from Settings. You'll see a warning in `Warnings`, and the JSON marks it
`drive_time_estimated: true`.

## Rewiring the bedtime shortcut

Replace the calendar, maps and alarm part of the shortcut with:

```
Plan Wake-Up Alarms (Set Alarms: on)            → Wake Plan
If  Wake Plan › Has Alarm  is  false
    Ask for Input (Time) "Alarm for your day off?"
    If  Provided Input has any value
        Set Wake-Up Alarms (Wake-Up Time: Provided Input)  → Wake Plan
    End If
    Choose from Menu "Turn on Sleep In?"  …                 (your existing step)
End If
Start Bedtime Routine                    → Started      (replaces the HomeKit "Bedtime Routine on" step)
If  Wake Plan › Needs Clock Alarms  is  true              (Clock app mode only)
    Repeat with Each item in Wake Plan › Alarm Dates
        Create Alarm at Repeat Item
    End Repeat
End If
…arm house alarm (existing)…
…send to Home Assistant (existing). Send Wake Plan › First Alarm and
   Wake Plan › Alarm Cause, or the whole Wake Plan › Home Assistant JSON…
```

Everything after that stays the same: Home Assistant sets `input_boolean.sleep_in` from the
alarm time and sends back the spoken readout.

`Home Assistant JSON` looks like this:

```json
{"alarm_cause":"calendar","alarm_time":"2026-10-26T05:26:00-04:00","alarm_times":["…","…","…"],
 "appointment":{"drive_minutes":24,"drive_time_estimated":false,"leave_by":"2026-10-26T06:26:00-04:00",
                "location":"…","start":"2026-10-26T07:00:00-04:00","title":"Dentist"},
 "has_alarm":true,"reason":"Dentist at 7:00 AM. Leave by 6:26 AM (24 min drive, 10 min early)",
 "shift":{"start":"…","title":"Days"}}
```

## Building

Requires Xcode 26 and an iPhone on iOS 26 or later (AlarmKit is iOS 26+).

```sh
brew install xcodegen
xcodegen generate
open BedtimeBridge.xcodeproj
```

In Xcode, choose your team under *Signing & Capabilities*, change the bundle ID if you need to,
and run it on your phone. On first launch, tap **Preview plan** to grant calendar access.
Tap **Plan and set alarms** once to grant alarm access and notifications. Then open the gear and set:

- your shift words and how long before each shift you want the first alarm
- get-ready time (default 60 min) and arrive-early buffer (default 10 min)
- drive-time service and API key, and your home address (required for TomTom and Google; with
  Apple Maps a blank address uses your current location)
- which calendars hold shifts and appointments (none ticked = all calendars)
- alarm style and snooze length
- Home Assistant URL and a long-lived access token (HA → your profile → Security), then tap
  **Test connection**. The helper names default to your existing ones (`wake_fade`,
  `wake_mike`, `select_shift_override`, `current_shift`, `forecast_home`). Plain `http://`
  works on your home network. Away from home, use your Nabu Casa or other `https` URL.

The planning logic (`WakePlanner.swift`, `PlanAdjustments.swift`, `DepartureSolver`) has no
EventKit, MapKit, AlarmKit or network code and is covered by `BedtimeBridgeTests` (⌘U).

## Layout

```
BedtimeBridge/
  App/        app entry point
  Core/       settings, WakePlanner + PlanAdjustments (pure logic), calendar, AlarmKit,
              Home Assistant client, leave-by reminder, coordinator
    DriveTime/  Apple Maps, TomTom and Google drive-time providers
  Intents/    Shortcuts actions, Snooze/Stop button actions, Wake Plan result type
  Views/      main screen and settings
BedtimeBridgeWidgets/  Lock Screen "Next Alarm" widget and the snooze-countdown Live Activity
Shared/       Nightfall theme, alarm metadata and widget snapshot used by the app and the widgets
BedtimeBridgeTests/
custom_components/bedtime_bridge/  Home Assistant integration (HACS)
blueprints/automation/bedtime_bridge/  "Bedtime Bridge alarm event" blueprint
tests/ha/     integration tests
project.yml   XcodeGen spec (the .xcodeproj is generated, not committed)
```
