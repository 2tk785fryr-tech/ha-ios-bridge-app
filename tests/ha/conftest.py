"""Fixtures for the Bedtime Bridge integration tests."""

import pytest
from pytest_homeassistant_custom_component.common import MockConfigEntry

from custom_components.bedtime_bridge.const import (
    CONF_SHIFT_OVERRIDE,
    CONF_SHIFT_SENSOR,
    CONF_SHIFT_TYPES,
    CONF_SNOOZE_HELPER,
    CONF_STOP_HELPER,
    CONF_WAKE_ACTION,
    CONF_WEBHOOK_ID,
    DOMAIN,
    WAKE_BOTH,
)

WEBHOOK_ID = "test_webhook"


@pytest.fixture(autouse=True)
def auto_enable_custom_integrations(enable_custom_integrations):
    yield


def make_entry(**options) -> MockConfigEntry:
    return MockConfigEntry(
        domain=DOMAIN,
        unique_id=DOMAIN,
        data={CONF_WEBHOOK_ID: WEBHOOK_ID},
        options={
            CONF_WAKE_ACTION: WAKE_BOTH,
            CONF_SNOOZE_HELPER: "input_boolean.wake_fade",
            CONF_STOP_HELPER: "input_boolean.wake_mike",
            CONF_SHIFT_OVERRIDE: "input_select.select_shift_override",
            CONF_SHIFT_SENSOR: "sensor.current_shift",
            CONF_SHIFT_TYPES: "Days, Swings",
            **options,
        },
    )
