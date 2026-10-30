"""Drive times worked out in Home Assistant (0.4.4)."""

from datetime import datetime, timedelta, timezone

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from pytest_homeassistant_custom_component.common import async_mock_service

from custom_components.bedtime_bridge import drivetime as dtm

from .test_ladder import TZ, ladder, calendar_days, local, plan  # noqa: F401
from .test_v043 import at, days_plan, messages
from .test_webhook import send

KEY = ec.generate_private_key(ec.SECP256R1()).private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
).decode()
ARRIVE = datetime(2026, 10, 28, 10, 20, tzinfo=timezone.utc)
HOME = dtm.Place("home", 42.0, -71.0)
WORK = dtm.Place("1 Main St", 42.1, -71.1)


async def test_departure_solver_works_back_from_the_arrival():
    calls = []

    async def duration(depart):
        calls.append(depart)
        return 1800 if depart.minute < 40 else 2100  # heavier traffic later

    seconds = await dtm.solve_departure(ARRIVE, ARRIVE - timedelta(hours=3), duration)
    # 9:50 takes 35 min (late); 9:45 also takes 35 and arrives right on 10:20.
    assert seconds == 2100
    assert calls[0] == ARRIVE - timedelta(minutes=30)


async def test_apple_maps_token_then_eta_for_the_arrival(hass, aioclient_mock):
    aioclient_mock.get("https://maps-api.apple.com/v1/token", json={"accessToken": "acc", "expiresInSeconds": 1800})
    aioclient_mock.get("https://maps-api.apple.com/v1/etas", json={"etas": [{"expectedTravelTimeSeconds": 1920}]})
    apple = dtm.AppleMaps(async_get_clientsession(hass), KEY, "MAPSKEY123", "TEAM123456")
    assert await apple.drive_seconds(HOME, WORK, ARRIVE) == 1920
    _, url, _, headers = aioclient_mock.mock_calls[-1]
    assert url.query["arrivalDate"] == "2026-10-28T10:20:00Z" and url.query["transportType"] == "Automobile"
    assert headers["Authorization"] == "Bearer acc"
    await apple.drive_seconds(HOME, WORK, ARRIVE)
    assert sum(1 for call in aioclient_mock.mock_calls if "token" in str(call[1])) == 1, "the access token is reused"


async def test_apple_maps_geocodes_an_address(hass, aioclient_mock):
    aioclient_mock.get("https://maps-api.apple.com/v1/token", json={"accessToken": "acc"})
    aioclient_mock.get("https://maps-api.apple.com/v1/geocode", json={"results": [{"coordinate": {"latitude": 42.2, "longitude": -71.2}}]})
    aioclient_mock.get("https://maps-api.apple.com/v1/etas", json={"etas": [{"expectedTravelTimeSeconds": 600}]})
    apple = dtm.AppleMaps(async_get_clientsession(hass), KEY, "MAPSKEY123", "TEAM123456")
    assert await apple.drive_seconds(HOME, dtm.Place("Dentist, Main St"), ARRIVE) == 600
    assert aioclient_mock.mock_calls[-1][1].query["destinations"] == "42.2,-71.2"


async def test_tomtom_arrive_at(hass, aioclient_mock):
    aioclient_mock.get("https://api.tomtom.com/routing/1/calculateRoute/42.0,-71.0:42.1,-71.1/json",
                       json={"routes": [{"summary": {"travelTimeInSeconds": 2000}}]})
    assert await dtm.TomTom(async_get_clientsession(hass), "tt").drive_seconds(HOME, WORK, ARRIVE) == 2000
    assert aioclient_mock.mock_calls[-1][1].query["arriveAt"] == "2026-10-28T10:20:00Z"


async def test_google_takes_an_address_and_names_the_app(hass, aioclient_mock):
    aioclient_mock.post("https://routes.googleapis.com/directions/v2:computeRoutes", json={"routes": [{"duration": "1800s"}]})
    google = dtm.Google(async_get_clientsession(hass), "g", bundle_id="io.example.bedtime")
    seconds = await google.drive_seconds(HOME, dtm.Place("1 Main St"), ARRIVE, now=ARRIVE - timedelta(hours=3))
    assert seconds == 1800
    _, _, body, headers = aioclient_mock.mock_calls[-1]
    assert body["destination"] == {"address": "1 Main St"}
    assert headers["X-Ios-Bundle-Identifier"] == "io.example.bedtime"


async def test_longest_of_those_that_answer(hass):
    class Fixed:
        def __init__(self, value):
            self.value = value

        async def drive_seconds(self, *_):
            if self.value is None:
                raise dtm.DriveTimeError("down")
            return self.value

    assert await dtm.drive_seconds([Fixed(1500), Fixed(None), Fixed(1700)], HOME, WORK, ARRIVE) == 1700


def trip_plan():
    p = days_plan()
    p["data"]["leave_by"] = local("05:45").isoformat()
    p["data"]["leave_reminders"] = [15, 0]
    p["data"]["trip"] = {"title": "Days", "location": "1 Main St", "latitude": 42.1, "longitude": -71.1,
                         "start": local("06:30").isoformat(), "arrive_by": local("06:20").isoformat(), "planned_minutes": 35}
    return p


async def test_leave_check_done_here_moves_leave_by_and_tells_you(hass, ladder, hass_client_no_auth, freezer, aioclient_mock):
    aioclient_mock.get("https://api.tomtom.com/routing/1/calculateRoute/32.87336,-117.22743:42.1,-71.1/json",
                       json={"routes": [{"summary": {"travelTimeInSeconds": 42 * 60}}]})
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone", phone_commands=True, drive_time_source="tomtom", tomtom_key="tt")
    reply = await send(hass_client_no_auth, trip_plan())
    assert reply["drive_checks_here"] is True, "the app skips its own reminders while home"
    await at(hass, freezer, local("05:30"))
    assert "RUN_LEAVE_CHECK" not in messages(notes), "no need to wake the phone"
    leave = [c for c in notes if (c.data.get("title") or "").startswith("Leave by 5:38")]
    assert leave and leave[0].data["title"] == "Leave by 5:38 · 42 min drive (7 min worse than planned)"
    assert leave[0].data["data"]["push"]["interruption-level"] == "time-sensitive"
    assert hass.states.get("sensor.bedtime_bridge_drive_time").state == "42"


async def test_a_service_that_fails_falls_back_to_the_phone(hass, ladder, hass_client_no_auth, freezer, aioclient_mock):
    aioclient_mock.get("https://api.tomtom.com/routing/1/calculateRoute/32.87336,-117.22743:42.1,-71.1/json", status=500)
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone", phone_commands=True, drive_time_source="tomtom", tomtom_key="tt")
    await send(hass_client_no_auth, trip_plan())
    await at(hass, freezer, local("05:30"))
    assert "RUN_LEAVE_CHECK" in messages(notes)


async def test_phone_is_the_default(hass, ladder, hass_client_no_auth, freezer):
    notes = async_mock_service(hass, "notify", "phone")
    await ladder(notify_service="notify.phone", phone_commands=True)
    reply = await send(hass_client_no_auth, trip_plan())
    assert reply["drive_checks_here"] is False
    await at(hass, freezer, local("05:30"))
    assert "RUN_LEAVE_CHECK" in messages(notes)
