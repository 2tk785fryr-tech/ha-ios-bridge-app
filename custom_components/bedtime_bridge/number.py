"""Settings the phone reads back each time it runs, adjustable from Home Assistant."""

from __future__ import annotations

from homeassistant.components.number import NumberEntity, NumberMode
from homeassistant.const import EntityCategory, UnitOfTime
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from . import BedtimeBridgeConfigEntry
from .const import LADDER_SETTINGS, SETTINGS, SHIFT_LEAD_PREFIX
from .entity import BedtimeBridgeEntity


async def async_setup_entry(
    hass: HomeAssistant, entry: BedtimeBridgeConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    bridge = entry.runtime_data
    async_add_entities(BridgeSetting(bridge, key) for key in bridge.setting_keys())


class BridgeSetting(BedtimeBridgeEntity, NumberEntity):
    """Unknown until the phone's first plan seeds it; after that, Home Assistant's value wins."""

    _attr_entity_category = EntityCategory.CONFIG
    _attr_mode = NumberMode.BOX
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES
    _attr_icon = "mdi:timer-cog-outline"

    def __init__(self, bridge, key: str) -> None:
        super().__init__(bridge, key.replace(":", "_").lower())
        self._key = key
        if key.startswith(SHIFT_LEAD_PREFIX):
            shift = key.removeprefix(SHIFT_LEAD_PREFIX)
            self._attr_translation_key = "shift_lead"
            self._attr_translation_placeholders = {"shift": shift}
            self._attr_native_min_value, self._attr_native_max_value, self._attr_native_step = 0, 240, 5
        elif key in LADDER_SETTINGS:
            _, low, high, step, _default = LADDER_SETTINGS[key]
            self._attr_translation_key = key
            self._attr_native_min_value, self._attr_native_max_value, self._attr_native_step = low, high, step
            self._attr_icon = "mdi:stairs"
        else:
            _, low, high, step = SETTINGS[key]
            self._attr_translation_key = key
            self._attr_native_min_value, self._attr_native_max_value, self._attr_native_step = low, high, step

    @property
    def native_value(self) -> float | None:
        return self.bridge.setting_value(self._key)

    async def async_set_native_value(self, value: float) -> None:
        self.bridge.set_setting(self._key, int(value))
