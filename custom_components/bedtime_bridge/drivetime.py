"""Drive times worked out in Home Assistant (0.4.4): Apple Maps, TomTom, Google, or the longest.

Each asks for the drive arriving by a time, with the traffic expected then, as the app does. With
one chosen in the options, the leave checks re-check the drive here instead of asking the phone
(RUN_LEAVE_CHECK), so they work with the phone asleep.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import logging
import re
import time
from typing import Any
from urllib.parse import quote

from aiohttp import ClientError, ClientSession, ClientTimeout

_LOGGER = logging.getLogger(__name__)

SOURCE_PHONE = "phone"
SOURCE_APPLE = "apple"
SOURCE_TOMTOM = "tomtom"
SOURCE_GOOGLE = "google"
SOURCE_LONGEST = "longest"
SOURCES = [SOURCE_PHONE, SOURCE_APPLE, SOURCE_TOMTOM, SOURCE_GOOGLE, SOURCE_LONGEST]
TIMEOUT = ClientTimeout(total=15)


# key=…, api_key=…, token=… in a request address (v0.4.7 item 3).
_SECRET_PARAM = re.compile(r"((?:[?&]|\b)(?:key|api_key|apikey|token|access_token)=)[^&\s'\")]+", re.IGNORECASE)


def scrub(text: str, *secrets: str | None) -> str:
    """The text with API keys taken out, so an error never puts one in the log (v0.4.7 item 3)."""
    for secret in secrets:
        if secret and len(secret) >= 6:
            text = text.replace(secret, "•••")
    return _SECRET_PARAM.sub(r"\1•••", text)


class DriveTimeError(Exception):
    """A service couldn't give a drive time. Its text never carries a key."""

    def __init__(self, message: str, *secrets: str | None) -> None:
        super().__init__(scrub(message, *secrets))


@dataclass
class Place:
    """Where a drive goes: coordinates when the calendar had them, else the address."""

    text: str = ""
    latitude: float | None = None
    longitude: float | None = None

    @property
    def has_coordinates(self) -> bool:
        return self.latitude is not None and self.longitude is not None

    @property
    def latlon(self) -> str:
        return f"{self.latitude},{self.longitude}"


def utc(when: datetime) -> str:
    """ISO 8601 in UTC with Z, which every service takes without query-string trouble."""
    return when.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class AppleMaps:
    """Apple Maps Server API: a Maps key (.p8) signs a token, exchanged for a 30-minute access token."""

    BASE = "https://maps-api.apple.com/v1"

    def __init__(self, session: ClientSession, key: str, key_id: str, team_id: str) -> None:
        self._session = session
        self._key = key.strip()
        self._key_id = key_id.strip()
        self._team_id = team_id
        self._access: tuple[str, float] | None = None

    def _auth_token(self) -> str:
        import jwt  # noqa: PLC0415 (PyJWT ships with Home Assistant)

        now = int(time.time())
        return jwt.encode({"iss": self._team_id, "iat": now, "exp": now + 1800}, self._key, algorithm="ES256",
                          headers={"kid": self._key_id, "typ": "JWT"})

    async def _access_token(self) -> str:
        if self._access and time.time() < self._access[1] - 60:
            return self._access[0]
        data = await self._get("/token", token=self._auth_token())
        token = data.get("accessToken")
        if not token:
            raise DriveTimeError("Apple Maps gave no access token")
        self._access = (token, time.time() + int(data.get("expiresInSeconds") or 1800))
        return token

    async def _get(self, path: str, *, token: str, params: dict[str, str] | None = None) -> dict[str, Any]:
        try:
            async with self._session.get(f"{self.BASE}{path}", params=params, timeout=TIMEOUT,
                                         headers={"Authorization": f"Bearer {token}"}) as response:
                if response.status != 200:
                    raise DriveTimeError(f"Apple Maps {response.status}: {(await response.text())[:150]}")
                return await response.json()
        except (ClientError, TimeoutError) as err:
            raise DriveTimeError(f"Apple Maps: {err}") from err

    async def locate(self, place: Place) -> Place:
        if place.has_coordinates:
            return place
        data = await self._get("/geocode", token=await self._access_token(), params={"q": place.text})
        results = data.get("results") or []
        if not results:
            raise DriveTimeError(f"Apple Maps couldn't find {place.text}")
        coordinate = results[0].get("coordinate") or {}
        return Place(place.text, coordinate.get("latitude"), coordinate.get("longitude"))

    async def drive_seconds(self, origin: Place, destination: Place, arrive_by: datetime) -> float:
        destination = await self.locate(destination)
        data = await self._get("/etas", token=await self._access_token(), params={
            "origin": origin.latlon, "destinations": destination.latlon,
            "transportType": "Automobile", "arrivalDate": utc(arrive_by),
        })
        etas = data.get("etas") or []
        if not etas or etas[0].get("expectedTravelTimeSeconds") is None:
            raise DriveTimeError("Apple Maps found no route")
        return float(etas[0]["expectedTravelTimeSeconds"])


