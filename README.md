# Bedtime Bridge

An iOS app that takes over the parts of the bedtime shortcut that Shortcuts does badly:
reading the calendar, working out drive time, and setting the alarms. Your shortcut still
runs the routine and still talks to Home Assistant. It just calls this app's actions
instead of a long chain of calendar, maps and alarm actions.

## What it does

1. **Next shift.** Finds the first event within the look-ahead window (24 h by default) whose
   title contains one of your shift words (`Days`, `Nights`, …). The first alarm goes off a
   set number of minutes before that shift starts. Each shift word has its own lead time.
2. **Appointments.** Finds events whose notes contain `wake up` and that have a location. It
   gets the driving time **for arriving at the appointment's start time**. Setting an arrival
   time makes Apple Maps use the traffic it predicts for that hour, not current or free-flow
   traffic. Wake time = start − drive − get-ready time.
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
| **Plan Wake-Up Alarms** | The main step. Returns a *Wake Plan*: `Has Alarm`, `First Alarm`, `Alarm Times`, `Source` (`shift` / `appointment` / `none`), `Reason`, `Warnings`, `Home Assistant JSON`. Turn off *Set Alarms* to preview only. |
| **Set Wake-Up Alarms** | The day-off path. Give it a time and it sets the usual alarm series. A time already past today rolls to tomorrow. |
| **Cancel Wake-Up Alarms** | Clears every alarm the app has set. |
| **Get Drive Time** | Drive minutes from home to a place, arriving by a given time. Useful in other shortcuts. |

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
…send to Home Assistant (existing). Send Wake Plan › First Alarm,
   or the whole Wake Plan › Home Assistant JSON…
```

Everything after that stays the same: Home Assistant sets `input_boolean.sleep_in` from the
alarm time and sends back the spoken readout.

`Home Assistant JSON` looks like this:

```json
{"alarm_time":"2026-10-26T05:30:00-04:00","alarm_times":["…","…","…"],
 "appointment":{"drive_minutes":24,"location":"…","start":"…","title":"Dentist"},
 "has_alarm":true,"reason":"Dentist at 7:00 AM, 24 min drive","shift":{"start":"…","title":"Days"},
 "source":"appointment"}
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
- get-ready time (default 60 min)
- your home address (otherwise current location is used as the start point)
- which calendars hold shifts and appointments (none ticked = all calendars)

The planning logic is in `BedtimeBridge/Core/WakePlanner.swift`. It has no EventKit, MapKit
or AlarmKit code and is covered by `BedtimeBridgeTests` (⌘U).

## Layout

```
BedtimeBridge/
  App/        app entry point
  Core/       settings, WakePlanner (pure logic), calendar, drive time, AlarmKit, coordinator
  Intents/    Shortcuts actions and the Wake Plan result type
  Views/      main screen and settings
BedtimeBridgeTests/
project.yml   XcodeGen spec (the .xcodeproj is generated, not committed)
```
