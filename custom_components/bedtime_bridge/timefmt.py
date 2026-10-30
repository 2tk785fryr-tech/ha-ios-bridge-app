"""How times read in notifications and Live Activities (v0.4.7 item 10): 12- or 24-hour, as the
app's Settings → Clock says (sent with every message as `clock_24h`)."""

from __future__ import annotations

from datetime import datetime

from homeassistant.util import dt as dt_util

_use_24h = False


def set_24h(on: bool) -> None:
    global _use_24h
    _use_24h = bool(on)


def uses_24h() -> bool:
    return _use_24h


def short(when: datetime) -> str:
    """8:50, or 20:50"""
    return dt_util.as_local(when).strftime("%H:%M" if _use_24h else "%-I:%M")


def long(when: datetime) -> str:
    """7:00 AM, or 07:00"""
    return dt_util.as_local(when).strftime("%H:%M" if _use_24h else "%-I:%M %p")


def day_long(when: datetime) -> str:
    """Fri 7:00 AM, or Fri 07:00"""
    return dt_util.as_local(when).strftime("%a %H:%M" if _use_24h else "%a %-I:%M %p")


def hour(when: datetime) -> str:
    """6 AM, or 06:00"""
    return dt_util.as_local(when).strftime("%H:00" if _use_24h else "%-I %p")
