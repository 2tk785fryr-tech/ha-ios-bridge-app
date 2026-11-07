"""v0.4.11 integration tests, by spec item."""

from datetime import timedelta
from unittest.mock import AsyncMock, patch

from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_mock_service

from custom_components.bedtime_bridge import liveactivity as la
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


# MARK: Item 12, home late only on arriving


async def test_item12_a_location_update_while_home_moves_nothing(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    hass.states.async_set("person.me", "home", {"latitude": 1.0})
    await wind_setup(hass, ladder, presence_entities=["person.me"])
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("20:30", day=27))
    hass.states.async_set("person.me", "home", {"latitude": 1.1})
    await hass.async_block_till_done()
    assert _wind(hass) == "8:50"


async def test_item12_arriving_home_late_moves_it_once(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    hass.states.async_set("person.me", "not_home")
    await wind_setup(hass, ladder, presence_entities=["person.me"])
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("20:40", day=27))
    hass.states.async_set("person.me", "home")
    await hass.async_block_till_done()
    assert _wind(hass) == "9:10", "home + 30 min free"
    await at(hass, freezer, local("20:45", day=27))
    hass.states.async_set("person.me", "home", {"latitude": 1.1})
    await hass.async_block_till_done()
    assert _wind(hass) == "9:10", "a later location update doesn't move it again"


async def test_item12_a_press_and_an_arrival_dont_add_up(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    hass.states.async_set("person.me", "not_home")
    await wind_setup(hass, ladder, presence_entities=["person.me"])
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("20:45", day=27))
    await _later(hass)
    assert _wind(hass) == "9:05"
    await at(hass, freezer, local("20:46", day=27))
    hass.states.async_set("person.me", "home")
    await hass.async_block_till_done()
    assert _wind(hass) == "9:16", "home + 30, not 9:05 + 30"


# MARK: Item 16, always a warning before the new start


def _moved(notes):
    return [c for c in notes if c.data.get("title") == "Wind-down moved"]


async def test_item16_a_15_min_warning_pressed_at_20_36_warns_again_at_20_50(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    notes = await wind_setup(hass, ladder)
    planned = days_plan()
    planned["data"]["wind_down_settings"] = {"enabled": True, "warning_minutes": 15}
    await send(hass_client_no_auth, planned)
    await at(hass, freezer, local("20:36", day=27))
    await _later(hass)
    await at(hass, freezer, local("20:50", day=27))
    assert [c.data["message"] for c in _moved(notes)] == ["Wind-down moved to 9:05 · bed 9:50"]
    assert status_of(hass) == "scheduled"
    await at(hass, freezer, local("21:05", day=27))
    assert status_of(hass) == "winding_down"


async def test_item16_a_warning_time_already_past_warns_a_minute_after_the_press(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    notes = await wind_setup(hass, ladder)
    planned = days_plan()
    planned["data"]["wind_down_settings"] = {"enabled": True, "warning_minutes": 20}
    await send(hass_client_no_auth, planned)
    await at(hass, freezer, local("20:49", day=27))
    await _later(hass)  # 9:05 − 20 min = 8:45, already past
    assert not _moved(notes)
    await at(hass, freezer, local("20:50", day=27))
    assert len(_moved(notes)) == 1


async def test_item16_the_last_possible_move_offers_cancel_only(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    notes = await wind_setup(hass, ladder)
    await send(hass_client_no_auth, days_plan())
    await at(hass, freezer, local("20:45", day=27))
    first = [c for c in notes if c.data.get("title") == "Wind-down soon"][0]
    assert [a["action"] for a in first.data["data"]["actions"]] == [LATER, "BEDTIME_BRIDGE_WIND_DOWN_CANCEL"]
    await _later(hass)
    await at(hass, freezer, local("21:00", day=27))
    await _later(hass)
    assert _wind(hass) == "9:20", "up against bed 9:50 − 30 min"
    await at(hass, freezer, local("21:15", day=27))
    last = _moved(notes)[-1]
    assert last.data["message"] == "Wind-down moved to 9:20 · bed 9:50"
    assert [a["action"] for a in last.data["data"]["actions"]] == ["BEDTIME_BRIDGE_WIND_DOWN_CANCEL"]
    await _later(hass)
    assert _wind(hass) == "9:20"


# MARK: Item 20, past leave time and on your way


async def _morning(hass, ladder, hass_client_no_auth, freezer, sent):
    from .test_live_activity import APP, KEY as key

    notes = async_mock_service(hass, "notify", "phone")
    hass.states.async_set("person.me", "home")
    await ladder(notify_service="notify.phone", phone_commands=True, presence_entities=["person.me"],
                 apns_key=key, apns_key_id="KEYID12345")
    await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "start", "token": "start-token"}})
    freezer.move_to(local("04:20"))
    planned = days_plan()
    planned["data"]["leave_by"] = local("05:45").isoformat()
    planned["data"]["leave_reminders"] = [15, 0]
    await send(hass_client_no_auth, planned)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": [], "last": True}})
    await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "morning", "token": "m-token", "activity_id": "M"}})
    return notes


