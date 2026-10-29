"""v0.4 item 6: the leave-by backstop ladder. Spec acceptance tests, in local time (New York):
06:30 Days start, 35 min fallback drive, 10 min early → calendar leave-by 05:45."""

from datetime import datetime, timedelta
import logging

import pytest
from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_fire_time_changed

from .test_webhook import send, setup

TZ = "America/New_York"
SHIFT = "2026-10-28T06:30:00-04:00"
CALENDAR = "calendar.work"
WEATHER = "weather.forecast_home"


def local(hhmm: str, day: int = 28) -> datetime:
    hour, minute = (int(x) for x in hhmm.split(":"))
    return datetime(2026, 10, day, hour, minute, tzinfo=dt_util.get_time_zone(TZ))


def shift_sensor(hass, start=SHIFT, shift="Days", source="calendar", state="Days"):
    hass.states.async_set(
        "sensor.current_shift", state,
        {"next_shift_start": start, "next_shift_type": shift, "effective_shift": shift, "deadline_source": source},
    )


def rungs(hass) -> list[str] | None:
    out = []
    for rung in ("early", "deadline", "late"):
        state = hass.states.get(f"sensor.bedtime_bridge_ladder_{rung}")
        if state.state in ("unavailable", "unknown"):
            return None
        out.append(dt_util.as_local(dt_util.parse_datetime(state.state)).strftime("%H:%M"))
    return out


def attrs(hass) -> dict:
    return hass.states.get("sensor.bedtime_bridge_ladder_early").attributes


def status(hass) -> str:
    return hass.states.get("sensor.bedtime_bridge_ladder_status").state


def plan(leave_by=None, *, kind="shift", shift_start=SHIFT, first_day_back=False, **extra) -> dict:
    ladder = {"type": kind, "leave_by": leave_by, "first_day_back": first_day_back, "work_buffer_minutes": 10, **extra}
    if kind == "shift":
        ladder["shift_start"] = shift_start
    return {"type": "planned", "data": {"alarm_cause": "Days", "alarm_times": [], "has_alarm": True, "ladder": ladder}}


@pytest.fixture
async def calendar_days(hass: HomeAssistant):
    """The work calendar; by default the day before had a shift (so not a first day back)."""
    days_worked = {"value": True}

    async def get_events(call: ServiceCall):
        events = [{"summary": "Days", "start": "x", "end": "y"}] if days_worked["value"] else []
        return {CALENDAR: {"events": events}}

    hass.states.async_set(CALENDAR, "off")
    hass.services.async_register("calendar", "get_events", get_events, supports_response=SupportsResponse.ONLY)
    return days_worked


@pytest.fixture
async def ladder(hass: HomeAssistant, freezer, calendar_days):
    await hass.config.async_set_time_zone(TZ)
    freezer.move_to(local("20:00", day=27))
    shift_sensor(hass)
    hass.states.async_set("input_select.select_shift_override", "Days")

    async def start(**options):
        entry = await setup(hass, calendar_entity=CALENDAR, weather_entity=WEATHER, **options)
        await hass.async_block_till_done()
        return entry

    return start


async def tick(hass, freezer, **delta):
    freezer.tick(timedelta(**delta))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()


async def test_no_plan_normal_days(hass, ladder):
    await ladder()
    assert rungs(hass) == ["04:55", "05:10", "05:25"]
    assert attrs(hass)["leave_by_source"] == "calendar"
    assert attrs(hass)["first_day_back"] is False
    assert status(hass) == "armed"


async def test_plan_leave_by_earlier(hass, ladder, hass_client_no_auth):
    await ladder()
    await send(hass_client_no_auth, plan(local("05:30").isoformat()))
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:40", "04:55", "05:10"]
    assert attrs(hass)["leave_by_source"] == "plan"


async def test_plan_leave_by_within_thirty_minutes_later(hass, ladder, hass_client_no_auth):
    await ladder()
    await send(hass_client_no_auth, plan(local("06:05").isoformat()))
    await hass.async_block_till_done()
    assert rungs(hass) == ["05:15", "05:30", "05:45"]
    assert attrs(hass)["leave_by_source"] == "plan"


