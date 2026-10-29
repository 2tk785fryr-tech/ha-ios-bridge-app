# Home Assistant hand-offs for Bedtime Bridge v0.4.2

These are the Home Assistant changes v0.4.2 needs, for the Home Assistant chat to apply. Nothing
here has been changed in the live instance from this repo. Read every entity id back first.

Integration version: **0.4.2**. Install it from HACS and restart first.

## 1. Napping helper (item 3)

1. Create a toggle helper: **Settings → Devices & services → Helpers → Create helper → Toggle**,
   named *Napping*. Read back its entity id (expected `input_boolean.napping`).
2. Integration options (**Settings → Devices & services → Bedtime Bridge → Configure**): set
   **Napping helper** to that entity.
3. What the integration does with it:
   - **Nap starts** (you tap a length in the app): the helper turns on, only while you're home.
   - **Nap ends** (its last alarm stopped, or End nap): the helper turns off if it's on, wherever
     you are, so a nap started at home doesn't leave it on after you go out.
4. House automations on the helper are yours to write (Michael's, Home Assistant side). For
   example: bedroom lights off and a quiet mode while it's on.

The integration also fires `bedtime_bridge` events of type `nap_started` (with `alarm_times`
and `napping_helper`) and `nap_ended`. Last event shows them.

## 2. Nap Focus commands (item 3), phone side only

With **Send phone commands** on, the integration sends `RUN_NAP_START` at the start of a nap and
`RUN_NAP_END` at the end, **home or away**. Nothing to change in Home Assistant. On the phone,
build **Nap Start - App** and **Nap End - App** and their two "When I receive a notification from
Home Assistant" automations (see `docs/shortcuts.md`).

## 3. Leave checks keep going after a morning change (item 1)

Nothing to change in Home Assistant. Since 0.4.2:

- **Entire wake-up shifted** (a snow delay): leave-by moves by the delay, and the `RUN_LEAVE_CHECK`
  pushes follow it, the same minutes before it.
- **Alarms only shifted:** leave-by and the checks stay.
- **No alarms on a work morning:** the checks continue while `sensor.current_shift` still shows
  that shift's start. If the shift is deleted, they stop.
- **Skip, cancel and undo bedtime:** still stop them.

## 4. Nothing else

Items 2, 5, 6 and 7 are app-only. Item 4 (dynamic wind-down) isn't built; it's not decided yet.
