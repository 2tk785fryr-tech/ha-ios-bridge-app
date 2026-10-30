"""v0.4.3 integration tests, by spec item."""

from homeassistant.setup import async_setup_component
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events

from .test_ladder import TZ, ladder, calendar_days, local, plan, rungs, shift_sensor, status  # noqa: F401
from .test_webhook import send, setup


# MARK: Item 3, No alarms tomorrow


async def test_item3_no_alarms_with_shift_keeps_backstops_and_sets_sleep_in(hass, ladder, hass_client_no_auth):
    assert await async_setup_component(hass, "input_boolean", {"input_boolean": {"sleep_in": {}}})
    await ladder(sleep_in_helper="input_boolean.sleep_in")
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, plan(local("05:30").isoformat()))
    await send(hass_client_no_auth, {"type": "cancelled", "data": {"sleep_in": True, "morning": local("04:20", day=28).isoformat()}})
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.sleep_in").state == "on"
    # The Days shift is still on the calendar: its backstops stay on.
    assert status(hass) == "armed"
    assert rungs(hass) == ["04:40", "04:55", "05:10"]
    cancelled = [e for e in events if e.data.get("type") == "cancelled"]
    assert cancelled and cancelled[-1].data["sleep_in"] is True


async def test_item3_no_alarms_without_shift_goes_idle(hass, ladder, hass_client_no_auth):
    await ladder()
    shift_sensor(hass, start=None, shift=None, state="Off")
    hass.states.async_set("input_select.select_shift_override", "Off")
    await send(hass_client_no_auth, {"type": "cancelled", "data": {"sleep_in": False}})
    await hass.async_block_till_done()
    assert status(hass).startswith("idle")
    assert rungs(hass) is None


# MARK: Stale leave-by after a deleted shift (reported 29 Oct, fixed with v0.4.3)


async def test_no_alarms_after_the_shift_was_deleted_drops_leave_by(hass, ladder, hass_client_no_auth):
    await ladder()
    planned = plan(local("05:48").isoformat())
    planned["data"]["leave_by"] = local("05:48").isoformat()
    await send(hass_client_no_auth, planned)
    assert hass.states.get("sensor.bedtime_bridge_leave_by").state != "unknown"
    # The Days shift comes off the calendar; the next shift is days later.
    shift_sensor(hass, start="2026-11-02T06:30:00-05:00")
    await send(hass_client_no_auth, {"type": "morning_changed", "data": {
        "alarm_times": [], "alarms_planned": 0, "delay_minutes": 0, "phase": "bedtime", "scope": "alarms", "sleep_in": True,
    }})
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_leave_by").state == "unknown"


async def test_no_alarms_with_the_shift_still_on_keeps_leave_by(hass, ladder, hass_client_no_auth):
    await ladder()
    planned = plan(local("05:48").isoformat())
    planned["data"]["leave_by"] = local("05:48").isoformat()
    await send(hass_client_no_auth, planned)
    assert hass.states.get("sensor.bedtime_bridge_leave_by").state != "unknown"
    await send(hass_client_no_auth, {"type": "morning_changed", "data": {
        "alarm_times": [], "alarms_planned": 0, "delay_minutes": 0, "phase": "bedtime", "scope": "alarms", "sleep_in": True,
    }})
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_leave_by").state != "unknown"


# MARK: Item 5, wind-down

from datetime import datetime, timedelta  # noqa: E402

from homeassistant.core import callback  # noqa: E402
from pytest_homeassistant_custom_component.common import async_fire_time_changed, async_mock_service  # noqa: E402

from custom_components.bedtime_bridge import winddown  # noqa: E402

WIND = {"enabled": True}


async def test_item5_times_from_the_first_alarm(hass):
    await hass.config.async_set_time_zone(TZ)
    first = local("04:20", day=28)
    times = winddown.compute(first, sleep_goal=390, length=60, free=30, minimum=30)
    assert (winddown.short(times.wind_down), winddown.short(times.go_to_bed)) == ("8:50", "9:50")


