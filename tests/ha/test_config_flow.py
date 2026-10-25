"""Setup and options flows."""

from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType

from pytest_homeassistant_custom_component.common import async_mock_service

from custom_components.bedtime_bridge.const import (
    CONF_NOTIFY,
    CONF_SHIFT_TYPES,
    CONF_SNOOZE_HELPER,
    CONF_WAKE_ACTION,
    CONF_WEBHOOK_ID,
    DOMAIN,
    WAKE_EVENTS,
)

from .conftest import make_entry


async def _run_flow(hass: HomeAssistant):
    result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    assert result["type"] is FlowResultType.FORM
    assert result["step_id"] == "user"
    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_WAKE_ACTION: "both", CONF_SHIFT_TYPES: "Days, Swings"}
    )
    assert result["step_id"] == "pair"
    return result


async def test_pairing_offers_nabu_casa_cloudhook_and_local(hass: HomeAssistant):
    await hass.config.async_update(internal_url="http://192.168.1.10:8123")
    with patch(
        "custom_components.bedtime_bridge.pairing._async_cloudhook",
        return_value="https://hooks.nabu.casa/abc123",
    ):
        result = await _run_flow(hass)
    placeholders = result["description_placeholders"]
    assert placeholders["remote_url"] == "https://hooks.nabu.casa/abc123"
    assert placeholders["local_url"].startswith("http://192.168.1.10:8123/api/webhook/")
    link = urlparse(placeholders["pair_link"])
    assert (link.scheme, link.netloc) == ("bedtimebridge", "pair")
    query = parse_qs(link.query)
    assert query["remote"] == ["https://hooks.nabu.casa/abc123"]
    assert query["local"][0] == placeholders["local_url"]

    result = await hass.config_entries.flow.async_configure(result["flow_id"], {})
    assert result["type"] is FlowResultType.CREATE_ENTRY
    assert result["data"][CONF_WEBHOOK_ID]
    assert result["options"][CONF_SHIFT_TYPES] == "Days, Swings"


async def test_pairing_uses_external_url_without_nabu_casa(hass: HomeAssistant):
    await hass.config.async_update(external_url="https://ha.example.com", internal_url="http://homeassistant.local:8123")
    result = await _run_flow(hass)
    placeholders = result["description_placeholders"]
    assert placeholders["remote_url"].startswith("https://ha.example.com/api/webhook/")
    assert placeholders["local_url"].startswith("http://homeassistant.local:8123/api/webhook/")


async def test_pairing_with_only_a_local_address_says_so(hass: HomeAssistant):
    await hass.config.async_update(internal_url="http://192.168.1.10:8123")
    result = await _run_flow(hass)
    placeholders = result["description_placeholders"]
    assert placeholders["remote_url"].startswith("Not available")
    assert "remote" not in parse_qs(urlparse(placeholders["pair_link"]).query)


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
    assert entry.options[CONF_SNOOZE_HELPER] is None  # cleared, and stays cleared
    assert hass.states.get("number.bedtime_bridge_nights_lead_time") is not None


def suggested(result, key):
    for marker in result["data_schema"].schema:
        if marker == key:
            return (marker.description or {}).get("suggested_value")
    raise KeyError(key)


async def test_notify_suggests_the_iphone_not_the_mac(hass: HomeAssistant):
    async_mock_service(hass, "notify", "mobile_app_michaels_macbook_pro")
    async_mock_service(hass, "notify", "mobile_app_mikes_iphone")
    result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    assert suggested(result, CONF_NOTIFY) == "notify.mobile_app_mikes_iphone"


async def test_configure_suggests_options_the_entry_never_had(hass: HomeAssistant):
    async_mock_service(hass, "notify", "mobile_app_michaels_macbook_pro")
    async_mock_service(hass, "notify", "mobile_app_mikes_iphone")
    entry = make_entry()  # set up before the notify option existed
    entry.add_to_hass(hass)
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()
    result = await hass.config_entries.options.async_init(entry.entry_id)
    assert suggested(result, CONF_NOTIFY) == "notify.mobile_app_mikes_iphone"


async def test_cleared_option_stays_cleared(hass: HomeAssistant):
    async_mock_service(hass, "notify", "mobile_app_mikes_iphone")
    entry = make_entry()
    entry.add_to_hass(hass)
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()
    result = await hass.config_entries.options.async_init(entry.entry_id)
    # Save without a notify action (the field cleared).
    await hass.config_entries.options.async_configure(result["flow_id"], {CONF_WAKE_ACTION: "both", CONF_SHIFT_TYPES: "Days, Swings"})
    await hass.async_block_till_done()
    assert entry.options[CONF_NOTIFY] is None
    result = await hass.config_entries.options.async_init(entry.entry_id)
    assert suggested(result, CONF_NOTIFY) is None
