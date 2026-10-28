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
