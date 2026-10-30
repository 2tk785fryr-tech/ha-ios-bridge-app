"""State kept for the phone, and handling of the app's webhook messages."""

from __future__ import annotations

import logging
from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import Event, EventStateChangedData, HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import (
    async_call_later,
    async_track_point_in_utc_time,
    async_track_state_change_event,
    async_track_time_interval,
)
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import drivetime as dtm
from . import ladder as ldr
from . import timefmt, weekly
from .awake import NoAlarmMorning
from .liveactivity import LiveActivities
from .winddown import WindDown
from .const import (
    BED_EMPTY_SECONDS,
    CMD_ARM,
    CMD_BACK_TO_BED,
    CMD_NAP_END,
    CMD_PLAN_PREVIEW,
    CMD_MORNING_UPDATE,
    CMD_NAP_START,
    CMD_LEAVE_CHECK,
    CMD_BEDTIME,
    CMD_DISARM,
    CMD_MORNING,
    COMMAND_TAG,
    COMMAND_NAMES,
    COMMANDS,
    LADDER_SETTINGS,
    LEAVE_CHECK_TAIL_MINUTES,
    CONF_AWAKE_HELPER,
    CONF_NAP_HELPER,
    CONF_WIND_DOWN_HELPER,
    CONF_PHONE_BATTERY,
    CONF_PHONE_BATTERY_STATE,
    CONF_DRIVE_SOURCE,
    CONF_GOOGLE_KEY,
    CONF_MAPS_KEY,
    CONF_MAPS_KEY_ID,
    CONF_TOMTOM_KEY,
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
    CONF_COMPLETE_MINUTES,
    CONF_HOUSE_BACKSTOP,
    CONF_OLD_RUNGS,
    CONF_EARLY_HELPER,
    CONF_RESTART_AUTOMATIONS,
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
    DEFAULT_COMPLETE_MINUTES,
    DEFAULT_OLD_RUNGS,
    HOUSE_OLD,
    DEFAULT_LADDER_SHIFT_TYPES,
    DEFAULT_RESTART_AUTOMATIONS,
    RESTART_NOTIFICATION_TAGS,
    DEFAULT_WORK_BUFFER,
    DOMAIN,
    EVENT,
    EVENT_PLAN_OUTDATED,
    EVENT_ALARMS_MISSING,
    EVENT_CHANGE_REFUSED,
    EVENT_COMMAND_INCOMPLETE,
    EVENT_REARMED,
    EVENT_RERUN,
    HOME_STATES,
    MSG_BEDTIME,
    MSG_BEDTIME_UNDONE,
    MSG_COMMAND_RAN,
    MSG_MORNING_CHANGED,
    MSG_NAP_ENDED,
    MSG_PREVIEW,
    MSG_RESET,
    MSG_LIVE_ACTIVITY,
    MSG_AWAKE,
    MSG_WIND_DOWN,
    MSG_NAP_STARTED,
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
        # Phone shortcuts that reported Started and are expected to report Completed.
        self._command_unsubs: dict[str, Callable[[], None]] = {}
        # The leave checks still to send (item 17).
        self._leave_unsubs: list[Callable[[], None]] = []
        # Tonight's wind-down (v0.4.3 item 5).
        self.wind_down = WindDown(self)
        # Live Activities by Apple push (0.4.4).
        self.live = LiveActivities(self)
        # Mornings with no alarms (v0.4.6 item 2).
        self.awake = NoAlarmMorning(self)
        # Apple Maps' client keeps its access token between checks.
        self._maps: dtm.AppleMaps | None = None
        # RUN_MORNING_UPDATE timers for the morning Live Activity (v0.4.3 item 14).
        self._morning_unsubs: list[Callable[[], None]] = []
        # The weekly summary's timer (v0.4.3 item 15).
        self._weekly_unsub: Callable[[], None] | None = None

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
        timefmt.set_24h(bool(self.state.get("clock_24h")))

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
        self._schedule_leave_checks()
        for command in list(self.state.get("command_started") or {}):
            self._watch_command(command)
        # The ladder: recompute once loaded (keeping a stored one inside its lock), then check the
        # forecast every 15 minutes before leave-by.
        self.hass.async_create_task(self._recompute_ladder())
        self.entry.async_on_unload(async_track_time_interval(self.hass, self._weather_tick, timedelta(minutes=15)))
        self.wind_down.async_start()
        self.awake.async_start()
        presence = self.options.get(CONF_PRESENCE) or []
        if isinstance(presence, str):
            presence = [presence]
        if presence:
            self.entry.async_on_unload(async_track_state_change_event(self.hass, presence, self._morning_presence))
        self.entry.async_on_unload(self._cancel_morning_updates)
        self._schedule_weekly()
        self.entry.async_on_unload(lambda: self._weekly_unsub() if self._weekly_unsub else None)
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
            MSG_MORNING_CHANGED: self._morning_changed,
            MSG_NAP_STARTED: self._nap_started,
            MSG_NAP_ENDED: self._nap_ended,
            MSG_PREVIEW: self._preview,
            MSG_WIND_DOWN: self._wind_down_action,
            MSG_RESET: self._reset,
            MSG_LIVE_ACTIVITY: self._live_activity,
            MSG_AWAKE: self._awake,
        }.get(kind)
        if handler is None:
            return {"error": f"unknown message type: {kind}"}
        # Every message may carry the app's wind-down settings (v0.4.3 item 5) and when this
        # install of the app stops opening (item 9).
        self.wind_down.adopt_settings(data.get("wind_down_settings"))
        self.awake.adopt_settings(data.get("awake_settings"))
        if isinstance(data.get("clock_24h"), bool) and data["clock_24h"] != self.state.get("clock_24h"):
            self.state["clock_24h"] = data["clock_24h"]
            timefmt.set_24h(data["clock_24h"])
            self._changed()
        if isinstance(data.get("notification_levels"), dict):
            self.state["notification_levels"] = {
                k: v for k, v in data["notification_levels"].items() if v in ("normal", "time_sensitive", "critical")
            }
        if isinstance(data.get("charge_warning"), dict):
            self.state["charge_warning"] = data["charge_warning"]
        if isinstance(data.get("weekly_summary"), dict) and data["weekly_summary"] != self.state.get("weekly_settings"):
            self.state["weekly_settings"] = data["weekly_summary"]
            self._schedule_weekly()
        if isinstance(data.get("app_expires"), str) and data["app_expires"] != self.state.get("app_expires"):
            self.state["app_expires"] = data["app_expires"]
            self._changed()
        result = await handler(data) or {}
        if kind in (MSG_PLANNED, MSG_CANCELLED, MSG_SKIPPED, MSG_UNSKIPPED, MSG_BEDTIME_UNDONE):
            await self._recompute_ladder()
        if kind == MSG_PLANNED:
            self._schedule_leave_checks()
        elif kind in (MSG_CANCELLED, MSG_SKIPPED, MSG_BEDTIME_UNDONE):
            # The morning went: no more leave checks (item 17). A morning change keeps them
            # (v0.4.2 item 1, in _morning_changed).
            self.state["leave_reminders"] = []
            self._cancel_leave_checks()
        if kind == MSG_STOPPED:
            self._schedule_morning_updates()
            if self.live.configured and self.state.get("morning_updates_until") and self.is_home():
                await self.live.morning()
        elif kind in (MSG_CANCELLED, MSG_SKIPPED, MSG_RESET) or (kind == MSG_MORNING_CHANGED and not data.get("alarm_times")):
            self._cancel_morning_updates()
            if self.live.configured:
                await self.live.end_morning()
        elif kind == MSG_LEAVE_BY and self.live.configured and self.state.get("morning_updates_until"):
            # A new leave-by from a drive re-check: the countdown follows.
            await self.live.morning()
        if kind in (MSG_PLANNED, MSG_CANCELLED, MSG_SKIPPED, MSG_UNSKIPPED, MSG_MORNING_CHANGED):
            changed = kind == MSG_MORNING_CHANGED
            self.wind_down.refresh(
                moved=True if changed else bool(data.get("first_alarm_moved")),
                moved_reason=data.get("reason") if changed else data.get("moved_reason"),
            )
        return {
            "settings": self.settings_for_app(), "wind_down": self.wind_down.summary(),
            # Whether I'm awake is offered now (v0.4.6 item 2).
            "no_alarm_morning": self.awake.summary(),
            # The app skips its own leave reminders while home when the checks happen here.
            "drive_checks_here": bool(self._drive_services()),
            **result,
        }

    async def _awake(self, data: dict[str, Any]) -> dict[str, Any]:
        """I'm awake from the app, Siri or a control: good morning now (v0.4.6 item 2)."""
        return await self.awake.good_morning(by_hand=True)

    # MARK: Plug in your phone (v0.4.3 item 10)

    def _battery(self) -> tuple[float | None, bool | None]:
        """The companion app's battery level and whether it's charging (Full counts)."""
        level_state = self.hass.states.get(self.options.get(CONF_PHONE_BATTERY) or "")
        charge_state = self.hass.states.get(self.options.get(CONF_PHONE_BATTERY_STATE) or "")
        try:
            level = float(level_state.state) if level_state else None
        except ValueError:
            level = None
        charging = None
        if charge_state is not None and charge_state.state not in UNKNOWN_STATES:
            charging = charge_state.state.lower() in ("charging", "full")
        return level, charging

    async def charge_check(self, level: Any = None, charging: Any = None, *, again: bool = True) -> None:
        """At bedtime (with the phone's own reading) and at go to bed: under the threshold and
        not charging → "Plug in your phone · alarms at 4:20", once more after 10 min if still
        not charging."""
        cfg = self.state.get("charge_warning") or {}
        if not cfg.get("enabled", True):
            return
        sensor_level, sensor_charging = self._battery()
        level = level if isinstance(level, (int, float)) else sensor_level
        charging = charging if isinstance(charging, bool) else sensor_charging
        if level is None or charging is None or charging or level >= int(cfg.get("threshold", 30)):
            return
        times = sorted(t for t in (_time(v) for v in self.state.get("alarm_times") or []) if t and t > dt_util.utcnow())
        alarms = f" · alarms at {timefmt.short(times[0])}" if times else ""
        await self.wind_down._notify("Plug in your phone", f"Plug in your phone{alarms}", tag="charge", time_sensitive=True)
        if again:
            async_call_later(self.hass, timedelta(minutes=10), callback(
                lambda _now: self.hass.async_create_task(self.charge_check(again=False))))

    # MARK: Morning Live Activity (v0.4.3 item 14)

    @callback
    def _schedule_morning_updates(self) -> None:
        """After the first stop on a leave-by morning: RUN_MORNING_UPDATE every hour until 15 min
        after leave-by, while home."""
        until = _time(self.state.get("morning_updates_until"))
        if self._morning_unsubs and until is not None and until > dt_util.utcnow():
            return
        # Last morning's timers have all fired: start over.
        self._cancel_morning_updates()
        leave_by = _time(self.state.get("leave_by"))
        now = dt_util.utcnow()
        end = leave_by + timedelta(minutes=LEAVE_CHECK_TAIL_MINUTES) if leave_by else None
        if end is None or end <= now:
            return
        self.state["morning_updates_until"] = end.isoformat()
        when = now + timedelta(hours=1)
        while when < end:
            self._morning_unsubs.append(async_track_point_in_utc_time(self.hass, self._morning_update_due, when))
            when += timedelta(hours=1)
        # The last one ends it.
        self._morning_unsubs.append(async_track_point_in_utc_time(self.hass, self._morning_update_due, end))

    @callback
    def _cancel_morning_updates(self) -> None:
        for unsub in self._morning_unsubs:
            unsub()
        self._morning_unsubs = []
        self.state["morning_updates_until"] = None

    @callback
    def _morning_update_due(self, _now: datetime) -> None:
        if not self.is_home():
            return
        if self.live.configured:
            # By push: refreshed (or ended, 15 min after leave-by) without the app.
            self.hass.async_create_task(self.live.morning())
        else:
            self.hass.async_create_task(self._command(CMD_MORNING_UPDATE))

    @callback
    def _morning_presence(self, event: Event[EventStateChangedData]) -> None:
        """Left home during the morning: one more update, so the app ends the activity."""
        until = _time(self.state.get("morning_updates_until"))
        new = event.data.get("new_state")
        if until is None or dt_util.utcnow() > until or new is None or self.is_home():
            return
        self._cancel_morning_updates()
        if self.live.configured:
            self.hass.async_create_task(self.live.end_morning())
        else:
            self.hass.async_create_task(self._command(CMD_MORNING_UPDATE))

    # MARK: Weekly summary (v0.4.3 item 15)

    @callback
    def _schedule_weekly(self) -> None:
        if self._weekly_unsub:
            self._weekly_unsub()
            self._weekly_unsub = None
        when = weekly.next_run(self.state.get("weekly_settings") or {}, dt_util.utcnow())
        if when is not None:
            self._weekly_unsub = async_track_point_in_utc_time(
                self.hass, callback(lambda _now: self.hass.async_create_task(self.send_weekly_summary())), when)

    async def send_weekly_summary(self) -> dict[str, Any]:
        """The week, as a sensor and a notification that opens the app's summary screen."""
        # The week that just ended, cut at the setting's day and time (v0.4.6 item 5).
        now = dt_util.utcnow()
        cutoff = weekly.last_cutoff(self.state.get("weekly_settings") or {}, now)
        summary = weekly.summarize(self.state.get("history") or [], self.state.get("wind_down_history") or [], now,
                                   since=weekly.week_start(cutoff), until=cutoff)
        summary["vacation"] = weekly.vacation_text(self.state.get("vacations"), weekly.week_start(cutoff), cutoff)
        self.state["weekly_summary"] = summary
        self._changed()
        self._schedule_weekly()
        # On vacation: the summary is there, without the notification (v0.4.7 item 6f).
        if weekly.on_vacation(self.state.get("vacations"), now):
            return summary
        await self.wind_down._notify("Your week", summary["text"] or "Nothing tracked this week.", tag="weekly",
                                     url="bedtimebridge://summary")
        return summary

    async def bedtime_started(self, data: dict[str, Any]) -> None:
        """Bedtime ran (the bedtime shortcut's Report Shortcut Ran RUN_BEDTIME, or Start Bedtime
        Routine): wind-down ends (v0.4.3 item 5), the expiry warning (item 9) and Plug in your
        phone (item 10), each once a night."""
        await self.wind_down.bedtime_ran()
        await self._warn_app_expiry()
        today = dt_util.as_local(dt_util.utcnow()).date().isoformat()
        if self.state.get("charge_checked_night") != today:
            self.state["charge_checked_night"] = today
            await self.charge_check(data.get("battery_level"), data.get("battery_charging"))

    async def _warn_app_expiry(self) -> None:
        """At bedtime on each of the last 2 days before the app stops opening (v0.4.3 item 9)."""
        expires = _time(self.state.get("app_expires"))
        now = dt_util.utcnow()
        today = dt_util.as_local(now).date().isoformat()
        if expires is None or not now < expires <= now + timedelta(days=2) or self.state.get("app_expiry_warned") == today:
            return
        self.state["app_expiry_warned"] = today
        when = timefmt.day_long(expires)
        await self.wind_down._notify("Reinstall Bedtime Bridge", f"The app stops opening {when}. Reinstall it from Xcode (⌘R); settings are kept.",
                                     tag="app_expiry")

    async def _reset(self, data: dict[str, Any]) -> dict[str, Any]:
        """Reset alarms and backstops to nothing set (v0.4.3 item 7a): clears the alarm state, the
        ladder's delay and weather moves, pending leave checks and phone commands, turns the
        napping and winding-down helpers off, then recalculates the ladder from the calendar
        alone (armed again if a covered shift is on it). Settings, the override, Sleep In and
        Awake For Day are left as they are."""
        self.state.update(empty_state())
        self.state["last_morning_change"] = None
        self.state["ladder"] = {}
        self.state["ladder_plan"] = {}
        self.state["ladder_delay"] = None
        self.state["nap_alarm_times"] = []
        self.state["leave_reminders"] = []
        self._cancel_leave_checks()
        for command in list(self._pending_commands):
            await self._clear_command(command)
        for command in list(self._command_unsubs):
            self._unwatch_command(command)
        self.state["command_started"] = {}
        for option in (CONF_NAP_HELPER, CONF_WIND_DOWN_HELPER):
            helper = self.options.get(option)
            state = self.hass.states.get(helper or "")
            if helper and state is not None and state.state == "on":
                await self._turn_off(helper)
        self.wind_down.cancel_timers()
        self.state["wind_down"] = {"status": "off"}
        await self._recompute_ladder()
        self.wind_down.async_reschedule()
        self._event(MSG_RESET)
        return {}

    async def _live_activity(self, data: dict[str, Any]) -> dict[str, Any]:
        return self.live.handle(data)

    async def _preview(self, data: dict[str, Any]) -> dict[str, Any]:
        """The phone's Preview tomorrow (RUN_PLAN_PREVIEW): sets nothing, gives the wind-down
        tomorrow's first alarm."""
        await self._clear_command(CMD_PLAN_PREVIEW)
        self.wind_down.preview_answered(data)
        return {}

    async def _wind_down_action(self, data: dict[str, Any]) -> dict[str, Any]:
        """From the app, a control or Siri: start, cancel, later or stop_reminders."""
        action = data.get("action")
        if action == "start":
            return {"started": await self.wind_down.start_now()}
        if action == "cancel":
            await self.wind_down.cancel()
        elif action == "later":
            await self.wind_down.later()
        elif action == "stop_reminders":
            self.wind_down.stop_reminders()
        return {}

    async def _context(self, data: dict[str, Any]) -> dict[str, Any]:
        """Shift override and HA's next shift, read before the app plans."""
        override = self.hass.states.get(self.options.get(CONF_SHIFT_OVERRIDE) or "")
        sensor = self.hass.states.get(self.options.get(CONF_SHIFT_SENSOR) or "")
        return {
            "shift_override": override.state if override else None,
            "next_shift_start": sensor.attributes.get("next_shift_start") if sensor else None,
            "next_shift_type": sensor.attributes.get("next_shift_type") if sensor else None,
            "at_home": self.is_home(),
            # For item 3's confirm screen: the backstops now, and when the curtains open on the
            # morning of the first new alarm (Sleep In's rule).
            "ladder": self._ladder_summary(),
            # The override or HA's next shift changed after the plan (v0.4.1 item 10).
            "plan_outdated": bool(self.state.get("plan_outdated")),
            "outdated_reason": self.state.get("outdated_reason"),
            "wind_down": self.wind_down.summary(),
            "weekly_summary": self.state.get("weekly_summary"),
            # This week so far and up to 8 earlier weeks, newest first (v0.4.6 item 5).
            "weekly_summaries": weekly.weeks(self.state.get("history") or [], self.state.get("wind_down_history") or [],
                                             self.state.get("weekly_settings") or {}, dt_util.utcnow(), self.state.get("vacations")),
            "curtains_open_at": self._curtains_open(_time(data.get("first_alarm")) or dt_util.utcnow()),
        }

    def _ladder_summary(self) -> dict[str, Any]:
        ladder = self.state.get("ladder") or {}
        summary = {key: ladder.get(key) for key in (
            "status", "reason", "kind", "times", "shift_start", "appointment", "delay_minutes", "leave_by", "first_day_back",
        )}
        summary["house_backstop"] = self.house_backstop()
        return summary

    def house_backstop(self) -> dict[str, Any]:
        """What the house backstop fires on (item 8): the old template's rungs until the
        cutover, then this ladder."""
        source = self.options.get(CONF_HOUSE_BACKSTOP) or HOUSE_OLD
        if source != HOUSE_OLD:
            return {"source": source, "times": (self.state.get("ladder") or {}).get("times") or {}}
        times: dict[str, str] = {}
        for rung, entity_id in zip(("early", "deadline", "late"), self.options.get(CONF_OLD_RUNGS) or DEFAULT_OLD_RUNGS):
            state = self.hass.states.get(entity_id)
            when = _time(state.state) if state else None
            if when:
                times[rung] = when.isoformat()
        return {"source": HOUSE_OLD, "times": times}

    def _curtains_open(self, on: datetime) -> str | None:
        """Sunrise + the curtain offset on the local day of `on`."""
        sun = self.hass.states.get("sun.sun")
        rising = _time(sun.attributes.get("next_rising")) if sun else None
        if rising is None:
            return None
        rising += timedelta(days=(dt_util.as_local(on).date() - dt_util.as_local(rising).date()).days)
        offset = timedelta(minutes=int(self.options.get(CONF_CURTAIN_OFFSET) or DEFAULT_CURTAIN_OFFSET))
        return (rising + offset).isoformat()

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
        if self.state.get("snooze_count"):
            # A morning that never got its last stop: the next plan closes it (item 5).
            self._end_morning()
        self.state.update(empty_state())
        self.state.update({key: data.get(key) for key in PLAN_FIELDS if key in data})
        self.state["last_plan"] = dt_util.utcnow().isoformat()
        self.state["plan_error"] = None
        self.state["ladder_plan"] = data.get("ladder") or {}
        self.state["leave_reminders"] = [int(m) for m in data.get("leave_reminders") or []]
        # Where and when the morning's drive arrives, for drive checks here (0.4.4).
        self.state["trip"] = data.get("trip") if isinstance(data.get("trip"), dict) else None
        self._check_alarms_set(data)
        if (data.get("ladder") or {}).get("work_buffer_minutes") is not None:
            self.state["work_buffer_minutes"] = int(data["ladder"]["work_buffer_minutes"])
        # Bedtime ran again (by hand, or the nudge): no need to wait for you to get into bed.
        self._end_bed("rerun")
        self.state["planned_override"] = self._state_of(CONF_SHIFT_OVERRIDE)
        self.state["planned_shift_start"] = self._next_shift_start()
        times = sorted(t for t in (_time(v) for v in self.state.get("alarm_times") or []) if t)
        self.state["series_start"] = times[0].isoformat() if times else None
        await self._sync_sleep_in()
        # v0.4.7 item 6: Sleep In on for a vacation morning with no alarms; the vacations for the
        # weekly summary.
        if data.get("vacation") and not times:
            await self._set_sleep_in(True)
        if isinstance(data.get("vacations"), list):
            self.state["vacations"] = data["vacations"]
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
        times = [t for t in (_time(v) for v in (ladder.get("times") or {}).values()) if t]
        # The first and last rung (your own alarm's preview can leave one out, item 18).
        return bool(times) and min(times) <= now < max(times) + ldr.LADDER_TAIL

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
        if morning.fixed_times:
            shift_by = timedelta(minutes=delay.get("minutes", 0) - earlier)
            base = {rung: when + shift_by for rung, when in morning.fixed_times.items()}
        else:
            base = ldr.rung_times(morning.leave_by, offsets, morning.first_day_back, delay.get("minutes", 0) - earlier)
        floor = self.state.get("ladder_early_floor") or {}
        if floor.get("morning") == morning.key and _time(floor.get("at")):
            base["early"] = max(base["early"], _time(floor["at"]))
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
            "replaces_shift": morning.replaces_shift,
            "firing": morning.firing,
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
                shift_morning = await self._shift_morning(next_start, plan)
        own: ldr.Morning | None = None
        own_off = False
        last_alarm = _time(plan.get("last_alarm"))
        if plan.get("type") == "own" and last_alarm:
            # Your own alarm on a day off or leave (item 14): off unless switched on.
            if plan.get("on"):
                own = ldr.Morning(
                    "own", last_alarm, "plan", False,
                    fixed_times=ldr.own_times(last_alarm, plan.get("offsets"), plan.get("times")),
                    firing=plan.get("firing") or "gentle",
                )
            elif last_alarm + timedelta(minutes=int((plan.get("offsets") or {}).get("late") or 45)) + ldr.LADDER_TAIL > now:
                own_off = True
        appointment: ldr.Morning | None = None
        if plan.get("type") == "appointment" and _time(plan.get("leave_by")):
            appointment = ldr.Morning(
                "appointment", _time(plan["leave_by"]), "plan", False,
                appointment=plan.get("appointment"), appointment_start=_time(plan.get("appointment_start")),
                weather_extra_minutes=int(plan.get("weather_extra_minutes") or 0), condition=plan.get("condition"),
            )

        def finished(morning: ldr.Morning) -> bool:
            delay = self._ladder_delay_for(morning.key).get("minutes", 0)
            if morning.fixed_times:
                late = max(morning.fixed_times.values()) + timedelta(minutes=delay)
            else:
                late = ldr.rung_times(morning.leave_by, offsets, morning.first_day_back, delay)["late"]
            return late + ldr.LADDER_TAIL <= now

        if appointment and shift_morning and plan.get("replaces_shift") and ldr.same_morning(
            appointment.appointment_start or appointment.leave_by, shift_morning.shift_start
        ):
            # A "wake up" appointment replaces the shift for that morning (v0.4.1 item 11).
            appointment.replaces_shift = plan.get("replaces_shift")
            shift_morning = None
        if shift_morning and finished(shift_morning):
            # current_shift still shows the shift that just passed (it polls): read the next one
            # from the work calendar, so the status goes straight to the next state (item 19).
            shift_morning, status, reason = await self._next_shift_morning(shift_morning.shift_start, plan, finished)
        open_mornings = [m for m in (shift_morning, appointment, own) if m and not finished(m)]
        if open_mornings:
            return min(open_mornings, key=lambda m: m.leave_by), None, None
        if own_off:
            return None, ldr.STATUS_OWN_OFF, "Backstops are off for your own alarm"
        # A finished appointment morning falls through to the shift branch's own status: never a
        # standing "done" (item 19).
        return None, status, reason

    async def _shift_morning(self, start: datetime, plan: dict[str, Any]) -> ldr.Morning:
        """A covered shift's morning: the plan's leave-by when it's for that morning, else the
        calendar's."""
        buffer = int(self.state.get("work_buffer_minutes") or DEFAULT_WORK_BUFFER)
        calendar = ldr.calendar_leave_by(start, int(self.setting_value("fallback_drive_minutes")), buffer)
        planned = plan.get("type") == "shift" and ldr.same_morning(_time(plan.get("shift_start")), start)
        leave_by, source, warning = ldr.pick_leave_by(_time(plan.get("leave_by")) if planned else None, calendar)
        if warning:
            _LOGGER.warning("Bedtime Bridge ladder: %s", warning)
        if planned and plan.get("first_day_back") is not None:
            first_day_back = bool(plan["first_day_back"])
        else:
            first_day_back = await self._first_day_back(start)
        return ldr.Morning(
            "shift", leave_by, source, first_day_back, shift_start=start,
            weather_extra_minutes=int(plan.get("weather_extra_minutes") or 0) if planned else 0,
            condition=plan.get("condition") if planned else None,
        )

    async def _next_shift_morning(
        self, after: datetime | None, plan: dict[str, Any], finished: Callable[[ldr.Morning], bool]
    ) -> tuple[ldr.Morning | None, str, str]:
        """The next shift after one that's over, from the work calendar."""
        calendar = self.options.get(CONF_CALENDAR)
        if after is None or not calendar or self.hass.states.get(calendar) is None:
            return None, ldr.STATUS_NO_SHIFT, "No shift on the calendar yet"
        try:
            response = await self.hass.services.async_call(
                "calendar", "get_events",
                {"entity_id": calendar, "start_date_time": (after + timedelta(minutes=1)).isoformat(),
                 "end_date_time": (after + timedelta(days=8)).isoformat()},
                blocking=True, return_response=True,
            )
        except Exception as err:  # noqa: BLE001 - reported as a fault, not a silent "done"
            return None, ldr.STATUS_FAULT, f"Couldn't read the next shift from {calendar}: {err}"
        names = shift_types(self.options.get(CONF_SHIFT_TYPES))
        covered = [t.lower() for t in (self.options.get(CONF_LADDER_SHIFT_TYPES) or DEFAULT_LADDER_SHIFT_TYPES)]
        events = ((response or {}).get(calendar) or {}).get("events") or []
        for event in sorted(events, key=lambda e: str(e.get("start"))):
            title = str(event.get("summary") or "").lower()
            name = next((n for n in names if n.lower() in title), None)
            start = _time(event.get("start"))
            if name is None or start is None or start <= after:
                continue
            if name.lower() not in covered:
                return None, ldr.STATUS_UNCOVERED, f"{name} mornings have no ladder"
            morning = await self._shift_morning(start, plan)
            if not finished(morning):
                return morning, ldr.STATUS_ARMED, ""
        return None, ldr.STATUS_NO_SHIFT, "No shift on the calendar"

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
        """A delay or early floor belongs to its morning; once another morning's ladder is up, it goes."""
        if (self.state.get("ladder_delay") or {}).get("morning") not in (None, morning):
            self.state["ladder_delay"] = None
        if (self.state.get("ladder_early_floor") or {}).get("morning") not in (None, morning):
            self.state["ladder_early_floor"] = None

    @callback
    def _schedule_ladder_rollover(self) -> None:
        """Once the late rung is 60 minutes past, this morning is over: roll to the next one."""
        if self._ladder_unsub:
            self._ladder_unsub()
            self._ladder_unsub = None
        times = [t for t in (_time(v) for v in ((self.state.get("ladder") or {}).get("times") or {}).values()) if t]
        if not times:
            return
        late = max(times)
        due = late + ldr.LADDER_TAIL
        if due <= dt_util.utcnow():
            return
        self._ladder_unsub = async_track_point_in_utc_time(self.hass, self._ladder_rollover, due)

    @callback
    def _ladder_rollover(self, _now: datetime) -> None:
        self._ladder_unsub = None
        self.state["ladder_delay"] = None
        self.state["ladder_early_floor"] = None
        # Straight to the next state (armed for the next morning, or why not); no "done" (item 19).
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

    def ladder_early_floor(self, floor: datetime, changed_by: str | None, reason: str | None) -> None:
        """Shift alarms only (item 7): the early rung may not come before the new last alarm
        plus the gap. Kept for that morning through recomputes, cleared when it ends."""
        ladder = self.state.get("ladder") or {}
        if ladder.get("status") != ldr.STATUS_ARMED:
            return
        self.state["ladder_early_floor"] = {"morning": ladder["morning"], "at": floor.isoformat()}
        # From the early rung before any floor, so moving the alarms back puts it back.
        base = _time(ladder.get("early_base")) or _time((ladder.get("times") or {}).get("early"))
        if base is not None:
            ladder["early_base"] = base.isoformat()
            ladder["times"]["early"] = max(base, floor).isoformat()
            self._schedule_ladder_rollover()
        ladder.update(changed_by=changed_by, change_reason=reason)
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
            reason = f"Next shift moved to {timefmt.day_long(when) if when else shift_start}"
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
        # How the phone decided what to keep (v0.4.1 item 1), so a morning can be traced.
        self.state["last_stop"] = {
            "time": dt_util.utcnow().isoformat(), "all": stop_all, "up": data.get("up"),
            "stop_behavior": data.get("stop_behavior"), "alarms_left": len(remaining),
        }
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

    def _check_alarms_set(self, data: dict[str, Any]) -> None:
        """The phone reads back what AlarmKit holds; fewer than it meant to set is reported."""
        planned = data.get("alarms_planned")
        actual = len(data.get("alarm_times") or [])
        if isinstance(planned, int) and actual < planned:
            self.state["alarms_missing"] = {"set": actual, "planned": planned, "time": dt_util.utcnow().isoformat()}
            _LOGGER.warning("Bedtime Bridge: the phone set %s of %s alarms", actual, planned)
            self.hass.bus.async_fire(EVENT, {"type": EVENT_ALARMS_MISSING, "set": actual, "planned": planned})
        else:
            self.state["alarms_missing"] = None

    @callback
    def _end_morning(self) -> None:
        """The wake-up is over (every alarm stopped, ended all, or changed): this morning's
        snoozes become Snoozes last morning and the count starts again at 0."""
        self.state["snoozes_last_morning"] = int(self.state.get("snooze_count") or 0)
        # For the weekly summary (v0.4.3 item 15): snoozes, and the backstops whose time came
        # while the ladder was armed before the morning ended.
        now = dt_util.utcnow()
        ladder = self.state.get("ladder") or {}
        fired = 0
        if ladder.get("status") == "armed":
            fired = sum(1 for v in (ladder.get("times") or {}).values() if (t := _time(v)) and now - timedelta(hours=6) < t <= now)
        weekly.record(self.state.setdefault("history", []), "morning", now,
                      snoozes=self.state["snoozes_last_morning"], backstops_fired=fired)
        self.state["snooze_count"] = 0

    # MARK: Temporary alarms

    # MARK: Nap (v0.4.2 item 3)

    async def _nap_started(self, data: dict[str, Any]) -> dict[str, Any]:
        """A nap's alarms are set. Like temporary alarms, nothing about the morning changes: no
        wake routines, Good Morning or backstops; Sleep In and Awake For Day stay. The napping
        helper goes on while you're home; the nap Focus shortcut runs home or away."""
        times = [t.isoformat() for t in sorted(t for t in (_time(v) for v in data.get("alarm_times") or []) if t)]
        weekly.record(self.state.setdefault("history", []), "nap", dt_util.utcnow(), minutes=data.get("minutes"))
        self.state["nap_alarm_times"] = times
        helper = self.options.get(CONF_NAP_HELPER)
        helper_on = bool(helper) and self.is_home()
        if helper_on:
            await self._turn_on(helper)
        focus = await self._command(CMD_NAP_START)
        self._event(MSG_NAP_STARTED, alarm_times=times, napping_helper=helper_on)
        return {"napping_helper": helper_on, "nap_focus": focus}

    async def _nap_ended(self, data: dict[str, Any]) -> dict[str, Any]:
        """The nap is over (its last alarm stopped, or End nap). The helper goes off if it's on,
        so a nap started at home doesn't leave it on after you've gone out."""
        self.state["nap_alarm_times"] = []
        helper = self.options.get(CONF_NAP_HELPER)
        if helper and self.hass.states.is_state(helper, "on"):
            await self._turn_off(helper)
        await self._clear_command(CMD_NAP_START)
        focus = await self._command(CMD_NAP_END)
        self._event(MSG_NAP_ENDED)
        return {"nap_focus": focus}

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
        for command in list(self._command_unsubs):
            self._unwatch_command(command)
        self._cancel_leave_checks()

    # MARK: Leave checks (v0.4.1 item 17)

    @callback
    def _cancel_leave_checks(self) -> None:
        for unsub in self._leave_unsubs:
            unsub()
        self._leave_unsubs = []

    @callback
    def _schedule_leave_checks(self) -> None:
        """A RUN_LEAVE_CHECK push at each reminder (minutes before leave-by) still ahead, until 15
        minutes after leave-by. The phone re-checks the drive, notifies and reports leave_by."""
        self._cancel_leave_checks()
        leave_by = _time(self.state.get("leave_by"))
        if leave_by is None:
            return
        now = dt_util.utcnow()
        if now > leave_by + timedelta(minutes=LEAVE_CHECK_TAIL_MINUTES):
            return
        for minutes in sorted(set(self.state.get("leave_reminders") or []), reverse=True):
            due = leave_by - timedelta(minutes=minutes)
            if due <= now:
                continue
            self._leave_unsubs.append(
                async_track_point_in_utc_time(self.hass, callback(lambda _now: self.hass.async_create_task(self._leave_check_due())), due)
            )

    async def _leave_check_due(self) -> None:
        leave_by = _time(self.state.get("leave_by"))
        now = dt_util.utcnow()
        if leave_by is None or now > leave_by + timedelta(minutes=LEAVE_CHECK_TAIL_MINUTES):
            return
        if not self.is_home() or not self._leave_shift_still_on():
            # Already left, or the shift came off the calendar: no more checks.
            self.state["leave_reminders"] = []
            self._cancel_leave_checks()
            if self.is_home():
                self._drop_leave_by()
            return
        if await self._drive_check_here():
            return
        await self._command(CMD_LEAVE_CHECK)

    # MARK: Drive times here (0.4.4)

    def _drive_services(self) -> list[Any]:
        """The services chosen in the options, as far as their keys are in; empty means the phone."""
        source = self.options.get(CONF_DRIVE_SOURCE) or dtm.SOURCE_PHONE
        if source == dtm.SOURCE_PHONE:
            return []
        session = async_get_clientsession(self.hass)
        live = self.state.get("live_activity") or {}
        services: dict[str, Any] = {}
        if self.options.get(CONF_MAPS_KEY) and self.options.get(CONF_MAPS_KEY_ID) and live.get("team_id"):
            if self._maps is None:
                self._maps = dtm.AppleMaps(session, self.options[CONF_MAPS_KEY], self.options[CONF_MAPS_KEY_ID], live["team_id"])
            services[dtm.SOURCE_APPLE] = self._maps
        if self.options.get(CONF_TOMTOM_KEY):
            services[dtm.SOURCE_TOMTOM] = dtm.TomTom(session, self.options[CONF_TOMTOM_KEY])
        if self.options.get(CONF_GOOGLE_KEY):
            services[dtm.SOURCE_GOOGLE] = dtm.Google(session, self.options[CONF_GOOGLE_KEY], live.get("bundle_id"))
        if source == dtm.SOURCE_LONGEST:
            return list(services.values())
        return [services[source]] if source in services else []

    def _home_place(self) -> dtm.Place | None:
        home = self.hass.states.get("zone.home")
        if home is None or home.attributes.get("latitude") is None:
            if self.hass.config.latitude is None:
                return None
            return dtm.Place("home", self.hass.config.latitude, self.hass.config.longitude)
        return dtm.Place("home", home.attributes["latitude"], home.attributes["longitude"])

    async def _drive_check_here(self) -> bool:
        """A leave check worked out here: the drive arriving by the trip's arrive-by with the
        traffic expected then; leave-by moves and you're told. False: ask the phone instead."""
        services = self._drive_services()
        trip = self.state.get("trip") or {}
        arrive_by = _time(trip.get("arrive_by"))
        origin = self._home_place()
        if not services or arrive_by is None or origin is None or not (trip.get("location") or trip.get("latitude") is not None):
            return False
        destination = dtm.Place(trip.get("location") or "", trip.get("latitude"), trip.get("longitude"))
        try:
            seconds = await dtm.drive_seconds(services, origin, destination, arrive_by)
        except dtm.DriveTimeError as err:
            _LOGGER.warning("Bedtime Bridge couldn't check the drive here, asking the phone: %s", err)
            return False
        planned = int(trip.get("planned_minutes") or self.state.get("drive_minutes") or 0)
        minutes = round(seconds / 60)
        leave_by = arrive_by - timedelta(seconds=seconds)
        await self._leave_by({"leave_by": leave_by.isoformat(), "drive_minutes": minutes, "note": "checked by Home Assistant"})
        await self._notify_leave(leave_by, minutes, planned, trip)
        # The phone's leave-time backup can go (v0.4.7 item 2).
        await self.live.leave_checked()
        if self.live.configured and self.state.get("morning_updates_until"):
            await self.live.morning()
        return True

    async def _notify_leave(self, leave_by: datetime, minutes: int, planned: int, trip: dict[str, Any]) -> None:
        """"Leave by 5:48 · 32 min drive (5 min worse than planned)", or "Leave now · …", as the app says it."""
        now = dt_util.utcnow()
        head = "Leave now" if leave_by <= now + timedelta(minutes=1) else f"Leave by {timefmt.short(leave_by)}"
        difference = minutes - planned if planned else 0
        change = f" ({abs(difference)} min {'worse' if difference > 0 else 'lighter'} than planned)" if abs(difference) >= 3 else ""
        start = _time(trip.get("start"))
        body = f"{trip.get('title') or 'Your drive'}" + (f" at {timefmt.long(start)}." if start else ".")
        await self.wind_down._notify(f"{head} · {minutes} min drive{change}", body, tag="leave_check", time_sensitive=True)

    def _drop_leave_by(self) -> None:
        """The shift behind leave-by is gone: leave-by goes too, so nothing shows a morning
        that isn't happening."""
        self.state["leave_by"] = None
        self.state["leave_reminders"] = []
        self._cancel_leave_checks()
        self._changed()

    def _leave_shift_still_on(self) -> bool:
        """With no alarms left on a work morning, the checks run only while the calendar still
        shows the shift (v0.4.2 item 1): the shift sensor's next start is the planned one."""
        plan = self.state.get("ladder_plan") or {}
        if self.state.get("alarm_times") or plan.get("type") != "shift":
            return True
        planned = _time(plan.get("shift_start"))
        sensor = self.hass.states.get(self.options.get(CONF_SHIFT_SENSOR) or "")
        if planned is None or sensor is None:
            return True
        start = _time(sensor.attributes.get("next_shift_start"))
        return start is not None and abs((start - planned).total_seconds()) < 60

    # MARK: Change this morning (item 3)

    async def _morning_changed(self, data: dict[str, Any]) -> None:
        """The morning's alarms were moved later or earlier, or cancelled, while snoozing or
        after you were up. The backstops move with the wake-up (or stay with no alarms), Sleep
        In follows, and the house goes back to bedtime."""
        times = sorted(t for t in (_time(v) for v in data.get("alarm_times") or []) if t)
        delay = int(data.get("delay_minutes") or 0)
        # alarms: sleep longer, same start; wake_up: the start moved too (v0.4.1 item 7).
        scope = data.get("scope") or "wake_up"
        gap = int(data.get("early_gap_minutes") or 5)
        late = _time(((self.state.get("ladder") or {}).get("times") or {}).get("late"))
        if scope == "alarms" and times and late and (self.state.get("ladder") or {}).get("status") == "armed" and times[-1] > late:
            message = (f"The last new alarm ({dt_util.as_local(times[-1]).strftime('%H:%M')}) is after the late backstop "
                       f"({dt_util.as_local(late).strftime('%H:%M')}); nothing was changed. Shift the entire wake-up instead.")
            _LOGGER.warning("Bedtime Bridge refused a morning change: %s", message)
            self.hass.bus.async_fire(EVENT, {"type": EVENT_CHANGE_REFUSED, "reason": message})
            return {"error": message}
        phase = data.get("phase") or "up"
        if phase == "snoozing" and (self.state.get("routine_ran") or self._state_of(CONF_AWAKE_HELPER) == "on"):
            # Don't trust the phase alone (v0.4.1 item 2): once the wake routine ran or Awake For
            # Day is on, the house has to go back to bed.
            phase = "up"
        reason, note = data.get("reason"), data.get("note")
        # The snooze count keeps going across a change (v0.4.1 item 5): it's one morning.
        self.state["snoozed_until"] = None
        self.state["alarm_times"] = [t.isoformat() for t in times]
        self.state["alarm_time"] = times[0].isoformat() if times else None
        self.state["series_start"] = times[0].isoformat() if times else None
        if phase != "edit":
            # A new series is a new wake-up; an edited one is the same (v0.4.1 item 13).
            self.state["routine_ran"] = False
        self._check_alarms_set(data)
        if not times:
            self.state["alarm_cause"] = "noalarm"
        if data.get("phase") not in ("bedtime", "edit"):
            # Mornings changed, for the weekly summary: once per morning, not Sleep later or edits.
            history = self.state.setdefault("history", [])
            today = dt_util.as_local(dt_util.utcnow()).date().isoformat()
            if not any(h.get("kind") == "change" and dt_util.as_local(dt_util.parse_datetime(h["time"])).date().isoformat() == today for h in history):
                weekly.record(history, "change", dt_util.utcnow(), reason=data.get("reason"))
        self.state["last_morning_change"] = {
            "delay_minutes": delay if times else None,
            "alarm_times": self.state["alarm_times"],
            "reason": reason,
            "note": note,
            "phase": phase,
            "scope": scope,
            "time": dt_util.utcnow().isoformat(),
        }
        # The one thing allowed to move the backstops later. No alarms: they stay (the calendar
        # still shows the shift; deleting it is what turns them off).
        if times and scope == "alarms":
            # Deadline and late stay; early follows the new last alarm.
            self.ladder_early_floor(times[-1] + timedelta(minutes=gap), data.get("changed_by") or "app", reason)
        elif times and delay:
            self.change_morning_ladder(delay, data.get("changed_by") or "app", reason)
        # Leave checks (v0.4.2 item 1): an entire wake-up moved takes leave-by and the checks
        # with it; shifting the alarms only, or no alarms, keeps them as they are.
        leave_by = _time(self.state.get("leave_by"))
        if times and scope == "wake_up" and delay and leave_by is not None:
            self.state["leave_by"] = (leave_by + timedelta(minutes=delay)).isoformat()
            trip = self.state.get("trip") or {}
            if _time(trip.get("arrive_by")):
                trip["arrive_by"] = (_time(trip["arrive_by"]) + timedelta(minutes=delay)).isoformat()
            self._schedule_leave_checks()
        if phase not in ("bedtime", "edit"):
            await self._restart_wake_automations()
        # Blocking: Sleep In must be set before the bedtime routine can move the curtains.
        if times:
            await self._sync_sleep_in(blocking=True)
        else:
            await self._set_sleep_in(bool(data.get("sleep_in", True)), blocking=True)
            if not self._leave_shift_still_on():
                # No alarms, and the shift is already off the calendar: no leave-by either.
                self._drop_leave_by()
        at_home = self.is_home()
        if phase in ("bedtime", "edit"):
            # Sleep later before bed (item 12) or an edited alarm (item 13): nothing in the house,
            # except that an edit ending the only snooze fades the bedroom back down.
            helper = self.options.get(CONF_SNOOZE_HELPER)
            if phase == "edit" and data.get("snooze_ended") and helper:
                await self._turn_off(helper)
        elif phase == "snoozing":
            # Only the snooze ramp has started: fade the nightstands back down.
            helper = self.options.get(CONF_SNOOZE_HELPER)
            if helper:
                await self._turn_off(helper)
        elif at_home:
            # After a stop: Sleep In first (above), then the bedtime routine, then the phone.
            bedtime = self.options.get(CONF_BEDTIME_HELPER)
            if bedtime:
                await self._turn_on(bedtime, blocking=True)
            await self._command(CMD_BACK_TO_BED)
        self._event(
            MSG_MORNING_CHANGED, delay_minutes=delay if times else None, reason=reason, note=note,
            phase=phase, scope=scope, sleep_in=self._state_of(CONF_SLEEP_IN),
        )

    async def _restart_wake_automations(self) -> None:
        """Until v0.5 fires the ladder: stop Wake Confirm's nudges and a Backstop loop already
        running (turning an automation off cancels its runs) and clear their notifications."""
        configured = self.options.get(CONF_RESTART_AUTOMATIONS)
        for entity_id in DEFAULT_RESTART_AUTOMATIONS if configured is None else configured:
            state = self.hass.states.get(entity_id)
            if state is None or state.state != "on":
                continue
            try:
                await self.hass.services.async_call(
                    "automation", "turn_off", {"entity_id": entity_id, "stop_actions": True}, blocking=True
                )
                await self.hass.services.async_call("automation", "turn_on", {"entity_id": entity_id}, blocking=True)
            except HomeAssistantError as err:
                _LOGGER.warning("Bedtime Bridge couldn't restart %s: %s", entity_id, err)
        notify = (self.options.get(CONF_NOTIFY) or "").strip()
        if notify:
            domain, _, service = notify.partition(".")
            for tag in RESTART_NOTIFICATION_TAGS:
                try:
                    await self.hass.services.async_call(
                        domain, service, {"message": "clear_notification", "data": {"tag": tag}}, blocking=False
                    )
                except HomeAssistantError as err:
                    _LOGGER.warning("Bedtime Bridge couldn't clear %s: %s", tag, err)

    async def _turn_off(self, entity_id: str) -> None:
        try:
            await self.hass.services.async_call("homeassistant", "turn_off", {"entity_id": entity_id}, blocking=False)
        except HomeAssistantError as err:
            _LOGGER.warning("Bedtime Bridge couldn't turn off %s: %s", entity_id, err)

    # MARK: Undo bedtime

    async def _bedtime_undone(self, data: dict[str, Any]) -> None:
        """Up again after bedtime ran: alarms are off on the phone; here the house is
        disarmed, Awake For Day goes back on and Sleep In off. Once you're back in bed, bedtime
        runs again (RUN_BEDTIME, the same push the bedtime nudge sends)."""
        # Wind-down doesn't restart; only its reminders run (v0.4.3 item 5).
        self.wind_down.bedtime_undone()
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

    async def _sync_sleep_in(self, blocking: bool = False) -> None:
        """Sleep In follows the plan: on when the first alarm is after the curtains would open
        (sunrise + offset), off when it's before. No alarm leaves it as it is (the bedtime
        shortcut asks). Only while you're home."""
        first = _time(self.state.get("series_start"))
        # The sunrise on the first alarm's own day: in the morning (item 3) next_rising is tomorrow's.
        curtains = _time(self._curtains_open(first)) if first else None
        if first is None or curtains is None:
            return
        await self._set_sleep_in(first > curtains, blocking)

    async def _set_sleep_in(self, on: bool, blocking: bool = False) -> None:
        helper = self.options.get(CONF_SLEEP_IN)
        state = self.hass.states.get(helper or "")
        if not helper or not self.is_home() or (state is not None and state.state == ("on" if on else "off")):
            return
        try:
            await self.hass.services.async_call(
                "homeassistant", "turn_on" if on else "turn_off", {"entity_id": helper}, blocking=blocking
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
        # "ran" is Started (the shortcut's first step); "completed" its last; "already_done".
        outcome = data.get("outcome") or "ran"
        if command == CMD_BEDTIME and outcome == "ran":
            # The bedtime shortcut's first step: this is bedtime, whether a push or you ran it
            # (it never sends "bedtime" itself).
            await self.bedtime_started(data)
        now = dt_util.utcnow().isoformat()
        if command in COMMANDS:
            await self._clear_command(command)
        started: dict[str, str] = self.state.setdefault("command_started", {})
        completing: list[str] = self.state.setdefault("commands_completing", [])
        last = self.state.get("last_command") or {}
        if outcome == "ran":
            # Only watched once that shortcut has reported Completed at least once, so one with
            # just a Started step never raises a false alarm.
            if command in completing:
                started[command] = now
                self._watch_command(command)
            last = {"command": command, "outcome": outcome, "time": now, "started": now, "completed": None}
        else:
            started.pop(command, None)
            self._unwatch_command(command)
            if outcome == "completed" and command not in completing:
                completing.append(command)
            same = last.get("command") == command
            last = {
                "command": command, "outcome": outcome, "time": now,
                "started": last.get("started") if same else None,
                "completed": now if outcome == "completed" else None,
            }
        self.state["last_command"] = last
        self._event(MSG_COMMAND_RAN, command=command, outcome=outcome)

    @callback
    def _watch_command(self, command: str) -> None:
        """Flags a shortcut that started but hasn't completed in time (it stopped partway)."""
        self._unwatch_command(command)
        started = _time((self.state.get("command_started") or {}).get(command))
        if started is None:
            return
        minutes = int(self.options.get(CONF_COMPLETE_MINUTES) or DEFAULT_COMPLETE_MINUTES)
        due = max(started + timedelta(minutes=minutes), dt_util.utcnow() + timedelta(seconds=1))
        self._command_unsubs[command] = async_track_point_in_utc_time(
            self.hass, callback(lambda _now: self.hass.async_create_task(self._command_stuck(command))), due
        )

    @callback
    def _unwatch_command(self, command: str) -> None:
        unsub = self._command_unsubs.pop(command, None)
        if unsub:
            unsub()

    async def _command_stuck(self, command: str) -> None:
        self._command_unsubs.pop(command, None)
        started = (self.state.get("command_started") or {}).pop(command, None)
        if started is None:
            return
        name = COMMAND_NAMES.get(command, command)
        self.hass.bus.async_fire(EVENT, {"type": EVENT_COMMAND_INCOMPLETE, "command": command, "started": started})
        await self._push(
            {
                "title": "Phone shortcut didn't finish",
                "message": f"{name} started on your phone but didn't finish. Check what it should have done.",
                "data": {"tag": f"{COMMAND_TAG}_incomplete", "push": {"interruption-level": "time-sensitive"}},
            },
            f"{command} incomplete",
        )
        _LOGGER.warning("Bedtime Bridge: %s started at %s but never reported Completed", command, started)
        self._changed()

    async def _cancelled(self, data: dict[str, Any]) -> None:
        """Alarms cleared. "No alarms tomorrow" (v0.4.3 item 3) sends sleep_in; the ladder then
        follows the calendar alone (armed while a covered shift is on it)."""
        self.state.update(empty_state())
        if "sleep_in" in data:
            await self._set_sleep_in(bool(data["sleep_in"]))
        self._event(MSG_CANCELLED, sleep_in=data.get("sleep_in"), morning=data.get("morning"))

    async def _bedtime(self, data: dict[str, Any]) -> dict[str, Any]:
        """Starts the bedtime routine by turning on its helper, only when you're home."""
        await self.bedtime_started(data)
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
        # A fresh drive time: the reminders still ahead follow the new leave-by (item 17).
        await self._clear_command(CMD_LEAVE_CHECK)
        self._schedule_leave_checks()
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

    async def _turn_on(self, entity_id: str, blocking: bool = False) -> bool:
        try:
            await self.hass.services.async_call("homeassistant", "turn_on", {"entity_id": entity_id}, blocking=blocking)
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