async def test_plan_leave_by_too_late_uses_calendar(hass, ladder, hass_client_no_auth, caplog):
    await ladder()
    with caplog.at_level(logging.WARNING):
        await send(hass_client_no_auth, plan(local("06:30").isoformat()))
        await hass.async_block_till_done()
    assert rungs(hass) == ["04:55", "05:10", "05:25"]
    assert attrs(hass)["leave_by_source"] == "calendar"
    assert "more than 30 min after the calendar" in caplog.text


async def test_plan_for_another_morning_is_ignored(hass, ladder, hass_client_no_auth):
    await ladder()
    await send(hass_client_no_auth, plan(local("05:30", day=29).isoformat(), shift_start="2026-10-29T06:30:00-04:00"))
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:55", "05:10", "05:25"]
    assert attrs(hass)["leave_by_source"] == "calendar"


async def test_appointment(hass, ladder, hass_client_no_auth):
    shift_sensor(hass, start="2026-10-30T06:30:00-04:00")
    await ladder()
    await send(hass_client_no_auth, plan(
        local("09:00").isoformat(), kind="appointment", appointment="Dentist", appointment_start=local("09:40").isoformat()
    ))
    await hass.async_block_till_done()
    assert rungs(hass) == ["08:10", "08:25", "08:40"]
    assert attrs(hass)["appointment"] == "Dentist"
    assert attrs(hass)["first_day_back"] is False


async def test_first_day_back(hass, ladder, calendar_days):
    calendar_days["value"] = False
    await ladder()
    assert rungs(hass) == ["04:40", "04:55", "05:10"]
    assert attrs(hass)["first_day_back"] is True

    await hass.services.async_call(
        "number", "set_value", {"entity_id": "number.bedtime_bridge_first_day_back_extra", "value": 0}, blocking=True
    )
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:55", "05:10", "05:25"], "0 turns the extra off"


async def test_first_day_back_from_the_plan(hass, ladder, hass_client_no_auth):
    await ladder()
    await send(hass_client_no_auth, plan(local("05:45").isoformat(), first_day_back=True))
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:40", "04:55", "05:10"]
    assert attrs(hass)["first_day_back"] is True


async def test_calendar_lookup_failing_applies_the_extra(hass, ladder):
    hass.states.async_remove(CALENDAR)
    await ladder()
    assert rungs(hass) == ["04:40", "04:55", "05:10"], "fail early, not late"


@pytest.mark.parametrize(
    ("change", "expected"),
    [
        ({"override": "Off"}, "idle_override_off"),
        ({"source": "leave"}, "idle_leave"),
        ({"shift": "Swings"}, "idle_uncovered"),
        ({"start": None}, "idle_no_shift"),
    ],
)
async def test_what_turns_it_off(hass, ladder, change, expected):
    if "override" in change:
        hass.states.async_set("input_select.select_shift_override", change["override"])
    shift_sensor(hass, start=change.get("start", SHIFT), shift=change.get("shift", "Days"), source=change.get("source", "calendar"))
    await ladder()
    assert rungs(hass) is None, "rungs read unavailable whenever the ladder isn't armed"
    assert status(hass) == expected
    assert hass.states.get("sensor.bedtime_bridge_ladder_status").attributes["reason"]


async def test_turning_off_and_back_on_follows_the_shift_sensor(hass, ladder):
    await ladder()
    hass.states.async_set("input_select.select_shift_override", "Off")
    await hass.async_block_till_done()
    assert status(hass) == "idle_override_off"
    hass.states.async_set("input_select.select_shift_override", "Days")
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:55", "05:10", "05:25"]


async def test_alarms_never_move_it(hass, ladder, hass_client_no_auth):
    await ladder()
    for message in (
        {"type": "snoozed", "data": {"rings_again": local("04:40").isoformat()}},
        {"type": "stopped", "data": {"alarm_times": [local("04:45").isoformat()]}},
        {"type": "stopped", "data": {"all": True, "alarm_times": []}},
    ):
        await send(hass_client_no_auth, message)
        await hass.async_block_till_done()
        assert rungs(hass) == ["04:55", "05:10", "05:25"]


