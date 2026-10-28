"""State kept for the phone, and handling of the app's webhook messages."""

from __future__ import annotations

import logging
from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import Event, EventStateChangedData, HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import (
    async_call_later,
    async_track_point_in_utc_time,
    async_track_state_change_event,
    async_track_time_interval,
)
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import ladder as ldr
from .const import (
    BED_EMPTY_SECONDS,
    CMD_ARM,
    CMD_BEDTIME,
    CMD_DISARM,
    CMD_MORNING,
    COMMAND_TAG,
    COMMANDS,
    LADDER_SETTINGS,
    CONF_AWAKE_HELPER,
    CONF_BED_SENSOR,
    CONF_BEDTIME_HELPER,
    CONF_CURTAIN_OFFSET,
    CONF_EXIT_LATCH,
    CONF_HOME_CHECKS,
    CONF_HOME_ONLY,
    CONF_NOTIFY,
    CONF_PHONE_COMMANDS,
    CONF_PRESENCE,
    CONF_REARM_MINUTES,
    CONF_REPLAN_ALERT,
    CONF_RERUN_MINUTES,
    CONF_CALENDAR,
    CONF_EARLY_HELPER,
    CONF_LADDER_SHIFT_TYPES,
    CONF_SHIFT_OVERRIDE,
    CONF_SHIFT_SENSOR,
    CONF_SHIFT_TYPES,
    CONF_SLEEP_IN,
    CONF_SNOOZE_HELPER,
    CONF_STOP_HELPER,
    CONF_WAKE_ACTION,
    CONF_WEATHER,
    DEFAULT_CURTAIN_OFFSET,
    DEFAULT_REARM_MINUTES,
    DEFAULT_RERUN_MINUTES,
    DEFAULT_LADDER_SHIFT_TYPES,
    DEFAULT_WORK_BUFFER,
    DOMAIN,
    EVENT,
    EVENT_PLAN_OUTDATED,
    EVENT_REARMED,
    EVENT_RERUN,
    HOME_STATES,
    MSG_BEDTIME,
    MSG_BEDTIME_UNDONE,
    MSG_COMMAND_RAN,
    MSG_MORNING_CHANGED,
    MSG_CANCELLED,
    MSG_CONTEXT,
    MSG_FORECAST,
    MSG_HOME_CHECK,
    MSG_LEAVE_BY,
    MSG_PLAN_FAILED,
    MSG_PLANNED,
    MSG_SKIPPED,
    MSG_SNOOZED,
    MSG_STOPPED,
    MSG_TEMP_SNOOZED,
    MSG_TEMP_STOPPED,
    MSG_UNSKIPPED,
    MSG_UP_CHECK,
    REARM_GIVE_UP_HOURS,
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
        # The wake routine (stop helper, Good Morning) already ran for this series (item 9).
        "routine_ran": False,
        "last_event": None,
        "last_event_time": None,
        "skipped_away": False,
        "plan_outdated": False,
        "outdated_reason": None,
    }


def plan_record() -> dict[str, Any]:
    """Kept across new plans and cancels: when the phone last planned, why it failed, and the
    last finished morning's snooze total."""
    return {"last_plan": None, "plan_error": None, "undone_at": None, "snoozes_last_morning": None}


def pending_record() -> dict[str, Any]:
    """Kept across new plans too, and across restarts: a re-arm waiting for you to get back
    into bed, a shift override to put back after a skipped morning, and when the regular
    alarms began (so a trip out of the bedroom before them isn't read as being up)."""
    return {
        "rearm_since": None,
        "rearm_until": None,
        "rerun_since": None,
        "rerun_until": None,
        "skip_restore_to": None,
        "skip_restore_at": None,
        "series_start": None,
    }


def _command_tag(message: str) -> str:
    return f"{COMMAND_TAG}_{message.lower()}"


def _time(value: Any) -> datetime | None:
    return dt_util.parse_datetime(value) if isinstance(value, str) else None


