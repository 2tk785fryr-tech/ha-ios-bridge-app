"""Mornings with no alarms (v0.4.6 item 2): leaving the bedroom disarms, back in bed re-arms,
and once you're clearly up for the day (from 8:00 AM) good morning runs, asking first. "I'm
awake" in the app runs good morning straight away."""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timedelta
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import Event, EventStateChangedData, HomeAssistant, callback
from homeassistant.helpers.event import async_track_point_in_utc_time, async_track_state_change_event
from homeassistant.util import dt as dt_util

from .const import (
    AWAKE_ACTION_BACK_TO_BED,
    AWAKE_ACTION_GOOD_MORNING,
    CMD_DISARM,
    CMD_MORNING,
    CONF_AWAKE_HELPER,
    CONF_BED_SENSOR,
    CONF_BEDROOM_DOOR,
    CONF_HALLWAY_SENSORS,
    CONF_NAP_HELPER,
    CONF_PHONE_BATTERY_STATE,
    REARM_GIVE_UP_HOURS,
)

if TYPE_CHECKING:
    from .bridge import BedtimeBridge

_LOGGER = logging.getLogger(__name__)

# Settings → Mornings → No-alarm mornings in the app (defaults shown there too).
DEFAULTS: dict[str, Any] = {"enabled": True, "earliest": "08:00", "up_minutes": 15, "wait_minutes": 10}
# Leaving the bedroom means the bed emptied this recently, then the door, then the hallway.
LEAVE_WINDOW = timedelta(minutes=10)
CHARGING = {"charging", "full"}


def empty() -> dict[str, Any]:
    """This trip out of bed: when it began (the disarm), when Up for the day? was sent, and
    whether you answered Back to bed. `done` is when good morning last ran."""
    return {"out_since": None, "asked_at": None, "declined": False, "done": None}


def _time(value: Any) -> datetime | None:
    return dt_util.parse_datetime(value) if isinstance(value, str) else None


def earliest_today(settings: dict[str, Any], now: datetime) -> datetime:
    """Today's earliest time for good morning (8:00 AM by default), on the local clock."""
    hour, _, minute = str(settings.get("earliest") or DEFAULTS["earliest"]).partition(":")
    local = dt_util.as_local(now)
    return dt_util.as_utc(local.replace(hour=int(hour), minute=int(minute or 0), second=0, microsecond=0))


def ask_at(settings: dict[str, Any], out_since: datetime, now: datetime) -> datetime:
    """When Up for the day? goes out for this trip: up for the set minutes, and not before the
    earliest time."""
    up = out_since + timedelta(minutes=int(settings.get("up_minutes") or DEFAULTS["up_minutes"]))
    return max(up, earliest_today(settings, now))


def left_bedroom(bed: Any, door: Any, now: datetime) -> bool:
    """Out of bed, then the bedroom door opened: the bed is empty (since within the last few
    minutes) and the door changed after it, or is open."""
    if bed is None or bed.state != "off" or now - bed.last_changed > LEAVE_WINDOW:
        return False
    if door is None:
        return False
    return door.state == "on" or door.last_changed >= bed.last_changed