@pytest.mark.parametrize(
    "message",
    [
        {"type": "cancelled", "data": {}},
        {"type": "skipped", "data": {"morning": "2026-10-28T09:00:00-04:00"}},
        {"type": "bedtime_undone", "data": {}},
    ],
)
async def test_messages_that_clear_the_plan_recompute_without_wiping(hass, ladder, hass_client_no_auth, message):
    await ladder()
    await send(hass_client_no_auth, plan(local("05:30").isoformat()))
    await send(hass_client_no_auth, message)
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:40", "04:55", "05:10"]


async def test_inside_the_lock_nothing_moves_it(hass, ladder, freezer):
    await ladder()
    freezer.move_to(local("05:00"))
    shift_sensor(hass, start="2026-10-28T07:00:00-04:00")
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:55", "05:10", "05:25"]

    hass.states.async_set("input_select.select_shift_override", "Off")
    await hass.async_block_till_done()
    assert status(hass) == "armed", "fail loud: the morning lock holds"


async def test_morning_change_moves_all_three_and_persists(hass, ladder, freezer):
    entry = await ladder()
    entry.runtime_data.change_morning_ladder(120, "app", "snow delay")
    await hass.async_block_till_done()
    assert rungs(hass) == ["06:55", "07:10", "07:25"]
    assert attrs(hass)["delay_minutes"] == 120
    assert attrs(hass)["reason"] == "snow delay"

    # Through a restart...
    for _ in range(2):
        await tick(hass, freezer, seconds=5)
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    assert rungs(hass) == ["06:55", "07:10", "07:25"]
    # ...and a current_shift update before the lock.
    shift_sensor(hass)
    hass.states.async_set("sensor.current_shift", "Days", {**hass.states.get("sensor.current_shift").attributes, "last_success": "now"})
    await hass.async_block_till_done()
    assert rungs(hass) == ["06:55", "07:10", "07:25"]

    # Cleared once that morning's ladder ends (late + 60 min); the next morning has none.
    shift_sensor(hass, start="2026-10-29T06:30:00-04:00")
    await hass.async_block_till_done()
    freezer.move_to(local("08:26"))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:55", "05:10", "05:25"]
    assert attrs(hass)["delay_minutes"] == 0
    assert dt_util.as_local(dt_util.parse_datetime(attrs(hass)["shift_start"])).day == 29


async def test_worse_weather_moves_remaining_rungs_earlier(hass, ladder, hass_client_no_auth, freezer):
    forecast = {"condition": "rainy"}

    async def get_forecasts(call: ServiceCall):
        hours = [{"datetime": local(f"{h:02d}:00").isoformat(), "condition": forecast["condition"], "temperature": 40} for h in range(3, 9)]
        return {WEATHER: {"forecast": hours}}

    hass.states.async_set(WEATHER, "rainy")
    hass.services.async_register("weather", "get_forecasts", get_forecasts, supports_response=SupportsResponse.ONLY)
    await ladder()
    await send(hass_client_no_auth, plan(
        local("05:30").isoformat(), weather_extra_minutes=15, condition="rainy", weather_minutes={"rainy": 15, "snowy": 30}
    ))
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:40", "04:55", "05:10"]

    freezer.move_to(local("03:00"))
    await tick(hass, freezer, minutes=15)
    assert rungs(hass) == ["04:40", "04:55", "05:10"], "same weather as planned"

    forecast["condition"] = "snowy"
    await tick(hass, freezer, minutes=15)
    assert rungs(hass) == ["04:25", "04:40", "04:55"], "snow +30, the plan already had +15"
    assert attrs(hass)["condition"] == "snowy"

    forecast["condition"] = "rainy"
    await tick(hass, freezer, minutes=15)
    assert rungs(hass) == ["04:25", "04:40", "04:55"], "better weather never moves it later"


async def test_a_rung_moved_into_the_past_is_published_a_minute_ahead(hass, ladder, hass_client_no_auth, freezer):
    await ladder()
    await send(hass_client_no_auth, plan(local("05:30").isoformat()))
    await hass.async_block_till_done()
    freezer.move_to(local("04:50"))
    # Traffic: the phone's recheck on stop says leave 20 minutes earlier.
    await send(hass_client_no_auth, {"type": "leave_by", "data": {"leave_by": local("05:10").isoformat(), "drive_minutes": 55}})
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:40", "04:51", "04:51"], "early already passed; the others would be past, so now + 60 s"