class TomTom:
    """TomTom Routing API: takes an arrival time directly, with its traffic for that time."""

    def __init__(self, session: ClientSession, key: str) -> None:
        self._session = session
        self._key = key.strip()

    async def _get(self, url: str, params: dict[str, str]) -> dict[str, Any]:
        try:
            async with self._session.get(url, params={"key": self._key, **params}, timeout=TIMEOUT) as response:
                if response.status != 200:
                    raise DriveTimeError(f"TomTom {response.status}: {(await response.text())[:150]}", self._key)
                return await response.json()
        except (ClientError, TimeoutError) as err:
            raise DriveTimeError(f"TomTom: {err}", self._key) from err

    async def locate(self, place: Place) -> Place:
        if place.has_coordinates:
            return place
        data = await self._get(f"https://api.tomtom.com/search/2/geocode/{quote(place.text)}.json", {"limit": "1"})
        results = data.get("results") or []
        if not results:
            raise DriveTimeError(f"TomTom couldn't find {place.text}", self._key)
        position = results[0].get("position") or {}
        return Place(place.text, position.get("lat"), position.get("lon"))

    async def drive_seconds(self, origin: Place, destination: Place, arrive_by: datetime) -> float:
        destination = await self.locate(destination)
        data = await self._get(
            f"https://api.tomtom.com/routing/1/calculateRoute/{origin.latlon}:{destination.latlon}/json",
            {"travelMode": "car", "routeType": "fastest", "traffic": "true", "arriveAt": utc(arrive_by)},
        )
        routes = data.get("routes") or []
        if not routes:
            raise DriveTimeError("TomTom found no route", self._key)
        return float(routes[0]["summary"]["travelTimeInSeconds"])


class Google:
    """Google Routes API: departure times only, so it works back from the arrival (as the app's
    DepartureSolver does)."""

    def __init__(self, session: ClientSession, key: str, bundle_id: str | None = None, pessimistic: bool = False) -> None:
        self._session = session
        self._key = key.strip()
        self._bundle_id = bundle_id
        self._pessimistic = pessimistic

    async def _duration(self, origin: Place, destination: Place, depart: datetime) -> float:
        def waypoint(place: Place) -> dict[str, Any]:
            if place.has_coordinates:
                return {"location": {"latLng": {"latitude": place.latitude, "longitude": place.longitude}}}
            return {"address": place.text}

        headers = {"X-Goog-Api-Key": self._key, "X-Goog-FieldMask": "routes.duration"}
        if self._bundle_id:
            # A key restricted to the iOS app accepts requests that name it.
            headers["X-Ios-Bundle-Identifier"] = self._bundle_id
        body = {
            "origin": waypoint(origin), "destination": waypoint(destination), "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE_OPTIMAL", "trafficModel": "PESSIMISTIC" if self._pessimistic else "BEST_GUESS",
            "departureTime": utc(depart),
        }
        try:
            async with self._session.post("https://routes.googleapis.com/directions/v2:computeRoutes", json=body,
                                          headers=headers, timeout=TIMEOUT) as response:
                if response.status != 200:
                    raise DriveTimeError(f"Google {response.status}: {(await response.text())[:150]}", self._key)
                data = await response.json()
        except (ClientError, TimeoutError) as err:
            raise DriveTimeError(f"Google: {err}", self._key) from err
        routes = data.get("routes") or []
        if not routes or not routes[0].get("duration"):
            raise DriveTimeError("Google found no route", self._key)
        return float(str(routes[0]["duration"]).rstrip("s"))

    async def drive_seconds(self, origin: Place, destination: Place, arrive_by: datetime, now: datetime | None = None) -> float:
        return await solve_departure(arrive_by, now or datetime.now(arrive_by.tzinfo),
                                     lambda depart: self._duration(origin, destination, depart))


async def solve_departure(arrive_by: datetime, now: datetime, duration, max_requests: int = 4, tolerance: float = 60) -> float:
    """The time to allow (arrival − the latest departure found that still arrives in time)."""
    earliest = now + timedelta(minutes=1)
    depart = max(arrive_by - timedelta(minutes=30), earliest)
    latest_on_time: datetime | None = None
    longest = 0.0
    for _ in range(max_requests):
        trip = await duration(depart)
        longest = max(longest, trip)
        arrives = depart + timedelta(seconds=trip)
        if arrives <= arrive_by and (latest_on_time is None or depart > latest_on_time):
            latest_on_time = depart
        if abs((arrives - arrive_by).total_seconds()) <= tolerance:
            break
        following = max(arrive_by - timedelta(seconds=trip), earliest)
        if following == depart:
            break
        depart = following
    if latest_on_time is not None:
        return (arrive_by - latest_on_time).total_seconds()
    return longest


async def drive_seconds(services: list[Any], origin: Place, destination: Place, arrive_by: datetime) -> float:
    """The longest answer of the services that gave one (one service: its answer)."""
    answers: list[float] = []
    errors: list[str] = []
    for service in services:
        try:
            answers.append(await service.drive_seconds(origin, destination, arrive_by))
        except DriveTimeError as err:
            errors.append(str(err))
    if not answers:
        raise DriveTimeError("; ".join(errors) or "no drive-time service set up")
    if errors:
        _LOGGER.info("Bedtime Bridge drive time: %s", "; ".join(errors))
    return max(answers)