async def test_item5_home_late_moves_bed_later_not_cutting_wind_down(hass):
    await hass.config.async_set_time_zone(TZ)
    first = local("04:20", day=28)
    times = winddown.compute(first, sleep_goal=390, length=60, free=30, minimum=30, home_at=local("21:30", day=27))
    # Home 9:30 + 30 free = wind-down 10:00, at least 30 min of it: bed 10:30 (less sleep).
    assert (winddown.short(times.wind_down), winddown.short(times.go_to_bed)) == ("10:00", "10:30")
    early = winddown.compute(first, sleep_goal=390, length=60, free=30, minimum=30, home_at=local("19:00", day=27))
    assert winddown.short(early.wind_down) == "8:50", "home early changes nothing"


async def wind_setup(hass, ladder, **options):
    assert await async_setup_component(hass, "input_boolean", {"input_boolean": {"winding_down": {}}})
    hass.states.async_set("binary_sensor.bed", "off")
    hass.states.async_set("binary_sensor.door", "on")
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(winding_down_helper="input_boolean.winding_down", bed_sensor="binary_sensor.bed",
                 bedroom_door_sensor="binary_sensor.door", notify_service="notify.phone", phone_commands=True, **options)
    return notes


def days_plan(first="04:20"):
    p = plan(local("05:45").isoformat())
    p["data"]["alarm_times"] = [local(first).isoformat()]
    p["data"]["wind_down_settings"] = WIND
    return p


async def at(hass, freezer, when):
    freezer.move_to(when)
    async_fire_time_changed(hass, when)
    await hass.async_block_till_done()


def messages(notes):
    return [c.data.get("message") for c in notes]


async def test_item5_evening_warning_wind_down_and_go_to_bed(hass, ladder, hass_client_no_auth, freezer):
    notes = await wind_setup(hass, ladder)
    reply = await send(hass_client_no_auth, days_plan())
    assert reply["wind_down"]["status"] == "scheduled"
    assert status_of(hass) == "scheduled"
    await at(hass, freezer, local("20:45", day=27))
    warning = [c for c in notes if c.data.get("message") == "Wind-down at 8:50 · bed 9:50"]
    assert warning and [a["action"] for a in warning[0].data["data"]["actions"]] == [
        "BEDTIME_BRIDGE_WIND_DOWN_LATER", "BEDTIME_BRIDGE_WIND_DOWN_CANCEL"]
    await at(hass, freezer, local("20:50", day=27))
    assert status_of(hass) == "winding_down"
    assert hass.states.get("input_boolean.winding_down").state == "on"
    assert "RUN_WIND_DOWN" in messages(notes)
    assert not any("tomorrow" in (m or "") for m in messages(notes)), "a normal shift morning gets no notice"
    await at(hass, freezer, local("21:50", day=27))
    bed = [c for c in notes if c.data.get("message") == "Time for bed · first alarm 4:20"]
    assert bed and bed[0].data["data"]["push"]["sound"]["critical"] == 1
    assert hass.states.get("input_boolean.winding_down").state == "off"
    # Not in bed: Still up every 10 min, at most 6, time-sensitive.
    for minute in range(10, 80, 10):
        await at(hass, freezer, local("21:50", day=27) + timedelta(minutes=minute))
    still = [c for c in notes if (c.data.get("message") or "").startswith("Still up")]
    assert len(still) == 6
    assert still[0].data["data"]["push"]["interruption-level"] == "time-sensitive"


def status_of(hass):
    return hass.states.get("sensor.bedtime_bridge_wind_down_status").state


async def test_item5_later_and_cancel_buttons(hass, ladder, hass_client_no_auth, freezer):
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    hass.bus.async_fire("mobile_app_notification_action", {"action": "BEDTIME_BRIDGE_WIND_DOWN_LATER"})
    await hass.async_block_till_done()
    assert winddown.short(dt_util.parse_datetime(hass.states.get("sensor.bedtime_bridge_wind_down").state)) == "9:05"
    assert winddown.short(dt_util.parse_datetime(hass.states.get("sensor.bedtime_bridge_go_to_bed").state)) == "9:50"
    for _ in range(3):
        hass.bus.async_fire("mobile_app_notification_action", {"action": "BEDTIME_BRIDGE_WIND_DOWN_LATER"})
        await hass.async_block_till_done()
    assert winddown.short(dt_util.parse_datetime(hass.states.get("sensor.bedtime_bridge_wind_down").state)) == "9:20", "never below the minimum"
    hass.bus.async_fire("mobile_app_notification_action", {"action": "BEDTIME_BRIDGE_WIND_DOWN_CANCEL"})
    await hass.async_block_till_done()
    assert status_of(hass) == "cancelled"
    assert "RUN_WIND_DOWN_CANCEL" in messages(notes)
    await at(hass, freezer, local("22:30", day=27))
    assert not any((m or "").startswith(("Time for bed", "Still up")) for m in messages(notes))


