"""The leave-by backstop ladder (v0.4 item 6): which morning, its leave-by, and the three rung
times. Pure date arithmetic; the bridge feeds it Home Assistant's state and stores the result."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any

from homeassistant.util import dt as dt_util

RUNGS = ("early", "deadline", "late")
# How long after the late rung the morning's ladder stays (and stays locked).
LADDER_TAIL = timedelta(minutes=60)
# The app's leave-by may be at most this much later than the calendar figure.
PLAN_LATER_LIMIT = timedelta(minutes=30)
# A rung that would land in the past is published this far ahead: the Backstop's time trigger
# never fires a time that has already passed.
PAST_RUNG_LEAD = timedelta(seconds=60)

STATUS_ARMED = "armed"
STATUS_DONE = "done"
STATUS_OVERRIDE_OFF = "idle_override_off"
STATUS_LEAVE = "idle_leave"
STATUS_UNCOVERED = "idle_uncovered"
STATUS_NO_SHIFT = "idle_no_shift"
# Your own alarm on a day off or leave, with its backstops switched off (v0.4.1 item 14).
STATUS_OWN_OFF = "idle_own_off"
# Your own alarm's backstops, minutes after its LAST alarm.
DEFAULT_OWN_OFFSETS = {"early": 15, "deadline": 30, "late": 45}
STATUS_FAULT = "fault"

# Home Assistant's own bad-weather conditions, for a ladder no plan has described.
DEFAULT_WEATHER_CONDITIONS = ("pouring", "lightning-rainy", "snowy", "snowy-rainy", "hail")


@dataclass(frozen=True)
class Offsets:
    """Minutes before leave-by for each rung, and the first-day-back extra."""

    early: int = 50
    deadline: int = 35
    late: int = 20
    first_day_back: int = 15

    @property
    def valid(self) -> bool:
        return self.early > self.deadline > self.late > 0

    def as_dict(self) -> dict[str, int]:
        return {"early": self.early, "deadline": self.deadline, "late": self.late, "first_day_back": self.first_day_back}

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> Offsets:
        return cls(**{k: int(v) for k, v in (data or {}).items() if k in ("early", "deadline", "late", "first_day_back")})


@dataclass
class Morning:
    """The morning the ladder is for."""

    kind: str  # "shift" | "appointment"
    leave_by: datetime
    leave_by_source: str  # "plan" | "calendar"
    first_day_back: bool
    shift_start: datetime | None = None
    appointment: str | None = None
    appointment_start: datetime | None = None
    weather_extra_minutes: int = 0
    condition: str | None = None
    # A "wake up" appointment that replaced this shift for the morning (v0.4.1 item 11).
    replaces_shift: str | None = None
    # Your own alarm (item 14): the rungs are fixed times after its last alarm, not before a
    # leave-by; firing "gentle" (push and light ramp) or "full".
    fixed_times: dict[str, datetime] | None = None
    firing: str | None = None
    warnings: list[str] = field(default_factory=list)

    @property
    def key(self) -> str:
        """Identifies the morning, so a delay or an earlier move only applies to it."""
        start = self.shift_start or self.appointment_start or self.leave_by
        return f"{self.kind}:{dt_util.as_local(start).date().isoformat()}"


def calendar_leave_by(shift_start: datetime, fallback_drive: int, buffer: int) -> datetime:
    """Shift start − fallback drive − arrival buffer."""
    return shift_start - timedelta(minutes=fallback_drive + buffer)


def pick_leave_by(plan_leave_by: datetime | None, calendar: datetime) -> tuple[datetime, str, str | None]:
    """The app's leave-by unless it's more than 30 minutes later than the calendar's."""
    if plan_leave_by is None:
        return calendar, "calendar", None
    if plan_leave_by > calendar + PLAN_LATER_LIMIT:
        return calendar, "calendar", (
            f"Plan's leave-by {_hm(plan_leave_by)} is more than 30 min after the calendar's {_hm(calendar)}; "
            "using the calendar"
        )
    return plan_leave_by, "plan", None


def rung_times(leave_by: datetime, offsets: Offsets, first_day_back: bool, shift_minutes: int = 0) -> dict[str, datetime]:
    """The three rungs before leave-by. `shift_minutes` moves them all (positive = later)."""
    extra = offsets.first_day_back if first_day_back else 0
    move = timedelta(minutes=shift_minutes - extra)
    return {
        "early": leave_by - timedelta(minutes=offsets.early) + move,
        "deadline": leave_by - timedelta(minutes=offsets.deadline) + move,
        "late": leave_by - timedelta(minutes=offsets.late) + move,
    }


def own_times(last_alarm: datetime, offsets: dict[str, Any] | None) -> dict[str, datetime]:
    """Your own alarm's rungs: minutes after the last alarm, early < deadline < late, or the defaults."""
    try:
        minutes = {rung: int((offsets or {})[rung]) for rung in RUNGS}
    except (KeyError, TypeError, ValueError):
        minutes = DEFAULT_OWN_OFFSETS
    if not 0 <= minutes["early"] < minutes["deadline"] < minutes["late"]:
        minutes = DEFAULT_OWN_OFFSETS
    return {rung: last_alarm + timedelta(minutes=minutes[rung]) for rung in RUNGS}


def not_in_past(times: dict[str, datetime], now: datetime) -> dict[str, datetime]:
    """Rungs that would land in the past are published as now + 60 s."""
    return {rung: max(when, now + PAST_RUNG_LEAD) for rung, when in times.items()}


def same_morning(a: datetime | None, b: datetime | None) -> bool:
    return a is not None and b is not None and dt_util.as_local(a).date() == dt_util.as_local(b).date()


def worst_weather(
    forecast: list[dict[str, Any]], start: datetime, end: datetime, minutes: dict[str, int], freezing_at: float | None
) -> tuple[int, str | None]:
    """The most extra time any hour of the drive window asks for, and its condition."""
    worst, worst_condition = 0, None
    precipitation = {"rainy", "pouring", "lightning-rainy", "snowy", "snowy-rainy", "hail"}
    for hour in forecast:
        when = dt_util.parse_datetime(str(hour.get("datetime") or ""))
        if when is None or when + timedelta(hours=1) <= start or when > end:
            continue
        condition = hour.get("condition")
        found = []
        if condition in minutes:
            found.append((int(minutes[condition]), condition))
        temperature = hour.get("temperature")
        if freezing_at is not None and temperature is not None and float(temperature) <= freezing_at and condition in precipitation:
            found.append((int(minutes.get("freezing", 0)), f"freezing {condition}"))
        for amount, name in found:
            if amount > worst:
                worst, worst_condition = amount, name
    return worst, worst_condition


def _hm(when: datetime) -> str:
    return dt_util.as_local(when).strftime("%H:%M")
