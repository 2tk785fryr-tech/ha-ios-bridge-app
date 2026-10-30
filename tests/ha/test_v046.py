"""v0.4.6 integration tests, by spec item."""

from datetime import datetime, timedelta

from homeassistant.util import dt as dt_util

from custom_components.bedtime_bridge import weekly

from .test_ladder import TZ, calendar_days, ladder, local  # noqa: F401
from .test_v043 import at
from .test_webhook import send

SUNDAY_6PM = {"enabled": True, "weekday": 6, "time": "18:00"}


def _tz():
    return dt_util.get_time_zone(TZ)


# MARK: Item 5, weekly summary: this week so far, and earlier weeks


async def test_item5_cutoff_is_the_settings_day_and_time(hass):
    await hass.config.async_set_time_zone(TZ)
    # Friday 30 Oct 2026: the last cut-off was Sunday 25 Oct, 6 PM.
    now = datetime(2026, 10, 30, 9, 0, tzinfo=_tz())
    assert dt_util.as_local(weekly.last_cutoff(SUNDAY_6PM, now)) == datetime(2026, 10, 25, 18, 0, tzinfo=_tz())
    # At the cut-off itself, the new week starts.
    sunday = datetime(2026, 11, 1, 18, 0, tzinfo=_tz())
    assert weekly.last_cutoff(SUNDAY_6PM, sunday) == dt_util.as_utc(sunday)
    # Wednesday 7:30 AM, even with the notification off.
    wednesday = {"enabled": False, "weekday": 2, "time": "07:30"}
    assert dt_util.as_local(weekly.last_cutoff(wednesday, now)) == datetime(2026, 10, 28, 7, 30, tzinfo=_tz())


async def test_item5_this_week_so_far_then_earlier_weeks(hass):
    await hass.config.async_set_time_zone(TZ)
    now = datetime(2026, 10, 30, 9, 0, tzinfo=_tz())
    history = []
    # This week (since Sun 25 Oct 6 PM): two mornings and a nap.
    weekly.record(history, "morning", datetime(2026, 10, 27, 5, 0, tzinfo=_tz()), snoozes=1)
    weekly.record(history, "morning", datetime(2026, 10, 29, 5, 0, tzinfo=_tz()), snoozes=3)
    weekly.record(history, "nap", datetime(2026, 10, 28, 14, 0, tzinfo=_tz()), minutes=20)
    # The week before (18 – 25 Oct): one morning, one change, and one right at the cut-off.
    weekly.record(history, "morning", datetime(2026, 10, 20, 5, 0, tzinfo=_tz()), snoozes=0)
    weekly.record(history, "change", datetime(2026, 10, 21, 22, 0, tzinfo=_tz()), reason="Snow delay")
    weekly.record(history, "change", datetime(2026, 10, 25, 18, 0, tzinfo=_tz()), reason="At the cut-off")
    # Three weeks back (4 – 11 Oct); the two weeks between have nothing and are left out.
    weekly.record(history, "morning", datetime(2026, 10, 6, 5, 0, tzinfo=_tz()), snoozes=2)
    nights = [{"go_to_bed": datetime(2026, 10, 26, 22, 0, tzinfo=_tz()).isoformat(), "minutes_off": 8}]

    weeks = weekly.weeks(history, nights, SUNDAY_6PM, now)
    assert [w["current"] for w in weeks] == [True, False, False]
    this, last, older = weeks
    assert dt_util.as_local(dt_util.parse_datetime(this["from"])) == datetime(2026, 10, 25, 18, 0, tzinfo=_tz())
    assert this["mornings"] == 2 and this["naps"] == 1 and this["nights_tracked"] == 1
    # The change at the cut-off belongs to this week, not the one before.
    assert this["change_reasons"] == ["At the cut-off"]
    assert dt_util.as_local(dt_util.parse_datetime(last["from"])) == datetime(2026, 10, 18, 18, 0, tzinfo=_tz())
    assert dt_util.as_local(dt_util.parse_datetime(last["to"])) == datetime(2026, 10, 25, 18, 0, tzinfo=_tz())
    assert last["mornings"] == 1 and last["change_reasons"] == ["Snow delay"]
    assert dt_util.as_local(dt_util.parse_datetime(older["from"])) == datetime(2026, 10, 4, 18, 0, tzinfo=_tz())


async def test_item5_at_most_eight_earlier_weeks(hass):
    await hass.config.async_set_time_zone(TZ)
    now = datetime(2026, 10, 30, 9, 0, tzinfo=_tz())
    history = []
    for back in range(12):
        weekly.record(history, "morning", now - timedelta(days=7 * back), snoozes=0)
    weeks = weekly.weeks(history, [], SUNDAY_6PM, now)
    assert len(weeks) == 1 + 8
    assert weekly.KEEP_DAYS >= 7 * 9


