"""Live Activities by Apple push: wind-down and the morning's leave-by countdown.

The app reports each activity's push token and its push-to-start token. With an Apple push key
(.p8) and its Key ID in the options, Home Assistant starts, updates and ends the activities itself,
so they change while the app isn't running. Without a key, RUN_MORNING_UPDATE (a phone shortcut
that runs the app) stands in for the morning updates.
"""

from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta
import logging
import time
from typing import TYPE_CHECKING, Any

from homeassistant.exceptions import HomeAssistantError
from homeassistant.util import dt as dt_util

from . import timefmt
from .const import CONF_APNS_KEY, CONF_APNS_KEY_ID, CONF_WEATHER

if TYPE_CHECKING:
    from .bridge import BedtimeBridge

_LOGGER = logging.getLogger(__name__)

HOSTS = {"development": "https://api.sandbox.push.apple.com", "production": "https://api.push.apple.com"}
# Swift's Date encodes as seconds since 1 Jan 2001, which is what ActivityKit decodes.
REFERENCE_DATE = 978307200
ATTRIBUTES_TYPE = "BedtimeActivityAttributes"
MORNING_TAIL = timedelta(minutes=15)

CONDITIONS = {
    "clear-night": "Clear", "sunny": "Clear", "partlycloudy": "Partly cloudy", "cloudy": "Cloudy", "fog": "Fog",
    "rainy": "Rain", "pouring": "Heavy rain", "lightning": "Storms", "lightning-rainy": "Storms", "snowy": "Snow",
    "snowy-rainy": "Sleet", "hail": "Hail", "windy": "Windy", "windy-variant": "Windy",
}
WET = {"rainy", "pouring", "lightning-rainy", "snowy", "snowy-rainy", "hail"}


def ref(when: datetime) -> float:
    return round(when.timestamp() - REFERENCE_DATE, 3)


def content_state(kind: str, **fields: datetime | int | str | None) -> dict[str, Any]:
    """The Swift ContentState: camelCase keys, dates as reference-date seconds, nil left out."""
    state: dict[str, Any] = {"kind": kind}
    for key, value in fields.items():
        if value is None:
            continue
        state[key] = ref(value) if isinstance(value, datetime) else value
    return state


def payload(event: str, state: dict[str, Any], now: datetime, *, stale: datetime | None = None,
            dismissal: datetime | None = None, title: str | None = None, alert: dict[str, str] | None = None) -> dict[str, Any]:
    aps: dict[str, Any] = {"timestamp": int(now.timestamp()), "event": event, "content-state": state}
    if stale:
        aps["stale-date"] = int(stale.timestamp())
    if dismissal:
        aps["dismissal-date"] = int(dismissal.timestamp())
    if event == "start":
        aps["attributes-type"] = ATTRIBUTES_TYPE
        aps["attributes"] = {"title": title or ""}
        aps["alert"] = alert or {"title": title or "", "body": ""}
    return {"aps": aps}


def condition_name(condition: str) -> str:
    return CONDITIONS.get(condition, condition.replace("-", " ").capitalize())


def weather_lines(hours: list[dict[str, Any]], leave_by: datetime, now: datetime) -> tuple[str | None, str | None]:
    """("Rain · 58°", "Cloudy · 71°/55° · rain after 3 PM"), as the app works it out."""
    parsed = sorted(
        ((t, h) for h in hours if (t := dt_util.parse_datetime(str(h.get("datetime"))))), key=lambda pair: pair[0]
    )
    if not parsed:
        return None, None
    at_leave = next((h for t, h in reversed(parsed) if t <= leave_by), parsed[0][1])

    def temp(value: Any) -> str:
        return f" · {round(float(value))}°" if isinstance(value, (int, float)) else ""

    drive = condition_name(str(at_leave.get("condition"))) + temp(at_leave.get("temperature"))
    local_now = dt_util.as_local(now)
    start = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=1)
    today = [(t, h) for t, h in parsed if start <= dt_util.as_local(t) < end]
    if not today:
        return drive, None
    daytime = [h["condition"] for t, h in today if dt_util.as_local(t).hour >= 7 and h.get("condition")]
    main = Counter(daytime).most_common(1)[0][0] if daytime else today[0][1].get("condition", "")
    day = condition_name(str(main))
    temps = [float(h["temperature"]) for _, h in today if isinstance(h.get("temperature"), (int, float))]
    if temps:
        day += f" · {round(max(temps))}°/{round(min(temps))}°"
    ahead = [(t, h) for t, h in today if t > now]
    dry = next((i for i, (_, h) in enumerate(ahead) if h.get("condition") not in WET), None)
    if main not in WET and dry is not None:
        wet = next(((t, h) for t, h in ahead[dry:] if h.get("condition") in WET), None)
        if wet:
            hour = timefmt.hour(wet[0])
            day += f" · {condition_name(wet[1]['condition']).lower()} after {hour}"
    return drive, day


