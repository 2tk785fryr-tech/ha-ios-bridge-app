"""v0.4.8 integration tests, by spec item."""

import base64
import json
from datetime import datetime, timedelta
from pathlib import Path

from homeassistant.data_entry_flow import FlowResultType
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_fire_time_changed, async_mock_service

from custom_components.bedtime_bridge import config_flow as cf
from custom_components.bedtime_bridge import pending, reports

from .test_ladder import TZ
from .test_webhook import send, setup

BED = "binary_sensor.bed"
PENDING = "binary_sensor.bedtime_bridge_bedtime_pending"


def _local(day: int, hm: str) -> datetime:
    hour, minute = (int(x) for x in hm.split(":"))
    return datetime(2026, 10, day, hour, minute, tzinfo=dt_util.get_time_zone(TZ))


def _own_alarms(*times: datetime) -> dict:
    """What the app sends after Set alarms for a time."""
    return {"type": "planned", "data": {
        "alarm_cause": "manual", "alarm_time": times[0].isoformat(), "wake_time": times[-1].isoformat(),
        "alarm_times": [t.isoformat() for t in times], "reason": "Your own time", "alarm_style": "app", "has_alarm": True,
    }}


async def _start(hass, freezer, at: datetime, **options):
    await hass.config.async_set_time_zone(TZ)
    freezer.move_to(at)
    notify = async_mock_service(hass, "notify", "phone")
    hass.states.async_set(BED, "off")
    await setup(hass, **{"notify_service": "notify.phone", "phone_commands": True, "bed_sensor": BED, **options})
    return notify


async def _tick(hass, freezer, minutes: float):
    now = dt_util.utcnow() + timedelta(minutes=minutes)
    freezer.move_to(now)
    async_fire_time_changed(hass, now)
    await hass.async_block_till_done()


def _messages(notify) -> list[str]:
    return [call.data.get("message") for call in notify if call.data.get("message") != "clear_notification"]


# MARK: Item 1, bedtime pending


async def test_item1_last_night_own_alarms_at_352_make_bedtime_pending_at_401(hass, hass_client_no_auth, freezer):
    await _start(hass, freezer, _local(31, "03:52"))
    alarms = [_local(31, "09:40"), _local(31, "09:50"), _local(31, "10:00")]
    await send(hass_client_no_auth, _own_alarms(*alarms))
    await hass.async_block_till_done()
    state = hass.states.get(PENDING)
    assert state.state == "on"
    assert dt_util.parse_datetime(state.attributes["until"]) == alarms[0] - pending.CUTOFF
    # 4:01, past the nudge's 04:00 window end: still pending, so the nudge goes ahead.
    await _tick(hass, freezer, 9)
    assert hass.states.get(PENDING).state == "on"


async def test_item1_bedtime_running_ends_pending(hass, hass_client_no_auth, freezer):
    await _start(hass, freezer, _local(30, "22:00"))
    await send(hass_client_no_auth, _own_alarms(_local(31, "06:00")))
    await hass.async_block_till_done()
    assert hass.states.get(PENDING).state == "on"
    await send(hass_client_no_auth, {"type": "command_ran", "data": {"command": "RUN_BEDTIME", "outcome": "ran"}})
    await hass.async_block_till_done()
    assert hass.states.get(PENDING).state == "off"
    # The bedtime shortcut's own Plan Wake-Up Alarms right after doesn't make it pending again.
    await _tick(hass, freezer, 1)
    await send(hass_client_no_auth, _own_alarms(_local(31, "06:00")))
    await hass.async_block_till_done()
    assert hass.states.get(PENDING).state == "off"


async def test_item1_pending_turns_off_2_hours_before_the_first_alarm(hass, hass_client_no_auth, freezer):
    await _start(hass, freezer, _local(31, "05:00"))
    await send(hass_client_no_auth, _own_alarms(_local(31, "08:00")))
    await hass.async_block_till_done()
    assert hass.states.get(PENDING).state == "on"
    await _tick(hass, freezer, 61)
    assert hass.states.get(PENDING).state == "off"


async def test_item1_cancelled_alarms_end_pending(hass, hass_client_no_auth, freezer):
    await _start(hass, freezer, _local(30, "23:00"))
    await send(hass_client_no_auth, _own_alarms(_local(31, "09:00")))
    await send(hass_client_no_auth, {"type": "cancelled", "data": {"sleep_in": True}})
    await hass.async_block_till_done()
    assert hass.states.get(PENDING).state == "off"


# MARK: Item 5, Good night


async def test_item5_good_night_sends_run_bedtime_once(hass, hass_client_no_auth, freezer):
    notify = await _start(hass, freezer, _local(30, "23:00"))
    await send(hass_client_no_auth, _own_alarms(_local(31, "07:00")))
    reply = await send(hass_client_no_auth, {"type": "good_night", "data": {}})
    assert reply["good_night"] is True
    assert _messages(notify) == ["RUN_BEDTIME"]
    await send(hass_client_no_auth, {"type": "command_ran", "data": {"command": "RUN_BEDTIME", "outcome": "ran"}})
    reply = await send(hass_client_no_auth, {"type": "good_night", "data": {}})
    assert reply == {**reply, "good_night": False, "already": True}
    assert _messages(notify) == ["RUN_BEDTIME"]


async def test_item5_good_night_without_phone_commands_says_not_sent(hass, hass_client_no_auth, freezer):
    await _start(hass, freezer, _local(30, "23:00"), phone_commands=False)
    reply = await send(hass_client_no_auth, {"type": "good_night", "data": {}})
    assert reply["good_night"] is False and "already" not in reply


