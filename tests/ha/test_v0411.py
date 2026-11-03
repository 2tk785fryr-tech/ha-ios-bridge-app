"""v0.4.11 integration tests, by spec item."""

from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_mock_service

from custom_components.bedtime_bridge import winddown

from .test_ladder import calendar_days, ladder, local, plan, rungs, status  # noqa: F401
from .test_v043 import at, days_plan, messages, status_of, wind_setup
from .test_webhook import send


# MARK: Item 5, remote work days


async def test_item5_a_remote_day_gets_no_leave_check(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await ladder(notify_service="notify.mobile_app_test", phone_commands=True)
    data = plan(local("05:45").isoformat(), remote=True)
    data["data"]["leave_by"] = local("05:45").isoformat()
    data["data"]["leave_reminders"] = [15, 0]
    data["data"]["remote"] = True
    await send(hass_client_no_auth, data)
    await at(hass, freezer, local("05:31"))
    await at(hass, freezer, local("05:46"))
    assert "RUN_LEAVE_CHECK" not in messages(notify)


async def test_item5_an_office_day_still_gets_its_leave_check(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await ladder(notify_service="notify.mobile_app_test", phone_commands=True)
    data = plan(local("05:45").isoformat())
    data["data"]["leave_by"] = local("05:45").isoformat()
    data["data"]["leave_reminders"] = [15, 0]
    await send(hass_client_no_auth, data)
    # The remote flag doesn't stick from an earlier plan.
    await at(hass, freezer, local("05:31"))
    assert "RUN_LEAVE_CHECK" in messages(notify)


# MARK: Item 6, one morning Live Activity, after the last alarm


async def test_item6_ending_one_alarm_with_another_snoozing_leaves_it(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone", phone_commands=True)
    freezer.move_to(local("04:30"))
    planned = days_plan()
    planned["data"]["leave_by"] = local("05:43").isoformat()
    await send(hass_client_no_auth, planned)
    snoozed = local("04:34").isoformat()
    await send(hass_client_no_auth, {"type": "stopped", "data": {
        "alarm_times": [snoozed], "alarm_time": snoozed, "snoozed_until": snoozed, "last": False, "alarm_cause": "Days"}})
    state = hass.states.get("sensor.bedtime_bridge_alarm_cause").state
    assert state != "noalarm", "the snoozed 4:25 is still set"
    assert hass.states.get("sensor.bedtime_bridge_snooze_count") is not None
    # Not the last: no morning updates yet.
    await at(hass, freezer, local("05:31"))
    assert messages(notes).count("RUN_MORNING_UPDATE") == 0


async def test_item6_the_last_stop_starts_the_morning_updates(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone", phone_commands=True)
    freezer.move_to(local("04:44"))
    planned = days_plan()
    planned["data"]["leave_by"] = local("06:45").isoformat()
    await send(hass_client_no_auth, planned)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": [], "last": True}})
    await at(hass, freezer, local("05:45"))
    assert messages(notes).count("RUN_MORNING_UPDATE") == 1


async def test_item6_tomorrows_alarms_dont_hold_back_the_last_stop(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone", phone_commands=True)
    freezer.move_to(local("04:44"))
    planned = days_plan()
    planned["data"]["leave_by"] = local("06:45").isoformat()
    await send(hass_client_no_auth, planned)
    tomorrow = local("04:20", day=29).isoformat()
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": [tomorrow], "last": True}})
    await at(hass, freezer, local("05:45"))
    assert messages(notes).count("RUN_MORNING_UPDATE") == 1


# MARK: Item 9, "15 min later" once per warning

LATER = "BEDTIME_BRIDGE_WIND_DOWN_LATER"


def _wind(hass) -> str:
    return winddown.short(dt_util.parse_datetime(hass.states.get("sensor.bedtime_bridge_wind_down").state))


async def _later(hass):
    hass.bus.async_fire("mobile_app_notification_action", {"action": LATER})
    await hass.async_block_till_done()


async def test_item9_a_second_later_for_the_same_warning_does_nothing(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("20:45", day=27))  # warned: wind-down 8:50
    await _later(hass)
    assert _wind(hass) == "9:05"
    await _later(hass)  # a second tap, or the phone replaying it
    assert _wind(hass) == "9:05"


async def test_item9_no_warning_again_right_after_the_press(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    # A 15-min warning (20:35 for 20:50), pressed at 20:36: the next would be 20:50, 14 min on.
    notes = await wind_setup(hass, ladder)
    planned = days_plan()
    planned["data"]["wind_down_settings"] = {"enabled": True, "warning_minutes": 15}
    await send(hass_client_no_auth, planned)
    await at(hass, freezer, local("20:36", day=27))
    await _later(hass)
    await at(hass, freezer, local("20:51", day=27))
    assert not [c for c in notes if c.data.get("title") == "Wind-down moved"]
    assert sum(1 for c in notes if c.data.get("title") == "Wind-down soon") == 1
    await at(hass, freezer, local("21:05", day=27))
    assert status_of(hass) == "winding_down", "it starts at the new time"


async def test_item9_the_next_warning_says_it_moved(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("20:00", day=27))
    await send(hass_client_no_auth, {"type": "wind_down", "data": {"action": "later"}})
    await at(hass, freezer, local("21:00", day=27))  # 5 min before 9:05
    moved = [c for c in notes if c.data.get("title") == "Wind-down moved"]
    assert moved and moved[0].data["message"] == "Wind-down moved to 9:05 · bed 9:50"
    assert status_of(hass) == "scheduled", "not started at the old time"


async def test_item9_on_2_nov_the_moved_warning_comes_at_9(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    # Warned 20:45 for 20:50 (5 min), pressed at once: wind-down 21:05, told again at 21:00.
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("20:45", day=27))
    await _later(hass)
    await at(hass, freezer, local("20:50", day=27))
    assert status_of(hass) == "scheduled"
    await at(hass, freezer, local("21:00", day=27))
    assert [c.data["message"] for c in notes if c.data.get("title") == "Wind-down moved"] == ["Wind-down moved to 9:05 · bed 9:50"]


# MARK: Item 10, remote days' backstops


async def test_item10_the_ladder_uses_the_remote_plans_times(hass, ladder, hass_client_no_auth):  # noqa: F811
    await ladder()
    data = plan(None, remote=True, remote_times={
        "early": local("06:07").isoformat(), "deadline": local("06:15").isoformat(), "late": local("06:22").isoformat()})
    await send(hass_client_no_auth, data)
    await hass.async_block_till_done()
    assert rungs(hass) == ["06:07", "06:15", "06:22"], "not the calendar's 4:55, 5:10, 5:25"
    assert status(hass) == "armed"


async def test_item10_no_gap_no_backstops(hass, ladder, hass_client_no_auth):  # noqa: F811
    await ladder()
    await send(hass_client_no_auth, plan(None, remote=True, remote_times={}))
    await hass.async_block_till_done()
    assert status(hass) == "idle_remote"