async def test_restart_with_the_shift_sensor_unavailable_keeps_the_ladder(hass, ladder, freezer):
    entry = await ladder()
    for _ in range(2):
        await tick(hass, freezer, seconds=5)
    hass.states.async_set("sensor.current_shift", "unavailable", {})
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    assert rungs(hass) == ["04:55", "05:10", "05:25"]


async def test_crossed_settings_keep_the_last_valid_ladder(hass, ladder, caplog):
    await ladder()
    with caplog.at_level(logging.WARNING):
        await hass.services.async_call(
            "number", "set_value", {"entity_id": "number.bedtime_bridge_ladder_late", "value": 40}, blocking=True
        )
        await hass.async_block_till_done()
    assert rungs(hass) == ["04:55", "05:10", "05:25"]
    assert "ladder settings cross" in caplog.text


async def test_no_shift_sensor_at_all_is_a_fault(hass, ladder):
    hass.states.async_remove("sensor.current_shift")
    await ladder()
    assert status(hass) == "fault"
    assert rungs(hass) is None


async def test_after_an_appointment_morning_with_no_covered_shift_the_status_is_idle_not_done(hass, ladder, hass_client_no_auth, freezer):
    """v0.4.1 item 19: a day off before Swings must not read "done" all day."""
    shift_sensor(hass, start="2026-10-30T14:00:00-04:00", shift="Swings")
    await ladder()
    await send(hass_client_no_auth, plan(local("09:00").isoformat(), kind="appointment", appointment="Dentist",
                                         appointment_start=local("09:40").isoformat()))
    await hass.async_block_till_done()
    assert status(hass) == "armed"
    freezer.move_to(local("09:41"))  # late 08:40 + 60 min
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert status(hass) == "idle_uncovered"
    assert rungs(hass) is None


async def test_after_a_shift_morning_the_next_shift_arms_without_waiting_for_current_shift(hass, ladder, freezer):
    """v0.4.1 item 19: current_shift still shows today's shift after late + 60."""
    async def get_events(call):
        start = dt_util.parse_datetime(str(call.data["start_date_time"]))
        if start.date().isoformat() >= "2026-10-28":
            return {CALENDAR: {"events": [{"summary": "Days", "start": "2026-10-29T06:30:00-04:00", "end": "2026-10-29T19:00:00-04:00"}]}}
        return {CALENDAR: {"events": [{"summary": "Days", "start": "x", "end": "y"}]}}

    hass.services.async_register("calendar", "get_events", get_events, supports_response=SupportsResponse.ONLY)
    await ladder()
    assert rungs(hass) == ["04:55", "05:10", "05:25"]
    freezer.move_to(local("06:26"))  # late 05:25 + 60 min; current_shift unchanged
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert status(hass) == "armed"
    assert dt_util.as_local(dt_util.parse_datetime(attrs(hass)["shift_start"])).day == 29
    assert rungs(hass) == ["04:55", "05:10", "05:25"]


async def test_after_a_shift_morning_with_nothing_ahead_the_status_says_so(hass, ladder, freezer):
    async def get_events(call):
        start = dt_util.parse_datetime(str(call.data["start_date_time"]))
        if start.date().isoformat() >= "2026-10-28":
            return {CALENDAR: {"events": []}}
        return {CALENDAR: {"events": [{"summary": "Days", "start": "x", "end": "y"}]}}

    hass.services.async_register("calendar", "get_events", get_events, supports_response=SupportsResponse.ONLY)
    await ladder()
    freezer.move_to(local("06:26"))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert status(hass) == "idle_no_shift"


async def test_a_marked_appointment_replacing_the_shift_gets_the_ladder(hass, ladder, hass_client_no_auth):
    """v0.4.1 item 11: going in late for a 7:00 ultrasound on a Days morning."""
    await ladder()
    await send(hass_client_no_auth, plan(local("06:35").isoformat(), kind="appointment", appointment="Ultrasound",
                                         appointment_start=local("07:00").isoformat(), replaces_shift="Days"))
    await hass.async_block_till_done()
    assert rungs(hass) == ["05:45", "06:00", "06:15"], "the appointment's leave-by, not the shift's 05:45"
    assert attrs(hass)["replaces_shift"] == "Days"
    assert attrs(hass)["appointment"] == "Ultrasound"


