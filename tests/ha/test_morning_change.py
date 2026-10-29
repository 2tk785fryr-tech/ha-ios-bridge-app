"""v0.4 item 3: change this morning (sleep longer or no alarms), Home Assistant's side."""

from homeassistant.core import callback
from homeassistant.setup import async_setup_component
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service

from .test_ladder import SHIFT, TZ, attrs, local, rungs, shift_sensor  # noqa: F401
from .test_ladder import calendar_days, ladder  # noqa: F401 - fixtures
from .test_webhook import send

COMMANDS = {"notify_service": "notify.mobile_app_test", "phone_commands": True}
AUTOMATIONS = ["automation.wake_confirm_still_in_bed_after_alarm", "automation.wake_deadline_backstop"]


def change(*times, delay=0, phase="up", **extra) -> dict:
    return {"type": "morning_changed", "data": {
        "alarm_times": [t.isoformat() for t in times], "delay_minutes": delay, "phase": phase,
        "reason": "Snow delay", "note": "roads closed", "changed_by": "app", **extra,
    }}


async def helpers(hass):
    assert await async_setup_component(hass, "input_boolean", {"input_boolean": {
        "wake_fade": {}, "wake_mike": {}, "bedtime_routine": {}, "sleep_in": {},
    }})


def record_calls(hass) -> list[str]:
    calls = []

    def note(event):
        data = event.data
        target = data["service_data"].get("entity_id")
        message = data["service_data"].get("message")
        calls.append(f"{data['domain']}.{data['service']}:{message or target}")

    hass.bus.async_listen("call_service", note)
    return calls


async def test_back_to_bed_after_a_stop(hass, ladder, hass_client_no_auth):
    await helpers(hass)
    order: list[str] = []

    async def automation_call(call):
        order.append(f"automation.{call.service}:{call.data['entity_id']}")

    async def push(call):
        order.append(f"push:{call.data['message']}")

    for entity_id in AUTOMATIONS:
        hass.states.async_set(entity_id, "on")
    hass.services.async_register("automation", "turn_off", automation_call)
    hass.services.async_register("automation", "turn_on", automation_call)
    hass.services.async_register("notify", "mobile_app_test", push)

    @callback
    def state_changed(event):
        # A callback runs in the event loop, in order; a plain function would run in a worker
        # thread and record its state changes late.
        if event.data["entity_id"].startswith("input_boolean."):
            order.append(f"state:{event.data['entity_id']}={event.data['new_state'].state}")

    hass.bus.async_listen("state_changed", state_changed)
    hass.states.async_set("sun.sun", "above_horizon", {"next_rising": local("07:20", day=29).isoformat()})
    await ladder(sleep_in_helper="input_boolean.sleep_in", bedtime_helper="input_boolean.bedtime_routine",
                 curtain_offset_minutes=15, **COMMANDS)
    events = async_capture_events(hass, "bedtime_bridge")

    # Up after the alarms; then a 2-hour snow delay: back to bed, new alarms 8:20-8:40.
    await send(hass_client_no_auth, change(local("08:20"), local("08:30"), local("08:40"), delay=120))
    await hass.async_block_till_done()

    for entity_id in AUTOMATIONS:  # off (cancelling running actions), then straight back on
        assert order.index(f"automation.turn_off:{entity_id}") < order.index(f"automation.turn_on:{entity_id}")
    sleep_in = order.index("state:input_boolean.sleep_in=on")
    bedtime = order.index("state:input_boolean.bedtime_routine=on")
    assert sleep_in < bedtime < order.index("push:RUN_BACK_TO_BED"), order
    assert "push:clear_notification" in order, "wake_backstop / wake_confirm cleared"
    assert hass.states.get("input_boolean.sleep_in").state == "on", "first alarm 8:20 is after sunrise + 15"

    assert rungs(hass) == ["06:55", "07:10", "07:25"], "backstops move with the wake-up"
    assert attrs(hass)["reason"] == "Snow delay"
    assert events[-1].data["type"] == "morning_changed"
    assert events[-1].data["reason"] == "Snow delay" and events[-1].data["note"] == "roads closed"
    last = hass.states.get("sensor.bedtime_bridge_last_event").attributes["last_morning_change"]
    assert last["reason"] == "Snow delay" and last["delay_minutes"] == 120
    assert hass.states.get("sensor.bedtime_bridge_next_alarm").state == local("08:20").astimezone(dt_util.UTC).isoformat()


