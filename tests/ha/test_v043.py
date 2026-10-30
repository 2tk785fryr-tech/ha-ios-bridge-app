"""v0.4.3 integration tests, by spec item."""

from homeassistant.setup import async_setup_component
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
