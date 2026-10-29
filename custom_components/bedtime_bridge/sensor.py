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
    available: Callable[[dict[str, Any]], bool] | None = None
    bridge_attributes: Callable[[Any], dict[str, Any]] | None = None


LADDER_STATUSES = [
    "armed", "done", "idle_override_off", "idle_leave", "idle_uncovered", "idle_no_shift", "fault",
]


def _ladder(s: dict[str, Any]) -> dict[str, Any]:
    return s.get("ladder") or {}


def _rung_attributes(s: dict[str, Any]) -> dict[str, Any]:
    """What the Bedtime Readout and the watchdog read instead of re-deriving it."""
    ladder = _ladder(s)
    return {
        "leave_by": ladder.get("leave_by"),
        "leave_by_source": ladder.get("leave_by_source"),
        "first_day_back": ladder.get("first_day_back"),
        "shift_start": ladder.get("shift_start"),
        "appointment": ladder.get("appointment"),
        "appointment_start": ladder.get("appointment_start"),
        "replaces_shift": ladder.get("replaces_shift"),
        "delay_minutes": ladder.get("delay_minutes", 0),
        "changed_by": ladder.get("changed_by"),
        "reason": ladder.get("change_reason"),
        "weather_extra_minutes": ladder.get("weather_extra_minutes", 0),
        "condition": ladder.get("condition"),
        # Wake Deadline Backstop's shift gate reads this; Days whenever the ladder is armed.
        "effective_shift": "Days",
    }


def _next_rung(s: dict[str, Any]) -> str | None:
    now = dt_util.utcnow()
    ahead = [(when, rung) for rung, v in (_ladder(s).get("times") or {}).items() if (when := _time(v)) and when > now]
    return min(ahead)[1] if ahead else None


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
    # The leave-by backstop ladder (item 6): unavailable whenever it isn't armed.
    *(
        BridgeSensorDescription(
            key=f"rung_{rung}",
            translation_key=f"rung_{rung}",
            device_class=SensorDeviceClass.TIMESTAMP,
            value=lambda s, rung=rung: _time((_ladder(s).get("times") or {}).get(rung)),
            attributes=_rung_attributes,
            available=lambda s: _ladder(s).get("status") == "armed",
        )
        for rung in ("early", "deadline", "late")
    ),
    BridgeSensorDescription(
        key="ladder_status",
        translation_key="ladder_status",
        device_class=SensorDeviceClass.ENUM,
        options=LADDER_STATUSES,
        icon="mdi:stairs",
        value=lambda s: _ladder(s).get("status") or "idle_no_shift",
        attributes=lambda s: {
            "reason": _ladder(s).get("reason"),
            "morning": _ladder(s).get("shift_start") or _ladder(s).get("appointment_start"),
            "next_rung": _next_rung(s),
        },
        # The house backstop's own times (old template until the cutover) come from the bridge.
        bridge_attributes=lambda bridge: {"house_backstop": bridge.house_backstop()},
    ),
    BridgeSensorDescription(
        key="last_event",
        translation_key="last_event",
        icon="mdi:history",
        entity_category=EntityCategory.DIAGNOSTIC,
        value=lambda s: s.get("last_event"),
        attributes=lambda s: {
            "time": s.get("last_event_time"),
            "skipped_away": s.get("skipped_away", False),
            # The phone's last Report Shortcut Ran: which command, and "ran" or "already_done".
            "last_command": s.get("last_command"),
            # Item 3: the last morning change, with its reason, for tracking.
            "last_morning_change": s.get("last_morning_change"),
            # v0.4.1 item 1: how the last stop was decided, and alarms the phone couldn't set.
            "last_stop": s.get("last_stop"),
            "alarms_missing": s.get("alarms_missing"),
        },
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
    def available(self) -> bool:
        check = self.entity_description.available
        return check is None or check(self.bridge.state)

    @property
    def native_value(self) -> Any:
        return self.entity_description.value(self.bridge.state)

    @property
    def extra_state_attributes(self) -> dict[str, Any] | None:
        if self.entity_description.attributes is None:
            return None
        attributes = self.entity_description.attributes(self.bridge.state)
        if self.entity_description.bridge_attributes:
            attributes |= self.entity_description.bridge_attributes(self.bridge)
        return attributes