async def test_item5_into_bed_early_ends_it_and_undo_runs_only_reminders(hass, ladder, hass_client_no_auth, freezer):
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("21:00", day=27))
    assert status_of(hass) == "winding_down"
    await send(hass_client_no_auth, {"type": "bedtime", "data": {}})
    assert status_of(hass) == "bedtime"
    assert hass.states.get("input_boolean.winding_down").state == "off"
    await send(hass_client_no_auth, {"type": "bedtime_undone", "data": {}})
    await at(hass, freezer, local("21:50", day=27))
    assert not any((m or "").startswith("Time for bed") for m in messages(notes)), "wind-down doesn't restart"
    await at(hass, freezer, local("22:00", day=27))
    assert any((m or "").startswith("Still up") for m in messages(notes))


async def test_item5_in_bed_skips_go_to_bed_and_records_went_to_bed(hass, ladder, hass_client_no_auth, freezer):
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("21:40", day=27))
    hass.states.async_set("binary_sensor.door", "off")
    hass.states.async_set("binary_sensor.bed", "on")
    await hass.async_block_till_done()
    await at(hass, freezer, local("22:10", day=27))
    assert not any((m or "").startswith(("Time for bed", "Still up")) for m in messages(notes))
    assert hass.states.get("sensor.bedtime_bridge_bedtime_off_target").state == "-10"


async def test_item5_event_morning_says_so_at_wind_down(hass, ladder, hass_client_no_auth, freezer):
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, {"type": "preview", "data": {
        "first_alarm": local("05:00").isoformat(), "cause": "calendar", "event": "Ultrasound",
        "event_start": local("07:00").isoformat(), "leave_by": local("06:15").isoformat(), "wind_down_settings": WIND}})
    await at(hass, freezer, local("21:30", day=27))
    assert "Ultrasound at 7:00 AM tomorrow · leave by 6:15 · first alarm 5:00" in messages(notes)


async def test_item5_preview_unanswered_uses_the_calendar_and_says_so(hass, ladder, hass_client_no_auth, freezer):
    freezer.move_to(local("17:00", day=27))
    notes = await wind_setup(hass, ladder)
    # Settings arrive with any message; nothing planned yet.
    await send(hass_client_no_auth, {"type": "context", "data": {"wind_down_settings": WIND}})
    await hass.async_block_till_done()
    # Days 6:30 − 120 min lead = first alarm 4:30 → wind-down 9:00; preview 2 h before, at 7:00 PM.
    await at(hass, freezer, local("19:00", day=27))
    assert "RUN_PLAN_PREVIEW" in messages(notes)
    await at(hass, freezer, local("19:11", day=27))
    await at(hass, freezer, local("20:55", day=27))
    assert "Wind-down at 9:00 · bed 10:00 (appointments not checked)" in messages(notes)


async def test_item5_off_until_set_up(hass, ladder, hass_client_no_auth, freezer):
    notes = await wind_setup(hass, ladder)
    p = days_plan()
    p["data"].pop("wind_down_settings")
    await send(hass_client_no_auth, p)
    assert status_of(hass) == "off"
    await at(hass, freezer, local("22:30", day=27))
    assert not any((m or "").startswith(("Wind-down", "Time for bed")) for m in messages(notes))


# MARK: Item 7a, reset alarms and backstops


