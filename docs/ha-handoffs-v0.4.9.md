# Home Assistant hand-offs for Bedtime Bridge 0.4.9

What 0.4.9 needs on the Home Assistant side. Nothing here has been changed in the live instance
from this repo. Entities are named by what they are, with the id as read from your Home
Assistant on 31 Oct 2026 (item 2); a fresh install may pick different ids.

## 1. Install 0.4.9

**HACS → Bedtime Bridge → Update** to 0.4.9, then restart Home Assistant and open the app once.
No settings change. What's different:

- **No in-bed report during a nap (item 1).** "In bed 10 minutes with bedtime pending and no
  RUN_BEDTIME" isn't filed while a nap is on: its alarms are set (up to 4 hours after the last
  one), or the napping helper (`input_boolean.napping`) has been on for less than 4 hours. The
  same 4-hour fallback the Bedtime Nudge blueprint uses.
- **The morning Live Activity's next backstop (item 6)** only comes from the ladder for that
  morning. On 31 Oct the ladder (**Bedtime Bridge → Ladder status**,
  `sensor.master_bedroom_bedtime_bridge_ladder_status`) was armed for Monday 2 Nov 6:30; a Sunday
  morning no longer shows Monday's backstops.
- **Curtains open (item 7)** keep sunrise's clock time on another day across a clock change (it
  was an hour out from 1 Nov until the next sunrise).

## 2. A nap that runs into the night (item 1, for the Home Assistant chat)

Decided 31 Oct: the blueprint handles it, and nothing in Bedtime Bridge changes for it. In
**Bedtime Nudge v1-05** (`bedtime_nudge_v1-05.yaml`, used by `automation.bedtime_nudge`), the
napping helper going off isn't a trigger, so staying in bed after the nap sends nothing until you
get back into bed or the door closes.

The change: add the **napping helper turning off** (`input_boolean.napping`, `on` → `off`) as a
trigger that runs the blueprint's usual checks. Still in bed, inside tonight's window, it
auto-runs; outside it, with **Bedtime pending**
(`binary_sensor.master_bedroom_bedtime_bridge_bedtime_pending`) on, it's the tap-to-run push. The
one-bedtime-per-night rule and the cut-off stay as they are.

Bedtime Bridge turns the napping helper off when the nap ends: *End nap*, or stopping its last
alarm (from the app or, from 0.4.9, the banner).

## 3. Stop on a nap alarm's banner (item 4)

App only, nothing to set up. On 31 Oct, Stop on a nap alarm's banner was taken for a morning
alarm: Home Assistant got `stopped` (Last event: `up: true`, `alarms_left: 0`), ran the stop
routine and sent RUN_GOOD_MORNING, and tomorrow's alarms were cancelled. From 0.4.9 the app
knows it's a nap alarm even after the system has removed it, so Home Assistant gets *Nap ended*
(once the last nap alarm is stopped) and nothing else, and a stop never cancels a later
wake-up's alarms.

To check after a nap: **Bedtime Bridge → Last event** says `nap_ended`, the napping helper is
off, and **Bedtime Bridge → Next alarm** still shows tomorrow's first alarm.