class ApnsClient:
    """Token-based (.p8) connection to Apple's push service, over HTTP/2."""

    def __init__(self, key: str, key_id: str, team_id: str) -> None:
        self._key = key.strip()
        self._key_id = key_id.strip()
        self._team_id = team_id
        self._jwt: tuple[str, float] | None = None

    def _token(self) -> str:
        # Apple wants a fresh signature at most once every 20 minutes and at least once an hour.
        if self._jwt and time.time() - self._jwt[1] < 40 * 60:
            return self._jwt[0]
        import jwt  # noqa: PLC0415 (PyJWT ships with Home Assistant)

        issued = time.time()
        token = jwt.encode({"iss": self._team_id, "iat": int(issued)}, self._key, algorithm="ES256",
                           headers={"kid": self._key_id})
        self._jwt = (token, issued)
        return token

    async def send(self, device_token: str, body: dict[str, Any], *, environment: str, topic: str,
                   priority: int = 10, push_type: str = "liveactivity") -> int:
        import httpx  # noqa: PLC0415

        url = f"{HOSTS.get(environment, HOSTS['production'])}/3/device/{device_token}"
        headers = {
            "authorization": f"bearer {self._token()}",
            "apns-push-type": push_type,
            "apns-topic": topic,
            "apns-priority": str(priority),
        }
        async with httpx.AsyncClient(http2=True, timeout=10) as client:
            response = await client.post(url, json=body, headers=headers)
        if response.status_code != 200:
            _LOGGER.warning("Bedtime Bridge Live Activity push failed (%s): %s", response.status_code, response.text[:200])
        return response.status_code


