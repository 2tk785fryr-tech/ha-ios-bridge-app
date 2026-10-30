"""Live Activities by Apple push (0.4.4)."""

from datetime import timedelta
from unittest.mock import AsyncMock, patch

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
import jwt
from homeassistant.setup import async_setup_component
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_mock_service

from custom_components.bedtime_bridge import liveactivity as la

from .test_ladder import TZ, ladder, calendar_days, local, plan  # noqa: F401
from .test_v043 import WIND, at, days_plan, messages, status_of, wind_setup
from .test_webhook import send

KEY = ec.generate_private_key(ec.SECP256R1()).private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
).decode()
APP = {"bundle_id": "io.example.bedtime", "team_id": "TEAM123456", "environment": "development"}


def test_content_state_uses_swift_reference_dates():
    when = dt_util.parse_datetime("2001-01-01T00:01:00+00:00")
    state = la.content_state("windDown", goToBed=when, firstAlarm=None, driveMinutes=32)
    assert state == {"kind": "windDown", "goToBed": 60.0, "driveMinutes": 32}, "nil left out, dates as seconds since 2001"
    start = la.payload("start", state, when, title="Wind-down", alert={"title": "Winding down", "body": "Bed at 9:50"})
    assert start["aps"]["attributes-type"] == "BedtimeActivityAttributes"
    assert start["aps"]["attributes"] == {"title": "Wind-down"}
    assert "alert" in start["aps"]
    assert "attributes-type" not in la.payload("update", state, when)["aps"]


async def test_weather_lines_match_the_app(hass):
    await hass.config.async_set_time_zone(TZ)

    def hour(h, condition, temp):
        return {"datetime": local(f"{h:02d}:00", day=30).isoformat(), "condition": condition, "temperature": temp}

    hours = [hour(5, "rainy", 58), hour(6, "rainy", 58), hour(9, "cloudy", 63), hour(12, "cloudy", 71),
             hour(13, "cloudy", 70), hour(15, "rainy", 66), hour(22, "cloudy", 55)]
    drive, day = la.weather_lines(hours, local("05:45", day=30), local("05:00", day=30))
    assert drive == "Rain · 58°"
    assert day == "Cloudy · 71°/55° · rain after 3 PM"


def test_signing_token_is_es256_with_the_key_id():
    client = la.ApnsClient(KEY, "KEYID12345", "TEAM123456")
    token = client._token()
    assert jwt.get_unverified_header(token) == {"alg": "ES256", "kid": "KEYID12345", "typ": "JWT"}
    assert jwt.decode(token, options={"verify_signature": False})["iss"] == "TEAM123456"
    assert client._token() == token, "reused for 40 minutes"


async def test_tokens_and_configured(hass, ladder, hass_client_no_auth):
    entry = await ladder(apns_key=KEY, apns_key_id="KEYID12345")
    live = entry.runtime_data.live
    assert not live.configured, "needs the app's team and bundle too"
    reply = await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "start", "token": "ab12"}})
    assert reply["live_activity_pushes"] is True
    await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "windDown", "token": "cd34", "activity_id": "A"}})
    assert live.s["tokens"]["windDown"]["token"] == "cd34"
    await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "windDown", "ended": True, "activity_id": "A"}})
    assert "windDown" not in live.s["tokens"]


async def test_wind_down_starts_by_push_and_ends_at_go_to_bed(hass, ladder, hass_client_no_auth, freezer):
    sent = AsyncMock(return_value=200)
    with patch.object(la.ApnsClient, "send", sent):
        await wind_setup(hass, ladder, apns_key=KEY, apns_key_id="KEYID12345")
        await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "start", "token": "start-token"}})
        await send(hass_client_no_auth, days_plan())
        await at(hass, freezer, local("20:50", day=27))
        assert status_of(hass) == "winding_down"
        token, body = sent.call_args.args
        assert token == "start-token" and body["aps"]["event"] == "start", "nothing running: started by push"
        assert body["aps"]["content-state"]["kind"] == "windDown"
        assert sent.call_args.kwargs == {"environment": "development", "topic": "io.example.bedtime.push-type.liveactivity"}
        # The phone reports the new activity's own token; go to bed ends it through that.
        await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "windDown", "token": "wd-token", "activity_id": "W"}})
        await at(hass, freezer, local("21:50", day=27))
        token, body = sent.call_args.args
        assert token == "wd-token" and body["aps"]["event"] == "end"


async def test_morning_by_push_instead_of_the_shortcut(hass, ladder, hass_client_no_auth, freezer):
    sent = AsyncMock(return_value=200)
    notes = async_mock_service(hass, "notify", "phone")
    hass.states.async_set("person.me", "home")
    with patch.object(la.ApnsClient, "send", sent):
        entry = await ladder(notify_service="notify.phone", phone_commands=True, presence_entities=["person.me"],
                             apns_key=KEY, apns_key_id="KEYID12345")
        await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "start", "token": "start-token"}})
        await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "morning", "content": {"worst_case_minutes": 41}}})
        freezer.move_to(local("04:20"))
        planned = days_plan()
        planned["data"]["leave_by"] = local("06:45").isoformat()
        await send(hass_client_no_auth, planned)
        await send(hass_client_no_auth, {"type": "stopped", "data": {"alarm_times": []}})
        token, body = sent.call_args.args
        state = body["aps"]["content-state"]
        assert body["aps"]["event"] == "start" and state["kind"] == "morning"
        assert state["worstCaseMinutes"] == 41, "the app's worst case is kept"
        assert state["leaveBy"] == la.ref(local("06:45"))
        await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "morning", "token": "m-token", "activity_id": "M"}})
        await at(hass, freezer, local("05:21"))
        assert sent.call_args.args[0] == "m-token" and sent.call_args.args[1]["aps"]["event"] == "update", "hourly by push"
        hass.states.async_set("person.me", "not_home")
        await hass.async_block_till_done()
        assert sent.call_args.args[1]["aps"]["event"] == "end", "left home: ended"
        assert "RUN_MORNING_UPDATE" not in messages(notes), "no shortcut needed with a key"
        assert "morning" not in entry.runtime_data.live.s["tokens"]


async def test_a_gone_token_is_dropped(hass, ladder, hass_client_no_auth, freezer):
    with patch.object(la.ApnsClient, "send", AsyncMock(return_value=410)):
        entry = await ladder(apns_key=KEY, apns_key_id="KEYID12345")
        await send(hass_client_no_auth, {"type": "live_activity", "data": {**APP, "kind": "windDown", "token": "old", "activity_id": "W"}})
        live = entry.runtime_data.live
        assert not await live.wind_down(local("21:50", day=27), None)
        assert "windDown" not in live.s["tokens"]