def own_plan(last: str, on: bool, **extra) -> dict:
    ladder = {"type": "own", "last_alarm": local(last).isoformat(), "on": on,
              "offsets": {"early": 15, "deadline": 30, "late": 45}, "firing": "gentle", **extra}
    return {"type": "planned", "data": {"alarm_cause": "automade", "alarm_times": [], "has_alarm": True, "ladder": ladder}}


async def test_own_alarm_backstops_are_off_unless_switched_on(hass, ladder, hass_client_no_auth):
    """v0.4.1 item 14: a day off, your own alarm at 8:00."""
    shift_sensor(hass, start=None)
    await ladder()
    await send(hass_client_no_auth, own_plan("08:00", on=False))
    await hass.async_block_till_done()
    assert status(hass) == "idle_own_off"
    assert rungs(hass) is None

    await send(hass_client_no_auth, own_plan("08:00", on=True))
    await hass.async_block_till_done()
    assert rungs(hass) == ["08:15", "08:30", "08:45"], "after the last alarm"
    assert attrs(hass)["firing"] == "gentle"


async def test_own_alarm_offsets_that_cross_fall_back_to_the_defaults(hass, ladder, hass_client_no_auth):
    shift_sensor(hass, start=None)
    await ladder()
    await send(hass_client_no_auth, own_plan("08:00", on=True, offsets={"early": 30, "deadline": 20, "late": 45}))
    await hass.async_block_till_done()
    assert rungs(hass) == ["08:15", "08:30", "08:45"]


async def test_own_alarm_backstops_edited_in_the_preview(hass, ladder, hass_client_no_auth):
    """v0.4.1 item 18: times edited (and one removed) in Wake at a different time's preview."""
    shift_sensor(hass, start=None)
    await ladder()
    await send(hass_client_no_auth, own_plan("08:00", on=True, times={"early": local("08:20").isoformat(), "late": local("09:00").isoformat()}))
    await hass.async_block_till_done()
    early = hass.states.get("sensor.bedtime_bridge_ladder_early").state
    assert dt_util.as_local(dt_util.parse_datetime(early)).strftime("%H:%M") == "08:20"
    assert hass.states.get("sensor.bedtime_bridge_ladder_deadline").state == "unknown", "removed"
    late = hass.states.get("sensor.bedtime_bridge_ladder_late").state
    assert dt_util.as_local(dt_util.parse_datetime(late)).strftime("%H:%M") == "09:00"


async def test_leave_checks_at_each_reminder_follow_a_new_leave_by(hass, ladder, hass_client_no_auth, freezer):
    """v0.4.1 item 17: RUN_LEAVE_CHECK at 15 min before and at leave time; a fresh leave-by moves the rest."""
    from pytest_homeassistant_custom_component.common import async_mock_service

    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await ladder(notify_service="notify.mobile_app_test", phone_commands=True)
    data = plan(local("05:45").isoformat())
    data["data"]["leave_by"] = local("05:45").isoformat()
    data["data"]["leave_reminders"] = [15, 0]
    await send(hass_client_no_auth, data)
    await hass.async_block_till_done()

    pushes = lambda: [c.data["message"] for c in notify if c.data.get("message") == "RUN_LEAVE_CHECK"]  # noqa: E731
    freezer.move_to(local("05:30"))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert pushes() == ["RUN_LEAVE_CHECK"]

    # The phone's check: 10 min worse, leave by 05:35, so "at leave time" moves to 05:35.
    await send(hass_client_no_auth, {"type": "leave_by", "data": {"leave_by": local("05:35").isoformat(), "drive_minutes": 45}})
    freezer.move_to(local("05:35") + timedelta(seconds=30))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert pushes() == ["RUN_LEAVE_CHECK", "RUN_LEAVE_CHECK"]


async def test_leave_checks_stop_once_youve_left(hass, ladder, hass_client_no_auth, freezer):
    from pytest_homeassistant_custom_component.common import async_mock_service

    notify = async_mock_service(hass, "notify", "mobile_app_test")
    hass.states.async_set("person.me", "home")
    await ladder(notify_service="notify.mobile_app_test", phone_commands=True, presence_entities=["person.me"])
    data = plan(local("05:45").isoformat())
    data["data"]["leave_by"] = local("05:45").isoformat()
    data["data"]["leave_reminders"] = [15, 0]
    await send(hass_client_no_auth, data)
    hass.states.async_set("person.me", "not_home")
    freezer.move_to(local("05:31"))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert not [c for c in notify if c.data.get("message") == "RUN_LEAVE_CHECK"]


