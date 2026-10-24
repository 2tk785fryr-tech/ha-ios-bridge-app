"""Webhook messages from the app: state, entities, helpers and events."""

from datetime import timedelta

import pytest
from homeassistant.core import HomeAssistant
from homeassistant.setup import async_setup_component
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_fire_time_changed

from custom_components.bedtime_bridge.const import CONF_WAKE_ACTION, WAKE_EVENTS, WAKE_HELPERS

from .conftest import WEBHOOK_ID, make_entry


async def setup(hass: HomeAssistant, **options):
    assert await async_setup_component(hass, "homeassistant", {})
    assert await async_setup_component(
        hass, "input_boolean", {"input_boolean": {"wake_fade": {}, "wake_mike": {}}}
    )
    entry = make_entry(**options)
    entry.add_to_hass(hass)
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()
    return entry


async def send(hass_client_no_auth, message):
    client = await hass_client_no_auth()
    response = await client.post(f"/api/webhook/{WEBHOOK_ID}", json=message)
    assert response.status == 200
    return await response.json()


PLAN = {
    "type": "planned",
    "data": {
        "alarm_cause": "calendar",
        "alarm_time": "2026-10-26T09:16:00+00:00",
        "wake_time": "2026-10-26T09:26:00+00:00",
        "alarm_times": ["2026-10-26T09:16:00+00:00", "2026-10-26T09:26:00+00:00"],
        "label": "Dentist",
        "reason": "Dentist at 7:00 AM. Leave by 6:26 AM",
        "leave_by": "2026-10-26T10:26:00+00:00",
        "drive_minutes": 24,
        "weather_extra_minutes": 15,
        "warnings": ["test warning"],
        "alarm_style": "app",
        "app_settings": {"get_ready_minutes": 60, "snooze_minutes": 9, "shift_lead_minutes": {"Days": 75}},
    },
}


async def test_plan_updates_entities_and_seeds_settings(hass, hass_client_no_auth):
    await setup(hass)
    events = async_capture_events(hass, "bedtime_bridge")

    reply = await send(hass_client_no_auth, PLAN)
    await hass.async_block_till_done()

    assert hass.states.get("sensor.bedtime_bridge_next_alarm").state == "2026-10-26T09:16:00+00:00"
    assert hass.states.get("sensor.bedtime_bridge_wake_up_time").state == "2026-10-26T09:26:00+00:00"
    assert hass.states.get("sensor.bedtime_bridge_alarm_cause").state == "calendar"
    assert hass.states.get("sensor.bedtime_bridge_drive_time").state == "24"
    assert hass.states.get("sensor.bedtime_bridge_leave_by").state == "2026-10-26T10:26:00+00:00"
    assert hass.states.get("sensor.bedtime_bridge_reason").attributes["warnings"] == ["test warning"]
    assert hass.states.get("number.bedtime_bridge_get_ready_time").state == "60"
    assert hass.states.get("number.bedtime_bridge_days_lead_time").state == "75"
    assert hass.states.get("number.bedtime_bridge_swings_lead_time").state == "unknown"
    assert reply["settings"] == {"get_ready_minutes": 60, "snooze_minutes": 9, "shift_lead_minutes": {"Days": 75}}
    assert events[-1].data["type"] == "planned"
    assert events[-1].data["alarm_cause"] == "calendar"


async def test_ha_setting_wins_after_first_plan(hass, hass_client_no_auth):
    await setup(hass)
    await send(hass_client_no_auth, PLAN)
    await hass.services.async_call(
        "number", "set_value", {"entity_id": "number.bedtime_bridge_get_ready_time", "value": 45}, blocking=True
    )
    reply = await send(hass_client_no_auth, PLAN)
    assert reply["settings"]["get_ready_minutes"] == 45


async def test_snooze_and_stop_turn_on_helpers_and_fire_events(hass, hass_client_no_auth):
    await setup(hass)
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, PLAN)

    rings_again = (dt_util.utcnow() + timedelta(minutes=9)).isoformat()
    await send(hass_client_no_auth, {"type": "snoozed", "data": {"rings_again": rings_again}})
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.wake_fade").state == "on"
    assert hass.states.get("binary_sensor.bedtime_bridge_snoozing").state == "on"
    assert hass.states.get("sensor.bedtime_bridge_snooze_count").state == "1"

    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.wake_mike").state == "on"
    assert hass.states.get("binary_sensor.bedtime_bridge_snoozing").state == "off"
    assert hass.states.get("sensor.bedtime_bridge_alarm_cause").state == "noalarm"
    assert [e.data["type"] for e in events] == ["planned", "snoozed", "stopped"]


