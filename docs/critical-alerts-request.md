# Critical Alerts entitlement request (v0.4.7 item 1)

Michael submits this; Claude drafted it. Where: developer.apple.com → **Contact Us** → *Development
and Technical* → **Request a Critical Alerts entitlement** (or search "Critical Alerts entitlement
request" on developer.apple.com/contact). Signed in as the Developer Program account (team
`E3P6U6KP7P`).

## Fields

- **App name:** Bedtime Bridge
- **Bundle ID:** `io.github.2tk785fryr-tech.bedtimebridge`
- **App Store status:** not on the App Store; installed from Xcode on the developer's own iPhone.
  (If the form requires an App Store app, say it's for personal use and ask whether that's
  accepted.)
- **Category:** time-sensitive safety / wake-up for shift work

## Why the app needs it (paste into the description box)

Bedtime Bridge sets wake-up alarms for a shift worker (military duty days that start as early as
6:30 AM) from their work calendar, and works out when they have to leave from the drive time and
the weather. Missing that leave time means arriving late for duty.

The alarms themselves use AlarmKit. Critical Alerts would be used only for a few notifications
the app sends itself, which today can be at most Time-sensitive:

1. **Leave-by reminders** on a work morning ("Leave by 5:48 · 32 min drive"), re-checked against
   live traffic. If the phone is on silent or in a Sleep Focus after the alarms, a missed reminder
   means leaving late.
2. **A backup leave reminder** that fires only when the home server that normally sends it can't
   be reached overnight.
3. **"Tomorrow changed"**: the next work morning's shift was moved or deleted after the alarms
   were set (the alarms may now be wrong).

Each notification's level is the user's choice in the app (Settings → Notifications: Normal,
Time-sensitive or Critical); nothing is Critical unless the user picks it, and the app asks for
Critical Alerts permission separately. The app has no ads, no marketing notifications, and sends
nothing to anyone but its own user.

## After Apple answers

- **Granted:** tell Claude. The rest of item 1 is then built: the entitlement and profile, asking
  for critical-alert permission with notifications, and Critical offered for the app's own
  notifications in Settings → Notifications (defaults unchanged; Time-sensitive if permission is
  off).
- **Declined or no answer:** nothing changes; the item stays open in the next spec.
