"""Shared base for Bedtime Bridge entities."""

from __future__ import annotations

from homeassistant.core import callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.entity import Entity

from .bridge import BedtimeBridge
from .const import DOMAIN, signal_update


class BedtimeBridgeEntity(Entity):
    """Pushed by the phone; redraws whenever a webhook message changes the state."""

    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, bridge: BedtimeBridge, key: str) -> None:
        self.bridge = bridge
        self._attr_unique_id = f"{bridge.entry.entry_id}_{key}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, bridge.entry.entry_id)},
            name="Bedtime Bridge",
            manufacturer="Bedtime Bridge",
            model="iPhone wake-up planner",
        )

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(
            async_dispatcher_connect(self.hass, signal_update(self.bridge.entry.entry_id), self._handle_update)
        )

    @callback
    def _handle_update(self) -> None:
        self.async_write_ha_state()