async def test_item5_reply_carries_the_weeks_and_the_notification_the_week_that_ended(hass, ladder, hass_client_no_auth, freezer):
    await ladder()
    await send(hass_client_no_auth, {"type": "context", "data": {"weekly_summary": SUNDAY_6PM}})
    await send(hass_client_no_auth, {"type": "nap_started", "data": {"alarm_times": [local("21:00", day=27).isoformat()], "minutes": 20}})
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    weeks = reply["weekly_summaries"]
    assert weeks[0]["current"] is True and weeks[0]["naps"] == 1
    # Sunday 1 Nov, 6 PM: the summary sent is the week that just ended (25 Oct – 1 Nov).
    await at(hass, freezer, datetime(2026, 11, 1, 18, 0, tzinfo=_tz()))
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    sent = reply["weekly_summary"]
    assert dt_util.as_local(dt_util.parse_datetime(sent["from"])) == datetime(2026, 10, 25, 18, 0, tzinfo=_tz())
    assert sent["naps"] == 1
    # And a new week has started, with nothing in it yet.
    assert reply["weekly_summaries"][0]["current"] is True and reply["weekly_summaries"][0]["naps"] == 0
    assert reply["weekly_summaries"][1]["naps"] == 1


# MARK: Item 2, mornings with no alarms

from homeassistant.setup import async_setup_component  # noqa: E402
from pytest_homeassistant_custom_component.common import async_fire_time_changed, async_mock_service  # noqa: E402

from .test_webhook import setup  # noqa: E402

BED, DOOR, HALL, PATIO = "binary_sensor.bed_left", "binary_sensor.bedroom_door", "binary_sensor.hallway", "binary_sensor.patio_door"
CHARGER = "sensor.phone_battery_state"


def _messages(notify):
    return [c.data["message"] for c in notify if c.data.get("message") != "clear_notification"]


def _titles(notify):
    return [c.data.get("title") for c in notify if c.data.get("title") not in (None, "Bedtime Bridge")]


async def _morning(hass, freezer, when="06:30"):
    """Friday 30 Oct, no alarms, Sleep In on, in bed."""
    await hass.config.async_set_time_zone(TZ)
    freezer.move_to(datetime(2026, 10, 30, *map(int, when.split(":")), tzinfo=_tz()))
    notify = async_mock_service(hass, "notify", "phone")
    assert await async_setup_component(hass, "input_boolean", {"input_boolean": {"sleep_in": {"initial": True}, "awake_for_day": {"initial": False}}})
    for entity, state in ((BED, "on"), (DOOR, "off"), (HALL, "off"), (PATIO, "off"), (CHARGER, "Charging")):
        hass.states.async_set(entity, state)
    await setup(hass, notify_service="notify.phone", phone_commands=True, bed_sensor=BED, bedroom_door_sensor=DOOR,
                hallway_sensors=[HALL], awake_helper="input_boolean.awake_for_day", sleep_in_helper="input_boolean.sleep_in",
                phone_battery_state_sensor=CHARGER, rearm_minutes=5)
    return notify


async def _tick(hass, freezer, **delta):
    freezer.tick(timedelta(**delta))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()


async def _leave_bedroom(hass, freezer):
    hass.states.async_set(BED, "off")
    await _tick(hass, freezer, seconds=20)
    hass.states.async_set(DOOR, "on")
    await _tick(hass, freezer, seconds=5)
    hass.states.async_set(HALL, "on")
    await hass.async_block_till_done()


async def test_item2_leaving_the_bedroom_disarms_and_back_in_bed_rearms(hass, freezer):
    notify = await _morning(hass, freezer, "06:30")
    await _leave_bedroom(hass, freezer)
    assert _messages(notify) == ["RUN_DISARM"]
    # Letting the dog out the patio door, then back to bed: re-armed after 5 min in bed.
    hass.states.async_set(PATIO, "on")
    await _tick(hass, freezer, minutes=3)
    hass.states.async_set(BED, "on")
    await _tick(hass, freezer, minutes=6)
    assert _messages(notify) == ["RUN_DISARM", "RUN_ARM_STAY"]
    # Nothing else happened: Sleep In and Awake For Day as they were, no question asked.
    assert hass.states.get("input_boolean.sleep_in").state == "on"
    assert hass.states.get("input_boolean.awake_for_day").state == "off"
    assert _titles(notify) == []