async def test_item7_reset_clears_alarms_moves_and_helpers_then_follows_the_calendar(hass, ladder, hass_client_no_auth, freezer):
    assert await async_setup_component(hass, "input_boolean", {"input_boolean": {"winding_down": {}, "napping": {}, "sleep_in": {}}})
    await ladder(winding_down_helper="input_boolean.winding_down", napping_helper="input_boolean.napping",
                 sleep_in_helper="input_boolean.sleep_in")
    hass.states.async_set("input_boolean.sleep_in", "on")
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, days_plan())
    # A delay this morning moved the ladder.
    await send(hass_client_no_auth, {"type": "morning_changed", "data": {
        "alarm_times": [local("06:20").isoformat()], "alarms_planned": 1, "delay_minutes": 120, "phase": "bedtime", "scope": "wake_up"}})
    await hass.services.async_call("input_boolean", "turn_on", {"entity_id": ["input_boolean.winding_down", "input_boolean.napping"]}, blocking=True)
    await send(hass_client_no_auth, {"type": "reset", "data": {}})
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_alarm_cause").state == "noalarm"
    assert hass.states.get("sensor.bedtime_bridge_next_alarm").state == "unknown"
    assert hass.states.get("input_boolean.winding_down").state == "off"
    assert hass.states.get("input_boolean.napping").state == "off"
    assert hass.states.get("input_boolean.sleep_in").state == "on", "Sleep In is left alone"
    # The Days shift is still on the calendar: armed again at the calendar's own times, no delay.
    assert status(hass) == "armed"
    assert rungs(hass) == ["04:55", "05:10", "05:25"]
    assert any(e.data.get("type") == "reset" for e in events)
    assert status_of(hass) == "off"


# MARK: Item 9, app expiry


async def test_item9_app_expires_sensor_and_bedtime_warning_on_the_last_two_days(hass, ladder, hass_client_no_auth, freezer):
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone")
    await send(hass_client_no_auth, {"type": "context", "data": {"app_expires": local("21:14", day=30).isoformat()}})
    state = hass.states.get("sensor.bedtime_bridge_app_expires")
    assert dt_util.parse_datetime(state.state) == local("21:14", day=30)
    await send(hass_client_no_auth, {"type": "bedtime", "data": {}})
    assert not [c for c in notes if "Reinstall" in (c.data.get("title") or "")], "3 days out: nothing yet"
    freezer.move_to(local("22:00", day=28))
    await send(hass_client_no_auth, {"type": "bedtime", "data": {}})
    await send(hass_client_no_auth, {"type": "bedtime", "data": {}})
    warned = [c for c in notes if "Reinstall" in (c.data.get("title") or "")]
    assert len(warned) == 1, "once a night"
    freezer.move_to(local("22:00", day=29))
    await send(hass_client_no_auth, {"type": "bedtime", "data": {}})
    assert len([c for c in notes if "Reinstall" in (c.data.get("title") or "")]) == 2


# MARK: Item 10, phone not charging


async def test_item10_plug_in_at_bedtime_and_again_after_10_min(hass, ladder, hass_client_no_auth, freezer):
    notes = async_mock_service(hass, "notify", "phone")
    hass.states.async_set("sensor.batt", "22")
    hass.states.async_set("sensor.batt_state", "Not Charging")
    await ladder(notify_service="notify.phone", phone_battery_sensor="sensor.batt", phone_battery_state_sensor="sensor.batt_state")
    await send(hass_client_no_auth, days_plan())
    await send(hass_client_no_auth, {"type": "bedtime", "data": {"battery_level": 22, "battery_charging": False,
                                                                 "charge_warning": {"enabled": True, "threshold": 30}}})
    plug = [c for c in notes if c.data.get("message") == "Plug in your phone · alarms at 4:20"]
    assert len(plug) == 1 and plug[0].data["data"]["push"]["interruption-level"] == "time-sensitive"
    await at(hass, freezer, local("20:10", day=27) + timedelta(seconds=30))
    assert len([c for c in notes if (c.data.get("message") or "").startswith("Plug in")]) == 2, "still not charging"


async def test_item10_charging_or_above_threshold_says_nothing(hass, ladder, hass_client_no_auth, freezer):
    notes = async_mock_service(hass, "notify", "phone")
    hass.states.async_set("sensor.batt_state", "Charging")
    await ladder(notify_service="notify.phone", phone_battery_state_sensor="sensor.batt_state")
    await send(hass_client_no_auth, {"type": "bedtime", "data": {"battery_level": 22, "battery_charging": True}})
    await send(hass_client_no_auth, {"type": "bedtime", "data": {"battery_level": 80, "battery_charging": False}})
    await send(hass_client_no_auth, {"type": "bedtime", "data": {"battery_level": 10, "battery_charging": False,
                                                                 "charge_warning": {"enabled": False, "threshold": 30}}})
    await at(hass, freezer, local("20:15", day=27))
    assert not [c for c in notes if (c.data.get("message") or "").startswith("Plug in")]


