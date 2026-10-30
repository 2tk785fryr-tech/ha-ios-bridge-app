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
