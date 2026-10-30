"""Weekly summary (v0.4.3 item 15), from the integration's own history (Store)."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from homeassistant.util import dt as dt_util

# What the app sends (Settings → Weekly summary): on, the day (0 = Monday … 6 = Sunday), the time.
DEFAULTS: dict[str, Any] = {"enabled": True, "weekday": 6, "time": "18:00"}
# This week so far plus 8 earlier weeks (v0.4.6 item 5): 9 weeks back from the latest cut-off.
KEEP_DAYS = 64
EARLIER_WEEKS = 8


def record(history: list[dict[str, Any]], kind: str, when: datetime, **data: Any) -> None:
    """Adds an entry (morning, change, nap) and drops what's older than KEEP_DAYS."""
    history.append({"kind": kind, "time": when.isoformat(), **data})
    cutoff = when - timedelta(days=KEEP_DAYS)
    history[:] = [h for h in history if (t := dt_util.parse_datetime(h.get("time") or "")) and t >= cutoff]


def summarize(history: list[dict[str, Any]], nights: list[dict[str, Any]], now: datetime,
              since: datetime | None = None, until: datetime | None = None) -> dict[str, Any]:
    """From `since` (7 days back by default) to `until` (not included; everything up to now by
    default): average went-to-bed vs target, snoozes per morning, backstops fired, mornings
    changed (with reasons), naps."""
    since = since or now - timedelta(days=7)

    def within(t: datetime | None) -> bool:
        return t is not None and t >= since and (until is None or t < until)

    def recent(kind: str) -> list[dict[str, Any]]:
        return [h for h in history if h.get("kind") == kind and within(dt_util.parse_datetime(h.get("time") or ""))]

    mornings = recent("morning")
    changes = recent("change")
    naps = recent("nap")
    week_nights = [n for n in nights if within(dt_util.parse_datetime(n.get("go_to_bed") or ""))]
    offs = [int(n["minutes_off"]) for n in week_nights if isinstance(n.get("minutes_off"), (int, float))]
    snoozes = [int(m.get("snoozes") or 0) for m in mornings]
    summary: dict[str, Any] = {
        "from": since.isoformat(),
        "to": (until or now).isoformat(),
        "nights_tracked": len(offs),
        "bed_minutes_off_average": round(sum(offs) / len(offs)) if offs else None,
        "mornings": len(mornings),
        "snoozes_per_morning": round(sum(snoozes) / len(snoozes), 1) if snoozes else None,
        "backstops_fired": sum(int(m.get("backstops_fired") or 0) for m in mornings),
        "mornings_changed": len(changes),
        "change_reasons": [c.get("reason") or "no reason" for c in changes],
        "naps": len(naps),
        "nap_minutes": sum(int(n.get("minutes") or 0) for n in naps),
    }
    summary["text"] = text(summary)
    return summary


def text(s: dict[str, Any]) -> str:
    """"Bed 12 min after target on average · 1.3 snoozes a morning · 1 backstop fired · 2 mornings
    changed (Snow delay, Tired) · 2 naps\""""
    parts = []
    off = s.get("bed_minutes_off_average")
    if off is not None:
        parts.append("Bed on target on average" if off == 0 else f"Bed {abs(off)} min {'after' if off > 0 else 'before'} target on average")
    if s.get("snoozes_per_morning") is not None:
        parts.append(f"{s['snoozes_per_morning']:g} snoozes a morning")
    fired = s.get("backstops_fired") or 0
    parts.append("no backstops fired" if not fired else f"{fired} backstop{'s' if fired != 1 else ''} fired")
    changed = s.get("mornings_changed") or 0
    if changed:
        reasons = ", ".join(dict.fromkeys(s.get("change_reasons") or []))
        parts.append(f"{changed} morning{'s' if changed != 1 else ''} changed ({reasons})")
    naps = s.get("naps") or 0
    if naps:
        parts.append(f"{naps} nap{'s' if naps != 1 else ''}")
    return " · ".join(parts)


def last_cutoff(settings: dict[str, Any], now: datetime) -> datetime:
    """The latest week cut-off at or before `now`: the day and time in Settings → Weekly
    summary (v0.4.6 item 5), whether the notification is on or not."""
    cfg = {**DEFAULTS, **(settings or {})}
    hour, _, minute = str(cfg["time"]).partition(":")
    local = dt_util.as_local(now)
    cutoff = local.replace(hour=int(hour), minute=int(minute or 0), second=0, microsecond=0)
    cutoff -= timedelta(days=(cutoff.weekday() - int(cfg["weekday"])) % 7)
    if cutoff > local:
        cutoff -= timedelta(days=7)
    return dt_util.as_utc(cutoff)


def week_start(cutoff: datetime) -> datetime:
    """The cut-off a week before, on the local clock (the same 6 PM across a time change)."""
    return dt_util.as_utc(dt_util.as_local(cutoff) - timedelta(days=7))


def _empty(s: dict[str, Any]) -> bool:
    return not (s["nights_tracked"] or s["mornings"] or s["mornings_changed"] or s["naps"])


def weeks(history: list[dict[str, Any]], nights: list[dict[str, Any]], settings: dict[str, Any],
          now: datetime) -> list[dict[str, Any]]:
    """This week so far (since the last cut-off), then up to 8 earlier weeks, newest first,
    each as it was at its cut-off. Earlier weeks with nothing in them are left out."""
    cutoff = dt_util.as_local(last_cutoff(settings, now))
    current = {**summarize(history, nights, now, since=dt_util.as_utc(cutoff)), "current": True}
    result = [current]
    for back in range(EARLIER_WEEKS):
        end = cutoff - timedelta(days=7 * back)
        start = end - timedelta(days=7)
        week = summarize(history, nights, now, since=dt_util.as_utc(start), until=dt_util.as_utc(end))
        if not _empty(week):
            result.append({**week, "current": False})
    return result


def next_run(settings: dict[str, Any], now: datetime) -> datetime | None:
    cfg = {**DEFAULTS, **(settings or {})}
    if not cfg["enabled"]:
        return None
    hour, _, minute = str(cfg["time"]).partition(":")
    local = dt_util.as_local(now)
    candidate = local.replace(hour=int(hour), minute=int(minute or 0), second=0, microsecond=0)
    candidate += timedelta(days=(int(cfg["weekday"]) - candidate.weekday()) % 7)
    if candidate <= local:
        candidate += timedelta(days=7)
    return dt_util.as_utc(candidate)