# MARK: Item 14, morning Live Activity updates


async def test_item14_hourly_morning_updates_after_the_first_stop_and_one_on_leaving(hass, ladder, hass_client_no_auth, freezer):
    notes = async_mock_service(hass, "notify", "phone")
    hass.states.async_set("person.me", "home")
    await ladder(notify_service="notify.phone", phone_commands=True, presence_entities=["person.me"])
    freezer.move_to(local("04:20"))
    planned = days_plan()
    planned["data"]["leave_by"] = local("06:45").isoformat()
    await send(hass_client_no_auth, planned)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await at(hass, freezer, local("05:21"))
    assert messages(notes).count("RUN_MORNING_UPDATE") == 1
    await at(hass, freezer, local("06:21"))
    assert messages(notes).count("RUN_MORNING_UPDATE") == 2
    hass.states.async_set("person.me", "not_home")
    await hass.async_block_till_done()
    assert messages(notes).count("RUN_MORNING_UPDATE") == 3, "left home: once more, so the app ends it"
    await at(hass, freezer, local("07:01"))
    assert messages(notes).count("RUN_MORNING_UPDATE") == 3, "and no more after that"


async def test_item14_no_alarms_change_stops_the_updates(hass, ladder, hass_client_no_auth, freezer):
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone", phone_commands=True)
    freezer.move_to(local("04:20"))
    planned = days_plan()
    planned["data"]["leave_by"] = local("06:45").isoformat()
    await send(hass_client_no_auth, planned)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await send(hass_client_no_auth, {"type": "morning_changed", "data": {
        "alarm_times": [], "alarms_planned": 0, "delay_minutes": 0, "phase": "up", "scope": "alarms", "sleep_in": True}})
    await at(hass, freezer, local("06:30"))
    assert "RUN_MORNING_UPDATE" not in messages(notes)


# MARK: Item 15, weekly summary

from custom_components.bedtime_bridge import weekly  # noqa: E402


def test_item15_summary_text():
    now = dt_util.utcnow()
    history = []
    for day, snoozes in ((1, 2), (2, 1), (3, 0)):
        weekly.record(history, "morning", now - timedelta(days=day), snoozes=snoozes, backstops_fired=1 if day == 1 else 0)
    weekly.record(history, "change", now - timedelta(days=2), reason="Snow delay")
    weekly.record(history, "change", now - timedelta(days=9), reason="Too old")
    weekly.record(history, "nap", now - timedelta(days=1), minutes=30)
    nights = [{"go_to_bed": (now - timedelta(days=d)).isoformat(), "minutes_off": off} for d, off in ((1, 10), (2, 14))]
    summary = weekly.summarize(history, nights, now)
    assert summary["text"] == "Bed 12 min after target on average · 1 snoozes a morning · 1 backstop fired · 1 morning changed (Snow delay) · 1 nap"
    assert summary["change_reasons"] == ["Snow delay"]


async def test_item15_sent_on_its_day_with_a_link_to_the_app(hass, ladder, hass_client_no_auth, freezer):
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone")
    # 27 Oct 2026 is a Tuesday; Sunday 6 PM is 1 Nov.
    await send(hass_client_no_auth, {"type": "context", "data": {"weekly_summary": {"enabled": True, "weekday": 6, "time": "18:00"}}})
    await send(hass_client_no_auth, {"type": "nap_started", "data": {"alarm_times": [local("21:00", day=27).isoformat()], "minutes": 20}})
    await at(hass, freezer, local("18:00", day=31))
    assert not [c for c in notes if c.data.get("title") == "Your week"]
    await at(hass, freezer, datetime(2026, 11, 1, 18, 0, tzinfo=dt_util.get_time_zone(TZ)))
    sent = [c for c in notes if c.data.get("title") == "Your week"]
    assert sent and sent[0].data["data"]["url"] == "bedtimebridge://summary"
    assert "1 nap" in hass.states.get("sensor.bedtime_bridge_weekly_summary").state


# MARK: Review fixes (29 Oct)