async def test_item2_not_on_alarm_mornings(hass, freezer, hass_client_no_auth):
    notify = await _morning(hass, freezer, "06:30")
    alarm = datetime(2026, 10, 30, 7, 30, tzinfo=_tz()).isoformat()
    await send(hass_client_no_auth, {"type": "planned", "data": {"alarm_times": [alarm], "alarm_time": alarm, "wake_time": alarm, "alarm_cause": "manual"}})
    await _leave_bedroom(hass, freezer)
    assert "RUN_DISARM" not in _messages(notify)


async def test_item2_asks_from_eight_then_goes_ahead(hass, freezer):
    notify = await _morning(hass, freezer, "07:30")
    await _leave_bedroom(hass, freezer)
    # Up 15 min by 7:45, but nothing before 8:00.
    await _tick(hass, freezer, minutes=20)
    assert _titles(notify) == []
    await _tick(hass, freezer, minutes=10)
    assert _titles(notify) == ["Up for the day?"]
    actions = [a["action"] for a in notify[-1].data["data"]["actions"]]
    assert actions == ["BEDTIME_BRIDGE_GOOD_MORNING", "BEDTIME_BRIDGE_BACK_TO_BED"]
    # No answer, still up 10 min later: good morning.
    await _tick(hass, freezer, minutes=11)
    assert _messages(notify)[-1] == "RUN_GOOD_MORNING"
    assert hass.states.get("input_boolean.sleep_in").state == "off"
    assert hass.states.get("input_boolean.awake_for_day").state == "on"
    # Up for the day: lying down again doesn't re-arm.
    hass.states.async_set(BED, "on")
    await _tick(hass, freezer, minutes=10)
    assert "RUN_ARM_STAY" not in _messages(notify)


async def test_item2_back_to_bed_answer(hass, freezer):
    notify = await _morning(hass, freezer, "08:10")
    await _leave_bedroom(hass, freezer)
    await _tick(hass, freezer, minutes=16)
    assert _titles(notify) == ["Up for the day?"]
    hass.bus.async_fire("mobile_app_notification_action", {"action": "BEDTIME_BRIDGE_BACK_TO_BED"})
    await _tick(hass, freezer, minutes=15)
    assert "RUN_GOOD_MORNING" not in _messages(notify)
    assert hass.states.get("input_boolean.awake_for_day").state == "off"


async def test_item2_good_morning_button(hass, freezer):
    notify = await _morning(hass, freezer, "08:10")
    await _leave_bedroom(hass, freezer)
    await _tick(hass, freezer, minutes=16)
    hass.bus.async_fire("mobile_app_notification_action", {"action": "BEDTIME_BRIDGE_GOOD_MORNING"})
    await hass.async_block_till_done()
    assert _messages(notify)[-1] == "RUN_GOOD_MORNING"
    assert hass.states.get("input_boolean.awake_for_day").state == "on"


async def test_item2_off_the_charger_counts_as_up(hass, freezer):
    notify = await _morning(hass, freezer, "08:30")
    await _leave_bedroom(hass, freezer)
    await _tick(hass, freezer, minutes=2)
    hass.states.async_set(CHARGER, "Not Charging")
    await hass.async_block_till_done()
    assert _titles(notify) == ["Up for the day?"]


async def test_item2_im_awake_by_hand(hass, freezer, hass_client_no_auth):
    notify = await _morning(hass, freezer, "06:45")
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    assert reply["no_alarm_morning"]["offered"] is True
    reply = await send(hass_client_no_auth, {"type": "awake", "data": {}})
    assert reply["good_morning"] is True and reply["disarmed"] is True
    assert _messages(notify) == ["RUN_DISARM", "RUN_GOOD_MORNING"]
    assert hass.states.get("input_boolean.sleep_in").state == "off"
    assert hass.states.get("input_boolean.awake_for_day").state == "on"
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    assert reply["no_alarm_morning"]["offered"] is False


async def test_item2_settings_from_the_app(hass, freezer, hass_client_no_auth):
    notify = await _morning(hass, freezer, "07:00")
    await send(hass_client_no_auth, {"type": "context", "data": {"awake_settings": {"enabled": True, "earliest": "07:00", "up_minutes": 5, "wait_minutes": 2}}})
    await _leave_bedroom(hass, freezer)
    await _tick(hass, freezer, minutes=6)
    assert _titles(notify) == ["Up for the day?"]
    await _tick(hass, freezer, minutes=3)
    assert _messages(notify)[-1] == "RUN_GOOD_MORNING"



async def test_item2_turned_off(hass, freezer, hass_client_no_auth):
    notify = await _morning(hass, freezer, "06:30")
    await send(hass_client_no_auth, {"type": "context", "data": {"awake_settings": {"enabled": False}}})
    await _leave_bedroom(hass, freezer)
    assert _messages(notify) == []
