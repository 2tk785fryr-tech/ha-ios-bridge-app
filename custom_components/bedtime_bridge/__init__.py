"""Bedtime Bridge: the iPhone wake-up planner's companion in Home Assistant."""

from __future__ import annotations

import json
import logging

from aiohttp import web

from homeassistant.components import webhook
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant

from .bridge import BedtimeBridge
from .const import CONF_WEBHOOK_ID, DOMAIN

_LOGGER = logging.getLogger(__name__)

PLATFORMS = [Platform.SENSOR, Platform.BINARY_SENSOR, Platform.NUMBER]

type BedtimeBridgeConfigEntry = ConfigEntry[BedtimeBridge]


async def async_setup_entry(hass: HomeAssistant, entry: BedtimeBridgeConfigEntry) -> bool:
    bridge = BedtimeBridge(hass, entry)
    await bridge.async_load()
    entry.runtime_data = bridge

    async def handle_webhook(hass: HomeAssistant, webhook_id: str, request: web.Request) -> web.Response:
        try:
            message = await request.json()
        except (ValueError, json.JSONDecodeError):
            return web.json_response({"error": "body must be JSON"}, status=400)
        if not isinstance(message, dict):
            return web.json_response({"error": "body must be a JSON object"}, status=400)
        try:
            return web.json_response(await bridge.async_handle(message))
        except Exception:  # noqa: BLE001 - report to the phone instead of a bare 500
            _LOGGER.exception("Bedtime Bridge message failed: %s", message.get("type"))
            return web.json_response({"error": "Home Assistant could not handle the message"}, status=500)

    # local_only=False: the phone also reports snoozes and stops when it's away from home.
    webhook.async_register(
        hass, DOMAIN, "Bedtime Bridge", entry.data[CONF_WEBHOOK_ID], handle_webhook, local_only=False
    )
    entry.async_on_unload(lambda: webhook.async_unregister(hass, entry.data[CONF_WEBHOOK_ID]))
    entry.async_on_unload(entry.add_update_listener(_async_reload))

    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: BedtimeBridgeConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)


async def _async_reload(hass: HomeAssistant, entry: BedtimeBridgeConfigEntry) -> None:
    """Options changed (e.g. new shift types add lead-time numbers): reload."""
    await hass.config_entries.async_reload(entry.entry_id)
