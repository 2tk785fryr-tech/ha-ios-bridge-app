"""v0.4.7 integration tests, by spec item."""

import logging

from aiohttp import ClientError
from homeassistant.helpers.aiohttp_client import async_get_clientsession
import pytest

from custom_components.bedtime_bridge import drivetime as dtm

from .test_drive_times import ARRIVE, HOME, WORK

KEY = "tt-SECRET-key-123456"


# MARK: Item 3, no API keys in the log


def test_item3_scrub_takes_keys_out():
    text = f"TomTom: 403, url='https://api.tomtom.com/routing/1/x/json?key={KEY}&arriveAt=2026'"
    clean = dtm.scrub(text, KEY)
    assert KEY not in clean and "arriveAt=2026" in clean
    # Even without being told the key, a key= parameter is hidden.
    assert "abc123def" not in dtm.scrub("https://x.test/a?api_key=abc123def&b=1")
    assert "SECRET" not in str(dtm.DriveTimeError(f"Google 400: bad key {KEY}", KEY))


async def test_item3_failed_tomtom_request_leaves_no_key_in_the_log(hass, aioclient_mock, caplog):
    url = "https://api.tomtom.com/routing/1/calculateRoute/42.0,-71.0:42.1,-71.1/json"
    aioclient_mock.get(url, exc=ClientError(f"Cannot connect to host api.tomtom.com {url}?key={KEY}"))
    aioclient_mock.get("https://maps-api.apple.com/v1/token", status=401, text=f"echo key={KEY}")
    caplog.set_level(logging.DEBUG)
    services = [dtm.TomTom(async_get_clientsession(hass), KEY)]
    with pytest.raises(dtm.DriveTimeError) as err:
        await dtm.drive_seconds(services, HOME, WORK, ARRIVE)
    assert KEY not in str(err.value)
    aioclient_mock.clear_requests()
    aioclient_mock.get(url, status=403, text=f'{{"error": "Invalid key {KEY}"}}')
    with pytest.raises(dtm.DriveTimeError) as err:
        await services[0].drive_seconds(HOME, WORK, ARRIVE)
    assert KEY not in str(err.value) and "403" in str(err.value)
    assert KEY not in caplog.text


# MARK: Item 10, 12- or 24-hour clock

from datetime import datetime, timedelta  # noqa: E402

from homeassistant.util import dt as dt_util  # noqa: E402

from custom_components.bedtime_bridge import timefmt, weekly, winddown  # noqa: E402

from .test_ladder import TZ  # noqa: E402
from .test_webhook import send, setup  # noqa: E402


async def test_item10_times_follow_the_app_clock(hass, hass_client_no_auth):
    await hass.config.async_set_time_zone(TZ)
    await setup(hass)
    evening = datetime(2026, 10, 30, 21, 50, tzinfo=dt_util.get_time_zone(TZ))
    await send(hass_client_no_auth, {"type": "context", "data": {"clock_24h": False}})
    assert winddown.short(evening) == "9:50" and winddown.long(evening) == "9:50 PM"
    await send(hass_client_no_auth, {"type": "context", "data": {"clock_24h": True}})
    assert timefmt.uses_24h()
    assert winddown.short(evening) == "21:50" and winddown.long(evening) == "21:50"
    assert timefmt.day_long(evening) == "Fri 21:50" and timefmt.hour(evening) == "21:00"
    timefmt.set_24h(False)


# MARK: Item 6, vacations

from pytest_homeassistant_custom_component.common import async_mock_service  # noqa: E402

from .test_ladder import calendar_days, ladder, local, plan  # noqa: E402,F401
from .test_v043 import at  # noqa: E402

VACATIONS = [{"first": "2026-11-02", "last": "2026-11-06"}]


async def test_item6_vacation_morning_turns_sleep_in_on(hass, ladder, hass_client_no_auth):
    from homeassistant.setup import async_setup_component
    assert await async_setup_component(hass, "input_boolean", {"input_boolean": {"sleep_in": {"initial": False}}})
    await ladder(sleep_in_helper="input_boolean.sleep_in")
    await send(hass_client_no_auth, {"type": "planned", "data": {"has_alarm": False, "alarm_times": [], "alarm_cause": "noalarm",
                                                                  "vacation": True, "vacations": VACATIONS}})
    await hass.async_block_till_done()
    assert hass.states.get("input_boolean.sleep_in").state == "on"


async def test_item6_no_wind_down_before_a_vacation_morning_without_alarms(hass, ladder, hass_client_no_auth):
    await ladder()
    reply = await send(hass_client_no_auth, {"type": "planned", "data": {"has_alarm": False, "alarm_times": [], "alarm_cause": "noalarm",
                                                                          "vacation": True, "wind_down_settings": {"enabled": True}}})
    assert reply["wind_down"].get("status") in (None, "off")


def test_item6_weeks_with_vacation_days_are_marked():
    since = datetime(2026, 11, 1, 23, 0, tzinfo=dt_util.UTC)
    until = datetime(2026, 11, 8, 23, 0, tzinfo=dt_util.UTC)
    assert weekly.vacation_text(VACATIONS, since, until) == "Vacation Nov 2 – 6"
    assert weekly.vacation_text([{"first": "2026-10-30", "last": "2026-11-02"}], since, until) == "Vacation Oct 30 – Nov 2"
    assert weekly.vacation_text(VACATIONS, since + timedelta(days=7), until + timedelta(days=7)) is None
    assert weekly.on_vacation(VACATIONS, datetime(2026, 11, 4, 18, 0, tzinfo=dt_util.UTC))


async def test_item6_no_weekly_notification_on_vacation(hass, ladder, hass_client_no_auth, freezer):
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone")
    await send(hass_client_no_auth, {"type": "context", "data": {"weekly_summary": {"enabled": True, "weekday": 6, "time": "18:00"}}})
    await send(hass_client_no_auth, {"type": "planned", "data": {"has_alarm": False, "alarm_times": [], "alarm_cause": "noalarm",
                                                                  "vacations": [{"first": "2026-10-31", "last": "2026-11-03"}]}})
    await at(hass, freezer, datetime(2026, 11, 1, 18, 0, tzinfo=dt_util.get_time_zone(TZ)))
    assert not [c for c in notes if c.data.get("title") == "Your week"]
    assert hass.states.get("sensor.bedtime_bridge_weekly_summary").attributes.get("vacation") == "Vacation Oct 31 – Nov 3"