class NoAlarmMorning:
    def __init__(self, bridge: BedtimeBridge) -> None:
        self.bridge = bridge
        self.hass: HomeAssistant = bridge.hass
        self._unsubs: list[Callable[[], None]] = []
        self._timer: Callable[[], None] | None = None

    # MARK: State and settings

    @property
    def s(self) -> dict[str, Any]:
        state = self.bridge.state.setdefault("awake", empty())
        for key, value in empty().items():
            state.setdefault(key, value)
        return state

    @property
    def settings(self) -> dict[str, Any]:
        return {**DEFAULTS, **(self.bridge.state.get("awake_settings") or {})}

    def adopt_settings(self, settings: dict[str, Any] | None) -> None:
        if not isinstance(settings, dict) or not settings:
            return
        new = {k: v for k, v in settings.items() if k in DEFAULTS}
        if new != self.bridge.state.get("awake_settings"):
            self.bridge.state["awake_settings"] = new
            self.bridge._changed()
            self._reschedule()

    def _option(self, key: str) -> str | None:
        return self.bridge.options.get(key)

    def _hallway(self) -> list[str]:
        entities = self._option(CONF_HALLWAY_SENSORS) or []
        return [entities] if isinstance(entities, str) else list(entities)

    def _alarms_ahead(self, now: datetime) -> bool:
        return any(t and t > now for t in (_time(v) for v in self.bridge.state.get("alarm_times") or []))

    def morning_without_alarms(self, now: datetime | None = None) -> bool:
        """At home, before Awake For Day, with no alarm still to ring and not napping. Alarm
        mornings wake the house when their alarms are stopped."""
        now = now or dt_util.utcnow()
        if not self.bridge.is_home() or self._alarms_ahead(now) or self.bridge.state.get("routine_ran"):
            return False
        if self.bridge._state_of(CONF_NAP_HELPER) == "on":
            return False
        awake = self.bridge._state_of(CONF_AWAKE_HELPER)
        return awake is not None and awake != "on"

    def summary(self) -> dict[str, Any]:
        """For the app: whether I'm awake is offered now."""
        return {"offered": self.morning_without_alarms(), "asked": self.s.get("asked_at") is not None}

    # MARK: Watching

    @callback
    def async_start(self) -> None:
        bed, door = self._option(CONF_BED_SENSOR), self._option(CONF_BEDROOM_DOOR)
        watched = [e for e in (bed, door, *self._hallway()) if e]
        if watched:
            self._unsubs.append(async_track_state_change_event(self.hass, watched, self._moved))
        if charger := self._option(CONF_PHONE_BATTERY_STATE):
            self._unsubs.append(async_track_state_change_event(self.hass, [charger], self._charger))
        self._unsubs.append(self.hass.bus.async_listen("mobile_app_notification_action", self._action))
        self.bridge.entry.async_on_unload(self.cancel)
        self._reschedule()

    @callback
    def cancel(self) -> None:
        for unsub in self._unsubs:
            unsub()
        self._unsubs = []
        self._cancel_timer()

    @callback
    def _cancel_timer(self) -> None:
        if self._timer:
            self._timer()
            self._timer = None

    @callback
    def _moved(self, event: Event[EventStateChangedData]) -> None:
        entity_id = event.data["entity_id"]
        new = event.data.get("new_state")
        if new is None:
            return
        if entity_id == self._option(CONF_BED_SENSOR) and new.state == "on":
            self._back_in_bed()
            return
        if not self.settings.get("enabled", True) or self.s.get("out_since"):
            return
        hallway = [self.hass.states.get(e) for e in self._hallway()]
        if not any(h is not None and h.state == "on" for h in hallway):
            return
        now = dt_util.utcnow()
        if not self.morning_without_alarms(now):
            return
        if not left_bedroom(self.hass.states.get(self._option(CONF_BED_SENSOR) or ""),
                            self.hass.states.get(self._option(CONF_BEDROOM_DOOR) or ""), now):
            return
        self.hass.async_create_task(self._left_bedroom(now))

    async def _left_bedroom(self, now: datetime) -> None:
        """Step 1: disarm only, and re-arm once back in bed (step 2), like a temporary alarm."""
        self.s.update({"out_since": now.isoformat(), "asked_at": None, "declined": False})
        disarmed = await self.bridge._command(CMD_DISARM)
        if disarmed and self.bridge.state.get("rearm_since") is None:
            self.bridge.state["rearm_since"] = now.isoformat()
            self.bridge.state["rearm_until"] = (now + timedelta(hours=REARM_GIVE_UP_HOURS)).isoformat()
            self.bridge._watch_bed("rearm")
        self.bridge._event("left_bedroom", disarmed=disarmed)
        self.bridge._changed()
        self._reschedule()

    @callback
    def _back_in_bed(self) -> None:
        """The trip is over; the re-arm waits on its own time in bed."""
        if self.s.get("out_since") is None and self.s.get("asked_at") is None:
            return
        asked = self.s.get("asked_at") is not None
        self.s.update({"out_since": None, "asked_at": None, "declined": False})
        self._cancel_timer()
        self.bridge._changed()
        if asked:
            self.hass.async_create_task(self.bridge.wind_down._clear("up_for_day"))

    @callback
    def _charger(self, event: Event[EventStateChangedData]) -> None:
        """Off the charger while up counts as clearly up (from the earliest time)."""
        old, new = event.data.get("old_state"), event.data.get("new_state")
        if old is None or new is None or old.state.lower() not in CHARGING or new.state.lower() in CHARGING:
            return
        now = dt_util.utcnow()
        if self.s.get("out_since") and now >= earliest_today(self.settings, now):
            self.hass.async_create_task(self._ask(now))

    # MARK: Step 3: Up for the day?

    @callback
    def _reschedule(self) -> None:
        self._cancel_timer()
        if not self.settings.get("enabled", True):
            return
        now = dt_util.utcnow()
        out = _time(self.s.get("out_since"))
        asked = _time(self.s.get("asked_at"))
        if out is None or self.s.get("declined"):
            return
        if asked is not None:
            when = asked + timedelta(minutes=int(self.settings.get("wait_minutes") or DEFAULTS["wait_minutes"]))
            action = self._unanswered
        else:
            when = ask_at(self.settings, out, now)
            action = self._due
        if when <= now:
            self.hass.async_create_task(action(now))
            return
        self._timer = async_track_point_in_utc_time(
            self.hass, callback(lambda at: self.hass.async_create_task(action(at))), when)

    async def _due(self, now: datetime) -> None:
        self._timer = None
        if self.s.get("out_since") and self.s.get("asked_at") is None:
            await self._ask(now)

    async def _ask(self, now: datetime) -> None:
        if self.s.get("asked_at") or self.s.get("declined") or not self.morning_without_alarms(now):
            return
        self.s["asked_at"] = now.isoformat()
        self.bridge._changed()
        await self.bridge.wind_down._notify(
            "Up for the day?", "Good morning runs in a few minutes unless you go back to bed.", tag="up_for_day",
            actions=[{"action": AWAKE_ACTION_GOOD_MORNING, "title": "Good morning"},
                     {"action": AWAKE_ACTION_BACK_TO_BED, "title": "Back to bed"}])
        self._reschedule()

    async def _unanswered(self, now: datetime) -> None:
        """No answer and still up: it goes ahead."""
        self._timer = None
        if self.s.get("out_since") and self.s.get("asked_at") and not self.s.get("declined"):
            await self.good_morning(by_hand=False)

    @callback
    def _action(self, event: Event) -> None:
        action = event.data.get("action")
        if action == AWAKE_ACTION_GOOD_MORNING:
            self.hass.async_create_task(self.good_morning(by_hand=False))
        elif action == AWAKE_ACTION_BACK_TO_BED:
            self.s["declined"] = True
            self._cancel_timer()
            self.bridge._changed()

    # MARK: Good morning

    async def good_morning(self, *, by_hand: bool) -> dict[str, Any]:
        """Sleep In off, Awake For Day on, and RUN_GOOD_MORNING (Good Morning - App: Sleep
        Focus off, the announcement). By hand it also disarms, unless leaving the bedroom
        already did."""
        bridge = self.bridge
        if not bridge.is_home():
            return {"good_morning": False, "away": True}
        disarmed = False
        if by_hand and self.s.get("out_since") is None:
            disarmed = await bridge._command(CMD_DISARM)
        # Up for the day: no re-arm when you lie down again.
        bridge._end_bed("rearm")
        await bridge._set_sleep_in(False)
        if awake := self._option(CONF_AWAKE_HELPER):
            await bridge._turn_on(awake)
        sent = await bridge._command(CMD_MORNING)
        if self.s.get("asked_at"):
            await bridge.wind_down._clear("up_for_day")
        self.s.update({**empty(), "done": dt_util.utcnow().isoformat()})
        self._cancel_timer()
        bridge._event("good_morning", by_hand=by_hand, disarmed=disarmed, sent=sent)
        bridge._changed()
        return {"good_morning": sent, "disarmed": disarmed}
