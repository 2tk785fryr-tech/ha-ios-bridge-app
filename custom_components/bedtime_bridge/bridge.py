"""State kept for the phone, and handling of the app's webhook messages."""

from __future__ import annotations

import logging
from datetime import timedelta
from typing import Any

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import Event, EventStateChangedData, HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import async_track_state_change_event
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import (
    BED_EMPTY_SECONDS,
    CONF_BED_SENSOR,
    CONF_BEDTIME_HELPER,
    CONF_EXIT_LATCH,
    CONF_HOME_ONLY,
    CONF_NOTIFY,
    CONF_PRESENCE,
    CONF_REPLAN_ALERT,
    CONF_SAFETY_CAUSES,
    CONF_SAFETY_MINUTES,
    CONF_SHIFT_OVERRIDE,
    CONF_SHIFT_SENSOR,
    CONF_SHIFT_TYPES,
    CONF_SNOOZE_HELPER,
    CONF_STOP_HELPER,
    CONF_WAKE_ACTION,
    CONF_WEATHER,
    DEFAULT_SAFETY_CAUSES,
    DEFAULT_SAFETY_MINUTES,
    DOMAIN,
    EVENT,
    EVENT_PLAN_OUTDATED,
    HOME_STATES,
    MSG_BEDTIME,
    MSG_CANCELLED,
    MSG_CONTEXT,
    MSG_FORECAST,
    MSG_LEAVE_BY,
    MSG_PLAN_FAILED,
    MSG_PLANNED,
    MSG_SNOOZED,
    MSG_STOPPED,
    MSG_UP_CHECK,
    REPLAN_URL,
    SETTINGS,
    SHIFT_LEAD_PREFIX,
    UNKNOWN_STATES,
    WAKE_BOTH,
    WAKE_EVENTS,
    WAKE_HELPERS,
    shift_types,
    signal_update,
)

_LOGGER = logging.getLogger(__name__)

STORAGE_VERSION = 1

# Plan fields copied from the app's "planned" message into the state.
PLAN_FIELDS = (
    "alarm_cause",
    "alarm_time",
    "wake_time",
    "alarm_times",
    "label",
    "reason",
    "leave_by",
    "drive_minutes",
    "weather_extra_minutes",
    "warnings",
    "alarm_style",
)


def empty_state() -> dict[str, Any]:
    """State with no alarm planned."""
    return {
        "alarm_cause": "noalarm",
        "alarm_time": None,
        "wake_time": None,
        "alarm_times": [],
        "label": None,
        "reason": None,
        "leave_by": None,
        "drive_minutes": None,
        "weather_extra_minutes": 0,
        "warnings": [],
        "alarm_style": None,
        "snoozed_until": None,
        "snooze_count": 0,
        "last_event": None,
        "last_event_time": None,
        "skipped_away": False,
        # Safety-net times for Wake Deadline Backstop (only for the chosen causes).
        "rung_early": None,
        "rung_deadline": None,
        "rung_late": None,
        "plan_outdated": False,
        "outdated_reason": None,
    }


def plan_record() -> dict[str, Any]:
    """Kept across new plans and cancels: when the phone last planned, and why it failed."""
    return {"last_plan": None, "plan_error": None}


