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
4. **Sets the alarms.** Sets 3 alarms 10 minutes apart (you can change this) with
   **AlarmKit**. They ring through Silent mode and Focus like Clock alarms. Every run clears
   the app's earlier alarms first, so re-running bedtime never leaves duplicates.
5. **Nothing found.** It returns `Has Alarm = false` so your shortcut can ask about a
   day-off alarm and the Sleep In helper, as it does now.

> AlarmKit alarms belong to this app and **don't appear in the Clock app**. Once you switch
> over, delete the Clock alarms your shortcut used to toggle so you don't get two sets.

## Shortcuts actions

| Action | Use |
|---|---|
| **Plan Wake-Up Alarms** | The main step. Returns a *Wake Plan*: `Has Alarm`, `First Alarm`, `Alarm Times`, `Alarm Cause`, `Reason`, `Warnings`, `Home Assistant JSON`. Turn off *Set Alarms* to preview only. If nothing needs an alarm, it also clears the app's old alarms. |
| **Set Wake-Up Alarms** | The day-off path. Give it a time and it sets the usual alarm series. A time already past today rolls to tomorrow. |
| **Cancel Wake-Up Alarms** | Clears every alarm the app has set. |
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
Tap **Plan and set alarms** once to grant alarm access. Then open the gear and set:

- your shift words and how long before each shift you want the first alarm
- get-ready time (default 60 min) and arrive-early buffer (default 10 min)
- drive-time service and API key, and your home address (required for TomTom and Google; with
  Apple Maps a blank address uses your current location)
- which calendars hold shifts and appointments (none ticked = all calendars)

The planning logic is in `BedtimeBridge/Core/WakePlanner.swift`. It has no EventKit, MapKit
or AlarmKit code and is covered by `BedtimeBridgeTests` (⌘U).

## Layout

```
BedtimeBridge/
  App/        app entry point
  Core/       settings, WakePlanner (pure logic), calendar, AlarmKit, coordinator
    DriveTime/  Apple Maps, TomTom and Google drive-time providers
  Intents/    Shortcuts actions and the Wake Plan result type
  Views/      main screen and settings
BedtimeBridgeTests/
project.yml   XcodeGen spec (the .xcodeproj is generated, not committed)
```
