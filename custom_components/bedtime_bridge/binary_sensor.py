"""Snoozing: on from a snooze tap until the alarm is due to ring again."""

from __future__ import annotations

from datetime import datetime

from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity
from homeassistant.core import CALLBACK_TYPE, HomeAssistant, callback
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.event import async_track_point_in_utc_time
from homeassistant.util import dt as dt_util

from . import BedtimeBridgeConfigEntry
from .entity import BedtimeBridgeEntity


async def async_setup_entry(
    hass: HomeAssistant, entry: BedtimeBridgeConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    async_add_entities([SnoozingSensor(entry.runtime_data), PlanOutdatedSensor(entry.runtime_data)])


class PlanOutdatedSensor(BedtimeBridgeEntity, BinarySensorEntity):
    """On when the shift override or next shift changed after tonight's plan."""

    _attr_translation_key = "plan_outdated"
    _attr_device_class = BinarySensorDeviceClass.PROBLEM

    def __init__(self, bridge) -> None:
        super().__init__(bridge, "plan_outdated")

    @property
    def is_on(self) -> bool:
        return bool(self.bridge.state.get("plan_outdated"))

    @property
    def extra_state_attributes(self) -> dict[str, str | None]:
        return {"reason": self.bridge.state.get("outdated_reason")}


class SnoozingSensor(BedtimeBridgeEntity, BinarySensorEntity):
    _attr_translation_key = "snoozing"
    _attr_icon = "mdi:alarm-snooze"

    def __init__(self, bridge) -> None:
        super().__init__(bridge, "snoozing")
        self._unsub_timer: CALLBACK_TYPE | None = None

    @property
    def _until(self) -> datetime | None:
        value = self.bridge.state.get("snoozed_until")
        return dt_util.parse_datetime(value) if isinstance(value, str) else None

    @property
    def is_on(self) -> bool:
        until = self._until
        return until is not None and until > dt_util.utcnow()

    @property
    def extra_state_attributes(self) -> dict[str, str | None]:
        return {"rings_again": self.bridge.state.get("snoozed_until")}

    async def async_added_to_hass(self) -> None:
        await super().async_added_to_hass()
        self._schedule_off()
        self.async_on_remove(self._cancel_timer)

    @callback
    def _handle_update(self) -> None:
        self._schedule_off()
        super()._handle_update()

    @callback
    def _schedule_off(self) -> None:
        """Turns itself off when the snooze runs out, even if the phone never reports back."""
        self._cancel_timer()
        if self.is_on:
            self._unsub_timer = async_track_point_in_utc_time(self.hass, self._snooze_over, self._until)

    @callback
    def _snooze_over(self, _now: datetime) -> None:
        self._unsub_timer = None
        self.async_write_ha_state()

    @callback
    def _cancel_timer(self) -> None:
        if self._unsub_timer:
            self._unsub_timer()
            self._unsub_timer = None
