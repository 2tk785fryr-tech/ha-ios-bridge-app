"""Sensors: what the phone planned and what happened to the alarm."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorEntityDescription,
    SensorStateClass,
)
from homeassistant.const import EntityCategory, UnitOfTime
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util

from . import BedtimeBridgeConfigEntry
from .entity import BedtimeBridgeEntity


def _time(value: Any) -> datetime | None:
    return dt_util.parse_datetime(value) if isinstance(value, str) else None


@dataclass(frozen=True, kw_only=True)
class BridgeSensorDescription(SensorEntityDescription):
    value: Callable[[dict[str, Any]], Any]
    attributes: Callable[[dict[str, Any]], dict[str, Any]] | None = None


SENSORS = (
    BridgeSensorDescription(
        key="next_alarm",
        translation_key="next_alarm",
        device_class=SensorDeviceClass.TIMESTAMP,
        value=lambda s: _time(s.get("alarm_time")),
        attributes=lambda s: {
            "alarm_times": s.get("alarm_times") or [],
            "alarm_cause": s.get("alarm_cause"),
            "label": s.get("label"),
            "alarm_style": s.get("alarm_style"),
        },
    ),
    BridgeSensorDescription(
        key="wake_time",
        translation_key="wake_time",
        device_class=SensorDeviceClass.TIMESTAMP,
        value=lambda s: _time(s.get("wake_time")),
    ),
    BridgeSensorDescription(
        key="alarm_cause",
        translation_key="alarm_cause",
        icon="mdi:alarm-note",
        value=lambda s: s.get("alarm_cause"),
    ),
    BridgeSensorDescription(
        key="reason",
        translation_key="reason",
        icon="mdi:text-short",
        value=lambda s: (s.get("reason") or "")[:255] or None,
        attributes=lambda s: {"warnings": s.get("warnings") or []},
    ),
    BridgeSensorDescription(
        key="leave_by",
        translation_key="leave_by",
        device_class=SensorDeviceClass.TIMESTAMP,
        value=lambda s: _time(s.get("leave_by")),
    ),
    BridgeSensorDescription(
        key="drive_time",
        translation_key="drive_time",
        device_class=SensorDeviceClass.DURATION,
        native_unit_of_measurement=UnitOfTime.MINUTES,
        value=lambda s: s.get("drive_minutes"),
    ),
    BridgeSensorDescription(
        key="weather_extra",
        translation_key="weather_extra",
        device_class=SensorDeviceClass.DURATION,
        native_unit_of_measurement=UnitOfTime.MINUTES,
        value=lambda s: s.get("weather_extra_minutes") or 0,
    ),
    BridgeSensorDescription(
        key="snooze_count",
        translation_key="snooze_count",
        icon="mdi:sleep",
        state_class=SensorStateClass.MEASUREMENT,
        value=lambda s: s.get("snooze_count") or 0,
    ),
    BridgeSensorDescription(
        key="snoozes_last_morning",
        translation_key="snoozes_last_morning",
        icon="mdi:sleep",
        state_class=SensorStateClass.MEASUREMENT,
        value=lambda s: s.get("snoozes_last_morning"),
    ),
    BridgeSensorDescription(
        key="last_plan",
        translation_key="last_plan",
        device_class=SensorDeviceClass.TIMESTAMP,
        value=lambda s: _time(s.get("last_plan")),
        attributes=lambda s: {"error": s.get("plan_error"), "undone_at": s.get("undone_at")},
    ),
    *(
        BridgeSensorDescription(
            key=f"rung_{rung}",
            translation_key=f"rung_{rung}",
            device_class=SensorDeviceClass.TIMESTAMP,
            value=lambda s, rung=rung: _time(s.get(f"rung_{rung}")),
            # Wake Deadline Backstop gates on its shift sensor's effective_shift attribute;
            # point a second instance's "Shift sensor" at the deadline sensor and keep Days.
            attributes=lambda s, rung=rung: {"effective_shift": "Days" if s.get(f"rung_{rung}") else None},
        )
        for rung in ("early", "deadline", "late")
    ),
    BridgeSensorDescription(
        key="last_event",
        translation_key="last_event",
        icon="mdi:history",
        entity_category=EntityCategory.DIAGNOSTIC,
        value=lambda s: s.get("last_event"),
        attributes=lambda s: {"time": s.get("last_event_time"), "skipped_away": s.get("skipped_away", False)},
    ),
)


async def async_setup_entry(
    hass: HomeAssistant, entry: BedtimeBridgeConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    async_add_entities(BridgeSensor(entry.runtime_data, description) for description in SENSORS)


class BridgeSensor(BedtimeBridgeEntity, SensorEntity):
    entity_description: BridgeSensorDescription

    def __init__(self, bridge, description: BridgeSensorDescription) -> None:
        super().__init__(bridge, description.key)
        self.entity_description = description

    @property
    def native_value(self) -> Any:
        return self.entity_description.value(self.bridge.state)

    @property
    def extra_state_attributes(self) -> dict[str, Any] | None:
        if self.entity_description.attributes is None:
            return None
        return self.entity_description.attributes(self.bridge.state)