async def test_item20_the_morning_goes_stale_at_leave_by(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    sent = AsyncMock(return_value=200)
    with patch.object(la.ApnsClient, "send", sent):
        await _morning(hass, ladder, hass_client_no_auth, freezer, sent)
        body = sent.call_args.args[1]
        assert body["aps"]["stale-date"] == int(local("05:45").timestamp()), "Past leave time from 5:45 on its own"


async def test_item20_leaving_home_says_on_your_way_until_the_start(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    sent = AsyncMock(return_value=200)
    with patch.object(la.ApnsClient, "send", sent):
        notes = await _morning(hass, ladder, hass_client_no_auth, freezer, sent)
        await at(hass, freezer, local("05:25"))
        hass.states.async_set("person.me", "not_home")
        await hass.async_block_till_done()
        token, body = sent.call_args.args
        state = body["aps"]["content-state"]
        assert token == "m-token" and body["aps"]["event"] == "end"
        assert state["departed"] == la.ref(local("05:25")) and state["eventStart"] == la.ref(local("06:30"))
        assert body["aps"]["dismissal-date"] == int(local("06:30").timestamp()), "stays until Days starts"
        await at(hass, freezer, local("05:31"))
        await at(hass, freezer, local("05:45"))
        assert "RUN_LEAVE_CHECK" not in messages(notes), "leave reminders withdrawn"


async def test_item20_a_location_update_while_home_does_nothing(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    sent = AsyncMock(return_value=200)
    with patch.object(la.ApnsClient, "send", sent):
        await _morning(hass, ladder, hass_client_no_auth, freezer, sent)
        await at(hass, freezer, local("05:25"))
        calls = sent.call_count
        hass.states.async_set("person.me", "home", {"latitude": 1.1})
        await hass.async_block_till_done()
        assert sent.call_count == calls


async def test_item20_back_home_before_the_start(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    sent = AsyncMock(return_value=200)
    with patch.object(la.ApnsClient, "send", sent):
        await _morning(hass, ladder, hass_client_no_auth, freezer, sent)
        await at(hass, freezer, local("05:25"))
        hass.states.async_set("person.me", "not_home")
        await hass.async_block_till_done()
        await at(hass, freezer, local("05:35"))
        hass.states.async_set("person.me", "home")
        await hass.async_block_till_done()
        body = sent.call_args.args[1]
        assert body["aps"]["event"] in ("start", "update")
        assert "departed" not in body["aps"]["content-state"], "Leave in again"


# MARK: Item 26, a red fired tag on backstops that went off


async def test_item26_a_fired_backstop_is_in_the_morning_context_until_the_next_plan(hass, ladder, hass_client_no_auth, freezer):  # noqa: F811
    await ladder()
    await send(hass_client_no_auth, days_plan())
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    assert reply["backstops_fired"] == []
    await at(hass, freezer, local("05:10"))
    hass.bus.async_fire("bedtime_bridge_backstop_fired", {"rung": "deadline", "level": "soft"})
    await hass.async_block_till_done()
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    assert [(f["rung"], f["level"]) for f in reply["backstops_fired"]] == [("deadline", "soft")]
    assert reply["weekly_summaries"][0]["backstops_fired"] == 1
    # An unknown rung is ignored.
    hass.bus.async_fire("bedtime_bridge_backstop_fired", {"rung": "nonsense"})
    await hass.async_block_till_done()
    assert len((await send(hass_client_no_auth, {"type": "context", "data": {}}))["backstops_fired"]) == 1
    # The next plan clears it; the weekly count stays.
    await send(hass_client_no_auth, days_plan())
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    assert reply["backstops_fired"] == []
    assert reply["weekly_summaries"][0]["backstops_fired"] == 1


def test_item26_rung_times_passing_no_longer_count():
    from custom_components.bedtime_bridge import weekly
    now = dt_util.utcnow()
    history = []
    weekly.record(history, "morning", now - timedelta(days=1), snoozes=1, backstops_fired=3)
    assert weekly.summarize(history, [], now)["backstops_fired"] == 0