class BedtimeBridge:
    """One paired phone: its latest plan, alarm events and the settings it reads back."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self.state: dict[str, Any] = {**empty_state(), **plan_record(), **pending_record()}
        # None means "not set yet"; filled from the app's own settings on its first plan.
        self.settings: dict[str, int | None] = {}
        self._store: Store[dict[str, Any]] = Store(hass, STORAGE_VERSION, f"{DOMAIN}.{entry.entry_id}")
        self._bed_unsubs: dict[str, list[Callable[[], None]]] = {}
        # When you got back into bed, per kind, carried across the sensor's short dropouts.
        self._in_bed_since: dict[str, datetime] = {}
        # Command pushes still showing on the phone, cleared once the shortcut has run.
        self._pending_commands: set[str] = set()
        self._restore_unsub: Callable[[], None] | None = None
        self._ladder_unsub: Callable[[], None] | None = None

    @property
    def options(self) -> dict[str, Any]:
        return {**self.entry.data, **self.entry.options}

    def setting_keys(self) -> list[str]:
        """Built-in settings plus one lead time per configured shift type."""
        shifts = shift_types(self.options.get(CONF_SHIFT_TYPES))
        return list(SETTINGS) + list(LADDER_SETTINGS) + [f"{SHIFT_LEAD_PREFIX}{name}" for name in shifts]

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.state = {**empty_state(), **plan_record(), **pending_record(), **stored.get("state", {})}
        self.settings = stored.get("settings", {})

    @callback
    def async_start(self) -> None:
        """Watches the shift override and shift sensor for changes after a plan."""
        watched = [e for e in (self.options.get(CONF_SHIFT_OVERRIDE), self.options.get(CONF_SHIFT_SENSOR)) if e]
        if watched:
            self.entry.async_on_unload(async_track_state_change_event(self.hass, watched, self._shift_changed))
        self.entry.async_on_unload(self._cancel_timers)
        # Picks up a re-arm or an override restore that was waiting when HA restarted.
        self._watch_bed("rearm")
        self._watch_bed("rerun")
        self._schedule_skip_restore()
        # The ladder: recompute once loaded (keeping a stored one inside its lock), then check the
        # forecast every 15 minutes before leave-by.
        self.hass.async_create_task(self._recompute_ladder())
        self.entry.async_on_unload(async_track_time_interval(self.hass, self._weather_tick, timedelta(minutes=15)))
    def _save(self) -> None:
        self._store.async_delay_save(lambda: {"state": self.state, "settings": self.settings}, 1)

    def _changed(self) -> None:
        self._save()
        async_dispatcher_send(self.hass, signal_update(self.entry.entry_id))

    def set_setting(self, key: str, value: int) -> None:
        self.settings[key] = value
        self._changed()
        if key in LADDER_SETTINGS:
            self.hass.async_create_task(self._recompute_ladder())

    def setting_value(self, key: str) -> int | None:
        """A setting's value, or the ladder setting's default."""
        value = self.settings.get(key)
        if value is None and key in LADDER_SETTINGS:
            return LADDER_SETTINGS[key][4]
        return value

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
        for key in LADDER_SETTINGS:
            flat[key] = int(self.setting_value(key))
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
            MSG_SKIPPED: self._skipped,
            MSG_UNSKIPPED: self._unskipped,
            MSG_TEMP_SNOOZED: self._temporary_snoozed,
            MSG_TEMP_STOPPED: self._temporary_stopped,
            MSG_HOME_CHECK: self._home_check,
            MSG_BEDTIME_UNDONE: self._bedtime_undone,
            MSG_COMMAND_RAN: self._command_ran,
        }.get(kind)
        if handler is None:
            return {"error": f"unknown message type: {kind}"}
        result = await handler(data) or {}
        if kind in (MSG_PLANNED, MSG_CANCELLED, MSG_SKIPPED, MSG_UNSKIPPED, MSG_BEDTIME_UNDONE):
            await self._recompute_ladder()
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
        self.state["ladder_plan"] = data.get("ladder") or {}
        if (data.get("ladder") or {}).get("work_buffer_minutes") is not None:
            self.state["work_buffer_minutes"] = int(data["ladder"]["work_buffer_minutes"])
        # Bedtime ran again (by hand, or the nudge): no need to wait for you to get into bed.
        self._end_bed("rerun")
        self.state["planned_override"] = self._state_of(CONF_SHIFT_OVERRIDE)
        self.state["planned_shift_start"] = self._next_shift_start()
        times = sorted(t for t in (_time(v) for v in self.state.get("alarm_times") or []) if t)
        self.state["series_start"] = times[0].isoformat() if times else None
        await self._sync_sleep_in()
        # The phone reports a plan only once its alarms are scheduled, so with app alarms this
        # means they're really set; in Clock app mode the shortcut still has to make them.
        has_alarm = data.get("has_alarm", bool(data.get("alarm_times")))
        if not has_alarm:
            outcome = "no_alarm"
        elif data.get("alarm_style") == "clock":
            outcome = "planned_for_clock"
        else:
            outcome = "alarms_set"
        self._event(MSG_PLANNED, last_event=outcome, alarms_set=outcome == "alarms_set")

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
        if latch is not None and latch.state == "on" and self._latched_this_morning(latch.last_changed):
            return True
        if bed is not None and bed.state == "off":
            return (dt_util.utcnow() - bed.last_changed).total_seconds() >= BED_EMPTY_SECONDS
        return False

    def _latched_this_morning(self, latched_at: datetime) -> bool:
        """The door only proves you're up if it opened once the alarms began: a trip out for
        the trash (a temporary alarm, before them) leaves the latch on but you back in bed."""
        start = _time(self.state.get("series_start"))
        return start is None or latched_at >= start

    async def _plan_failed(self, data: dict[str, Any]) -> None:
        """The phone couldn't plan. The previous plan's alarms may still be set."""
        self.state["plan_error"] = data.get("error") or "unknown error"
        self._event(MSG_PLAN_FAILED, error=self.state["plan_error"])

    # MARK: Leave-by backstop ladder (item 6)

    def _ladder_offsets(self) -> ldr.Offsets:
        """The settings, or the last valid ladder when they cross (early > deadline > late)."""
        offsets = ldr.Offsets(
            early=int(self.setting_value("rung_early_minutes")),
            deadline=int(self.setting_value("rung_deadline_minutes")),
            late=int(self.setting_value("rung_late_minutes")),
            first_day_back=int(self.setting_value("first_day_back_minutes")),
        )
        if offsets.valid:
            self.state["ladder_offsets"] = offsets.as_dict()
            return offsets
        _LOGGER.warning(
            "Bedtime Bridge ladder settings cross (early %s, deadline %s, late %s); keeping the last valid ladder",
            offsets.early, offsets.deadline, offsets.late,
        )
        return ldr.Offsets.from_dict(self.state.get("ladder_offsets"))

    @staticmethod
    def _ladder_locked(ladder: dict[str, Any], now: datetime) -> bool:
        """From the early rung until 60 minutes after the late rung, nothing recomputes it."""
        if ladder.get("status") != ldr.STATUS_ARMED:
            return False
        early = _time((ladder.get("times") or {}).get("early"))
        late = _time((ladder.get("times") or {}).get("late"))
        return early is not None and late is not None and early <= now < late + ldr.LADDER_TAIL

    async def _recompute_ladder(self) -> None:
        """Works out the ladder for the next morning with a leave-by. Inside the morning lock it
        stays as it is; item 3 and worse weather or traffic move it through their own paths."""
        now = dt_util.utcnow()
        ladder = self.state.get("ladder") or {}
        if self._ladder_locked(ladder, now):
            self._schedule_ladder_rollover()
            return
        offsets = self._ladder_offsets()
        morning, status, reason = await self._ladder_morning(now, offsets)
        if morning is None:
            if status == "keep":
                if ladder:
                    self._schedule_ladder_rollover()
                    return
                status, reason = ldr.STATUS_FAULT, reason
            self._set_ladder({"status": status, "reason": reason, "morning": None, "times": {}}, None)
            return
        delay = self._ladder_delay_for(morning.key)
        earlier = ladder.get("earlier_minutes", 0) if ladder.get("morning") == morning.key else 0
        base = ldr.rung_times(morning.leave_by, offsets, morning.first_day_back, delay.get("minutes", 0) - earlier)
        times = ldr.not_in_past(base, now)
        self._set_ladder({
            "status": ldr.STATUS_ARMED,
            "reason": None,
            "morning": morning.key,
            "kind": morning.kind,
            "times": {rung: when.isoformat() for rung, when in times.items()},
            "leave_by": morning.leave_by.isoformat(),
            "leave_by_source": morning.leave_by_source,
            "first_day_back": morning.first_day_back,
            "shift_start": morning.shift_start.isoformat() if morning.shift_start else None,
            "appointment": morning.appointment,
            "appointment_start": morning.appointment_start.isoformat() if morning.appointment_start else None,
            "delay_minutes": delay.get("minutes", 0),
            "changed_by": delay.get("changed_by"),
            "change_reason": delay.get("reason"),
            "weather_extra_minutes": morning.weather_extra_minutes + (ladder.get("weather_minutes", 0) if earlier else 0),
            "condition": (ladder.get("condition") if earlier else None) or morning.condition,
            "earlier_minutes": earlier,
            "weather_minutes": ladder.get("weather_minutes", 0) if earlier else 0,
            "traffic_minutes": ladder.get("traffic_minutes", 0) if earlier else 0,
        }, morning.key)

    def _set_ladder(self, ladder: dict[str, Any], morning: str | None) -> None:
        """Stores the ladder; saves and updates the entities only when it changed."""
        changed = ladder != self.state.get("ladder")
        self.state["ladder"] = ladder
        self._ladder_cleanup(morning)
        self._schedule_ladder_rollover()
        if changed:
            self._changed()

    async def _ladder_morning(self, now: datetime, offsets: ldr.Offsets) -> tuple[ldr.Morning | None, str | None, str | None]:
        """The morning the ladder is for, or why there isn't one ("keep": hold the stored ladder)."""
        plan = self.state.get("ladder_plan") or {}
        shift_morning: ldr.Morning | None = None
        status, reason = ldr.STATUS_NO_SHIFT, "No shift on the calendar"
        sensor = self.hass.states.get(self.options.get(CONF_SHIFT_SENSOR) or "")
        if sensor is None or sensor.state in UNKNOWN_STATES:
            status, reason = "keep", "Shift sensor unavailable"
        else:
            next_start = _time(sensor.attributes.get("next_shift_start"))
            shift_type = sensor.attributes.get("effective_shift") or sensor.attributes.get("next_shift_type")
            covered = [t.lower() for t in (self.options.get(CONF_LADDER_SHIFT_TYPES) or DEFAULT_LADDER_SHIFT_TYPES)]
            if self._state_of(CONF_SHIFT_OVERRIDE) == "Off":
                status, reason = ldr.STATUS_OVERRIDE_OFF, "Shift override is Off"
            elif sensor.attributes.get("deadline_source") == "leave":
                status, reason = ldr.STATUS_LEAVE, "Leave day"
            elif next_start is None:
                status, reason = ldr.STATUS_NO_SHIFT, "No shift on the calendar"
            elif str(shift_type or "").lower() not in covered:
                status, reason = ldr.STATUS_UNCOVERED, f"{shift_type or 'This shift'} mornings have no ladder"
            else:
                buffer = int(self.state.get("work_buffer_minutes") or DEFAULT_WORK_BUFFER)
                calendar = ldr.calendar_leave_by(next_start, int(self.setting_value("fallback_drive_minutes")), buffer)
                planned = plan.get("type") == "shift" and ldr.same_morning(_time(plan.get("shift_start")), next_start)
                leave_by, source, warning = ldr.pick_leave_by(_time(plan.get("leave_by")) if planned else None, calendar)
                if warning:
                    _LOGGER.warning("Bedtime Bridge ladder: %s", warning)
                if planned and plan.get("first_day_back") is not None:
                    first_day_back = bool(plan["first_day_back"])
                else:
                    first_day_back = await self._first_day_back(next_start)
                shift_morning = ldr.Morning(
                    "shift", leave_by, source, first_day_back, shift_start=next_start,
                    weather_extra_minutes=int(plan.get("weather_extra_minutes") or 0) if planned else 0,
                    condition=plan.get("condition") if planned else None,
                )
        appointment: ldr.Morning | None = None
        if plan.get("type") == "appointment" and _time(plan.get("leave_by")):
            appointment = ldr.Morning(
                "appointment", _time(plan["leave_by"]), "plan", False,
                appointment=plan.get("appointment"), appointment_start=_time(plan.get("appointment_start")),
                weather_extra_minutes=int(plan.get("weather_extra_minutes") or 0), condition=plan.get("condition"),
            )

        def finished(morning: ldr.Morning) -> bool:
            delay = self._ladder_delay_for(morning.key).get("minutes", 0)
            late = ldr.rung_times(morning.leave_by, offsets, morning.first_day_back, delay)["late"]
            return late + ldr.LADDER_TAIL <= now

        open_mornings = [m for m in (shift_morning, appointment) if m and not finished(m)]
        if open_mornings:
            return min(open_mornings, key=lambda m: m.leave_by), None, None
        if shift_morning or appointment:
            return None, ldr.STATUS_DONE, "This morning's ladder is over"
        return None, status, reason

    async def _first_day_back(self, shift_start: datetime) -> bool:
        """No shift the day before (a day off, or leave). Read from the work calendar when the app
        didn't say; if that fails, assume a first day back (fail early, not late)."""
        day = dt_util.as_local(shift_start).date()
        cache: dict[str, bool] = self.state.setdefault("ladder_first_day_back", {})
        if day.isoformat() in cache:
            return cache[day.isoformat()]
        calendar = self.options.get(CONF_CALENDAR)
        if not calendar or self.hass.states.get(calendar) is None:
            return True
        start = dt_util.start_of_local_day(day) - timedelta(days=1)
        try:
            response = await self.hass.services.async_call(
                "calendar",
                "get_events",
                {"entity_id": calendar, "start_date_time": start.isoformat(), "end_date_time": (start + timedelta(days=1)).isoformat()},
                blocking=True,
                return_response=True,
            )
        except Exception as err:  # noqa: BLE001 - any failure means "assume first day back"
            _LOGGER.warning("Bedtime Bridge couldn't read %s for first day back: %s", calendar, err)
            return True
        events = ((response or {}).get(calendar) or {}).get("events") or []
        names = [n.lower() for n in shift_types(self.options.get(CONF_SHIFT_TYPES))]
        worked = any(any(n in str(e.get("summary") or "").lower() for n in names) for e in events)
        cache.clear()
        cache[day.isoformat()] = not worked
        return not worked

    def _ladder_delay_for(self, morning: str) -> dict[str, Any]:
        delay = self.state.get("ladder_delay") or {}
        return delay if delay.get("morning") == morning else {}

    def _ladder_cleanup(self, morning: str | None) -> None:
        """A delay belongs to its morning; once another morning's ladder is up, it goes."""
        if (self.state.get("ladder_delay") or {}).get("morning") not in (None, morning):
            self.state["ladder_delay"] = None

    @callback
    def _schedule_ladder_rollover(self) -> None:
        """Once the late rung is 60 minutes past, this morning is over: roll to the next one."""
        if self._ladder_unsub:
            self._ladder_unsub()
            self._ladder_unsub = None
        late = _time(((self.state.get("ladder") or {}).get("times") or {}).get("late"))
        if late is None:
            return
        due = late + ldr.LADDER_TAIL
        if due <= dt_util.utcnow():
            return
        self._ladder_unsub = async_track_point_in_utc_time(self.hass, self._ladder_rollover, due)

    @callback
    def _ladder_rollover(self, _now: datetime) -> None:
        self._ladder_unsub = None
        self.state["ladder_delay"] = None
        if self.state.get("ladder"):
            self.state["ladder"]["status"] = ldr.STATUS_DONE
        self.hass.async_create_task(self._recompute_ladder())

    def _move_ladder(self, minutes: int, *, rungs_ahead_only: bool) -> None:
        """Shifts the stored rungs (negative = earlier). Earlier moves touch only rungs still
        ahead; anything landing in the past is published as now + 60 s."""
        ladder = self.state.get("ladder") or {}
        if ladder.get("status") != ldr.STATUS_ARMED or not minutes:
            return
        now = dt_util.utcnow()
        times = {}
        for rung, value in (ladder.get("times") or {}).items():
            when = _time(value)
            if when is None or (rungs_ahead_only and when <= now):
                times[rung] = value
                continue
            times[rung] = max(when + timedelta(minutes=minutes), now + ldr.PAST_RUNG_LEAD).isoformat()
        ladder["times"] = times
        self._schedule_ladder_rollover()

    def change_morning_ladder(self, delay_minutes: int, changed_by: str | None, reason: str | None) -> None:
        """Item 3: the backstops move by the same amount as the wake-up, later or earlier. The
        delay persists through recomputes that morning and is cleared when its ladder ends."""
        ladder = self.state.get("ladder") or {}
        if ladder.get("status") != ldr.STATUS_ARMED or not delay_minutes:
            return
        current = self._ladder_delay_for(ladder["morning"])
        total = int(current.get("minutes", 0)) + int(delay_minutes)
        self.state["ladder_delay"] = {"morning": ladder["morning"], "minutes": total, "changed_by": changed_by, "reason": reason}
        self._move_ladder(int(delay_minutes), rungs_ahead_only=False)
        ladder.update(delay_minutes=total, changed_by=changed_by, change_reason=reason)
        self._changed()

    def _ladder_earlier(self, minutes: int, kind: str, condition: str | None = None) -> None:
        """Worse weather or traffic: the rungs still ahead move earlier, never later."""
        ladder = self.state.get("ladder") or {}
        if minutes <= 0 or ladder.get("status") != ldr.STATUS_ARMED:
            return
        self._move_ladder(-minutes, rungs_ahead_only=True)
        ladder["earlier_minutes"] = ladder.get("earlier_minutes", 0) + minutes
        ladder[f"{kind}_minutes"] = ladder.get(f"{kind}_minutes", 0) + minutes
        if kind == "weather":
            ladder["weather_extra_minutes"] = ladder.get("weather_extra_minutes", 0) + minutes
            ladder["condition"] = condition
        _LOGGER.info("Bedtime Bridge ladder moved %s min earlier for %s", minutes, condition or kind)
        self._changed()

    def _traffic_moved(self, new_leave_by: datetime | None) -> None:
        """The phone rechecked the drive when an alarm was stopped. A longer drive (an earlier
        leave-by) moves the rungs earlier by the difference not already applied."""
        ladder = self.state.get("ladder") or {}
        planned = _time(ladder.get("leave_by"))
        if new_leave_by is None or planned is None or ladder.get("leave_by_source") != "plan":
            return
        needed = int((planned - new_leave_by).total_seconds() // 60)
        self._ladder_earlier(needed - ladder.get("traffic_minutes", 0), "traffic")

    async def _weather_tick(self, _now: datetime) -> None:
        """Every 15 minutes from 2 hours before the early rung until leave-by: if the drive's
        forecast is worse than the plan allowed for, move the rungs still ahead earlier."""
        ladder = self.state.get("ladder") or {}
        if ladder.get("status") != ldr.STATUS_ARMED:
            return
        now = dt_util.utcnow()
        early, leave_by = _time(ladder["times"].get("early")), _time(ladder.get("leave_by"))
        if early is None or leave_by is None or not (early - timedelta(hours=2) <= now < leave_by):
            return
        weather = self.options.get(CONF_WEATHER)
        if not weather or self.hass.states.get(weather) is None:
            return
        try:
            response = await self.hass.services.async_call(
                "weather", "get_forecasts", {"entity_id": weather, "type": "hourly"}, blocking=True, return_response=True
            )
        except Exception as err:  # noqa: BLE001 - a missed check is retried in 15 minutes
            _LOGGER.debug("Bedtime Bridge ladder forecast check failed: %s", err)
            return
        forecast = ((response or {}).get(weather) or {}).get("forecast") or []
        plan = self.state.get("ladder_plan") or {}
        minutes = plan.get("weather_minutes")
        if not minutes:
            extra = int(self.setting_value("weather_extra_minutes") or 15)
            minutes = {condition: extra for condition in ldr.DEFAULT_WEATHER_CONDITIONS}
        arrive = _time(ladder.get("shift_start")) or _time(ladder.get("appointment_start")) or leave_by + timedelta(hours=1)
        worst, condition = ldr.worst_weather(forecast, leave_by, arrive, minutes, plan.get("freezing_at"))
        planned_extra = int(plan.get("weather_extra_minutes") or 0) if ladder.get("leave_by_source") == "plan" else 0
        self._ladder_earlier(worst - planned_extra - ladder.get("weather_minutes", 0), "weather", condition)

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
        """Recomputes the ladder, and flags the plan as outdated when the override or HA's next
        shift changes after it."""
        self.hass.async_create_task(self._recompute_ladder())
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
        if self.state.get("routine_ran") or self._state_of(CONF_SNOOZE_HELPER) == "on":
            # Already up (the wake routine ran), or the fade is running: nothing to start.
            self.state["skipped_away"] = self._away_blocks()
        else:
            await self._wake(CONF_SNOOZE_HELPER)
        self._event(MSG_SNOOZED)

    async def _stopped(self, data: dict[str, Any]) -> None:
        if data.get("test"):
            # A test alarm runs the real routines but leaves tonight's plan alone.
            await self._wake(CONF_STOP_HELPER)
            self._event(MSG_STOPPED, test=True)
            return
        # all: the slide-and-hold that ends every alarm left in this wake-up (item 2).
        stop_all = bool(data.get("all"))
        remaining = [] if stop_all else data.get("alarm_times") or []
        self.state["snoozed_until"] = None
        self.state["alarm_times"] = remaining
        self.state["alarm_time"] = remaining[0] if remaining else None
        if not remaining:
            self.state["alarm_cause"] = "noalarm"
            self._end_morning()
        # early: ended from Tonight before any alarm rang (item 8), so the early helper runs.
        early = bool(data.get("early"))
        # The wake routine runs on the first stop of a wake-up only (item 9): Wake Sequence
        # treats its helper as a button, so every turn-on would re-run it.
        first = not self.state.get("routine_ran")
        if first:
            helper = CONF_EARLY_HELPER if early and self.options.get(CONF_EARLY_HELPER) else CONF_STOP_HELPER
            await self._wake(helper)
            self.state["routine_ran"] = True
        else:
            self.state["skipped_away"] = self._away_blocks()
        self._event(MSG_STOPPED, all=stop_all, early=early, routine=first)
        if first and not self.state.get("skipped_away"):
            # The phone's own morning shortcut (disarm, good morning, Focus off) used to run
            # from the Clock app; app alarms don't trigger that, so this push does instead.
            await self._command(CMD_MORNING)

    @callback
    def _end_morning(self) -> None:
        """The wake-up is over (every alarm stopped, ended all, or changed): this morning's
        snoozes become Snoozes last morning and the count starts again at 0."""
        self.state["snoozes_last_morning"] = int(self.state.get("snooze_count") or 0)
        self.state["snooze_count"] = 0

    # MARK: Temporary alarms

    async def _temporary_snoozed(self, data: dict[str, Any]) -> None:
        """Nothing in the house changes: no ramp, no snooze count."""
        self._event(MSG_TEMP_SNOOZED, rings_again=data.get("rings_again"))

    async def _temporary_stopped(self, data: dict[str, Any]) -> None:
        """Up for a moment, then back to bed. Awake For Day, Sleep In and the regular alarms
        stay. With "disarm", the phone disarms now and re-arms once you're back in bed."""
        house_alarm = data.get("house_alarm")
        disarmed = False
        if house_alarm == "disarm" and self.is_home():
            disarmed = await self._command(CMD_DISARM)
        if disarmed:
            now = dt_util.utcnow()
            regular = sorted(t for t in (_time(v) for v in data.get("alarm_times") or []) if t and t > now)
            give_up = now + timedelta(hours=REARM_GIVE_UP_HOURS)
            self.state["rearm_since"] = now.isoformat()
            self.state["rearm_until"] = min([give_up, *regular[:1]]).isoformat()
            self._watch_bed("rearm")
        self._event(MSG_TEMP_STOPPED, house_alarm=house_alarm, disarmed=disarmed)

    # MARK: Back in bed

    @callback
    def _watch_bed(self, kind: str) -> None:
        """Waits for you to be back in bed (occupied for the kind's delay, not counting the
        sensor's short dropouts) before its deadline: "rearm" re-arms the house, "rerun" runs
        bedtime again."""
        self._cancel_bed(kind)
        since = _time(self.state.get(f"{kind}_since"))
        until = _time(self.state.get(f"{kind}_until"))
        bed = self.options.get(CONF_BED_SENSOR)
        if since is None:
            return
        if not bed or until is None or until <= dt_util.utcnow():
            self._end_bed(kind)
            return
        check = lambda *_: self._bed_check(kind)  # noqa: E731
        self._bed_unsubs[kind] = [
            async_track_state_change_event(self.hass, [bed], callback(check)),
            async_track_point_in_utc_time(self.hass, callback(check), until),
        ]
        self._bed_check(kind)

    @callback
    def _bed_check(self, kind: str) -> None:
        since = _time(self.state.get(f"{kind}_since"))
        until = _time(self.state.get(f"{kind}_until"))
        if since is None:
            return
        now = dt_util.utcnow()
        if until is None or now >= until:
            # Not back in bed in time: leave it to the morning (re-arming or starting bedtime
            # as you get up would be worse than doing nothing).
            self._end_bed(kind)
            return
        bed = self.hass.states.get(self.options.get(CONF_BED_SENSOR) or "")
        if bed is None:
            return
        if bed.state != "on":
            # Out of bed only once it has been empty for a while: the sensor drops out for up
            # to ~19 s while you're in it, which mustn't start the wait over.
            empty_at = bed.last_changed + timedelta(seconds=BED_EMPTY_SECONDS)
            if now >= empty_at:
                self._in_bed_since.pop(kind, None)
            elif kind in self._in_bed_since:
                self._bed_unsubs.setdefault(kind, []).append(
                    async_track_point_in_utc_time(self.hass, callback(lambda _now: self._bed_check(kind)), empty_at)
                )
            return
        started = self._in_bed_since.setdefault(kind, max(bed.last_changed, since))
        minutes = self.options.get(CONF_REARM_MINUTES) if kind == "rearm" else self.options.get(CONF_RERUN_MINUTES)
        default = DEFAULT_REARM_MINUTES if kind == "rearm" else DEFAULT_RERUN_MINUTES
        delay = timedelta(minutes=int(minutes or default))
        in_bed_for = now - started
        if in_bed_for >= delay:
            self._end_bed(kind)
            self.hass.async_create_task(self._back_in_bed(kind))
            return
        self._bed_unsubs.setdefault(kind, []).append(
            async_call_later(self.hass, delay - in_bed_for, callback(lambda _now: self._bed_check(kind)))
        )

    async def _back_in_bed(self, kind: str) -> None:
        if kind == "rearm":
            self._event(EVENT_REARMED, armed=await self._command(CMD_ARM))
        else:
            self._event(EVENT_RERUN, sent=await self._command(CMD_BEDTIME))

    @callback
    def _end_bed(self, kind: str) -> None:
        self._cancel_bed(kind)
        if self.state.get(f"{kind}_since") is not None:
            self.state[f"{kind}_since"] = None
            self.state[f"{kind}_until"] = None
            self._changed()

    @callback
    def _cancel_bed(self, kind: str) -> None:
        self._in_bed_since.pop(kind, None)
        for unsub in self._bed_unsubs.pop(kind, []):
            unsub()

    @callback
    def _cancel_timers(self) -> None:
        for kind in list(self._bed_unsubs):
            self._cancel_bed(kind)
        if self._restore_unsub:
            self._restore_unsub()
            self._restore_unsub = None
        if self._ladder_unsub:
            self._ladder_unsub()
            self._ladder_unsub = None

    # MARK: Undo bedtime

    async def _bedtime_undone(self, data: dict[str, Any]) -> None:
        """Up again after bedtime ran: alarms are off on the phone; here the house is
        disarmed, Awake For Day goes back on and Sleep In off. Once you're back in bed, bedtime
        runs again (RUN_BEDTIME, the same push the bedtime nudge sends)."""
        self.state.update(empty_state())
        now = dt_util.utcnow()
        self.state["undone_at"] = now.isoformat()
        self._end_bed("rearm")
        at_home = self.is_home()
        disarmed = await self._command(CMD_DISARM) if at_home else False
        awake = self.options.get(CONF_AWAKE_HELPER)
        if awake and at_home:
            await self._turn_on(awake)
        await self._set_sleep_in(False)
        if at_home:
            self.state["rerun_since"] = now.isoformat()
            self.state["rerun_until"] = (now + timedelta(hours=REARM_GIVE_UP_HOURS)).isoformat()
            self._watch_bed("rerun")
        self._event(MSG_BEDTIME_UNDONE, disarmed=disarmed)

    # MARK: Skipped mornings

    async def _skipped(self, data: dict[str, Any]) -> None:
        """Skipped the night before: that morning's wake-up doesn't exist. A skipped shift
        turns the shift override Off (which disarms the wake failsafe) until the shift has
        passed. Stopping alarms in the morning never does this."""
        self.state.update(empty_state())
        # Counts as tonight's plan, so the missing-plan check doesn't nag about the shift.
        self.state["last_plan"] = dt_util.utcnow().isoformat()
        self.state["plan_error"] = None
        override = self.options.get(CONF_SHIFT_OVERRIDE)
        current = self._state_of(CONF_SHIFT_OVERRIDE)
        failsafe_off = False
        if data.get("shift") and override and current not in (None, "Off", *UNKNOWN_STATES):
            start = _time(data.get("shift_start"))
            restore_at = (start + timedelta(hours=1)) if start else dt_util.utcnow() + timedelta(hours=18)
            self.state["skip_restore_to"] = current
            self.state["skip_restore_at"] = restore_at.isoformat()
            # Our own change: not a reason to flag the plan as out of date.
            self.state["planned_override"] = "Off"
            failsafe_off = await self._select(override, "Off")
            self._schedule_skip_restore()
        if data.get("sleep_in"):
            await self._set_sleep_in(True)
        self._event(MSG_SKIPPED, shift=data.get("shift"), failsafe_off=failsafe_off, sleep_in=bool(data.get("sleep_in")))

    async def _unskipped(self, data: dict[str, Any]) -> None:
        """Undo: the override goes back first, so the plan that follows sees the shift."""
        await self._restore_override()
        self._event(MSG_UNSKIPPED)

    @callback
    def _schedule_skip_restore(self) -> None:
        if self._restore_unsub:
            self._restore_unsub()
            self._restore_unsub = None
        restore_at = _time(self.state.get("skip_restore_at"))
        if restore_at is None or not self.state.get("skip_restore_to"):
            return
        if restore_at <= dt_util.utcnow():
            self.hass.async_create_task(self._restore_override())
            return
        self._restore_unsub = async_track_point_in_utc_time(self.hass, self._restore_due, restore_at)

    @callback
    def _restore_due(self, _now: datetime) -> None:
        self._restore_unsub = None
        self.hass.async_create_task(self._restore_override())

    async def _restore_override(self) -> None:
        """Puts the override back, unless you've changed it yourself since."""
        restore_to = self.state.get("skip_restore_to")
        self.state["skip_restore_to"] = None
        self.state["skip_restore_at"] = None
        if self._restore_unsub:
            self._restore_unsub()
            self._restore_unsub = None
        override = self.options.get(CONF_SHIFT_OVERRIDE)
        if restore_to and override and self._state_of(CONF_SHIFT_OVERRIDE) == "Off":
            self.state["planned_override"] = restore_to
            await self._select(override, restore_to)
        self._changed()

    async def _select(self, entity_id: str, option: str) -> bool:
        domain = entity_id.partition(".")[0]
        try:
            await self.hass.services.async_call(
                domain, "select_option", {"entity_id": entity_id, "option": option}, blocking=True
            )
        except HomeAssistantError as err:
            _LOGGER.warning("Bedtime Bridge couldn't set %s to %s: %s", entity_id, option, err)
            return False
        return True

    # MARK: Sleep In

    async def _sync_sleep_in(self) -> None:
        """Sleep In follows the plan: on when the first alarm is after the curtains would open
        (sunrise + offset), off when it's before. No alarm leaves it as it is (the bedtime
        shortcut asks). Only while you're home."""
        first = _time(self.state.get("series_start"))
        sun = self.hass.states.get("sun.sun")
        sunrise = _time(sun.attributes.get("next_rising")) if sun else None
        if first is None or sunrise is None:
            return
        offset = timedelta(minutes=int(self.options.get(CONF_CURTAIN_OFFSET) or DEFAULT_CURTAIN_OFFSET))
        await self._set_sleep_in(first > sunrise + offset)

    async def _set_sleep_in(self, on: bool) -> None:
        helper = self.options.get(CONF_SLEEP_IN)
        state = self.hass.states.get(helper or "")
        if not helper or not self.is_home() or (state is not None and state.state == ("on" if on else "off")):
            return
        try:
            await self.hass.services.async_call(
                "homeassistant", "turn_on" if on else "turn_off", {"entity_id": helper}, blocking=False
            )
        except HomeAssistantError as err:
            _LOGGER.warning("Bedtime Bridge couldn't set %s: %s", helper, err)

    # MARK: Away bedtime

    async def _home_check(self, data: dict[str, Any]) -> dict[str, Any]:
        """For the bedtime summary when you're away: anything at home that needs a look."""
        issues: list[str] = []
        entity_ids = self.options.get(CONF_HOME_CHECKS) or []
        for entity_id in [entity_ids] if isinstance(entity_ids, str) else entity_ids:
            if (issue := home_issue(self.hass.states.get(entity_id), entity_id)) is not None:
                issues.append(issue)
        return {"issues": issues, "checked": len(entity_ids)}

    # MARK: Phone commands

    async def _command(self, message: str) -> bool:
        """A push the phone's Shortcuts automation turns into a shortcut run (Set Disarm, Set
        Arm Stay, the morning shortcut). Off unless phone commands are turned on."""
        sent = await self._push(
            {
                "title": "Bedtime Bridge",
                "message": message,
                # Time-sensitive like the bedtime nudge's RUN_BEDTIME, which reaches the
                # Shortcuts trigger with the phone locked. One tag per command, so each can
                # be cleared on its own once its shortcut has run.
                "data": {"tag": _command_tag(message), "push": {"interruption-level": "time-sensitive"}},
            },
            message,
        )
        if sent:
            self._pending_commands.add(message)
        return sent

    async def _clear_command(self, message: str) -> None:
        """Takes a command's push off the phone once its shortcut has run."""
        if message in self._pending_commands:
            self._pending_commands.discard(message)
            await self._push({"message": "clear_notification", "data": {"tag": _command_tag(message)}}, message)

    async def _push(self, payload: dict[str, Any], what: str) -> bool:
        notify = (self.options.get(CONF_NOTIFY) or "").strip()
        if not notify or not self.options.get(CONF_PHONE_COMMANDS):
            return False
        domain, _, service = notify.partition(".")
        try:
            await self.hass.services.async_call(domain, service, payload, blocking=False)
        except HomeAssistantError as err:
            _LOGGER.warning("Bedtime Bridge couldn't send %s to the phone: %s", what, err)
            return False
        return True

    async def _command_ran(self, data: dict[str, Any]) -> None:
        """The shortcut a command asked for has run (its Report Shortcut Ran step). Outcome
        "already_done": the phone got the push but had nothing to do (Good Morning already ran)."""
        command = data.get("command")
        outcome = data.get("outcome") or "ran"
        if command in COMMANDS:
            await self._clear_command(command)
        self.state["last_command"] = {"command": command, "outcome": outcome, "time": dt_util.utcnow().isoformat()}
        self._event(MSG_COMMAND_RAN, command=command, outcome=outcome)

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
        # The bedtime shortcut's own step, so a RUN_BEDTIME push has done its job.
        await self._clear_command(CMD_BEDTIME)
        self._event(MSG_BEDTIME, started=started, at_home=at_home)
        return {"started": started, "at_home": at_home}

    async def _leave_by(self, data: dict[str, Any]) -> None:
        self._traffic_moved(_time(data.get("leave_by")))
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

    def _event(self, kind: str, last_event: str | None = None, **extra: Any) -> None:
        """Fires a bedtime_bridge event of type `kind`; Last event shows `last_event` when
        it says more than the type (a plan: alarms_set, planned_for_clock or no_alarm)."""
        self.state["last_event"] = last_event or kind
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


def home_issue(state: Any, entity_id: str) -> str | None:
    """"Garage Door is open", "Front Door Lock isn't responding", or None when it's fine."""
    name = state.attributes.get("friendly_name", entity_id) if state is not None else entity_id
    if state is None or state.state in UNKNOWN_STATES:
        return f"{name} isn't responding"
    domain = entity_id.partition(".")[0]
    if domain == "cover" and state.state in ("open", "opening", "closing"):
        return f"{name} is open"
    if domain == "lock" and state.state in ("unlocked", "unlocking", "open", "opening"):
        return f"{name} is unlocked"
    if domain == "lock" and state.state == "jammed":
        return f"{name} is jammed"
    if domain == "binary_sensor" and state.state == "on":
        wet = state.attributes.get("device_class") in ("moisture", "smoke", "gas", "carbon_monoxide", "safety", "problem")
        return f"{name} {'is reporting a problem' if wet else 'is open'}"
    return None

