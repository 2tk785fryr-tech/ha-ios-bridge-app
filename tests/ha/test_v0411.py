"""v0.4.11 integration tests, by spec item."""

from pytest_homeassistant_custom_component.common import async_mock_service

from .test_ladder import calendar_days, ladder, local, plan  # noqa: F401
from .test_v043 import at, days_plan, messages
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