async def test_snoozing_turns_off_when_snooze_runs_out(hass, hass_client_no_auth, freezer):
    await setup(hass)
    rings_again = dt_util.utcnow() + timedelta(minutes=9)
    await send(hass_client_no_auth, {"type": "snoozed", "data": {"rings_again": rings_again.isoformat()}})
    await hass.async_block_till_done()
    assert hass.states.get("binary_sensor.bedtime_bridge_snoozing").state == "on"

    freezer.move_to(rings_again + timedelta(seconds=1))
    async_fire_time_changed(hass, rings_again + timedelta(seconds=1))
    await hass.async_block_till_done()
    assert hass.states.get("binary_sensor.bedtime_bridge_snoozing").state == "off"


async def test_events_only_leaves_helpers_alone(hass, hass_client_no_auth):
    await setup(hass, **{CONF_WAKE_ACTION: WAKE_EVENTS})
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, {"type": "snoozed", "data": {}})
    await send(hass_client_no_auth, {"type": "stopped", "data": {}})
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.wake_fade").state == "off"
    assert hass.states.get("input_boolean.wake_mike").state == "off"
    assert [e.data["type"] for e in events] == ["snoozed", "stopped"]


async def test_helpers_only_skips_wake_events(hass, hass_client_no_auth):
    await setup(hass, **{CONF_WAKE_ACTION: WAKE_HELPERS})
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "stopped", "data": {}})
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.wake_mike").state == "on"
    assert [e.data["type"] for e in events] == ["planned"]


async def test_context_reads_override_and_shift_sensor(hass, hass_client_no_auth):
    await setup(hass)
    hass.states.async_set("input_select.select_shift_override", "Off")
    hass.states.async_set("sensor.current_shift", "Day off", {"next_shift_start": "2026-10-26T06:30:00-04:00"})
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    assert reply["shift_override"] == "Off"
    assert reply["next_shift_start"] == "2026-10-26T06:30:00-04:00"


async def test_cancel_clears_plan(hass, hass_client_no_auth):
    await setup(hass)
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "cancelled"})
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_next_alarm").state == "unknown"
    assert hass.states.get("sensor.bedtime_bridge_alarm_cause").state == "noalarm"


async def test_missing_helper_still_fires_event(hass, hass_client_no_auth):
    await setup(hass, stop_helper="input_boolean.deleted_helper")
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, {"type": "stopped", "data": {}})
    await hass.async_block_till_done()
    assert [e.data["type"] for e in events] == ["stopped"]


async def test_unknown_message_and_bad_body(hass, hass_client_no_auth):
    await setup(hass)
    reply = await send(hass_client_no_auth, {"type": "nonsense"})
    assert "error" in reply
    client = await hass_client_no_auth()
    response = await client.post(f"/api/webhook/{WEBHOOK_ID}", data="not json")
    assert response.status == 400


async def test_state_survives_restart(hass, hass_client_no_auth):
    entry = await setup(hass)
    await send(hass_client_no_auth, PLAN)
    await hass.async_block_till_done()
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=5))  # flush delayed save
    await hass.async_block_till_done()

    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_alarm_cause").state == "calendar"
    assert hass.states.get("number.bedtime_bridge_get_ready_time").state == "60"


async def test_forecast_uses_configured_weather_entity(hass, hass_client_no_auth):
    assert await async_setup_component(hass, "weather", {"weather": {"platform": "template", "name": "Forecast Home",
        "condition_template": "rainy", "temperature_template": "{{ 31 }}", "humidity_template": "{{ 90 }}",
        "forecast_hourly_template": "{{ [{'datetime': '2026-10-26T10:00:00+00:00', 'condition': 'rainy', 'temperature': 31}] }}"}})
    await hass.async_block_till_done()
    await setup(hass, weather_entity="weather.forecast_home")

    reply = await send(hass_client_no_auth, {"type": "forecast", "data": {}})
    assert reply["forecast"] == [{"datetime": "2026-10-26T10:00:00+00:00", "condition": "rainy", "temperature": 31.0}]
    assert reply["temperature_unit"]
