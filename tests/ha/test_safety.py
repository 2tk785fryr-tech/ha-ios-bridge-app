"""Safety net times, last plan / failures, test alarms, out-of-date plans, missing-plan blueprint."""

import shutil
from datetime import timedelta
from pathlib import Path

from homeassistant.core import HomeAssistant
from homeassistant.setup import async_setup_component
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import (
    async_capture_events,
    async_fire_time_changed,
    async_mock_service,
)

from .test_webhook import PLAN, send, setup

REPO = Path(__file__).resolve().parents[2]


def plan_with(cause: str, wake: str) -> dict:
    data = {**PLAN["data"], "alarm_cause": cause, "wake_time": wake}
    return {"type": "planned", "data": data}


async def test_safety_net_times_for_calendar_mornings(hass, hass_client_no_auth):
    await setup(hass)
    await send(hass_client_no_auth, plan_with("calendar", "2026-10-26T09:26:00+00:00"))
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_safety_net_early").state == "2026-10-26T09:11:00+00:00"
    deadline = hass.states.get("sensor.bedtime_bridge_safety_net_deadline")
    assert deadline.state == "2026-10-26T09:26:00+00:00"
    assert deadline.attributes["effective_shift"] == "Days"
    assert hass.states.get("sensor.bedtime_bridge_safety_net_late").state == "2026-10-26T09:41:00+00:00"


async def test_no_safety_net_for_shift_mornings_by_default(hass, hass_client_no_auth):
    await setup(hass)
    await send(hass_client_no_auth, plan_with("Days", "2026-10-26T09:26:00+00:00"))
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_safety_net_deadline").state == "unknown"


async def test_no_safety_net_when_away(hass, hass_client_no_auth):
    hass.states.async_set("person.me", "not_home")
    await setup(hass, presence_entities=["person.me"])
    await send(hass_client_no_auth, plan_with("calendar", "2026-10-26T09:26:00+00:00"))
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_safety_net_deadline").state == "unknown"


async def test_last_plan_and_failure(hass, hass_client_no_auth):
    await setup(hass)
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, PLAN)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_last_plan").state not in ("unknown", "unavailable")

    await send(hass_client_no_auth, {"type": "plan_failed", "data": {"error": "Calendar access is off"}})
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_last_plan").attributes["error"] == "Calendar access is off"
    assert events[-1].data["type"] == "plan_failed"

    await send(hass_client_no_auth, PLAN)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_last_plan").attributes["error"] is None


async def test_test_alarm_runs_routines_but_keeps_plan(hass, hass_client_no_auth):
    await setup(hass)
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "snoozed", "data": {"test": True, "rings_again": "2026-10-25T20:00:00+00:00"}})
    await send(hass_client_no_auth, {"type": "stopped", "data": {"test": True, "alarm_times": []}})
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.wake_fade").state == "on"
    assert hass.states.get("input_boolean.wake_mike").state == "on"
    assert hass.states.get("sensor.bedtime_bridge_alarm_cause").state == "calendar"
    assert hass.states.get("sensor.bedtime_bridge_snooze_count").state == "0"
    assert [e.data.get("test") for e in events[1:]] == [True, True]


async def outdated_setup(hass, hass_client_no_auth, wake_in=timedelta(hours=6)):
    hass.states.async_set("input_select.select_shift_override", "Auto")
    hass.states.async_set("sensor.current_shift", "Day off", {"next_shift_start": "2026-10-26T06:30:00-04:00"})
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test")
    wake = (dt_util.utcnow() + wake_in).isoformat()
    await send(hass_client_no_auth, plan_with("Days", wake))
    await hass.async_block_till_done()
    return notify


async def test_override_change_after_plan_marks_outdated_and_notifies(hass, hass_client_no_auth):
    notify = await outdated_setup(hass, hass_client_no_auth)
    events = async_capture_events(hass, "bedtime_bridge")
    hass.states.async_set("input_select.select_shift_override", "Off")
    await hass.async_block_till_done()

    outdated = hass.states.get("binary_sensor.bedtime_bridge_plan_out_of_date")
    assert outdated.state == "on"
    assert "Off" in outdated.attributes["reason"]
    assert events[-1].data["type"] == "plan_outdated"
    assert len(notify) == 1
    assert notify[0].data["data"]["actions"][0]["uri"] == "bedtimebridge://replan"

    # One notification per plan, and a new plan clears it.
    hass.states.async_set("input_select.select_shift_override", "Days")
    await hass.async_block_till_done()
    assert len(notify) == 1
    await send(hass_client_no_auth, plan_with("Days", (dt_util.utcnow() + timedelta(hours=6)).isoformat()))
    await hass.async_block_till_done()
    assert hass.states.get("binary_sensor.bedtime_bridge_plan_out_of_date").state == "off"