# MARK: Items 9 and 11, reports


async def test_item9_a_report_is_saved_outside_www(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "08:30"))
    png = base64.b64encode(b"\x89PNG fake").decode()
    reply = await send(hass_client_no_auth, {"type": "report", "data": {
        "note": "Bar showed Re-plan in the up-early window", "app": {"bar": "Plan changed · re-plan"}, "screenshot": png}})
    await hass.async_block_till_done()
    assert reply["saved"] is True
    folder = Path(tmp_path) / reports.FOLDER
    lines = (folder / reports.FILE).read_text().splitlines()
    saved = json.loads(lines[-1])
    assert saved["note"].startswith("Bar showed Re-plan") and saved["app"]["bar"] == "Plan changed · re-plan"
    assert "screenshot" not in saved and (folder / saved["screenshot_file"]).read_bytes() == b"\x89PNG fake"
    assert "home_assistant" in saved and saved["source"] == "app"
    assert not (Path(tmp_path) / "www").exists()


async def test_item9_only_the_last_200_are_kept(hass, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "08:30"))
    bridge = hass.config_entries.async_entries("bedtime_bridge")[0].runtime_data
    for n in range(reports.KEEP + 5):
        await reports.save(bridge, {"note": f"r{n}"})
    lines = (Path(tmp_path) / reports.FOLDER / reports.FILE).read_text().splitlines()
    assert len(lines) == reports.KEEP and json.loads(lines[0])["note"] == "r5"


async def test_item11_in_bed_with_bedtime_pending_and_no_run_bedtime(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "03:52"))
    await send(hass_client_no_auth, _own_alarms(_local(31, "10:00")))
    await _tick(hass, freezer, 9)
    hass.states.async_set(BED, "on")
    await hass.async_block_till_done()
    await _tick(hass, freezer, 11)
    lines = (Path(tmp_path) / reports.FOLDER / reports.FILE).read_text().splitlines()
    saved = json.loads(lines[-1])
    assert saved["automatic"] is True and saved["kind"] == "bedtime_not_sent"
    # Once a night: getting up and back in doesn't add another.
    hass.states.async_set(BED, "off")
    hass.states.async_set(BED, "on")
    await hass.async_block_till_done()
    await _tick(hass, freezer, 11)
    assert len((Path(tmp_path) / reports.FOLDER / reports.FILE).read_text().splitlines()) == 1


async def test_item11_a_push_that_never_reports_it_ran(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(30, "23:00"))
    await send(hass_client_no_auth, {"type": "good_night", "data": {}})
    await _tick(hass, freezer, 11)
    saved = json.loads((Path(tmp_path) / reports.FOLDER / reports.FILE).read_text().splitlines()[-1])
    assert saved["kind"] == "not_ran_run_bedtime"


async def test_item11_no_report_when_the_shortcut_reports_it_ran(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(30, "23:00"))
    await send(hass_client_no_auth, {"type": "good_night", "data": {}})
    await send(hass_client_no_auth, {"type": "command_ran", "data": {"command": "RUN_BEDTIME", "outcome": "ran"}})
    await _tick(hass, freezer, 11)
    assert not (Path(tmp_path) / reports.FOLDER / reports.FILE).exists()


# MARK: Item 14, health check


async def test_item14_health_says_what_home_assistant_has(hass, hass_client_no_auth, freezer):
    await _start(hass, freezer, _local(30, "22:00"))
    await send(hass_client_no_auth, _own_alarms(_local(31, "06:00")))
    reply = await send(hass_client_no_auth, {"type": "health", "data": {}})
    assert reply["alarm_times"] == [_local(31, "06:00").isoformat()]
    assert reply["phone_commands"] is True and reply["push_token"] is False and reply["bedtime_pending"] is True
    await send(hass_client_no_auth, {"type": "live_activity", "data": {"kind": "device", "token": "abc"}})
    assert (await send(hass_client_no_auth, {"type": "health", "data": {}}))["push_token"] is True


# MARK: Item 10, back to the menu after a page


async def test_item10_a_page_goes_back_to_the_menu_and_save_saves_them_all(hass, freezer):
    entry = await setup(hass, notify_service="notify.phone")
    result = await hass.config_entries.options.async_init(entry.entry_id)
    assert result["menu_options"][-1] == "save"
    assert "Save and close" in cf.changed_text([]) and "Changed" not in cf.changed_text([])
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "bedroom"})
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"rearm_minutes": 7, "rerun_minutes": 15})
    assert result["type"] is FlowResultType.MENU
    assert result["description_placeholders"]["changed"].startswith("**Changed: Bedroom and bed.**")
    assert entry.options.get("rearm_minutes") != 7, "nothing saved yet"
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "phone"})
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"notify_service": "notify.other"})
    assert "Bedroom and bed, Phone" in result["description_placeholders"]["changed"]
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "save"})
    assert result["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()
    assert entry.options["rearm_minutes"] == 7 and entry.options["notify_service"] == "notify.other"


async def test_item10_a_page_submitted_unchanged_is_just_back(hass, freezer):
    entry = await setup(hass, notify_service="notify.phone")
    result = await hass.config_entries.options.async_init(entry.entry_id)
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "phone"})
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"notify_service": "notify.phone"})
    assert result["type"] is FlowResultType.MENU
    assert "Changed" not in result["description_placeholders"]["changed"]
