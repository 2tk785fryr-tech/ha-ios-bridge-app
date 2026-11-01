"""v0.4.10 integration tests, by spec item."""

import base64
import json
from pathlib import Path

from pytest_homeassistant_custom_component.common import async_mock_service

from custom_components.bedtime_bridge import reports

from .test_v048 import _local, _start
from .test_webhook import PLAN, send, setup


def _messages(notify) -> list[str]:
    return [c.data["message"] for c in notify]


# MARK: Item 2, good morning waits for the wake-up's last alarm


async def test_item2_no_good_morning_on_a_stop_with_alarms_still_set(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test", phone_commands=True)
    await send(hass_client_no_auth, PLAN)
    # 1 Nov 08:18: one alarm ended with the 8:19 snooze and the 8:20 still set.
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": ["2026-11-01T13:20:00+00:00"]}})
    await hass.async_block_till_done()
    assert "RUN_GOOD_MORNING" not in _messages(notify)
    # The last one, then a repeat: good morning once.
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()
    assert _messages(notify) == ["RUN_GOOD_MORNING"]


async def test_item2_the_hold_ends_them_all_and_runs_good_morning(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test", phone_commands=True)
    await send(hass_client_no_auth, PLAN)
    await send(hass_client_no_auth, {"type": "stopped", "data": {"all": True, "alarm_times": []}})
    await hass.async_block_till_done()
    assert _messages(notify) == ["RUN_GOOD_MORNING"]


async def test_item2_a_new_plan_is_a_new_wake_up(hass, hass_client_no_auth):
    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await setup(hass, notify_service="notify.mobile_app_test", phone_commands=True)
    for _ in range(2):
        await send(hass_client_no_auth, PLAN)
        await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
    await hass.async_block_till_done()
    assert _messages(notify) == ["RUN_GOOD_MORNING", "RUN_GOOD_MORNING"]


# MARK: Item 13, editing and deleting a report you sent


def _lines(tmp_path) -> list[dict]:
    path = Path(tmp_path) / reports.FOLDER / reports.FILE
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


async def test_item13_an_edit_replaces_the_line(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "08:30"))
    await send(hass_client_no_auth, {"type": "report", "data": {"note": "Typo here", "report_id": "A", "time": "t1"}})
    await send(hass_client_no_auth, {"type": "report", "data": {"note": "Other", "report_id": "B", "time": "t2"}})
    reply = await send(hass_client_no_auth, {"type": "report", "data": {"edits": "A", "time": "t1", "note": "Fixed here"}})
    assert reply["edited"] is True
    lines = _lines(tmp_path)
    assert [r["note"] for r in lines] == ["Fixed here", "Other"], "replaced in place, not appended"
    assert "received" in lines[0] and "edited" in lines[0]


async def test_item13_an_edit_of_an_unknown_report_is_saved_as_new(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "08:30"))
    await send(hass_client_no_auth, {"type": "report", "data": {"edits": "Z", "time": "t9", "note": "Lost one"}})
    lines = _lines(tmp_path)
    assert [(r["note"], r["report_id"]) for r in lines] == [("Lost one", "Z")]


async def test_item13_a_delete_removes_the_line_and_its_screenshot(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "08:30"))
    png = base64.b64encode(b"\x89PNG fake").decode()
    await send(hass_client_no_auth, {"type": "report", "data": {"note": "Delete me", "report_id": "A", "screenshot": png}})
    shot = Path(tmp_path) / reports.FOLDER / _lines(tmp_path)[0]["screenshot_file"]
    assert shot.exists()
    reply = await send(hass_client_no_auth, {"type": "report", "data": {"deletes": "A"}})
    assert reply["deleted"] is True
    assert _lines(tmp_path) == [] and not shot.exists()


async def test_item13_a_delete_of_an_unknown_report_changes_nothing(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "08:30"))
    await send(hass_client_no_auth, {"type": "report", "data": {"note": "Keep", "report_id": "A"}})
    reply = await send(hass_client_no_auth, {"type": "report", "data": {"deletes": "nope"}})
    assert reply["deleted"] is False
    assert [r["note"] for r in _lines(tmp_path)] == ["Keep"]


async def test_item13_automatic_reports_stay(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "08:30"))
    await send(hass_client_no_auth, {"type": "report", "data": {"note": "Auto", "automatic": True, "report_id": "A", "time": "t1"}})
    await send(hass_client_no_auth, {"type": "report", "data": {"deletes": "A", "time": "t1"}})
    assert [r["note"] for r in _lines(tmp_path)] == ["Auto"]


async def test_item13_reports_from_before_0410_match_by_time(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "08:30"))
    await send(hass_client_no_auth, {"type": "report", "data": {"note": "Old", "time": "2026-11-01T07:07:39-05:00"}})
    await send(hass_client_no_auth, {"type": "report", "data": {"edits": "X", "time": "2026-11-01T07:07:39-05:00", "note": "Old, edited"}})
    assert [r["note"] for r in _lines(tmp_path)] == ["Old, edited"]
