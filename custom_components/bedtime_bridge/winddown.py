"""Dynamic wind-down from tomorrow's first alarm (v0.4.3 item 5).

Times come from tomorrow's FIRST alarm: what the phone has set, else its "Preview tomorrow"
answer to RUN_PLAN_PREVIEW, else the shift calendar alone. Home Assistant runs the evening:
the warning (with "15 min later" and "Cancel tonight's wind-down"), RUN_WIND_DOWN and the
Winding down helper, the critical go to bed notification and the not-in-bed reminders.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import Event, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.event import async_track_point_in_utc_time, async_track_state_change_event
from homeassistant.util import dt as dt_util

from .const import (
    CMD_PLAN_PREVIEW,
    CMD_WIND_DOWN,
    CMD_WIND_DOWN_CANCEL,
    CONF_BED_SENSOR,
    CONF_BEDROOM_DOOR,
    CONF_NOTIFY,
    CONF_PRESENCE,
    CONF_SHIFT_SENSOR,
    CONF_WIND_DOWN_HELPER,
    CONF_WIND_DOWN_NOTIFY,
    SHIFT_LEAD_PREFIX,
    WIND_DOWN_ACTION_CANCEL,
    WIND_DOWN_ACTION_LATER,
)

if TYPE_CHECKING:
    from .bridge import BedtimeBridge

_LOGGER = logging.getLogger(__name__)

# The app's Settings → Wind-down, with its defaults (off until set up).
DEFAULTS: dict[str, Any] = {
    "enabled": False,
    "sleep_goal_minutes": 390,
    "length_minutes": 60,
    "free_minutes": 30,
    "minimum_minutes": 30,
    "warning_minutes": 5,
    "later_minutes": 15,
    "reminders": True,
    "reminder_first_minutes": 10,
    "reminder_every_minutes": 10,
    "reminder_stop_minutes": 60,
    "preview_before_minutes": 120,
    "preview_fallback": "18:00",
    "own_alarm": True,
    "start_hours": 2,
}
# Never send go to bed (critical) or a reminder this long after it was due (a restart, a late change).
LATE_LIMIT = timedelta(minutes=15)
STATUSES = ["scheduled", "winding_down", "bedtime", "cancelled", "off"]
# The phone has this long to answer RUN_PLAN_PREVIEW before the shift calendar is used alone.
PREVIEW_ANSWER_MINUTES = 10
# Causes that aren't a morning of their own.
NOT_MORNINGS = ("noalarm", "temporary", "nap", None, "")


@dataclass(frozen=True)
class Times:
    wind_down: datetime
    go_to_bed: datetime


def compute(
    first_alarm: datetime, *, sleep_goal: int, length: int, free: int, minimum: int, home_at: datetime | None = None
) -> Times:
    """Go to bed = first alarm − sleep goal; wind-down = go to bed − length. Getting home late,
    wind-down waits for home + free time and lasts at least `minimum`, so bedtime moves later
    (less sleep) rather than cutting wind-down short."""
    bed = first_alarm - timedelta(minutes=sleep_goal)
    wind = bed - timedelta(minutes=length)
    if home_at is not None:
        wind = max(wind, home_at + timedelta(minutes=free))
    bed = max(bed, wind + timedelta(minutes=minimum))
    return Times(wind, bed)


def short(when: datetime) -> str:
    """8:50"""
    return dt_util.as_local(when).strftime("%-I:%M")


def long(when: datetime) -> str:
    """7:00 AM"""
    return dt_util.as_local(when).strftime("%-I:%M %p")


class WindDown:
    """Tonight's wind-down for one paired phone. State lives in bridge.state["wind_down"]."""

    def __init__(self, bridge: BedtimeBridge) -> None:
        self.bridge = bridge
        self.hass = bridge.hass
        self._unsubs: list[Callable[[], None]] = []
        self._preview_unsub: Callable[[], None] | None = None
        # The 10-minute wait for the phone's answer, kept apart so rescheduling can't drop it.
        self._unanswered_unsub: Callable[[], None] | None = None

    # MARK: State

    @property
    def s(self) -> dict[str, Any]:
        return self.bridge.state.setdefault("wind_down", {"status": "off"})

    @property
    def settings(self) -> dict[str, Any]:
        return {**DEFAULTS, **(self.bridge.state.get("wind_down_settings") or {})}

    def summary(self) -> dict[str, Any]:
        """For the app (context and replies) and the sensors."""
        s = self.s
        return {
            "status": s.get("status", "off"),
            "wind_down": s.get("wind_down"),
            "go_to_bed": s.get("go_to_bed"),
            "first_alarm": s.get("first_alarm"),
            "source": s.get("source"),
            "appointments_checked": s.get("checked", True),
            "reminders_stopped": bool(s.get("reminders_stopped")),
            "in_bed": self._in_bed(),
            "bedtime_ran": bool(s.get("bedtime_ran")),
            "went_to_bed": s.get("went_to_bed"),
            "minutes_off_target": s.get("minutes_off"),
        }

    def _option(self, key: str) -> str | None:
        return self.bridge.options.get(key) or None

    def _now(self) -> datetime:
        return dt_util.utcnow()

    def _t(self, key: str) -> datetime | None:
        value = self.s.get(key)
        return dt_util.parse_datetime(value) if isinstance(value, str) else None

    # MARK: Start

    @callback
    def async_start(self) -> None:
        watched = [e for e in (self._option(CONF_BED_SENSOR), self._option(CONF_BEDROOM_DOOR)) if e]
        if watched:
            self.bridge.entry.async_on_unload(async_track_state_change_event(self.hass, watched, self._bedroom_changed))
        presence = self.bridge.options.get(CONF_PRESENCE) or []
        if isinstance(presence, str):
            presence = [presence]
        if presence:
            self.bridge.entry.async_on_unload(async_track_state_change_event(self.hass, presence, self._presence_changed))
        sensor = self._option(CONF_SHIFT_SENSOR)
        if sensor:
            self.bridge.entry.async_on_unload(async_track_state_change_event(self.hass, [sensor], self._shift_changed))
        self.bridge.entry.async_on_unload(self.cancel_timers)
        self.bridge.entry.async_on_unload(self.hass.bus.async_listen("mobile_app_notification_action", self._action))
        self._reschedule()

    @callback
    def async_reschedule(self) -> None:
        self._reschedule()

    @callback
    def cancel_timers(self) -> None:
        for unsub in self._unsubs:
            unsub()
        self._unsubs = []
        if self._preview_unsub:
            self._preview_unsub()
            self._preview_unsub = None
        if self._unanswered_unsub:
            self._unanswered_unsub()
            self._unanswered_unsub = None

    # MARK: Inputs

    def adopt_settings(self, settings: dict[str, Any] | None) -> None:
        if not isinstance(settings, dict) or not settings:
            return
        new = {k: v for k, v in settings.items() if k in DEFAULTS}
        if new == self.bridge.state.get("wind_down_settings"):
            return
        self.bridge.state["wind_down_settings"] = new
        # Changed settings move tonight's times (or turn it on or off).
        if self._t("first_alarm"):
            self._retime()
        else:
            self._reschedule()
        self.bridge._changed()

    def _counts(self, cause: str | None) -> bool:
        """Shift mornings, wake-up events, and your own alarm when that setting is on."""
        if cause in NOT_MORNINGS:
            return False
        if cause == "automade":
            return bool(self.settings["own_alarm"])
        return True

    def refresh(self, *, moved: bool | None = None, moved_reason: str | None = None) -> None:
        """After anything that may change tomorrow's first alarm (a plan, a change, a cancel)."""
        state = self.bridge.state
        times = sorted(t for t in (dt_util.parse_datetime(v) for v in state.get("alarm_times") or [] if isinstance(v, str)) if t)
        first = next((t for t in times if t > self._now()), None)
        if first is not None and self._counts(state.get("alarm_cause")):
            if moved is not None:
                self.s["moved"] = moved
                self.s["moved_reason"] = moved_reason
            self._set_first_alarm(first, source="alarms", cause=state.get("alarm_cause"), event=state.get("label"),
                                  leave_by=state.get("leave_by"), checked=True)
        elif self.s.get("source") == "alarms" or state.get("alarm_cause") in NOT_MORNINGS:
            # The alarms went (cancel, skip, No alarms tomorrow): no wind-down tonight, whatever
            # the times came from.
            self._turn_off("no alarm")
        self.bridge._changed()

    def preview_answered(self, data: dict[str, Any]) -> None:
        """The phone's "Preview tomorrow": first alarm, cause, event, leave-by."""
        self.adopt_settings(data.get("wind_down_settings"))
        self.s["preview_answered"] = self._now().isoformat()
        if self._unanswered_unsub:
            self._unanswered_unsub()
            self._unanswered_unsub = None
        if self.s.get("source") == "alarms" and self._t("first_alarm") and self._t("first_alarm") > self._now():
            # Alarms already set win over a preview.
            self._reschedule()
            return
        first = dt_util.parse_datetime(data["first_alarm"]) if isinstance(data.get("first_alarm"), str) else None
        if first is None or not self._counts(data.get("cause")):
            self._turn_off("no alarm tomorrow")
        else:
            self.s["moved"] = bool(data.get("moved"))
            self.s["moved_reason"] = data.get("moved_reason")
            self._set_first_alarm(first, source="preview", cause=data.get("cause"), event=data.get("event"),
                                  leave_by=data.get("leave_by"), checked=True, event_start=data.get("event_start"))
        self.bridge._changed()

    def _set_first_alarm(self, first: datetime, *, source: str, cause: str | None, event: str | None,
                         leave_by: str | None, checked: bool, event_start: str | None = None) -> None:
        s = self.s
        night = dt_util.as_local(first).date().isoformat()
        if s.get("night") != night:
            # A new night: start over (a cancel from last night doesn't carry).
            self._close_night()
            self.bridge.state["wind_down"] = s = {"status": "off", "night": night}
        s.update(first_alarm=first.isoformat(), source=source, cause=cause, event=event, leave_by=leave_by,
                 checked=checked, event_start=event_start)
        self._retime()

    def _retime(self) -> None:
        """Works the times out again; tells you once if wind-down is running and go to bed moved."""
        s = self.s
        first = self._t("first_alarm")
        if first is None or not self.settings["enabled"]:
            self._turn_off("wind-down off" if first else "no alarm")
            return
        cfg = self.settings
        times = compute(first, sleep_goal=int(cfg["sleep_goal_minutes"]), length=int(cfg["length_minutes"]),
                        free=int(cfg["free_minutes"]), minimum=int(cfg["minimum_minutes"]), home_at=self._home_at())
        wind = times.wind_down + timedelta(minutes=int(s.get("later_minutes") or 0))
        wind = min(wind, times.go_to_bed - timedelta(minutes=int(cfg["minimum_minutes"])))
        old_bed = self._t("go_to_bed")
        status = s.get("status", "off")
        if status in ("off", "scheduled") and times.go_to_bed <= self._now():
            # Go to bed already passed (a change in the morning, or a late plan): nothing tonight.
            s.update(status="off", wind_down=None, go_to_bed=times.go_to_bed.isoformat(), bed_notified=True, reminders_stopped=True)
            self._reschedule()
            return
        if status in ("off", "scheduled"):
            s["status"] = "scheduled"
            s["wind_down"] = wind.isoformat()
        elif status == "winding_down":
            # It carries on; only go to bed moves.
            pass
        s["go_to_bed"] = times.go_to_bed.isoformat()
        if status == "winding_down" and old_bed and abs((old_bed - times.go_to_bed).total_seconds()) >= 60:
            self.hass.async_create_task(self._notify(
                "New bedtime", f"Go to bed at {short(times.go_to_bed)} · first alarm {short(first)}", tag="wind_down_moved"))
            self.hass.async_create_task(self._live())
        self._reschedule()

    def _home_at(self) -> datetime | None:
        """When you got home this evening, if that's later than the usual wind-down allows for."""
        value = self.s.get("home_at")
        return dt_util.parse_datetime(value) if isinstance(value, str) else None

    def _turn_off(self, why: str) -> None:
        s = self.s
        if s.get("status") == "winding_down":
            self.hass.async_create_task(self._helper(False))
            self.hass.async_create_task(self.bridge._command(CMD_WIND_DOWN_CANCEL))
            self.hass.async_create_task(self.bridge.live.end_wind_down())
        if s.get("status") not in ("off", None):
            s["status"] = "off"
            s["off_reason"] = why
        s["wind_down"] = None
        s["go_to_bed"] = None
        s["first_alarm"] = None
        s["source"] = None
        self._reschedule()

    # MARK: Timers

    @callback
    def _reschedule(self) -> None:
        for unsub in self._unsubs:
            unsub()
        self._unsubs = []
        now = self._now()
        s = self.s
        status = s.get("status", "off")
        wind, bed, first = self._t("wind_down"), self._t("go_to_bed"), self._t("first_alarm")

        def at(when: datetime | None, action: Callable[[], Any]) -> None:
            if when is not None and when > now:
                self._unsubs.append(async_track_point_in_utc_time(self.hass, callback(lambda _n: self.hass.async_create_task(action())), when))

        if status == "scheduled" and wind:
            warning = int(self.settings["warning_minutes"] or 0)
            if warning and s.get("warned_for") != s.get("wind_down"):
                at(wind - timedelta(minutes=warning), self._warn)
            if wind <= now < (bed or wind):
                self.hass.async_create_task(self._start())
            else:
                at(wind, self._start)
        if status in ("scheduled", "winding_down") and bed:
            if bed <= now and not s.get("bed_notified"):
                if now - bed <= LATE_LIMIT:
                    self.hass.async_create_task(self._go_to_bed())
                else:
                    # Too late to say so (Home Assistant was down): it's bedtime, quietly.
                    s.update(status="bedtime", bed_notified=True)
                    self.hass.async_create_task(self._helper(False))
            else:
                at(bed, self._go_to_bed)
        reminding = self.settings["reminders"] and not (s.get("reminders_stopped") or s.get("bedtime_ran") or s.get("went_to_bed"))
        if status in ("scheduled", "winding_down", "bedtime") and bed and reminding:
            at(self._next_reminder(now), self._remind)
        if first:
            # The morning: tonight is over.
            at(first, self._morning)
        if status in ("off", "cancelled") or first is None:
            self._schedule_preview()

    def _schedule_preview(self) -> None:
        """RUN_PLAN_PREVIEW: preview-before the wind-down the shift calendar gives, or the
        fallback time when only an appointment might decide tomorrow."""
        if self._preview_unsub:
            self._preview_unsub()
            self._preview_unsub = None
        if not self.settings["enabled"]:
            return
        now = self._now()
        when = self._calendar_preview_time(now)
        if when is None:
            hour, _, minute = str(self.settings["preview_fallback"]).partition(":")
            local = dt_util.as_local(now).replace(hour=int(hour), minute=int(minute or 0), second=0, microsecond=0)
            when = dt_util.as_utc(local)
            if when <= now and self.s.get("preview_sent_day") == dt_util.as_local(now).date().isoformat():
                when = dt_util.as_utc(local + timedelta(days=1))
        if self.s.get("preview_sent_for") == when.isoformat():
            self._arm_unanswered()
            return
        if when <= now:
            # Missed (HA restarted): ask now if it's still the evening before.
            if now - when < timedelta(hours=4):
                self.hass.async_create_task(self._preview(when))
            return
        self._preview_unsub = async_track_point_in_utc_time(
            self.hass, callback(lambda _n: self.hass.async_create_task(self._preview(when))), when)

    def _calendar_estimate(self, now: datetime) -> tuple[datetime, str] | None:
        """Tomorrow's first alarm from the shift calendar alone: next shift start − its lead."""
        sensor = self.hass.states.get(self._option(CONF_SHIFT_SENSOR) or "")
        start = dt_util.parse_datetime(sensor.attributes.get("next_shift_start") or "") if sensor else None
        if start is None or not now < start < now + timedelta(hours=36):
            return None
        kind = sensor.attributes.get("next_shift_type") or "Days"
        lead = self.bridge.setting_value(f"{SHIFT_LEAD_PREFIX}{kind}") or 120
        return start - timedelta(minutes=int(lead)), kind

    def _calendar_preview_time(self, now: datetime) -> datetime | None:
        estimate = self._calendar_estimate(now)
        if estimate is None:
            return None
        cfg = self.settings
        times = compute(estimate[0], sleep_goal=int(cfg["sleep_goal_minutes"]), length=int(cfg["length_minutes"]),
                        free=int(cfg["free_minutes"]), minimum=int(cfg["minimum_minutes"]))
        return times.wind_down - timedelta(minutes=int(cfg["preview_before_minutes"]))

    def _next_reminder(self, now: datetime) -> datetime | None:
        """Every reminder_every after go to bed (or after you got up again), first after
        reminder_first, for reminder_stop."""
        s, cfg = self.s, self.settings
        start = self._t("reminders_from") or self._t("go_to_bed")
        if start is None:
            return None
        first, every, stop = (int(cfg[k]) for k in ("reminder_first_minutes", "reminder_every_minutes", "reminder_stop_minutes"))
        sent = int(s.get("reminders_sent") or 0)
        when = start + timedelta(minutes=first + every * sent)
        # Missed slots (a restart) are skipped, not sent in a burst.
        while when < now - timedelta(seconds=30):
            when += timedelta(minutes=every)
        if when > start + timedelta(minutes=stop):
            return None
        return max(when, now + timedelta(seconds=1))

    # MARK: The evening

    async def _preview(self, when: datetime) -> None:
        self.s["preview_sent_for"] = when.isoformat()
        self.s["preview_sent_day"] = dt_util.as_local(self._now()).date().isoformat()
        self.s["preview_sent_at"] = self._now().isoformat()
        self.s["preview_answered"] = None
        await self.bridge._command(CMD_PLAN_PREVIEW)
        self.bridge._changed()
        self._arm_unanswered()

    @callback
    def _arm_unanswered(self) -> None:
        """Waits PREVIEW_ANSWER_MINUTES for the phone (also after a restart)."""
        sent = self._t("preview_sent_at")
        if sent is None or self.s.get("preview_answered") or self._unanswered_unsub:
            return
        due = sent + timedelta(minutes=PREVIEW_ANSWER_MINUTES)
        if due <= self._now():
            self.hass.async_create_task(self._preview_unanswered())
            return
        self._unanswered_unsub = async_track_point_in_utc_time(
            self.hass, callback(lambda _n: self.hass.async_create_task(self._preview_unanswered())), due)

    async def _preview_unanswered(self) -> None:
        """No answer: the shift calendar alone, and the warning says appointments weren't checked."""
        self._unanswered_unsub = None
        if self.s.get("preview_answered"):
            return
        self.s["preview_answered"] = "unanswered"
        if self.s.get("source") in ("alarms", "preview") and (self._t("first_alarm") or self._now()) > self._now():
            return
        estimate = self._calendar_estimate(self._now())
        if estimate is None:
            return
        self.s["moved"] = False
        self._set_first_alarm(estimate[0], source="calendar", cause=estimate[1], event=estimate[1], leave_by=None, checked=False)
        self.bridge._changed()

    async def _warn(self) -> None:
        s = self.s
        wind, bed = self._t("wind_down"), self._t("go_to_bed")
        if s.get("status") != "scheduled" or wind is None or bed is None:
            return
        s["warned_for"] = s.get("wind_down")
        unchecked = "" if s.get("checked", True) else " (appointments not checked)"
        await self._notify(
            "Wind-down soon", f"Wind-down at {short(wind)} · bed {short(bed)}{unchecked}", tag="wind_down_warning",
            actions=[
                {"action": WIND_DOWN_ACTION_LATER, "title": f"{int(self.settings['later_minutes'])} min later"},
                {"action": WIND_DOWN_ACTION_CANCEL, "title": "Cancel tonight's wind-down", "destructive": True},
            ],
        )
        self.bridge._changed()

    async def start_now(self) -> bool:
        """"Start wind-down now" (app, control, Siri): everything wind-down does, right away;
        go to bed unchanged."""
        bed, wind, now = self._t("go_to_bed"), self._t("wind_down"), self._now()
        if self.s.get("status") not in ("scheduled", "cancelled") or bed is None:
            return False
        # Only from start_hours before go to bed, and not once go to bed has passed.
        if not bed - timedelta(hours=int(self.settings["start_hours"])) <= now < bed:
            return False
        if self.s.get("status") == "cancelled":
            self.s["reminders_stopped"] = False
        self.s["status"] = "scheduled"
        self.s["wind_down"] = self._now().isoformat()
        await self._start()
        return True

    async def _start(self) -> None:
        s = self.s
        if s.get("status") != "scheduled":
            return
        s["status"] = "winding_down"
        s["started_at"] = self._now().isoformat()
        if self.bridge.is_home():
            await self._helper(True)
        await self.bridge._command(CMD_WIND_DOWN)
        first = self._t("first_alarm")
        # An event morning, or a first alarm moved from its usual time: say so once.
        if first and (s.get("cause") == "calendar" or s.get("moved")):
            unchecked = "" if s.get("checked", True) else " (appointments not checked)"
            if s.get("cause") == "calendar":
                start = dt_util.parse_datetime(s.get("event_start") or "")
                what = f"{s.get('event') or 'Appointment'}" + (f" at {long(start)} tomorrow" if start else " tomorrow")
            else:
                why = f" ({s.get('moved_reason')})" if s.get("moved_reason") else ""
                what = f"{s.get('event') or s.get('cause')} tomorrow{why}"
            leave = dt_util.parse_datetime(s.get("leave_by") or "")
            parts = [what] + ([f"leave by {short(leave)}"] if leave else []) + [f"first alarm {short(first)}"]
            await self._notify("Tomorrow", " · ".join(parts) + unchecked, tag="wind_down_tomorrow")
        self.bridge._event("wind_down_started", wind_down=s.get("wind_down"), go_to_bed=s.get("go_to_bed"))
        self._reschedule()
        await self._live()

    async def later(self) -> None:
        """"15 min later": moves wind-down, not go to bed, never below the minimum."""
        s = self.s
        if s.get("status") != "scheduled":
            return
        s["later_minutes"] = int(s.get("later_minutes") or 0) + int(self.settings["later_minutes"])
        s["warned_for"] = None
        self._retime()
        self.bridge._changed()

    async def cancel(self) -> None:
        """Tonight's wind-down off: helper off, no go to bed notification or reminders."""
        s = self.s
        if s.get("status") not in ("scheduled", "winding_down"):
            return
        was_running = s.get("status") == "winding_down"
        s["status"] = "cancelled"
        s["reminders_stopped"] = True
        if was_running:
            await self._helper(False)
        await self.bridge._command(CMD_WIND_DOWN_CANCEL)
        await self._clear("wind_down_warning")
        await self.bridge.live.end_wind_down()
        self.bridge._event("wind_down_cancelled")
        self._reschedule()

    async def _go_to_bed(self) -> None:
        s = self.s
        if s.get("status") not in ("scheduled", "winding_down") or s.get("bed_notified"):
            return
        s["bed_notified"] = True
        first = self._t("first_alarm")
        if self.bridge.is_home():
            await self._helper(False)
        if not self._in_bed():
            # Critical: it's the one that has to get through. No buttons, no phone command
            # (the bedtime shortcut turns Sleep Focus on, which replaces Wind Down).
            await self._notify("Time for bed", f"Time for bed · first alarm {short(first)}" if first else "Time for bed",
                               tag="wind_down_bed", critical=True)
        s["status"] = "bedtime"
        await self.bridge.live.end_wind_down()
        # Plug in your phone at go to bed too (v0.4.3 item 10).
        await self.bridge.charge_check()
        self.bridge._event("wind_down_go_to_bed", go_to_bed=s.get("go_to_bed"))
        self._reschedule()

    async def _remind(self) -> None:
        s = self.s
        if s.get("reminders_stopped") or s.get("bedtime_ran") or s.get("went_to_bed") or not self.settings["reminders"]:
            return
        bed = self._t("go_to_bed")
        if bed is None or self._now() < bed:
            self._reschedule()
            return
        s["reminders_sent"] = int(s.get("reminders_sent") or 0) + 1
        # Away overnight: no reminders. In bed: nothing to say.
        if self.bridge.is_home() and not self._in_bed():
            first = self._t("first_alarm")
            await self._notify("Still up", f"Still up · first alarm {short(first)}" if first else "Still up",
                               tag="wind_down_reminder", time_sensitive=True)
        self.bridge._changed()
        self._reschedule()

    def stop_reminders(self) -> None:
        self.s["reminders_stopped"] = True
        self.bridge._changed()
        self._reschedule()

    async def bedtime_ran(self) -> None:
        """Into bed (the bedtime shortcut): before or during wind-down it ends there (helper
        off, nothing more); after go to bed the reminders stop."""
        s = self.s
        s["bedtime_ran"] = True
        status = s.get("status")
        if status == "winding_down":
            await self._helper(False)
            await self.bridge.live.end_wind_down()
        if status in ("scheduled", "winding_down", "bedtime"):
            s["status"] = "bedtime"
            s["bed_notified"] = True
        self._reschedule()

    def bedtime_undone(self) -> None:
        """Not ready for bed / undo bedtime: wind-down doesn't restart; only the reminders run,
        from go to bed (or from now, if that's past)."""
        s = self.s
        if s.get("status") != "bedtime" or self._t("go_to_bed") is None:
            return
        s["bedtime_ran"] = False
        s["reminders_stopped"] = False
        bed = self._t("go_to_bed")
        if bed <= self._now():
            s["reminders_from"] = self._now().isoformat()
            s["reminders_sent"] = 0
        self._reschedule()

    async def _morning(self) -> None:
        self._close_night()
        self.bridge.state["wind_down"] = {"status": "off"}
        self.bridge._changed()
        self._reschedule()

    def _close_night(self) -> None:
        """Keeps last night in history (went to bed vs target) for the weekly summary."""
        s = self.s
        if not s.get("go_to_bed") or s.get("recorded"):
            return
        s["recorded"] = True
        history = self.bridge.state.setdefault("wind_down_history", [])
        history.append({
            "night": s.get("night"), "go_to_bed": s.get("go_to_bed"), "went_to_bed": s.get("went_to_bed"),
            "minutes_off": s.get("minutes_off"), "cancelled": s.get("status") == "cancelled",
        })
        del history[:-60]

    # MARK: Bedroom and presence

    def _in_bed(self) -> bool:
        """Bedroom door closed AND bed occupied (either missing counts as not known: in bed)."""
        bed = self.hass.states.get(self._option(CONF_BED_SENSOR) or "")
        door = self.hass.states.get(self._option(CONF_BEDROOM_DOOR) or "")
        bed_on = bed is not None and bed.state == "on"
        door_closed = door is None or door.state == "off"
        return bed_on and door_closed

    @callback
    def _bedroom_changed(self, _event: Event) -> None:
        s = self.s
        started = self._t("started_at") or self._t("wind_down")
        if s.get("went_to_bed") or started is None or self._now() < started or not self._in_bed():
            return
        now = self._now()
        s["went_to_bed"] = now.isoformat()
        bed = self._t("go_to_bed")
        if bed:
            s["minutes_off"] = round((now - bed).total_seconds() / 60)
        self.bridge._changed()

    @callback
    def _presence_changed(self, event: Event) -> None:
        new = event.data.get("new_state")
        if new is None or new.state != "home":
            return
        s = self.s
        wind = self._t("wind_down")
        if s.get("status") == "scheduled" and wind is not None and self._now() + timedelta(minutes=int(self.settings["free_minutes"])) > wind:
            # Home late: wind-down waits for home + free time, then lasts at least the minimum.
            s["home_at"] = self._now().isoformat()
            self._retime()
            self.bridge._changed()

    @callback
    def _shift_changed(self, _event: Event) -> None:
        source = self.s.get("source")
        if source == "calendar" and self.s.get("status") in ("scheduled", "winding_down"):
            # Times from the calendar alone follow it: a changed or deleted shift moves or ends them.
            estimate = self._calendar_estimate(self._now())
            if estimate is None:
                self._turn_off("shift gone")
            else:
                self._set_first_alarm(estimate[0], source="calendar", cause=estimate[1], event=estimate[1], leave_by=None, checked=False)
            self.bridge._changed()
        elif source is None:
            self._reschedule()

    @callback
    def _action(self, event: Event) -> None:
        action = event.data.get("action")
        if action == WIND_DOWN_ACTION_LATER:
            self.hass.async_create_task(self.later())
        elif action == WIND_DOWN_ACTION_CANCEL:
            self.hass.async_create_task(self.cancel())

    # MARK: Effects

    async def _helper(self, on: bool) -> None:
        helper = self._option(CONF_WIND_DOWN_HELPER)
        if not helper:
            return
        state = self.hass.states.get(helper)
        if state is not None and state.state == ("on" if on else "off"):
            return
        try:
            await self.hass.services.async_call("homeassistant", "turn_on" if on else "turn_off", {"entity_id": helper})
        except HomeAssistantError as err:
            _LOGGER.warning("Bedtime Bridge couldn't turn %s %s: %s", helper, "on" if on else "off", err)

    async def _live(self) -> None:
        """The wind-down Live Activity by push (with an Apple push key)."""
        bed = self._t("go_to_bed")
        if self.s.get("status") == "winding_down" and bed and bed > self._now():
            await self.bridge.live.wind_down(bed, self._t("first_alarm"))

    async def turn_helper_off(self) -> None:
        await self._helper(False)

    def _notify_service(self) -> tuple[str, str] | None:
        notify = (self._option(CONF_WIND_DOWN_NOTIFY) or self._option(CONF_NOTIFY) or "").strip()
        if not notify:
            return None
        domain, _, service = notify.partition(".")
        return domain, service

    async def _notify(self, title: str, message: str, *, tag: str, actions: list[dict[str, Any]] | None = None,
                      critical: bool = False, time_sensitive: bool = False, url: str | None = None) -> None:
        target = self._notify_service()
        if target is None:
            return
        data: dict[str, Any] = {"tag": f"bedtime_bridge_{tag}"}
        if actions:
            data["actions"] = actions
        if url:
            data["url"] = url
        # Settings → Notifications in the app picks each one's level; the flags are the defaults.
        default = "critical" if critical else "time_sensitive" if time_sensitive else "normal"
        level = (self.bridge.state.get("notification_levels") or {}).get(tag, default)
        if level == "critical":
            data["push"] = {"sound": {"name": "default", "critical": 1, "volume": 1.0}, "interruption-level": "critical"}
        elif level == "time_sensitive":
            data["push"] = {"interruption-level": "time-sensitive"}
        try:
            await self.hass.services.async_call(target[0], target[1], {"title": title, "message": message, "data": data})
        except HomeAssistantError as err:
            _LOGGER.warning("Bedtime Bridge couldn't send %s: %s", title, err)

    async def _clear(self, tag: str) -> None:
        target = self._notify_service()
        if target is None:
            return
        try:
            await self.hass.services.async_call(target[0], target[1], {"message": "clear_notification", "data": {"tag": f"bedtime_bridge_{tag}"}})
        except HomeAssistantError:
            pass
