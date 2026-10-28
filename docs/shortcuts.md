# Phone shortcuts

What each shortcut on the iPhone does, step by step, as of 27 Oct 2026. These are the "- App"
versions built for Bedtime Bridge (imported from `shortcuts/`, which stays out of git because the
signed files hold the Home Assistant server and ecobee home IDs). Steps only: no addresses, tokens
or home IDs.

"At home" below means the phone is within 0.1 mi of the Home location in Shortcuts.

## Which shortcut runs when

| Trigger | Runs |
| --- | --- |
| Home Assistant push `RUN_BEDTIME` (Bedtime Nudge, or the integration after *Not going to sleep yet*) | I'm Ready For Bed - App |
| Home Assistant push `RUN_GOOD_MORNING` (integration, when a regular alarm is stopped at home) | Good Morning - App |
| Home Assistant push `RUN_DISARM` (temporary alarm in disarm mode stopped; *Not going to sleep yet*) | Set Disarm |
| Home Assistant push `RUN_ARM_STAY` (back in bed after a temporary alarm) | Set Arm Stay |
| Home Assistant push `RUN_BACK_TO_BED` (v0.4: *Back to bed* after you're up) | Back To Bed - App |
| By hand | Temporary Wake-Up - App |

Each push trigger is an iOS 27 "When I receive a notification from Home Assistant" personal
automation, filtering on the message text, set to run immediately.

## I'm Ready For Bed - App (the bedtime shortcut)

0. Bedtime Bridge **Report Shortcut Ran** (`RUN_BEDTIME`, Outcome **Started**), so Home Assistant
   clears the push that ran it (added 27 Oct 2026; harmless when run by hand).
1. Dismiss Siri.
2. Save `MorningState` = `sleeping` (a global stored value that Good Morning reads).
3. Get the current location and its distance from Home.
4. **At home:**
   1. Run **Set Arm Stay** (house alarm on).
   2. Bedtime Bridge **Plan Wake-Up Alarms**, with *Set Alarms* on. Keep the result as `Alarmtimes`.
   3. If the plan says "No alarm": ask "Would you like wake-up alarms?"
      - **Set wake-up alarms:** ask for the first wake-up time (default: 6 hours from now), then
        Bedtime Bridge **Set Wake-Up Alarms** with that time as the *first* alarm. `Alarmtimes` =
        that result.
      - **No alarms:** ask "Would you like to enable Sleep In?" **Yes** runs a HomeKit scene that
        turns Sleep In on. **No** does nothing.
   4. ecobee **Get Home Monitoring State** (the house alarm's state).
   5. Home Assistant **Call action** *Bedtime Readout* with `alarms` = `Alarmtimes`, `house_alarm` =
      the ecobee state, `run_routine: true`, `dry_run: false`.
   6. Home Assistant **Render template**: the readout message, if it's under 2 minutes old.
   7. Speak it (doesn't wait).
5. **Away:**
   1. **Plan Wake-Up Alarms** (set alarms on), with the same "No alarm" question, minus the Sleep In
      step.
   2. ecobee **Get Home Monitoring State**.
   3. Bedtime Bridge **Away Bedtime Summary** (sign-off "Good night handsome!") with that state.
   4. Speak it (doesn't wait).
6. Turn **Sleep Focus on**.
7. Bedtime Bridge **Report Shortcut Ran** (`RUN_BEDTIME`, Outcome **Completed**).

No house steps run while away: no arming, no Bedtime Readout routine.

It never calls Bedtime Bridge's **Start Bedtime Routine**: the Bedtime Readout call
(`run_routine: true`) starts the routine in Home Assistant instead.

## Good Morning - App

1. Read `MorningState`. If it's `complete` or `running`, **stop here** (it runs once per night).
   To do (app 0.4+): put Bedtime Bridge **Report Shortcut Ran** (`RUN_GOOD_MORNING`, Outcome
   **Already done**) just before each of the two *Stop This Shortcut* steps, so Home Assistant
   clears the push and records that the phone got it but Good Morning had already run.
2. Save `MorningState` = `running`.
3. Bedtime Bridge **Report Shortcut Ran** (`RUN_GOOD_MORNING`, Outcome **Started**; it showed as
   *Ran* before), so Home Assistant clears the push (added on the phone, 27 Oct 2026).
4. **At home:**
   1. Run **Set Disarm** (house alarm off).
   2. Weekend (the day's short name starts with "S"): nothing more.
   3. Weekday, between 8:00 AM and 3:30 PM: speak "Good morning handsome!" on the phone, and if
      still at home, announce it with Intercom to the Master Bedroom.
5. Turn **Sleep Focus off**.
6. Save `MorningState` = `complete`.
7. To do: Bedtime Bridge **Report Shortcut Ran** (`RUN_GOOD_MORNING`, Outcome **Completed**) as the
   last step, so Home Assistant knows it finished (and warns you on a later run that doesn't).

The old version (*Alarm Off Good Morning*) also ran a HomeKit scene (Home Assistant's wake helper)
and a *Toggle Alarm* shortcut for Clock alarms. Bedtime Bridge does both jobs now, so the App
version leaves them out.

## Back To Bed - App

New in v0.4, for item 3's *Back to bed*. Puts back on the phone what Good Morning changed.

0. Bedtime Bridge **Report Shortcut Ran** (`RUN_BACK_TO_BED`), so Home Assistant clears the push.
1. Save `MorningState` = `sleeping`, so the next alarm's Good Morning runs instead of stopping at
   its first step.
2. At home: run **Set Arm Stay**.
3. Turn **Sleep Focus on**.
4. Report Shortcut Ran (`RUN_BACK_TO_BED`, Outcome **Completed**).

Phone setup: a "When I receive a notification from Home Assistant" automation, message
`RUN_BACK_TO_BED`, running this shortcut immediately.

## Temporary Wake-Up - App

1. Ask for the date and time.
2. Ask "What should happen to the house alarm?"
   - **Disarm, then re-arm when I'm back in bed:** Bedtime Bridge **Set Temporary Alarm**, house alarm
     *disarm*.
   - **Keep it armed:** the same, house alarm *keep armed*.
3. Show a notification: "Temporary wake-up alarm set for (time). Your regular alarms are
   unchanged."

## Set Disarm and Set Arm Stay

Your own shortcuts, run by the shortcuts above and by the `RUN_DISARM` / `RUN_ARM_STAY` pushes. They
haven't been exported, so their steps aren't read here; what's known is that they set the ecobee
home monitoring state (Set Disarm: off; Set Arm Stay: armed, stay) and nothing else.
They don't report back yet: add Bedtime Bridge **Report Shortcut Ran** as the first step (Outcome
**Started**) and the last step (Outcome **Completed**) of each, with `RUN_DISARM` or
`RUN_ARM_STAY`. Home Assistant clears the push on the first and, once it has seen a Completed,
notifies you if a later run starts but doesn't finish within 5 minutes (for example, the house
didn't disarm).

## Retired

*Morning Snooze* (ran a HomeKit scene for the snooze fade; the app tells Home Assistant directly
now), *Find Wake Schedule V2* and *Bedtime V2 — Ready* (replaced by Plan Wake-Up Alarms).

## Back to bed (v0.4 item 3): what Good Morning leaves behind

After a stop at home, Good Morning has changed three things on the phone that "back to bed" has
to put back:

| Good Morning did | Why it matters for back to bed | Put back by |
| --- | --- | --- |
| House alarm disarmed (Set Disarm) | The house stays disarmed while you sleep | Set Arm Stay |
| Sleep Focus off | Notifications and calls come through while you sleep | Sleep Focus on |
| `MorningState` = `complete` | **The next Good Morning exits at step 1.** When the new alarm is stopped, `RUN_GOOD_MORNING` runs Good Morning, which sees `complete` and stops: no disarm, Sleep Focus stays on | `MorningState` = `sleeping` |

The greeting and Intercom announcement need nothing. Everything on the Home Assistant side (Awake
For Day, lights, curtains, Night Mode) is the integration's job, per the spec.

While snoozing, Good Morning hasn't run yet, so nothing on the phone needs undoing.

`RUN_ARM_STAY` alone (the spec as written) only covers the first row. `MorningState` and Sleep Focus
can only be changed on the phone.

**Agreed (27 Oct 2026), built:** a new phone command, `RUN_BACK_TO_BED`, sent instead of
`RUN_ARM_STAY` in item 3's "after a stop" step 3. It runs a new shortcut, **Back To Bed - App** (built and signed like the
others):

0. Report Shortcut Ran (`RUN_BACK_TO_BED`).
1. Save `MorningState` = `sleeping`.
2. At home: run **Set Arm Stay**.
3. Turn **Sleep Focus on**.

Why not add these steps to Set Arm Stay instead: Set Arm Stay is also run by the bedtime shortcut
and by the re-arm after a temporary alarm, and it's your own shortcut (not exported), so it can't
be rebuilt and signed from here. A separate shortcut keeps Set Arm Stay as "arm the house" only,
as the spec describes it. Phone setup is one more "When I receive a notification" automation
(message `RUN_BACK_TO_BED`).

## Found while reading: a third Sleep In writer (v0.4 item 7)

The bedtime shortcut's "No alarms → Would you like to enable Sleep In? → Yes" runs a HomeKit
scene that turns Sleep In on. With item 7 the integration is meant to be the only owner, but today
it leaves Sleep In alone on a no-alarm plan precisely because this question answers it. So either
the question stays as a phone-side input (and item 7's "one owner" means one owner *in Home
Assistant*), or the answer goes to the integration (for example in the plan) and the HomeKit step
is removed. Item 7 is built as written (integration-side only) until you decide.