class LiveActivities:
    """Tokens from the app, and what Home Assistant pushes. State lives in bridge.state["live_activity"]."""

    def __init__(self, bridge: BedtimeBridge) -> None:
        self.bridge = bridge
        self.hass = bridge.hass
        self._client: ApnsClient | None = None
        self._client_key: tuple[str, str, str] | None = None

    @property
    def s(self) -> dict[str, Any]:
        return self.bridge.state.setdefault("live_activity", {"tokens": {}})

    @property
    def configured(self) -> bool:
        options = self.bridge.options
        return bool(options.get(CONF_APNS_KEY) and options.get(CONF_APNS_KEY_ID) and self.s.get("team_id") and self.s.get("bundle_id"))

    def client(self) -> ApnsClient | None:
        if not self.configured:
            return None
        key = (self.bridge.options[CONF_APNS_KEY], self.bridge.options[CONF_APNS_KEY_ID], self.s["team_id"])
        if self._client is None or self._client_key != key:
            self._client = ApnsClient(*key)
            self._client_key = key
        return self._client

    # MARK: From the app

    def handle(self, data: dict[str, Any]) -> dict[str, Any]:
        """A token (an activity's, or push-to-start), an ended activity, or the morning lines."""
        s = self.s
        for key in ("bundle_id", "team_id"):
            if data.get(key):
                s[key] = data[key]
        kind = data.get("kind")
        environment = data.get("environment") or "production"
        if kind == "device" and data.get("token"):
            # The app's own token, for silent pushes (v0.4.7 item 2).
            s["device"] = {"token": data["token"], "environment": environment}
        elif kind == "start" and data.get("token"):
            s["start"] = {"token": data["token"], "environment": environment}
        elif kind in ("windDown", "morning"):
            tokens = s.setdefault("tokens", {})
            if data.get("ended"):
                if (tokens.get(kind) or {}).get("activity_id") in (None, data.get("activity_id")):
                    tokens.pop(kind, None)
            elif data.get("token"):
                tokens[kind] = {"token": data["token"], "environment": environment, "activity_id": data.get("activity_id")}
            if kind == "morning" and isinstance(data.get("content"), dict):
                s["morning_content"] = {**(s.get("morning_content") or {}), **data["content"]}
        self.bridge._changed()
        return {"live_activity_pushes": self.configured}

    # MARK: Sending

    async def leave_checked(self) -> bool:
        """A silent push telling the app Home Assistant's leave check went out, so it withdraws
        its leave-time backup reminder (v0.4.7 item 2)."""
        client, device = self.client(), self.s.get("device") or {}
        if client is None or not device.get("token"):
            return False
        status = await client.send(device["token"], {"aps": {"content-available": 1}, "bedtime_bridge": "leave_checked"},
                                   environment=device.get("environment") or "production", topic=self.s["bundle_id"],
                                   priority=5, push_type="background")
        return status == 200

    async def _push(self, kind: str, event: str, state: dict[str, Any], *, title: str, stale: datetime | None = None,
                    alert: dict[str, str] | None = None) -> bool:
        """Updates or ends the running activity of this kind, or starts one by push-to-start."""
        client = self.client()
        if client is None:
            return False
        now = dt_util.utcnow()
        tokens = self.s.setdefault("tokens", {})
        target = tokens.get(kind)
        if target is None:
            if event != "update" or not self.s.get("start"):
                return False
            # Nothing running: start one, without the app.
            target, event = self.s["start"], "start"
        topic = f"{self.s['bundle_id']}.push-type.liveactivity"
        body = payload(event, state, now, stale=stale, dismissal=now if event == "end" else None, title=title, alert=alert)
        try:
            status = await client.send(target["token"], body, environment=target.get("environment", "production"), topic=topic)
        except (HomeAssistantError, OSError, ImportError, ValueError) as err:
            _LOGGER.warning("Bedtime Bridge couldn't push a Live Activity: %s", err)
            return False
        if status == 410:
            # The token is no longer valid (the activity ended on the phone, or the app was removed).
            if event == "start":
                self.s.pop("start", None)
            else:
                tokens.pop(kind, None)
        if event == "end":
            tokens.pop(kind, None)
        self.bridge._changed()
        return status == 200

    async def wind_down(self, go_to_bed: datetime, first_alarm: datetime | None) -> bool:
        """Winding down: "Bed in 42 min · first alarm 4:20" (started by push if the app isn't running)."""
        state = content_state("windDown", goToBed=go_to_bed, firstAlarm=first_alarm)
        return await self._push("windDown", "update", state, title="Wind-down", stale=go_to_bed,
                                alert={"title": "Winding down", "body": f"Bed at {timefmt.short(go_to_bed)}"})

    async def end_wind_down(self) -> bool:
        return await self._push("windDown", "end", content_state("windDown"), title="Wind-down")

    async def morning(self) -> bool:
        """The morning countdown, from what Home Assistant knows plus the app's last lines."""
        state = self.bridge.state
        leave_by = dt_util.parse_datetime(state.get("leave_by") or "")
        now = dt_util.utcnow()
        if leave_by is None or now >= leave_by + MORNING_TAIL:
            return await self.end_morning()
        extra = self.s.get("morning_content") or {}
        drive_weather, day_weather = await self._weather(leave_by, now)
        rungs = [(t, name) for name, v in ((state.get("ladder") or {}).get("times") or {}).items()
                 if (t := dt_util.parse_datetime(v or "")) and t > now] if (state.get("ladder") or {}).get("status") == "armed" else []
        backstop = min(rungs) if rungs else None
        first = dt_util.parse_datetime(state.get("series_start") or "")
        drive = state.get("drive_minutes") if isinstance(state.get("drive_minutes"), int) else extra.get("drive_minutes")
        content = content_state(
            "morning", firstAlarm=first, leaveBy=leave_by, driveMinutes=drive,
            worstCaseMinutes=extra.get("worst_case_minutes"),
            driveWeather=drive_weather or extra.get("drive_weather"), dayWeather=day_weather or extra.get("day_weather"),
            nextBackstopName=backstop[1].capitalize() if backstop else None, nextBackstop=backstop[0] if backstop else None,
        )
        title = state.get("label") or "Leave by"
        return await self._push("morning", "update", content, title=title, stale=leave_by + MORNING_TAIL,
                                alert={"title": f"Leave by {timefmt.short(leave_by)}", "body": title})

    async def end_morning(self) -> bool:
        return await self._push("morning", "end", content_state("morning"), title="Leave by")

    async def _weather(self, leave_by: datetime, now: datetime) -> tuple[str | None, str | None]:
        entity = self.bridge.options.get(CONF_WEATHER)
        if not entity or self.hass.states.get(entity) is None:
            return None, None
        try:
            response = await self.hass.services.async_call(
                "weather", "get_forecasts", {"entity_id": entity, "type": "hourly"}, blocking=True, return_response=True
            )
        except HomeAssistantError:
            return None, None
        return weather_lines((response or {}).get(entity, {}).get("forecast", []), leave_by, now)
