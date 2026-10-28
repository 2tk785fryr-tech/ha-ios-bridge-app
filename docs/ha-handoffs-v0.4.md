# Home Assistant hand-offs for Bedtime Bridge v0.4

Changes on the Home Assistant side that v0.4 needs, for the Home Assistant chat to apply. Nothing
here has been changed in the live instance from this repo. Read each item back after applying it.

Integration version: **0.4.0**. Install it from HACS (and restart) before the item 6 steps.

## Item 7: Sleep In has one owner

The integration sets `input_boolean.sleep_in` on every plan, on a skipped morning, on *Not going to
sleep yet*, and (item 3) when the morning changes. The Bedtime Readout stops setting it.

1. In the Bedtime Readout (`script.bedtime_readout`, the YAML file in `/config/scripts/`), set
   `auto_set_sleep_in: false`. The readout still reads Sleep In for what it says; it just doesn't
   write it.
2. Reload scripts.
3. Read back: `auto_set_sleep_in` is `false`, and the readout's spoken text still mentions Sleep In
   correctly after a bedtime run (`dry_run: true` is enough).

Still writing Sleep In after this, outside Home Assistant: the bedtime shortcut's "No alarms →
enable Sleep In? → Yes" HomeKit scene (see `docs/shortcuts.md`). That's a phone-side decision for
Mike, not a hand-off.
