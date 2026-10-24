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
5. **Sets the alarms.** 3 alarms 10 minutes apart (you can change this), either as the app's own
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

## Shortcuts actions

| Action | Use |
|---|---|
| **Plan Wake-Up Alarms** | The main step. Returns a *Wake Plan*: `Has Alarm`, `First Alarm`, `Alarm Times`, `Alarm Dates`, `Needs Clock Alarms`, `Alarm Cause`, `Reason`, `Warnings`, `Home Assistant JSON`. Turn off *Set Alarms* to preview only. If nothing needs an alarm, it also clears the app's old alarms. |
| **Set Wake-Up Alarms** | The day-off path. Give it a time and it sets the usual alarm series. A time already past today rolls to tomorrow. |
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
        Set Wake-Up Alarms (First Alarm: Provided Input)   → Wake Plan
    End If
    Choose from Menu "Turn on Sleep In?"  …                 (your existing step)
End If
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
BedtimeBridgeWidgets/  Live Activity that shows the snooze countdown
Shared/       alarm metadata used by the app and the widget
BedtimeBridgeTests/
project.yml   XcodeGen spec (the .xcodeproj is generated, not committed)
```
