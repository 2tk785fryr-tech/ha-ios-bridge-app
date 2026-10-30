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

## 5. Drive times worked out in Home Assistant (optional)

Today each leave check wakes the phone (`RUN_LEAVE_CHECK`) to re-check the drive. With a drive
service chosen, Home Assistant re-checks it itself: the drive from home arriving by your
arrive-by, with the traffic expected then. It moves leave-by, updates the Live Activity, and sends
"Leave by 5:48 · 32 min drive (5 min worse than planned)" (level on the app's Settings →
Notifications page, *Leave by (checked by Home Assistant)*). It works with the phone asleep. If
the service doesn't answer, it asks the phone as before.

The app's own drive times don't change: it still plans at bedtime and re-checks when you stop an
alarm or open it, wherever you are. While Home Assistant does the checks and you're home at
bedtime, the app skips its own leave reminders (Home Assistant's replace them); away, or when Home
Assistant can't be reached, it schedules them as before.

**Integration options** (Configure):

| Option | What |
| --- | --- |
| Drive times from | Phone (default) · Apple Maps · TomTom · Google · Longest of all |
| Apple Maps key (.p8) and Key ID | For Apple Maps (below) |
| TomTom key | The same key the app uses |
| Google key | A Routes API key; the app's works unless it's restricted to the iOS app only |

The drive starts from Home Assistant's home zone.

**Apple Maps key** (Michael, on developer.apple.com; registering is a credential step):

1. Certificates, Identifiers & Profiles → **Identifiers** → **+** → **Maps IDs** → Continue.
   Description *Bedtime Bridge*, identifier `maps.io.github.2tk785fryr-tech.bedtimebridge` →
   Register.
2. **Keys** → **+** → name *Bedtime Bridge Maps*, tick **MapKit JS** (it covers the Maps Server
   API) → Configure → choose that Maps ID → Save → Continue → **Register**.
3. **Download** the `AuthKey_….p8` (once only; keep it with the push key) and note its Key ID.
4. Paste both into the integration's options and set *Drive times from* to Apple Maps (or Longest
   of all).