async def test_leave_checks_stop_when_the_morning_is_skipped(hass, ladder, hass_client_no_auth, freezer):
    from pytest_homeassistant_custom_component.common import async_mock_service

    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await ladder(notify_service="notify.mobile_app_test", phone_commands=True)
    data = plan(local("05:45").isoformat())
    data["data"]["leave_by"] = local("05:45").isoformat()
    data["data"]["leave_reminders"] = [15, 0]
    await send(hass_client_no_auth, data)
    await send(hass_client_no_auth, {"type": "skipped", "data": {}})
    freezer.move_to(local("05:31"))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert not [c for c in notify if c.data.get("message") == "RUN_LEAVE_CHECK"]


async def _leave_checks_planned(hass, ladder, client, notify_list=None):
    from pytest_homeassistant_custom_component.common import async_mock_service

    notify = async_mock_service(hass, "notify", "mobile_app_test")
    await ladder(notify_service="notify.mobile_app_test", phone_commands=True)
    data = plan(local("05:45").isoformat())
    data["data"]["leave_by"] = local("05:45").isoformat()
    data["data"]["leave_reminders"] = [15, 0]
    data["data"]["alarm_times"] = [local("04:20").isoformat(), local("04:25").isoformat()]
    await send(client, data)
    await hass.async_block_till_done()
    return lambda: [c for c in notify if c.data.get("message") == "RUN_LEAVE_CHECK"]


async def _at(hass, freezer, when):
    freezer.move_to(when)
    async_fire_time_changed(hass)
    await hass.async_block_till_done()


def _changed(times, delay, scope):
    return {"type": "morning_changed", "data": {
        "alarm_times": [t.isoformat() for t in times], "alarms_planned": len(times), "delay_minutes": delay,
        "scope": scope, "phase": "snoozing", "reason": "Snow delay",
    }}


async def test_v042_wake_up_change_moves_the_leave_checks(hass, ladder, hass_client_no_auth, freezer):
    """v0.4.2 item 1: shift the entire wake-up +120 → checks 120 min later."""
    client = hass_client_no_auth
    checks = await _leave_checks_planned(hass, ladder, client)
    await _at(hass, freezer, local("04:21"))
    await send(client, _changed([local("06:20"), local("06:25")], 120, "wake_up"))
    assert dt_util.parse_datetime(hass.states.get("sensor.bedtime_bridge_leave_by").state) == local("07:45")
    await _at(hass, freezer, local("05:31"))
    assert checks() == []
    await _at(hass, freezer, local("07:30") + timedelta(seconds=30))
    assert len(checks()) == 1


async def test_v042_alarms_only_change_keeps_the_leave_checks(hass, ladder, hass_client_no_auth, freezer):
    client = hass_client_no_auth
    checks = await _leave_checks_planned(hass, ladder, client)
    await _at(hass, freezer, local("04:21"))
    await send(client, _changed([local("04:50"), local("04:55")], 30, "alarms"))
    await _at(hass, freezer, local("05:30") + timedelta(seconds=30))
    assert len(checks()) == 1


async def test_v042_no_alarms_keeps_checks_while_the_shift_is_on(hass, ladder, hass_client_no_auth, freezer):
    client = hass_client_no_auth
    checks = await _leave_checks_planned(hass, ladder, client)
    await _at(hass, freezer, local("04:21"))
    await send(client, _changed([], 0, "wake_up"))
    await _at(hass, freezer, local("05:30") + timedelta(seconds=30))
    assert len(checks()) == 1
    # The shift comes off the calendar: the next check doesn't go out.
    shift_sensor(hass, start="2026-10-29T06:30:00-04:00")
    await _at(hass, freezer, local("05:45") + timedelta(seconds=30))
    assert len(checks()) == 1


async def test_v042_skip_still_stops_the_leave_checks(hass, ladder, hass_client_no_auth, freezer):
    client = hass_client_no_auth
    checks = await _leave_checks_planned(hass, ladder, client)
    await send(client, {"type": "skipped", "data": {}})
    await _at(hass, freezer, local("05:31"))
    assert checks() == []
