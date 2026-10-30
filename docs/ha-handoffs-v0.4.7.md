# Home Assistant hand-offs for Bedtime Bridge 0.4.7

What 0.4.7 needs on the Home Assistant side. Nothing here has been changed in the live instance
from this repo.

## 1. Install 0.4.7

**HACS → Bedtime Bridge → Update** to 0.4.7, then restart Home Assistant. It includes 0.4.6.

## 2. Configure is now a menu (item 9)

**Settings → Devices & services → Bedtime Bridge → Configure** opens a menu instead of one long
form: *You and home*, *Wake-up*, *Bedroom and bed*, *Bedtime and wind-down*, *Shifts and calendar*,
*Phone*, *Backstops*, *Keys*. Each page saves only its own options. Your settings carried over;
nothing to redo.

## 3. The backup leave reminder (item 2)

With *Drive times from* set to a service (not Phone), Home Assistant does the leave checks and the
app keeps one reminder at leave time as a backup, marked "not re-checked". When Home Assistant's
check goes out, it sends the app a silent push and the app withdraws the backup. That push uses the
Apple push key already in *Keys* (the same one the Live Activities use); without the key the backup
still fires at leave time.

Open the app once after updating so it sends Home Assistant its push token.

## 4. Vacations (item 6)

- A vacation morning with no alarms turns **Sleep In** on (the *Sleep In helper* on the *Wake-up*
  page).
- Weeks with vacation days are marked in the weekly summary sensor (attribute `vacation`, e.g.
  "Vacation Nov 2 – 6"), and the weekly notification is skipped while you're on vacation.
- The vacation titles are still matched separately by Home Assistant's `current_shift.yaml` (until
  v0.6). Yours stays "Leave", so nothing changes there.

## 5. 24-hour times (item 10)

Home Assistant now writes times in its notifications and Live Activity alerts the way the app's
**Settings → Clock** says (sent with every message). With your phone on 24-hour and Clock on
*Phone setting*, "Bed at 9:50 PM" becomes "Bed at 21:50".

## 6. Keys in the log (item 3)

A failed TomTom or Google request no longer writes its key into Home Assistant's log. Nothing to
set.
