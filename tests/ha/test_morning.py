"""v0.4: the snooze count per morning (item 5) and ending every alarm at once (item 2)."""

from pytest_homeassistant_custom_component.common import async_capture_events

from .test_webhook import PLAN, send, setup

SNOOZE = {"type": "snoozed", "data": {"rings_again": "2026-10-26T09:25:00+00:00"}}


def state(hass, key):
    return hass.states.get(f"sensor.bedtime_bridge_{key}").state


async def test_snooze_count_resets_when_the_last_alarm_is_stopped(hass, hass_client_no_auth):
    await setup(hass)
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, SNOOZE)
    await send(hass_client_no_auth, SNOOZE)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": ["2026-10-26T09:26:00+00:00"]}})
    await hass.async_block_till_done()
    assert state(hass, "snooze_count") == "2", "one alarm still to ring: the morning isn't over"
    assert state(hass, "snoozes_last_morning") == "unknown"

    await send(hass_client_no_auth, SNOOZE)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()
    assert state(hass, "snooze_count") == "0"
    assert state(hass, "snoozes_last_morning") == "3"

    # Tonight's plan starts a new morning without touching last morning's total.
    await send(hass_client_no_auth, PLAN)
    await hass.async_block_till_done()
    assert state(hass, "snoozes_last_morning") == "3"


async def test_stop_all_ends_the_morning_once(hass, hass_client_no_auth):
    await setup(hass)
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, SNOOZE)
    # The phone may still list alarms it hasn't cancelled yet; all: true ends them regardless.
    await send(hass_client_no_auth, {"type": "stopped", "data": {"all": True, "alarm_times": ["2026-10-26T09:26:00+00:00"]}})
    await hass.async_block_till_done()
    stops = [e for e in events if e.data["type"] == "stopped"]
    assert len(stops) == 1 and stops[0].data["all"] is True
    assert hass.states.get("input_boolean.wake_mike").state == "on"
    assert state(hass, "next_alarm") == "unknown"
    assert state(hass, "snooze_count") == "0"
    assert state(hass, "snoozes_last_morning") == "1"


async def test_wake_routine_runs_once_per_wake_up(hass, hass_client_no_auth):
    """Item 9: Wake Sequence treats wake_mike as a button, so later stops mustn't re-run it."""
    from pytest_homeassistant_custom_component.common import async_mock_service

    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test", phone_commands=True)
    turned_on = []
    hass.bus.async_listen("call_service", lambda e: turned_on.append(e.data["service_data"].get("entity_id"))
                          if e.data["service"] == "turn_on" else None)
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": ["2026-10-26T09:26:00+00:00"]}})
    await send(hass_client_no_auth, {"type": "command_ran", "data": {"command": "RUN_GOOD_MORNING", "outcome": "completed"}})
    await send(hass_client_no_auth, SNOOZE)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()

    assert turned_on.count("input_boolean.wake_mike") == 1
    assert "input_boolean.wake_fade" not in turned_on, "already up: no fade on a later snooze"
    assert [c.data["message"] for c in notify] == ["RUN_GOOD_MORNING", "clear_notification"]
    stops = [e.data for e in events if e.data["type"] == "stopped"]
    assert [s["routine"] for s in stops] == [True, False]

    # A new plan is a new wake-up.
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()
    assert turned_on.count("input_boolean.wake_mike") == 2


async def test_snooze_doesnt_restart_a_running_fade(hass, hass_client_no_auth):
    await setup(hass)
    turned_on = []
    hass.bus.async_listen("call_service", lambda e: turned_on.append(e.data["service_data"].get("entity_id"))
                          if e.data["service"] == "turn_on" else None)
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, SNOOZE)
    await hass.async_block_till_done()
    await send(hass_client_no_auth, SNOOZE)
    await hass.async_block_till_done()
    assert turned_on.count("input_boolean.wake_fade") == 1
    assert state(hass, "snooze_count") == "2"


async def test_ending_early_runs_the_early_helper(hass, hass_client_no_auth):
    """Item 8: ended from Tonight before any alarm rang."""
    # Any helper stands in for a gentler wake sequence's; the test setup has bedtime_routine.
    await setup(hass, early_wake_helper="input_boolean.bedtime_routine")
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"all": True, "early": True, "alarm_times": []}})
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.bedtime_routine").state == "on"
    assert hass.states.get("input_boolean.wake_mike").state == "off"
    assert events[-1].data["early"] is True and events[-1].data["all"] is True


async def test_ending_early_without_an_early_helper_uses_the_stop_helper(hass, hass_client_no_auth):
    await setup(hass)
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"all": True, "early": True, "alarm_times": []}})
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.wake_mike").state == "on"


async def test_the_morning_total_counts_across_a_change(hass, hass_client_no_auth):
    """v0.4.1 item 5 (28 Oct): 4 snoozes, a change, 1 more snooze, stop → 5, not 1."""
    await setup(hass)
    await send(hass_client_no_auth, PLAN)
    for _ in range(4):
        await send(hass_client_no_auth, SNOOZE)
    await send(hass_client_no_auth, {"type": "morning_changed", "data": {
        "alarm_times": ["2026-10-26T09:40:00+00:00", "2026-10-26T09:45:00+00:00"], "delay_minutes": 30, "phase": "snoozing",
    }})
    await send(hass_client_no_auth, SNOOZE)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()
    assert state(hass, "snoozes_last_morning") == "5"
    assert state(hass, "snooze_count") == "0"


async def test_the_next_plan_closes_an_unfinished_morning(hass, hass_client_no_auth):
    await setup(hass)
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, SNOOZE)
    await send(hass_client_no_auth, SNOOZE)
    await send(hass_client_no_auth, PLAN)
    await hass.async_block_till_done()
    assert state(hass, "snoozes_last_morning") == "2"
    assert state(hass, "snooze_count") == "0"
