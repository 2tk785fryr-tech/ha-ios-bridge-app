"""v0.4.2 item 3: nap_started / nap_ended, the napping helper and the nap Focus commands."""

from datetime import timedelta

from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service

from .test_webhook import send, setup

# input_boolean.bedtime_routine stands in for input_boolean.napping (setup creates it).
HELPER = "input_boolean.bedtime_routine"


def _times():
    first = dt_util.utcnow() + timedelta(minutes=20)
    return [first.isoformat(), (first + timedelta(minutes=10)).isoformat()]


async def test_nap_at_home_turns_the_helper_on_and_off_and_sends_both_commands(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    hass.states.async_set("person.me", "home")
    await setup(hass, napping_helper=HELPER, presence_entities=["person.me"], notify_service="notify.mobile_app_test", phone_commands=True)
    events = async_capture_events(hass, "bedtime_bridge")

    reply = await send(hass_client_no_auth, {"type": "nap_started", "data": {"alarm_times": _times()}})
    await hass.async_block_till_done()
    assert reply["napping_helper"] is True and reply["nap_focus"] is True
    assert hass.states.get(HELPER).state == "on"
    assert events[-1].data["type"] == "nap_started"
    assert len(events[-1].data["alarm_times"]) == 2
    # Nothing about the morning: no wake helpers.
    assert hass.states.get("input_boolean.wake_mike").state == "off"
    assert hass.states.get("input_boolean.wake_fade").state == "off"

    await send(hass_client_no_auth, {"type": "nap_ended", "data": {}})
    await hass.async_block_till_done()
    assert hass.states.get(HELPER).state == "off"
    assert events[-1].data["type"] == "nap_ended"
    assert [c.data["message"] for c in notify if c.data["message"].startswith("RUN_NAP")] == ["RUN_NAP_START", "RUN_NAP_END"]


async def test_nap_away_leaves_the_helper_but_still_sends_the_focus_command(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    hass.states.async_set("person.me", "not_home")
    await setup(hass, napping_helper=HELPER, presence_entities=["person.me"], notify_service="notify.mobile_app_test", phone_commands=True)

    reply = await send(hass_client_no_auth, {"type": "nap_started", "data": {"alarm_times": _times()}})
    await hass.async_block_till_done()
    assert reply["napping_helper"] is False
    assert hass.states.get(HELPER).state == "off"
    assert [c.data["message"] for c in notify] == ["RUN_NAP_START"]
