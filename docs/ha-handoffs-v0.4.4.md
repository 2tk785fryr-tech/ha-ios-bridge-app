# Home Assistant hand-offs for Bedtime Bridge 0.4.4: Live Activities by push

With the paid Developer Program membership (since 29 Oct 2026), Home Assistant can start, update
and end the app's Live Activities itself through Apple's push service, so they change while the
app isn't running:

- **Wind-down:** "Bed in 42 min · first alarm 4:20" appears when wind-down starts (Home
  Assistant's time, without opening the app), follows a changed go to bed, and goes at go to bed,
  on cancel or when you get into bed.
- **Morning:** "Leave in 25 min · 5:45" appears at the first stop, refreshes every hour (weather
  from Home Assistant's weather entity, drive and leave-by from the latest re-check, next
  backstop), and ends when you leave home, 15 min after leave-by, or when the morning changes to
  no alarms.

Nothing here has been changed in the live instance from this repo.

## 1. Install 0.4.4

Install it from HACS and restart. It needs the `h2` Python package (HTTP/2, which Apple's push
service requires); Home Assistant installs it from the manifest on restart.

## 2. The key (Michael does this; it's a private key)

The key was created on 29 Oct 2026 at developer.apple.com → Certificates, Identifiers & Profiles →
Keys: *Bedtime Bridge Live Activities*, Apple Push Notifications service, Sandbox & Production,
team scoped. The file is `~/Downloads/AuthKey_S663T448S3.p8`; keep a copy somewhere safe (Apple
only lets it be downloaded once) and don't put it in the repo.

1. Open the file in TextEdit and copy everything, including the `-----BEGIN PRIVATE KEY-----` and
   `-----END PRIVATE KEY-----` lines.
2. **Settings → Devices & services → Bedtime Bridge → Configure**:
   - **Apple push key (.p8):** paste it.
   - **Apple push Key ID:** `S663T448S3`.
3. Open the app once: it sends Home Assistant its push tokens (and its team and bundle ID).

The development build from Xcode uses Apple's sandbox push server; the app says which, so nothing
to choose.

## 3. Phone

**Morning Update - App** and its `RUN_MORNING_UPDATE` automation are no longer needed once the key
is in: with a key, Home Assistant pushes instead of sending the command. Leave them in place until
you've seen a morning work by push, then delete both.

## 4. Check

- `sensor.bedtime_bridge_last_event` attributes don't show push results; failures are logged
  (Settings → System → Logs, search "Live Activity push").
- First evening with wind-down on: the Lock Screen shows "Bed in …" at wind-down time without
  opening the app.