async def test_fix_bedtime_shortcut_report_ends_wind_down(hass, ladder, hass_client_no_auth, freezer):
    """The bedtime shortcut only reports RUN_BEDTIME; that's bedtime."""
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("21:00", day=27))
    await send(hass_client_no_auth, {"type": "command_ran", "data": {"command": "RUN_BEDTIME", "outcome": "ran"}})
    assert status_of(hass) == "bedtime"
    assert hass.states.get("input_boolean.winding_down").state == "off"
    await at(hass, freezer, local("22:30", day=27))
    assert not any((m or "").startswith(("Time for bed", "Still up")) for m in messages(notes)), "asleep with the door open: nothing"


async def test_fix_a_morning_change_never_rebuilds_last_night(hass, ladder, hass_client_no_auth, freezer):
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("04:25"))
    await send(hass_client_no_auth, {"type": "morning_changed", "data": {
        "alarm_times": [local("06:00").isoformat()], "alarms_planned": 1, "delay_minutes": 100, "phase": "snoozing", "scope": "alarms"}})
    await at(hass, freezer, local("04:40"))
    late = [m for m in messages(notes) if (m or "").startswith(("Time for bed", "Still up")) and "6:00" in m]
    assert not late, "no go to bed or reminders in the morning"


async def test_fix_reminders_skip_missed_slots(hass, ladder, hass_client_no_auth, freezer):
    await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    wd = hass.config_entries.async_entries("bedtime_bridge")[0].runtime_data.wind_down
    wd.s["reminders_sent"] = 1
    nxt = wd._next_reminder(local("22:31", day=27))
    assert nxt == local("22:40", day=27), "the next slot, not a burst of the missed ones"


async def test_fix_no_alarms_tomorrow_stops_a_previewed_wind_down(hass, ladder, hass_client_no_auth, freezer):
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, {"type": "preview", "data": {"first_alarm": local("04:20").isoformat(), "cause": "Days", "wind_down_settings": WIND}})
    assert status_of(hass) == "scheduled"
    await send(hass_client_no_auth, {"type": "cancelled", "data": {"sleep_in": True}})
    assert status_of(hass) == "off"
    await at(hass, freezer, local("22:30", day=27))
    assert not any((m or "").startswith(("Wind-down", "Time for bed")) for m in messages(notes))


async def test_fix_start_now_only_within_its_window(hass, ladder, hass_client_no_auth, freezer):
    await wind_setup(hass, ladder)
    freezer.move_to(local("15:00", day=27))
    await send(hass_client_no_auth, days_plan())
    reply = await send(hass_client_no_auth, {"type": "wind_down", "data": {"action": "start"}})
    assert reply["started"] is False and status_of(hass) == "scheduled"
    freezer.move_to(local("20:00", day=27))
    reply = await send(hass_client_no_auth, {"type": "wind_down", "data": {"action": "start"}})
    assert reply["started"] is True and status_of(hass) == "winding_down"


async def test_fix_preview_wait_survives_a_reschedule_and_a_deleted_shift_ends_it(hass, ladder, hass_client_no_auth, freezer):
    freezer.move_to(local("17:00", day=27))
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, {"type": "context", "data": {"wind_down_settings": WIND}})
    await at(hass, freezer, local("19:00", day=27))
    assert "RUN_PLAN_PREVIEW" in messages(notes)
    # An attribute update on the shift sensor during the wait used to drop it.
    shift_sensor(hass)
    hass.states.async_set("sensor.current_shift", "Days", {**hass.states.get("sensor.current_shift").attributes, "x": 1})
    await hass.async_block_till_done()
    await at(hass, freezer, local("19:11", day=27))
    assert status_of(hass) == "scheduled", "the calendar fallback still ran"
    # Then the shift is deleted: the calendar-only times go.
    shift_sensor(hass, start="2026-11-02T06:30:00-05:00")
    await hass.async_block_till_done()
    assert status_of(hass) == "off"


async def test_fix_morning_updates_work_the_next_morning_too(hass, ladder, hass_client_no_auth, freezer):
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone", phone_commands=True)
    for day in (28, 29):
        freezer.move_to(local("04:20", day=day))
        planned = days_plan()
        planned["data"]["leave_by"] = local("06:45", day=day).isoformat()
        planned["data"]["alarm_times"] = [local("04:20", day=day).isoformat()]
        await send(hass_client_no_auth, planned)
        await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
        await at(hass, freezer, local("05:21", day=day))
        await at(hass, freezer, local("07:05", day=day))
    assert messages(notes).count("RUN_MORNING_UPDATE") >= 4, "both mornings got their updates"
