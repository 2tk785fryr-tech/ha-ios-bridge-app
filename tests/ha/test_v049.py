"""v0.4.9 integration tests, by spec item."""

from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import AsyncMock, patch

from homeassistant.util import dt as dt_util

from custom_components.bedtime_bridge import liveactivity as la
from custom_components.bedtime_bridge import pending, reports

from .test_ladder import TZ
from .test_live_activity import APP, KEY
from .test_v048 import BED, _local, _own_alarms, _start, _tick
from .test_webhook import send

HELPER = "input_boolean.napping"


def _reports(tmp_path) -> list[str]:
    path = Path(tmp_path) / reports.FOLDER / reports.FILE
    return path.read_text().splitlines() if path.exists() else []


# MARK: Item 1, naps and the in-bed report


async def test_item1_no_report_in_bed_during_a_nap(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    # 31 Oct: own alarms for 5:00 tomorrow at 15:59, a nap at 16:00.
    await _start(hass, freezer, _local(31, "15:59"))
    await send(hass_client_no_auth, _own_alarms(_local(31, "05:00") + timedelta(days=1)))
    await _tick(hass, freezer, 1)
    await send(hass_client_no_auth, {"type": "nap_started", "data": {"alarm_times": [_local(31, "16:30").isoformat(), _local(31, "16:40").isoformat()]}})
    hass.states.async_set(BED, "on")
    await hass.async_block_till_done()
    await _tick(hass, freezer, 11)
    assert _reports(tmp_path) == [], "a nap isn't bedtime not starting"


async def test_item1_the_report_comes_back_once_the_nap_is_over(hass, hass_client_no_auth, freezer, tmp_path):
    hass.config.config_dir = str(tmp_path)
    await _start(hass, freezer, _local(31, "15:59"))
    await send(hass_client_no_auth, _own_alarms(_local(31, "05:00") + timedelta(days=1)))
    await send(hass_client_no_auth, {"type": "nap_started", "data": {"alarm_times": [_local(31, "16:30").isoformat()]}})
    await send(hass_client_no_auth, {"type": "nap_ended", "data": {}})
    hass.states.async_set(BED, "on")
    await hass.async_block_till_done()
    await _tick(hass, freezer, 11)
    assert len(_reports(tmp_path)) == 1


async def test_item1_the_napping_helper_counts_for_4_hours(hass, freezer):
    await _start(hass, freezer, _local(31, "16:00"), napping_helper=HELPER)
    bridge = hass.config_entries.async_entries("bedtime_bridge")[0].runtime_data
    hass.states.async_set(HELPER, "on")
    assert pending.napping(bridge, dt_util.utcnow() + timedelta(hours=3, minutes=59))
    assert not pending.napping(bridge, dt_util.utcnow() + timedelta(hours=4, minutes=1)), "the blueprint's fallback"
    hass.states.async_set(HELPER, "off")
    assert not pending.napping(bridge, dt_util.utcnow())


# MARK: Item 6, Home Assistant's morning Live Activity and another morning's ladder


async def test_item6_the_morning_activity_leaves_out_mondays_backstops_on_sunday(hass, hass_client_no_auth, freezer):
    sent = AsyncMock(return_value=200)
    with patch.object(la.ApnsClient, "send", sent):
        entry = await _start(hass, freezer, _local(31, "21:00"), apns_key=KEY, apns_key_id="KEYID12345")
        entry = hass.config_entries.async_entries("bedtime_bridge")[0]
        await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "start", "token": "start-token"}})
        bridge = entry.runtime_data
        sunday = _local(31, "07:00") + timedelta(days=1)
        monday = _local(31, "05:40") + timedelta(days=2)
        freezer.move_to(sunday - timedelta(hours=1))
        bridge.state["leave_by"] = sunday.isoformat()
        bridge.state["ladder"] = {"status": "armed", "morning": "shift:2026-11-02", "times": {"early": monday.isoformat()}}
        await bridge.live.morning()
        state = sent.call_args.args[1]["aps"]["content-state"]
        assert state.get("nextBackstop") is None, "Monday's ladder isn't Sunday's"
        bridge.state["ladder"]["morning"] = "shift:2026-11-01"
        bridge.state["ladder"]["times"] = {"early": (sunday - timedelta(minutes=20)).isoformat()}
        await bridge.live.morning()
        assert sent.call_args.args[1]["aps"]["content-state"]["nextBackstopName"] == "Early"


# MARK: Item 7, daylight saving time


async def test_item7_curtains_keep_sunrises_clock_time_across_the_clocks_going_back(hass, hass_client_no_auth, freezer):
    await _start(hass, freezer, _local(31, "05:00"), curtain_offset_minutes=15)
    # Saturday morning before sunrise: the next sunrise is today's, still on summer time.
    hass.states.async_set("sun.sun", "below_horizon", {"next_rising": _local(31, "07:34").isoformat()})
    monday = _local(31, "05:00") + timedelta(days=2)
    reply = await send(hass_client_no_auth, {"type": "context", "data": {"first_alarm": monday.isoformat()}})
    opens = dt_util.as_local(dt_util.parse_datetime(reply["curtains_open_at"]))
    assert opens.strftime("%d %H:%M") == "02 07:49", "sunrise 7:34 + 15, not an hour early on winter time"


async def test_item7_and_when_they_go_forward(hass, hass_client_no_auth, freezer):
    tz = dt_util.get_time_zone(TZ)
    await _start(hass, freezer, datetime(2027, 3, 13, 5, 0, tzinfo=tz), curtain_offset_minutes=15)
    hass.states.async_set("sun.sun", "below_horizon", {"next_rising": datetime(2027, 3, 13, 6, 30, tzinfo=tz).isoformat()})
    reply = await send(hass_client_no_auth, {"type": "context", "data": {"first_alarm": datetime(2027, 3, 14, 6, 0, tzinfo=tz).isoformat()}})
    opens = dt_util.as_local(dt_util.parse_datetime(reply["curtains_open_at"]))
    assert opens.strftime("%d %H:%M") == "14 06:45"


async def test_item7_a_5am_alarm_planned_the_evening_before_each_change(hass):
    await hass.config.async_set_time_zone(TZ)
    tz = dt_util.get_time_zone(TZ)
    for evening, alarm in ((datetime(2026, 10, 31, 21, 0, tzinfo=tz), datetime(2026, 11, 1, 5, 0, tzinfo=tz)),
                           (datetime(2027, 3, 13, 21, 0, tzinfo=tz), datetime(2027, 3, 14, 5, 0, tzinfo=tz))):
        bridge = type("B", (), {"state": {"bedtime_pending_since": evening.isoformat(), "alarm_times": [alarm.isoformat()]}})
        # Pending until 2 real hours before the alarm, whatever the clocks did in between.
        assert pending.until(bridge.state, evening) == alarm - pending.CUTOFF
        assert dt_util.as_local(pending.until(bridge.state, evening)).strftime("%H:%M") == "03:00"
