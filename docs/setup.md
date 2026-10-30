# Setting up v0.4.2 – 0.4.7: everything, in order

**New in 0.4.7:** update the integration to **0.4.7** in HACS and restart, then open the app once
(it sends Home Assistant its push token for the backup leave reminder). Configure is now a menu of
pages; your settings carried over. Optional: **Settings → Clock** (24-hour) and **Settings →
Vacations**. If you want Critical for the app's own notifications, submit the request in
`docs/critical-alerts-request.md`. Details: `docs/ha-handoffs-v0.4.7.md`.

**New in 0.4.6** (if you've done everything below already, this is all): update the integration
to **0.4.6** in HACS and restart, then set **Hallway presence** in Bedtime Bridge → Configure, and
check **Settings → Mornings → Mornings with no alarms** in the app. Details:
`docs/ha-handoffs-v0.4.6.md`. Optional: add the **I'm awake** control (step 12).

Everything you need to do by hand for the features added since v0.4.1 (nap, wind-down, Live
Activities by push, drive times in Home Assistant, the new notifications), in the order to do it.
Tick each box as you go. Items marked *(if not done yet)* are from v0.4.2; skip them if they're
already set up.

The app on your iPhone is already up to date (installed from Xcode on 29 Oct 2026, signed with
the paid account, good until 30 Oct 2027).

---

## Part 1: Home Assistant

### 1. Update the integration
- [ ] **HACS → Bedtime Bridge → Update** to **0.4.7** (it includes 0.4.2 – 0.4.6). Not 0.4.4:
      0.4.5 and later have the `RUN_CANCEL_WIND_DOWN` command the new Wind Down Off shortcut uses.
- [ ] **Settings → System → Restart Home Assistant.** On restart it installs `h2`, which the
      Live Activity pushes need.

### 2. Create two toggle helpers
**Settings → Devices & services → Helpers → Create helper → Toggle**, once for each:

- [ ] *(if not done yet)* **Napping** → should become `input_boolean.napping`
- [ ] **Winding down** → should become `input_boolean.winding_down`

Check each one's entity id after creating it (click it → settings cog).

### 3. Fill in the integration's options
**Settings → Devices & services → Bedtime Bridge → Configure.** It opens a menu of pages (You and
home, Wake-up, Bedroom and bed, Bedtime and wind-down, Shifts and calendar, Phone, Backstops,
Keys); each saves on its own. Set these and leave everything else as it is:

| Option | Set to |
| --- | --- |
| Send phone commands | **On** (check it's still on) |
| Napping helper *(if not done yet)* | `input_boolean.napping` |
| Winding down helper | `input_boolean.winding_down` |
| Bedroom door sensor | `binary_sensor.aqara_door_and_window_sensor_door_2` (Master Bedroom Door) |
| Bed sensor | leave as it is |
| Wind-down notifications to | leave empty |
| Phone battery level | `sensor.mikes_iphone_battery_level` |
| Phone battery state | `sensor.mikes_iphone_battery_state` |
| Apple push key (.p8) | the push key, see below |
| Apple push Key ID | `S663T448S3` |
| Drive times from | **Phone** for now (see Part 4 to change it) |
| Hallway presence (0.4.6) | `binary_sensor.hallway_master_presence` and the other hallway sensors it suggests |

**The push key:** on the Mac, open `Downloads/AuthKey_S663T448S3.p8` with TextEdit, press ⌘A
then ⌘C, and paste it into *Apple push key (.p8)*. It must include the
`-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines.

- [ ] Options saved.
- [ ] Move `AuthKey_S663T448S3.p8` out of Downloads into your password manager (or another safe
      place). Apple only lets you download it once, and it doesn't belong anywhere public.

---

## Part 2: iPhone settings

### 4. Allow critical alerts for Home Assistant
- [ ] **Settings → Notifications → Home Assistant → Critical Alerts: On.** Without it, "Time for
      bed" arrives as a normal notification.

### 5. Create the Wind Down Focus
- [ ] **Settings → Focus → + → Custom**, named **Wind Down** (any icon).
- [ ] People: allow **Seth**. Apps: allow **Home Assistant**. Allow **calls** (from everyone, or
      your favorites).
- [ ] Options: turn on **Dim Lock Screen**.

Use a custom Focus, not Sleep. Your bedtime shortcut turns on Sleep Focus, which replaces this
one, because only one Focus can be on at a time.

---

## Part 3: Shortcuts

### 6. Import the four new shortcuts
They're on the Mac in **Desktop → Shortcuts → to import → 2026-10-29**. Send the folder to the
iPhone (AirDrop it, or copy it to iCloud Drive and open it in Files), then tap each file →
**Add Shortcut**:

- [ ] **Wind Down On - App**
- [ ] **Wind Down Off - App**
- [ ] **Preview Tomorrow - App**
- [ ] **Morning Update - App** (only needed until a morning has worked by push; harmless to have)

### 7. Finish the two Wind Down shortcuts
Each has grey comment boxes saying **ADD BELOW: …**. Open the shortcut, and right under each box
add the action it names (tap the search field at the bottom, type the action's name):

**Wind Down On - App:**
- [ ] Under the first box: **Set Focus** → tap *Focus* → **Wind Down** → **Turned On**, *Until
      Turned Off*.
- [ ] Under the second box: **Set Night Shift** → **On**.
- [ ] Under the third box: **Set Reduce White Point** → **On**.

**Wind Down Off - App:**
- [ ] Under the first box: **Set Focus** → **Wind Down** → **Turned Off**.
- [ ] Under the second box: **Set Reduce White Point** → **Off**.
- [ ] Under the third box: **Set Night Shift** → **Off** (or skip it to leave Night Shift on its
      schedule).

You can delete the comment boxes afterwards.

- [ ] Test: run **Wind Down On**, then **Wind Down Off**. Afterwards, check auto-brightness still
      adjusts and Appearance is still Automatic (Settings → Display & Brightness).

### 8. *(if not done yet)* Build the two nap shortcuts
These aren't signed files; build them in Shortcuts (**+**):

- [ ] **Nap Start - App:** Bedtime Bridge *Report Shortcut Ran* (`RUN_NAP_START`, Started) →
      *Set Focus* (your nap Focus, e.g. Sleep) On → *Report Shortcut Ran* (`RUN_NAP_START`,
      Completed).
- [ ] **Nap End - App:** *Set Focus* (the same Focus) Off → *Report Shortcut Ran*
      (`RUN_NAP_END`, Completed).

### 9. Add the automations
For each row: **Shortcuts → Automation → + → Notification**. App: **Home Assistant**. Message
contains: the text in the first column. Then **Run Immediately**, turn **Notify When Run** off,
**Next**, and pick the shortcut.

| Message contains | Runs |
| --- | --- |
| `RUN_PLAN_PREVIEW` | Preview Tomorrow - App |
| `RUN_WIND_DOWN` | Wind Down On - App |
| `RUN_CANCEL_WIND_DOWN` | Wind Down Off - App |
| `RUN_MORNING_UPDATE` | Morning Update - App |
| `RUN_NAP_START` *(if not done yet)* | Nap Start - App |
| `RUN_NAP_END` *(if not done yet)* | Nap End - App |
| `RUN_LEAVE_CHECK` *(if not done yet)* | the Bedtime Bridge action **Check Drive and Remind** (no shortcut) |

- [ ] All automations added.

---

## Part 4: In the app

### 10. Turn things on
- [ ] Open **Bedtime Bridge** once. It sends Home Assistant its push tokens.
- [ ] **Settings → Wind-down → Wind-down: On.** Check the sleep goal (6.5 h) and wind-down
      length (60 min); the example under *Times* shows what they give.
- [ ] *(optional)* **Settings → Nap → Nap: On**, if you want the Nap button.
- [ ] *(optional)* **Settings → Bad weather → Forecast from → Apple Weather.** Then open Tonight
      and check it plans without a weather error. Apple can take up to half an hour after setup to
      allow it; if you see an error, switch back and try again later.
- [ ] *(optional)* **Settings → Notifications:** change any notification's level. Defaults:
      *Time for bed* critical; *Still up*, *Plug in your phone*, the leave-by reminders and
      *Tomorrow changed* time-sensitive; the rest normal.

### 11. *(optional)* Let Home Assistant check the drive itself
Only if you want the leave checks to work with the phone asleep. **Bedtime Bridge → Configure →
Drive times from**, and:

- **TomTom:** paste the same TomTom key the app uses into *TomTom key*.
- **Google:** paste a Routes API key into *Google key* (the app's works unless it's restricted to
  the iOS app only).
- **Apple Maps:** needs its own Maps key; the steps are in `docs/ha-handoffs-v0.4.4.md`, section 5.

### 12. *(optional)* Add controls and widgets
- [ ] **Widgets:** long-press the Home Screen → **Edit → Add Widget → Bedtime Bridge** (every size).
- [ ] **Lock Screen controls:** long-press the Lock Screen → **Customize → Lock Screen** → tap a
      bottom button → **Bedtime Bridge** → Nap, Wind-down, Tonight or I'm awake.
- [ ] **Control Center:** swipe down → **+ → Add a Control → Bedtime Bridge**.
- [ ] **Action button:** Settings → Action Button → **Controls → Bedtime Bridge**.

---

## Part 5: Check it worked

- [ ] **The first evening with wind-down on:**
  - The warning "Wind-down at … · bed …" arrives 5 min before.
  - At wind-down, the Wind Down Focus comes on and **Winding down** turns on in Home Assistant.
  - "Bed in …" shows on the Lock Screen without opening the app (that's the push working).
- [ ] **The next shift morning:** after you stop the first alarm, the "Leave in … · 5:45" Live
      Activity appears and updates. Once it has worked by push, you can delete **Morning Update -
      App** and its automation.
- [ ] **If something doesn't arrive:** Home Assistant → **Settings → System → Logs**, search
      "Bedtime Bridge".

---

## Still to come (not part of this setup)

- **Soak mornings 2 and 3**, then the backstop cutover: `docs/ha-handoffs-v0.4.1.md`, section 6.
- **Leave titles:** only if you add titles besides *Leave* in Settings → Leave. Then Home
  Assistant's `current_shift.yaml` leave list needs the same titles
  (`docs/ha-handoffs-v0.4.3.md`, section 5).
