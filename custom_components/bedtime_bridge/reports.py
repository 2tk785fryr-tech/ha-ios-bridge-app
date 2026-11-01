"""Testing reports (v0.4.8 items 9 and 11): what you report from the app, and what the app or
Home Assistant reports by itself, appended to bedtime_bridge_reports/reports.jsonl in the config
folder (not www, which is served without signing in), for Claude to read with the Home Assistant
tools."""

from __future__ import annotations

import base64
import binascii
from datetime import timedelta
import json
import logging
from pathlib import Path
from typing import TYPE_CHECKING, Any

from homeassistant.util import dt as dt_util

if TYPE_CHECKING:
    from .bridge import BedtimeBridge

_LOGGER = logging.getLogger(__name__)

FOLDER = "bedtime_bridge_reports"
FILE = "reports.jsonl"
# The last 200 reports are kept.
KEEP = 200
KEEP_SCREENSHOTS = 50
# A night runs noon to noon, so 1 AM and 11 PM are the same night.
_NIGHT_TURNS = timedelta(hours=12)


def _append(folder: Path, line: str, screenshot: bytes | None, name: str) -> None:
    """In the executor: adds the line, drops the oldest past KEEP, saves the screenshot."""
    folder.mkdir(exist_ok=True)
    path = folder / FILE
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    lines.append(line)
    path.write_text("\n".join(lines[-KEEP:]) + "\n", encoding="utf-8")
    if screenshot:
        (folder / f"{name}.png").write_bytes(screenshot)
        for old in sorted(folder.glob("*.png"))[:-KEEP_SCREENSHOTS]:
            old.unlink(missing_ok=True)


def _matches(report: dict[str, Any], report_id: str | None, time: str | None) -> bool:
    """The phone's own report: by its id, or (sent before 0.4.10) by the time it was made."""
    if report.get("automatic"):
        return False
    if report_id and report.get("report_id") == report_id:
        return True
    return bool(time) and not report.get("report_id") and report.get("time") == time


def _rewrite(folder: Path, report_id: str | None, time: str | None, note: str | None, edited: str) -> bool:
    """In the executor: replaces the matching report's note (note given) or removes it and its
    screenshot (note None). Whether one matched."""
    path = folder / FILE
    if not path.exists():
        return False
    kept: list[str] = []
    found = False
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            report = json.loads(line)
        except ValueError:
            kept.append(line)
            continue
        if found or not isinstance(report, dict) or not _matches(report, report_id, time):
            kept.append(line)
            continue
        found = True
        if note is None:
            if shot := report.get("screenshot_file"):
                (folder / Path(shot).name).unlink(missing_ok=True)
            continue
        report["note"] = note
        report["edited"] = edited
        kept.append(json.dumps(report, default=str, ensure_ascii=False))
    if found:
        path.write_text("\n".join(kept) + ("\n" if kept else ""), encoding="utf-8")
    return found


async def change(bridge: BedtimeBridge, data: dict[str, Any]) -> dict[str, Any]:
    """v0.4.10 item 13: `edits` (a new note) or `deletes` a report you sent, by the phone's
    `report_id` (or its `time`, for reports from before 0.4.10). Automatic reports can't be
    deleted or edited. An edit of a report that isn't there is saved as a new one."""
    deleting = "deletes" in data
    report_id = data.get("deletes") if deleting else data.get("edits")
    note = None if deleting else str(data.get("note") or "")
    folder = Path(bridge.hass.config.path(FOLDER))
    edited = dt_util.utcnow().isoformat()
    try:
        found = await bridge.hass.async_add_executor_job(_rewrite, folder, report_id, data.get("time"), note, edited)
    except OSError as err:
        _LOGGER.warning("Bedtime Bridge couldn't change a report: %s", err)
        return {"saved": False}
    if found or deleting:
        return {"saved": found, "deleted" if deleting else "edited": found}
    report = {k: v for k, v in data.items() if k != "edits"}
    report["report_id"] = report_id
    return await save(bridge, report)


async def save(bridge: BedtimeBridge, report: dict[str, Any]) -> dict[str, Any]:
    """One report. `screenshot` (base64 PNG) is saved next to the file, not in it."""
    report = dict(report)
    now = dt_util.utcnow()
    report.setdefault("time", now.isoformat())
    report.setdefault("received", now.isoformat())
    name = dt_util.as_local(now).strftime("%Y-%m-%d_%H%M%S")
    screenshot = None
    if isinstance(report.get("screenshot"), str):
        try:
            screenshot = base64.b64decode(report.pop("screenshot"), validate=True)
            report["screenshot_file"] = f"{name}.png"
        except (binascii.Error, ValueError):
            report.pop("screenshot", None)
    folder = Path(bridge.hass.config.path(FOLDER))
    line = json.dumps(report, default=str, ensure_ascii=False)
    try:
        await bridge.hass.async_add_executor_job(_append, folder, line, screenshot, name)
    except OSError as err:
        _LOGGER.warning("Bedtime Bridge couldn't save a report: %s", err)
        return {"saved": False}
    first = str(report.get("note") or report.get("kind") or "").strip().replace("\n", " ")[:60]
    _LOGGER.warning("Bedtime Bridge report%s: %s", " (automatic)" if report.get("automatic") else "", first or "(no note)")
    return {"saved": True, "id": name}


async def automatic(bridge: BedtimeBridge, kind: str, saw: str, **details: Any) -> bool:
    """Home Assistant's own report, at most one per kind per night (so a loop can't flood it)."""
    night = dt_util.as_local(dt_util.utcnow() - _NIGHT_TURNS).date().isoformat()
    sent: dict[str, str] = bridge.state.setdefault("auto_reported", {})
    if sent.get(kind) == night:
        return False
    sent[kind] = night
    bridge._changed()
    await save(bridge, {"automatic": True, "source": "home_assistant", "kind": kind, "note": saw, "details": details,
                        "state": snapshot(bridge)})
    return True


def snapshot(bridge: BedtimeBridge) -> dict[str, Any]:
    """What Home Assistant knows, alongside the app's snapshot."""
    s = bridge.state
    return {
        "alarm_times": s.get("alarm_times"),
        "alarm_cause": s.get("alarm_cause"),
        "bedtime_pending_since": s.get("bedtime_pending_since"),
        "bedtime_started_at": s.get("bedtime_started_at"),
        "ladder": (s.get("ladder") or {}).get("status"),
        "wind_down": (s.get("wind_down") or {}).get("status"),
        "snoozed_until": s.get("snoozed_until"),
        "last_command": s.get("last_command"),
        "home": bridge.is_home(),
    }
