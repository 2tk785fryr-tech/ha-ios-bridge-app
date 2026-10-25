"""Temporary alarms, phone commands, skipped mornings, Sleep In and the exit-latch timing."""

from datetime import timedelta

from homeassistant.setup import async_setup_component
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import (
    async_capture_events,
    async_fire_time_changed,
    async_mock_service,
)

from .test_webhook import PLAN, send, setup

COMMANDS = {"notify_service": "notify.mobile_app_test", "phone_commands": True}
BED = "binary_sensor.bed"


def messages(calls) -> list[str]:
    return [call.data["message"] for call in calls]


async def test_temporary_stop_leaves_the_house_alone(hass, hass_client_no_auth):
    await setup(hass)
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "temporary_snoozed", "data": {"rings_again": "2026-10-26T07:09:00+00:00"}})
    await send(hass_client_no_auth, {"type": "temporary_stopped", "data": {"house_alarm": "keep_armed", "alarm_times": []}})
    await hass.async_block_till_done()
    # No wake ramp, no wake sequence (which would turn on Awake For Day and clear Sleep In).
    assert hass.states.get("input_boolean.wake_fade").state == "off"
    assert hass.states.get("input_boolean.wake_mike").state == "off"
    # Tonight's plan is untouched.
    assert hass.states.get("sensor.bedtime_bridge_next_alarm").state == "2026-10-26T09:16:00+00:00"
    assert hass.states.get("sensor.bedtime_bridge_snooze_count").state == "0"
    assert [e.data["type"] for e in events][-2:] == ["temporary_snoozed", "temporary_stopped"]


async def test_disarm_then_rearm_once_back_in_bed(hass, hass_client_no_auth, freezer):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    hass.states.async_set(BED, "off")
    await setup(hass, bed_sensor=BED, rearm_minutes=5, **COMMANDS)
    regular = (dt_util.utcnow() + timedelta(hours=3)).isoformat()
    await send(hass_client_no_auth, {"type": "temporary_stopped", "data": {"house_alarm": "disarm", "alarm_times": [regular]}})
    await hass.async_block_till_done()
    assert messages(notify) == ["RUN_DISARM"]

    # Out taking the trash out, then back into bed.
    freezer.tick(timedelta(minutes=10))
    hass.states.async_set(BED, "on")
    await hass.async_block_till_done()
    freezer.tick(timedelta(minutes=4))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert messages(notify) == ["RUN_DISARM"], "not in bed long enough yet"

    freezer.tick(timedelta(minutes=2))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert messages(notify) == ["RUN_DISARM", "RUN_ARM_STAY"]


async def test_no_rearm_after_the_regular_alarms(hass, hass_client_no_auth, freezer):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    hass.states.async_set(BED, "off")
    await setup(hass, bed_sensor=BED, rearm_minutes=5, **COMMANDS)
    regular = (dt_util.utcnow() + timedelta(minutes=30)).isoformat()
    await send(hass_client_no_auth, {"type": "temporary_stopped", "data": {"house_alarm": "disarm", "alarm_times": [regular]}})
    freezer.tick(timedelta(minutes=31))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    hass.states.async_set(BED, "on")
    freezer.tick(timedelta(minutes=10))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert messages(notify) == ["RUN_DISARM"]