async def test_shift_move_marks_outdated_but_same_value_refresh_does_not(hass, hass_client_no_auth):
    notify = await outdated_setup(hass, hass_client_no_auth)
    # The calendar sensor refreshes every 30 min with the same start: no alert.
    hass.states.async_set("sensor.current_shift", "Day off", {"next_shift_start": "2026-10-26T06:30:00-04:00", "last_success": "x"})
    await hass.async_block_till_done()
    assert hass.states.get("binary_sensor.bedtime_bridge_plan_out_of_date").state == "off"

    hass.states.async_set("sensor.current_shift", "Day off", {"next_shift_start": "2026-10-26T14:30:00-04:00"})
    await hass.async_block_till_done()
    assert hass.states.get("binary_sensor.bedtime_bridge_plan_out_of_date").state == "on"
    assert len(notify) == 1


async def test_changes_after_wake_time_are_ignored(hass, hass_client_no_auth):
    notify = await outdated_setup(hass, hass_client_no_auth, wake_in=timedelta(hours=-1))
    hass.states.async_set("input_select.select_shift_override", "Off")
    await hass.async_block_till_done()
    assert hass.states.get("binary_sensor.bedtime_bridge_plan_out_of_date").state == "off"
    assert notify == []


async def test_missing_plan_blueprint(hass: HomeAssistant, freezer):
    # Home from Swings, in bed at 01:40 New York time.
    freezer.move_to(dt_util.parse_datetime("2026-10-26T05:40:00+00:00"))
    await hass.config.async_set_time_zone("America/New_York")
    target = Path(hass.config.path("blueprints/automation/bedtime_bridge"))
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy(REPO / "blueprints/automation/bedtime_bridge/bedtime_bridge_missing_plan.yaml", target)
    notify = async_mock_service(hass, "notify", "mobile_app_test")

    hass.states.async_set("binary_sensor.bed", "off")
    hass.states.async_set("sensor.current_shift", "Day off", {"next_shift_start": "2026-10-26T14:30:00-04:00"})
    # Last plan was yesterday: stale.
    hass.states.async_set("sensor.bedtime_bridge_last_plan", "2026-10-25T04:00:00+00:00", {"device_class": "timestamp", "error": None})

    assert await async_setup_component(
        hass,
        "automation",
        {
            "automation": {
                "alias": "Missing plan",
                "use_blueprint": {
                    "path": "bedtime_bridge/bedtime_bridge_missing_plan.yaml",
                    "input": {
                        "bed_sensor": "binary_sensor.bed",
                        "last_plan_sensor": "sensor.bedtime_bridge_last_plan",
                        "shift_sensor": "sensor.current_shift",
                        "notify_action": "notify.mobile_app_test",
                    },
                },
            }
        },
    )
    await hass.async_block_till_done()

    hass.states.async_set("binary_sensor.bed", "on")
    await hass.async_block_till_done()
    later = dt_util.parse_datetime("2026-10-26T06:00:01+00:00")  # 20 min in bed, 02:00 local
    freezer.move_to(later)
    async_fire_time_changed(hass, later)
    await hass.async_block_till_done()
    assert len(notify) == 1
    assert "2:30 PM" in notify[0].data["message"]

    # A fresh plan tonight: no warning.
    notify.clear()
    hass.states.async_set("sensor.bedtime_bridge_last_plan", "2026-10-26T05:45:00+00:00", {"device_class": "timestamp", "error": None})
    await hass.services.async_call("automation", "trigger", {"entity_id": "automation.missing_plan", "skip_condition": False}, blocking=True)
    await hass.async_block_till_done()
    assert notify == []


async def test_missing_plan_blueprint_ignores_afternoon_naps(hass: HomeAssistant, freezer):
    freezer.move_to(dt_util.parse_datetime("2026-10-25T18:00:00+00:00"))  # 14:00 local
    await hass.config.async_set_time_zone("America/New_York")
    target = Path(hass.config.path("blueprints/automation/bedtime_bridge"))
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy(REPO / "blueprints/automation/bedtime_bridge/bedtime_bridge_missing_plan.yaml", target)
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    hass.states.async_set("sensor.current_shift", "Day off", {"next_shift_start": "2026-10-26T06:30:00-04:00"})
    hass.states.async_set("sensor.bedtime_bridge_last_plan", "2026-10-24T04:00:00+00:00", {"device_class": "timestamp"})
    assert await async_setup_component(hass, "automation", {"automation": {"alias": "Missing plan", "use_blueprint": {
        "path": "bedtime_bridge/bedtime_bridge_missing_plan.yaml",
        "input": {"bed_sensor": "binary_sensor.bed", "last_plan_sensor": "sensor.bedtime_bridge_last_plan",
                  "shift_sensor": "sensor.current_shift", "notify_action": "notify.mobile_app_test"}}}})
    await hass.async_block_till_done()
    await hass.services.async_call("automation", "trigger", {"entity_id": "automation.missing_plan", "skip_condition": False}, blocking=True)
    await hass.async_block_till_done()
    assert notify == []
