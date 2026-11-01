"""Bedtime pending (v0.4.8 item 1) and Good night (item 5).

Alarms set for later and bedtime not run since they were set: getting into bed is bedtime at any
hour, until 2 hours before the first alarm. `binary_sensor.bedtime_bridge_bedtime_pending` is on
for that time, and the Bedtime Nudge blueprint nudges while it's on, even outside its window.
Good night (the app's bar, Siri) sends RUN_BEDTIME, the push the nudge sends."""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

from homeassistant.core import Event, EventStateChangedData, callback
from homeassistant.helpers.event import async_call_later, async_track_state_change_event
from homeassistant.util import dt as dt_util

from . import reports
from .const import CMD_BEDTIME, CONF_BED_SENSOR, CONF_NAP_HELPER

if TYPE_CHECKING:
    from .bridge import BedtimeBridge

# Getting into bed stops counting as bedtime this long before the first alarm.
CUTOFF = timedelta(hours=2)
# A plan this soon after bedtime started is the bedtime shortcut's own plan, not a new one.
PLAN_GRACE = timedelta(minutes=30)
# In bed while pending this long with no RUN_BEDTIME: an automatic report (item 11).
STUCK = timedelta(minutes=10)
# A nap counts for this long after its last alarm or after the napping helper went on, in case
# "nap ended" is lost (the Bedtime Nudge blueprint's own fallback, v0.4.9 item 1).
NAP_LIMIT = timedelta(hours=4)


def _time(value: Any) -> datetime | None:
    return dt_util.parse_datetime(value) if isinstance(value, str) else None


def until(state: dict[str, Any], now: datetime) -> datetime | None:
    """When bedtime stops being pending (2 h before the first alarm still to come), or None
    when it isn't pending now."""
    if _time(state.get("bedtime_pending_since")) is None:
        return None
    times = sorted(t for t in (_time(v) for v in state.get("alarm_times") or []) if t and t > now)
    if not times:
        return None
    cutoff = times[0] - CUTOFF
    return cutoff if now < cutoff else None


def napping(bridge: BedtimeBridge, now: datetime) -> bool:
    """A nap is on (v0.4.9 item 1): its alarms are set, or the napping helper has been on for
    less than 4 hours."""
    times = [t for t in (_time(v) for v in bridge.state.get("nap_alarm_times") or []) if t]
    if times and now < max(times) + NAP_LIMIT:
        return True
    helper = bridge.options.get(CONF_NAP_HELPER)
    state = bridge.hass.states.get(helper) if helper else None
    return state is not None and state.state == "on" and now - state.last_changed < NAP_LIMIT


class BedtimePending:
    """Tracks bedtime_pending_since and bedtime_started_at in bridge.state."""

    def __init__(self, bridge: BedtimeBridge) -> None:
        self.bridge = bridge
        self._stuck_unsub: Callable[[], None] | None = None

    @property
    def is_on(self) -> bool:
        return self.until is not None

    @property
    def until(self) -> datetime | None:
        return until(self.bridge.state, dt_util.utcnow())

    @callback
    def async_start(self) -> None:
        bed = self.bridge.options.get(CONF_BED_SENSOR)
        if bed:
            self.bridge.entry.async_on_unload(async_track_state_change_event(self.bridge.hass, [bed], self._bed_changed))
        self.bridge.entry.async_on_unload(self._cancel_stuck)

    def alarms_set(self) -> None:
        """App alarms were set for later. Not after bedtime already started (the bedtime
        shortcut plans as one of its steps)."""
        state = self.bridge.state
        now = dt_util.utcnow()
        started = _time(state.get("bedtime_started_at"))
        if started is not None and now - started < PLAN_GRACE:
            return
        state["bedtime_pending_since"] = now.isoformat()

    def bedtime_started(self) -> None:
        self.bridge.state["bedtime_started_at"] = dt_util.utcnow().isoformat()
        self.bridge.state["bedtime_pending_since"] = None
        self._cancel_stuck()

    def cleared(self) -> None:
        """No alarms any more (cancel, No alarms tomorrow, reset)."""
        self.bridge.state["bedtime_pending_since"] = None
        self._cancel_stuck()

    def started_tonight(self) -> bool:
        """Bedtime already ran for the alarms now set (or in the last 12 h with none set)."""
        state = self.bridge.state
        started = _time(state.get("bedtime_started_at"))
        if started is None:
            return False
        since = _time(state.get("bedtime_pending_since"))
        if since is not None:
            return started > since
        return dt_util.utcnow() - started < timedelta(hours=12)

    async def good_night(self) -> dict[str, Any]:
        """Good night from the app or Siri: RUN_BEDTIME, so the bedtime shortcut runs (it stops
        by itself if bedtime already ran tonight)."""
        if self.started_tonight():
            return {"good_night": False, "already": True}
        sent = await self.bridge._command(CMD_BEDTIME)
        self.bridge._event("good_night", sent=sent)
        return {"good_night": sent}

    # MARK: In bed with bedtime pending (item 11)

    @callback
    def _bed_changed(self, event: Event[EventStateChangedData]) -> None:
        new = event.data["new_state"]
        if new is None or new.state != "on" or not self.is_on:
            self._cancel_stuck()
            return
        if self._stuck_unsub is None:
            self._stuck_unsub = async_call_later(self.bridge.hass, STUCK, self._stuck)

    @callback
    def _stuck(self, _now: datetime) -> None:
        self._stuck_unsub = None
        bed = self.bridge.hass.states.get(self.bridge.options.get(CONF_BED_SENSOR) or "")
        # In bed for a nap isn't bedtime not starting (v0.4.9 item 1).
        if self.is_on and bed is not None and bed.state == "on" and not napping(self.bridge, dt_util.utcnow()):
            self.bridge.hass.async_create_task(reports.automatic(
                self.bridge, "bedtime_not_sent",
                f"In bed {int(STUCK.total_seconds() // 60)} minutes with bedtime pending and no RUN_BEDTIME",
                pending_since=self.bridge.state.get("bedtime_pending_since")))

    @callback
    def _cancel_stuck(self) -> None:
        if self._stuck_unsub:
            self._stuck_unsub()
            self._stuck_unsub = None
