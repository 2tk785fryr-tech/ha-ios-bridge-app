"""Setup and options flows."""

from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType

from custom_components.bedtime_bridge.const import (
    CONF_SHIFT_TYPES,
    CONF_SNOOZE_HELPER,
    CONF_WAKE_ACTION,
    CONF_WEBHOOK_ID,
    DOMAIN,
    WAKE_EVENTS,
)

from .conftest import make_entry


async def test_setup_shows_pairing_address_then_creates_entry(hass: HomeAssistant):
    await hass.config.async_update(external_url="https://example.ui.nabu.casa")
    result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    assert result["type"] is FlowResultType.FORM
    assert result["step_id"] == "user"

    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_WAKE_ACTION: "both", CONF_SHIFT_TYPES: "Days, Swings"}
    )
    assert result["step_id"] == "pair"
    assert result["description_placeholders"]["webhook_url"].startswith("https://example.ui.nabu.casa/api/webhook/")

    result = await hass.config_entries.flow.async_configure(result["flow_id"], {})
    assert result["type"] is FlowResultType.CREATE_ENTRY
    assert result["data"][CONF_WEBHOOK_ID]
    assert result["options"][CONF_SHIFT_TYPES] == "Days, Swings"


async def test_only_one_instance(hass: HomeAssistant):
    make_entry().add_to_hass(hass)
    result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    assert result["type"] is FlowResultType.ABORT


async def test_options_change_wake_action_and_add_shift(hass: HomeAssistant):
    entry = make_entry()
    entry.add_to_hass(hass)
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()

    result = await hass.config_entries.options.async_init(entry.entry_id)
    assert result["step_id"] == "init"
    result = await hass.config_entries.options.async_configure(
        result["flow_id"], {CONF_WAKE_ACTION: WAKE_EVENTS, CONF_SHIFT_TYPES: "Days, Swings, Nights"}
    )
    assert result["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()

    assert entry.options[CONF_WAKE_ACTION] == WAKE_EVENTS
    assert CONF_SNOOZE_HELPER not in entry.options
    assert hass.states.get("number.bedtime_bridge_nights_lead_time") is not None