async def test_while_snoozing_only_the_ramp_is_undone(hass, ladder, hass_client_no_auth):
    await helpers(hass)
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await ladder(bedtime_helper="input_boolean.bedtime_routine", **COMMANDS)
    await hass.services.async_call("input_boolean", "turn_on", {"entity_id": "input_boolean.wake_fade"}, blocking=True)
    await send(hass_client_no_auth, {"type": "snoozed", "data": {"rings_again": local("04:40").isoformat()}})
    await send(hass_client_no_auth, change(local("05:00"), local("05:10"), local("05:20"), delay=30, phase="snoozing"))
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.wake_fade").state == "off"
    assert hass.states.get("input_boolean.bedtime_routine").state == "off"
    assert "RUN_BACK_TO_BED" not in [c.data["message"] for c in notify]
    assert hass.states.get("sensor.bedtime_bridge_snooze_count").state == "0", "old series' count cleared"
    assert hass.states.get("sensor.bedtime_bridge_snoozes_last_morning").state == "1"
    assert rungs(hass) == ["05:25", "05:40", "05:55"]


async def test_no_alarms_with_the_shift_still_on_the_calendar(hass, ladder, hass_client_no_auth):
    await helpers(hass)
    await ladder(sleep_in_helper="input_boolean.sleep_in")
    await send(hass_client_no_auth, change(sleep_in=True))
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:55", "05:10", "05:25"], "backstops stay while the calendar shows the shift"
    assert hass.states.get("input_boolean.sleep_in").state == "on"
    assert hass.states.get("sensor.bedtime_bridge_next_alarm").state == "unknown"

    await send(hass_client_no_auth, change(sleep_in=False))
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.sleep_in").state == "off"


async def test_context_reply_has_the_ladder_and_curtain_time(hass, ladder, hass_client_no_auth):
    hass.states.async_set("sun.sun", "above_horizon", {"next_rising": local("07:21", day=29).isoformat()})
    await ladder(curtain_offset_minutes=15)
    reply = await send(hass_client_no_auth, {"type": "context", "data": {"first_alarm": local("08:00").isoformat()}})
    assert reply["ladder"]["status"] == "armed"
    assert reply["ladder"]["shift_start"]
    # Sunrise moved to the first alarm's own day (28th), plus 15 minutes.
    assert dt_util.as_local(dt_util.parse_datetime(reply["curtains_open_at"])).strftime("%d %H:%M") == "28 07:36"


async def test_fewer_alarms_set_than_planned_is_reported(hass, ladder, hass_client_no_auth):
    """v0.4.1 item 1: the phone sends what AlarmKit really holds."""
    await ladder()
    events = async_capture_events(hass, "bedtime_bridge")
    await send(hass_client_no_auth, change(local("05:00"), delay=30, alarms_planned=3))
    await hass.async_block_till_done()
    missing = [e.data for e in events if e.data["type"] == "alarms_missing"]
    assert missing == [{"type": "alarms_missing", "set": 1, "planned": 3}]
    assert hass.states.get("sensor.bedtime_bridge_last_event").attributes["alarms_missing"]["set"] == 1

    await send(hass_client_no_auth, change(local("05:00"), local("05:05"), local("05:10"), delay=30, alarms_planned=3))
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_last_event").attributes["alarms_missing"] is None


async def test_each_stop_records_how_it_was_decided(hass, ladder, hass_client_no_auth):
    await ladder()
    await send(hass_client_no_auth, {"type": "stopped", "data": {
        "all": False, "up": False, "stop_behavior": "keepUntilUp", "alarm_times": [local("04:50").isoformat()],
    }})
    await hass.async_block_till_done()
    last = hass.states.get("sensor.bedtime_bridge_last_event").attributes["last_stop"]
    assert last["all"] is False and last["up"] is False and last["alarms_left"] == 1
    await send(hass_client_no_auth, {"type": "stopped", "data": {"all": True, "alarm_times": []}})
    await hass.async_block_till_done()
    assert hass.states.get("sensor.bedtime_bridge_last_event").attributes["last_stop"]["all"] is True


async def test_change_from_the_snooze_screen_after_a_stop_goes_back_to_bed(hass, ladder, hass_client_no_auth):
    """v0.4.1 item 2 (28 Oct): stop, then snooze, then change from the snooze screen."""
    await helpers(hass)
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await ladder(bedtime_helper="input_boolean.bedtime_routine", sleep_in_helper="input_boolean.sleep_in", **COMMANDS)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": [local("04:30").isoformat()]}})
    await send(hass_client_no_auth, {"type": "snoozed", "data": {"rings_again": local("04:39").isoformat()}})
    await send(hass_client_no_auth, change(local("04:50"), local("04:55"), local("05:00"), delay=30, phase="snoozing"))
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.bedtime_routine").state == "on"
    assert "RUN_BACK_TO_BED" in [c.data["message"] for c in notify]
    last = hass.states.get("sensor.bedtime_bridge_last_event").attributes["last_morning_change"]
    assert last["phase"] == "up"