class BedtimeBridge:
    """One paired phone: its latest plan, alarm events and the settings it reads back."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self.state: dict[str, Any] = {**empty_state(), **plan_record()}
        # None means "not set yet"; filled from the app's own settings on its first plan.
        self.settings: dict[str, int | None] = {}
        self._store: Store[dict[str, Any]] = Store(hass, STORAGE_VERSION, f"{DOMAIN}.{entry.entry_id}")

    @property
    def options(self) -> dict[str, Any]:
        return {**self.entry.data, **self.entry.options}

    def setting_keys(self) -> list[str]:
        """Built-in settings plus one lead time per configured shift type."""
        shifts = shift_types(self.options.get(CONF_SHIFT_TYPES))
        return list(SETTINGS) + [f"{SHIFT_LEAD_PREFIX}{name}" for name in shifts]

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.state = {**empty_state(), **plan_record(), **stored.get("state", {})}
        self.settings = stored.get("settings", {})

    @callback
    def async_start(self) -> None:
        """Watches the shift override and shift sensor for changes after a plan."""
        watched = [e for e in (self.options.get(CONF_SHIFT_OVERRIDE), self.options.get(CONF_SHIFT_SENSOR)) if e]
        if watched:
            self.entry.async_on_unload(async_track_state_change_event(self.hass, watched, self._shift_changed))
    def _save(self) -> None:
        self._store.async_delay_save(lambda: {"state": self.state, "settings": self.settings}, 1)

    def _changed(self) -> None:
        self._save()
        async_dispatcher_send(self.hass, signal_update(self.entry.entry_id))

    def set_setting(self, key: str, value: int) -> None:
        self.settings[key] = value
        self._changed()

    def settings_for_app(self) -> dict[str, Any]:
        """Settings with a value, shift leads grouped as {"Days": 60}."""
        flat: dict[str, Any] = {}
        leads: dict[str, int] = {}
        for key, value in self.settings.items():
            if value is None:
                continue
            if key.startswith(SHIFT_LEAD_PREFIX):
                leads[key.removeprefix(SHIFT_LEAD_PREFIX)] = int(value)
            elif key in SETTINGS:
                flat[key] = int(value)
        if leads:
            flat["shift_lead_minutes"] = leads
        return flat

    def _adopt_app_settings(self, app_settings: dict[str, Any]) -> None:
        """First plan seeds the HA numbers from the phone; after that HA wins."""
        for key in SETTINGS:
            if self.settings.get(key) is None and isinstance(app_settings.get(key), int):
                self.settings[key] = app_settings[key]
        for name, minutes in (app_settings.get("shift_lead_minutes") or {}).items():
            key = f"{SHIFT_LEAD_PREFIX}{name}"
            if self.settings.get(key) is None and isinstance(minutes, int):
                self.settings[key] = minutes

    # MARK: Messages from the app

    async def async_handle(self, message: dict[str, Any]) -> dict[str, Any]:
        """Handle one webhook message; the returned dict is sent back as JSON."""
        kind = message.get("type")
        data = message.get("data") or {}
        handler = {
            MSG_CONTEXT: self._context,
            MSG_FORECAST: self._forecast,
            MSG_PLANNED: self._planned,
            MSG_SNOOZED: self._snoozed,
            MSG_STOPPED: self._stopped,
            MSG_CANCELLED: self._cancelled,
            MSG_LEAVE_BY: self._leave_by,
            MSG_BEDTIME: self._bedtime,
            MSG_PLAN_FAILED: self._plan_failed,
            MSG_UP_CHECK: self._up_check,
        }.get(kind)
        if handler is None:
            return {"error": f"unknown message type: {kind}"}
        result = await handler(data) or {}
        return {"settings": self.settings_for_app(), **result}

    async def _context(self, data: dict[str, Any]) -> dict[str, Any]:
        """Shift override and HA's next shift, read before the app plans."""
        override = self.hass.states.get(self.options.get(CONF_SHIFT_OVERRIDE) or "")
        sensor = self.hass.states.get(self.options.get(CONF_SHIFT_SENSOR) or "")
        return {
            "shift_override": override.state if override else None,
            "next_shift_start": sensor.attributes.get("next_shift_start") if sensor else None,
            "next_shift_type": sensor.attributes.get("next_shift_type") if sensor else None,
            "at_home": self.is_home(),
        }

    async def _forecast(self, data: dict[str, Any]) -> dict[str, Any]:
        weather = self.options.get(CONF_WEATHER)
        state = self.hass.states.get(weather or "")
        if state is None:
            return {"forecast": [], "temperature_unit": None}
        response = await self.hass.services.async_call(
            "weather",
            "get_forecasts",
            {"entity_id": weather, "type": "hourly"},
            blocking=True,
            return_response=True,
        )
        forecast = (response or {}).get(weather, {}).get("forecast", [])
        return {
            "forecast": [
                {
                    "datetime": str(hour.get("datetime")),
                    "condition": hour.get("condition"),
                    "temperature": hour.get("temperature"),
                }
                for hour in forecast
            ],
            "temperature_unit": state.attributes.get("temperature_unit"),
        }

    async def _planned(self, data: dict[str, Any]) -> None:
        self._adopt_app_settings(data.get("app_settings") or {})
        self.state.update(empty_state())
        self.state.update({key: data.get(key) for key in PLAN_FIELDS if key in data})
        self.state["last_plan"] = dt_util.utcnow().isoformat()
        self.state["plan_error"] = None
        self.state["planned_override"] = self._state_of(CONF_SHIFT_OVERRIDE)
        self.state["planned_shift_start"] = self._next_shift_start()
        self._set_rungs()
        self._event(MSG_PLANNED)

    async def _up_check(self, data: dict[str, Any]) -> dict[str, Any]:
        """Are you really up? The phone asks on Stop before cancelling the rest of the alarms."""
        return {"up": self.is_up()}

    def is_up(self) -> bool | None:
        """True: the bedroom door was opened (exit latch on) or the bed has been empty for over
        a minute. False: still in bed (or the bed reads unavailable). None: neither is set up.
        Stopping the first alarm and falling back asleep is exactly what this guards against,
        so anything uncertain counts as not up."""
        latch = self.hass.states.get(self.options.get(CONF_EXIT_LATCH) or "")
        bed = self.hass.states.get(self.options.get(CONF_BED_SENSOR) or "")
        if latch is None and bed is None:
            return None
        if latch is not None and latch.state == "on":
            return True
        if bed is not None and bed.state == "off":
            return (dt_util.utcnow() - bed.last_changed).total_seconds() >= BED_EMPTY_SECONDS
        return False

    async def _plan_failed(self, data: dict[str, Any]) -> None:
        """The phone couldn't plan. The previous plan's alarms may still be set."""
        self.state["plan_error"] = data.get("error") or "unknown error"
        self._event(MSG_PLAN_FAILED, error=self.state["plan_error"])

    def _set_rungs(self) -> None:
        """Safety-net times after the last alarm, for the chosen causes, when home.

        Mirrors the Days ladder in current_shift.yaml (alarms end 4:30, deadline 5:10): the
        checks start once the alarms are over, so they never fire while alarms still ring.
        Early = last alarm, deadline = +margin (out of bed by), late = +2×margin (left the room).
        """
        times = [t for t in (dt_util.parse_datetime(v) for v in self.state.get("alarm_times") or []) if t]
        last = max(times) if times else dt_util.parse_datetime(self.state.get("wake_time") or "")
        causes = self.options.get(CONF_SAFETY_CAUSES, DEFAULT_SAFETY_CAUSES)
        if last is None or self.state.get("alarm_cause") not in causes or not self.is_home():
            return
        margin = timedelta(minutes=int(self.options.get(CONF_SAFETY_MINUTES, DEFAULT_SAFETY_MINUTES)))
        self.state["rung_early"] = last.isoformat()
        self.state["rung_deadline"] = (last + margin).isoformat()
        self.state["rung_late"] = (last + 2 * margin).isoformat()

    # MARK: Changes after bedtime

    def _state_of(self, option: str) -> str | None:
        state = self.hass.states.get(self.options.get(option) or "")
        return state.state if state else None

    def _next_shift_start(self) -> str | None:
        sensor = self.hass.states.get(self.options.get(CONF_SHIFT_SENSOR) or "")
        value = sensor.attributes.get("next_shift_start") if sensor else None
        return str(value) if value else None

    @callback
    def _shift_changed(self, event: Event[EventStateChangedData]) -> None:
        """Flags the plan as outdated when the override or HA's next shift changes after it."""
        if self.state.get("plan_outdated") or not self._plan_still_ahead():
            return
        override = self._state_of(CONF_SHIFT_OVERRIDE)
        shift_start = self._next_shift_start()
        reason = None
        if override not in (None, *UNKNOWN_STATES) and override != self.state.get("planned_override"):
            reason = f"Shift override changed to {override}"
        elif shift_start and shift_start != self.state.get("planned_shift_start"):
            when = dt_util.parse_datetime(shift_start)
            reason = f"Next shift moved to {dt_util.as_local(when).strftime('%a %-I:%M %p') if when else shift_start}"
        if reason is None:
            return
        self.state["plan_outdated"] = True
        self.state["outdated_reason"] = reason
        self.hass.bus.async_fire(EVENT, {"type": EVENT_PLAN_OUTDATED, "reason": reason})
        self.hass.async_create_task(self._notify_outdated(reason))
        self._changed()

    def _plan_still_ahead(self) -> bool:
        """A plan exists and its wake-up hasn't happened yet (or it planned no alarm recently)."""
        last_plan = dt_util.parse_datetime(self.state.get("last_plan") or "")
        if last_plan is None:
            return False
        wake = dt_util.parse_datetime(self.state.get("wake_time") or "")
        if wake is not None:
            return wake > dt_util.utcnow()
        return dt_util.utcnow() - last_plan < timedelta(hours=18)

    async def _notify_outdated(self, reason: str) -> None:
        notify = (self.options.get(CONF_NOTIFY) or "").strip()
        if not notify or not self.options.get(CONF_REPLAN_ALERT, True):
            return
        domain, _, service = notify.partition(".")
        try:
            await self.hass.services.async_call(
                domain,
                service,
                {
                    "title": "Alarms may be wrong",
                    "message": f"{reason} after you planned. Tap to re-plan.",
                    "data": {
                        "tag": "bedtime_bridge_replan",
                        "url": REPLAN_URL,
                        "actions": [{"action": "URI", "title": "Re-plan now", "uri": REPLAN_URL}],
                    },
                },
                blocking=False,
            )
        except HomeAssistantError as err:
            _LOGGER.warning("Bedtime Bridge couldn't send the re-plan notification: %s", err)

    async def _snoozed(self, data: dict[str, Any]) -> None:
        if data.get("test"):
            await self._wake(CONF_SNOOZE_HELPER)
            self._event(MSG_SNOOZED, test=True)
            return
        self.state["snoozed_until"] = data.get("rings_again")
        self.state["snooze_count"] = int(self.state.get("snooze_count") or 0) + 1
        if data.get("rings_again"):
            self.state["alarm_time"] = data["rings_again"]
        await self._wake(CONF_SNOOZE_HELPER)
        self._event(MSG_SNOOZED)

    async def _stopped(self, data: dict[str, Any]) -> None:
        if data.get("test"):
            # A test alarm runs the real routines but leaves tonight's plan alone.
            await self._wake(CONF_STOP_HELPER)
            self._event(MSG_STOPPED, test=True)
            return
        remaining = data.get("alarm_times") or []
        self.state["snoozed_until"] = None
        self.state["alarm_times"] = remaining
        self.state["alarm_time"] = remaining[0] if remaining else None
        if not remaining:
            self.state["alarm_cause"] = "noalarm"
        await self._wake(CONF_STOP_HELPER)
        self._event(MSG_STOPPED)

    async def _cancelled(self, data: dict[str, Any]) -> None:
        self.state.update(empty_state())
        self._event(MSG_CANCELLED)

    async def _bedtime(self, data: dict[str, Any]) -> dict[str, Any]:
        """Starts the bedtime routine by turning on its helper, only when you're home."""
        at_home = self.is_home()
        helper = self.options.get(CONF_BEDTIME_HELPER)
        started = False
        if helper and (at_home or not self.options.get(CONF_HOME_ONLY, True)):
            started = await self._turn_on(helper)
        self.state["skipped_away"] = bool(helper) and not started and not at_home
        self._event(MSG_BEDTIME, started=started, at_home=at_home)
        return {"started": started, "at_home": at_home}

    async def _leave_by(self, data: dict[str, Any]) -> None:
        self.state["leave_by"] = data.get("leave_by")
        if data.get("drive_minutes") is not None:
            self.state["drive_minutes"] = data["drive_minutes"]
        self._event(MSG_LEAVE_BY, note=data.get("note"))

    # MARK: Effects

    def is_home(self) -> bool:
        """True when any presence entity is home (or unknown); True when none are set."""
        entity_ids = self.options.get(CONF_PRESENCE) or []
        if isinstance(entity_ids, str):
            entity_ids = [entity_ids]
        if not entity_ids:
            return True
        for entity_id in entity_ids:
            state = self.hass.states.get(entity_id)
            if state is None or state.state in UNKNOWN_STATES or state.state in HOME_STATES:
                return True
        return False

    def _away_blocks(self) -> bool:
        return bool(self.options.get(CONF_HOME_ONLY, True)) and not self.is_home()

    async def _wake(self, helper_option: str) -> None:
        """Turns on the snooze/stop helper unless the user picked events only, or is away."""
        self.state["skipped_away"] = self._away_blocks()
        if self.state["skipped_away"] or self.options.get(CONF_WAKE_ACTION, WAKE_BOTH) == WAKE_EVENTS:
            return
        entity_id = self.options.get(helper_option)
        if entity_id:
            await self._turn_on(entity_id)

    async def _turn_on(self, entity_id: str) -> bool:
        try:
            await self.hass.services.async_call("homeassistant", "turn_on", {"entity_id": entity_id}, blocking=False)
        except HomeAssistantError as err:
            # A renamed or deleted helper must not stop the event and state update.
            _LOGGER.warning("Bedtime Bridge couldn't turn on %s: %s", entity_id, err)
            return False
        return True

    def _event(self, kind: str, **extra: Any) -> None:
        self.state["last_event"] = kind
        self.state["last_event_time"] = dt_util.utcnow().isoformat()
        # Snooze/stop events are skipped with "helpers only" and while you're away (so event
        # automations don't light an empty house); plan/cancel/leave-by/bedtime always fire.
        helpers_only = self.options.get(CONF_WAKE_ACTION) == WAKE_HELPERS
        wake_event = kind in (MSG_SNOOZED, MSG_STOPPED)
        if not (wake_event and (helpers_only or self.state.get("skipped_away"))):
            self.hass.bus.async_fire(
                EVENT,
                {
                    "type": kind,
                    "alarm_cause": self.state.get("alarm_cause"),
                    "alarm_time": self.state.get("alarm_time"),
                    "wake_time": self.state.get("wake_time"),
                    "alarm_times": self.state.get("alarm_times"),
                    "label": self.state.get("label"),
                    "leave_by": self.state.get("leave_by"),
                    "snooze_count": self.state.get("snooze_count"),
                    **extra,
                },
            )
        self._changed()
