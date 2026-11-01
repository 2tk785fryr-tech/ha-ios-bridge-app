"""v0.4.10 integration tests, by spec item."""

from pytest_homeassistant_custom_component.common import async_mock_service

from .test_webhook import PLAN, send, setup


def _messages(notify) -> list[str]:
    return [c.data["message"] for c in notify]


# MARK: Item 2, good morning waits for the wake-up's last alarm


async def test_item2_no_good_morning_on_a_stop_with_alarms_still_set(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test", phone_commands=True)
    await send(hass_client_no_auth, PLAN)
    # 1 Nov 08:18: one alarm ended with the 8:19 snooze and the 8:20 still set.
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": ["2026-11-01T13:20:00+00:00"]}})
    await hass.async_block_till_done()
    assert "RUN_GOOD_MORNING" not in _messages(notify)
    # The last one, then a repeat: good morning once.
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()
    assert _messages(notify) == ["RUN_GOOD_MORNING"]


async def test_item2_the_hold_ends_them_all_and_runs_good_morning(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test", phone_commands=True)
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"all": True, "alarm_times": []}})
    await hass.async_block_till_done()
    assert _messages(notify) == ["RUN_GOOD_MORNING"]


async def test_item2_a_new_plan_is_a_new_wake_up(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test", phone_commands=True)
    for _ in range(2):
        await send(hass_client_no_auth, PLAN)
        await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()
    assert _messages(notify) == ["RUN_GOOD_MORNING", "RUN_GOOD_MORNING"]