async def test_phone_commands_are_off_unless_turned_on(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test")
    await send(hass_client_no_auth, {"type": "temporary_stopped", "data": {"house_alarm": "disarm", "alarm_times": []}})
    await hass.async_block_till_done()
    assert notify == []


async def test_keep_armed_sends_nothing(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, **COMMANDS)
    await send(hass_client_no_auth, {"type": "temporary_stopped", "data": {"house_alarm": "keep_armed", "alarm_times": []}})
    await hass.async_block_till_done()
    assert notify == []


async def test_regular_stop_sends_good_morning(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, **COMMANDS)
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()
    assert messages(notify) == ["RUN_GOOD_MORNING"]


async def test_skipped_shift_turns_failsafe_off_until_it_has_passed(hass, hass_client_no_auth, freezer):
    assert await async_setup_component(
        hass, "input_select", {"input_select": {"select_shift_override": {"options": ["Auto", "Off", "Days", "Swings"]}}}
    )
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test")
    await send(hass_client_no_auth, PLAN)
    shift_start = dt_util.utcnow() + timedelta(hours=10)
    await send(hass_client_no_auth, {
        "type": "skipped",
        "data": {"morning": shift_start.isoformat(), "shift": "Days", "shift_start": shift_start.isoformat(), "sleep_in": True},
    })
    await hass.async_block_till_done()
    assert hass.states.get("input_select.select_shift_override").state == "Off"
    assert hass.states.get("sensor.bedtime_bridge_next_alarm").state == "unknown"
    # Our own change is not an out-of-date plan.
    assert hass.states.get("binary_sensor.bedtime_bridge_plan_out_of_date").state == "off"
    assert notify == []

    freezer.tick(timedelta(hours=11, minutes=1))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert hass.states.get("input_select.select_shift_override").state == "Auto"


async def test_unskip_puts_the_override_back(hass, hass_client_no_auth):
    assert await async_setup_component(
        hass, "input_select", {"input_select": {"select_shift_override": {"options": ["Auto", "Off", "Days", "Swings"]}}}
    )
    await setup(hass)
    start = (dt_util.utcnow() + timedelta(hours=10)).isoformat()
    await send(hass_client_no_auth, {"type": "skipped", "data": {"morning": start, "shift": "Days", "shift_start": start}})
    await hass.async_block_till_done()
    assert hass.states.get("input_select.select_shift_override").state == "Off"
    await send(hass_client_no_auth, {"type": "unskipped", "data": {}})
    await hass.async_block_till_done()
    assert hass.states.get("input_select.select_shift_override").state == "Auto"


async def test_skipped_appointment_leaves_the_override(hass, hass_client_no_auth):
    assert await async_setup_component(
        hass, "input_select", {"input_select": {"select_shift_override": {"options": ["Auto", "Off", "Days", "Swings"]}}}
    )
    await setup(hass)
    await send(hass_client_no_auth, {"type": "skipped", "data": {"morning": "2026-10-26T09:00:00+00:00"}})
    await hass.async_block_till_done()
    assert hass.states.get("input_select.select_shift_override").state == "Auto"


async def test_sleep_in_follows_the_first_alarm(hass, hass_client_no_auth):
    assert await async_setup_component(hass, "input_boolean", {"input_boolean": {"sleep_in": {}}})
    sunrise = dt_util.utcnow() + timedelta(hours=10)
    hass.states.async_set("sun.sun", "below_horizon", {"next_rising": sunrise.isoformat()})
    await setup(hass, sleep_in_helper="input_boolean.sleep_in", curtain_offset_minutes=15)

    def plan(first):
        return {**PLAN, "data": {**PLAN["data"], "alarm_times": [first.isoformat()], "alarm_time": first.isoformat()}}

    await send(hass_client_no_auth, plan(sunrise + timedelta(minutes=30)))
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.sleep_in").state == "on"

    await send(hass_client_no_auth, plan(sunrise - timedelta(hours=1)))
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.sleep_in").state == "off"


async def test_latch_from_before_the_alarms_does_not_count_as_up(hass, hass_client_no_auth, freezer):
    hass.states.async_set("input_boolean.exited", "on")  # out for the trash at 2 AM
    hass.states.async_set(BED, "on")
    await setup(hass, exit_latch="input_boolean.exited", bed_sensor=BED)
    first = dt_util.utcnow() + timedelta(minutes=1)
    plan = {**PLAN, "data": {**PLAN["data"], "alarm_times": [first.isoformat()], "alarm_time": first.isoformat()}}
    await send(hass_client_no_auth, plan)
    freezer.tick(timedelta(minutes=5))
    reply = await send(hass_client_no_auth, {"type": "up_check", "data": {}})
    assert reply["up"] is False

    hass.states.async_set("input_boolean.exited", "off")
    hass.states.async_set("input_boolean.exited", "on")  # really up now
    reply = await send(hass_client_no_auth, {"type": "up_check", "data": {}})
    assert reply["up"] is True


async def test_home_check_reports_whats_open(hass, hass_client_no_auth):
    hass.states.async_set("cover.garage", "open", {"friendly_name": "Garage Door"})
    hass.states.async_set("lock.front", "locked", {"friendly_name": "Front Door Lock"})
    hass.states.async_set("binary_sensor.patio", "off", {"friendly_name": "Patio Door"})
    await setup(hass, home_check_entities=["cover.garage", "lock.front", "binary_sensor.patio", "lock.gone"])
    reply = await send(hass_client_no_auth, {"type": "home_check", "data": {}})
    assert reply["issues"] == ["Garage Door is open", "lock.gone isn't responding"]

    hass.states.async_set("cover.garage", "closed", {"friendly_name": "Garage Door"})
    await hass.async_block_till_done()
    reply = await send(hass_client_no_auth, {"type": "home_check", "data": {}})
    assert reply["issues"] == ["lock.gone isn't responding"]
