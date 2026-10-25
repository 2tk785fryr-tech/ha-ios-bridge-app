"""The addresses the phone uses to reach this integration, and the one-tap pairing link.

The webhook helper's own URL never uses Nabu Casa (it passes allow_cloud=False), so with no
external URL configured it hands out the local address, which stops working the moment the
phone leaves home Wi-Fi. Like the mobile app integration, this creates a Nabu Casa cloudhook
when Home Assistant Cloud is active: it works from anywhere, even with remote UI turned off.
"""

from __future__ import annotations

import logging
from urllib.parse import urlencode

from homeassistant.components import webhook
from homeassistant.core import HomeAssistant
from homeassistant.helpers.network import NoURLAvailableError, get_url

_LOGGER = logging.getLogger(__name__)

PAIR_URL = "bedtimebridge://pair"


async def _async_cloudhook(hass: HomeAssistant, webhook_id: str) -> str | None:
    """The Nabu Casa cloudhook for this webhook, created if needed; None without an active
    Home Assistant Cloud subscription. Cloud is imported here, only when it's loaded."""
    if "cloud" not in hass.config.components:
        return None
    from homeassistant.components import cloud

    if not cloud.async_active_subscription(hass):
        return None
    try:
        return await cloud.async_get_or_create_cloudhook(hass, webhook_id)
    except cloud.CloudNotAvailable as err:  # includes CloudNotConnected
        _LOGGER.info("Bedtime Bridge: Nabu Casa cloudhook not available yet (%s)", type(err).__name__)
        return None


async def async_delete_cloudhook(hass: HomeAssistant, webhook_id: str) -> None:
    if "cloud" not in hass.config.components:
        return
    from homeassistant.components import cloud

    try:
        await cloud.async_delete_cloudhook(hass, webhook_id)
    except (cloud.CloudNotAvailable, ValueError):
        pass


async def async_remote_url(hass: HomeAssistant, webhook_id: str) -> str | None:
    """Nabu Casa cloudhook if available, else the configured external URL, else None."""
    if hook := await _async_cloudhook(hass, webhook_id):
        return hook
    try:
        base = get_url(hass, allow_internal=False, allow_cloud=False, prefer_external=True)
    except NoURLAvailableError:
        return None
    return f"{base}{webhook.async_generate_path(webhook_id)}"


def local_url(hass: HomeAssistant, webhook_id: str) -> str | None:
    """The home-network address (fallback when the internet is down at home)."""
    try:
        base = get_url(hass, allow_external=False, allow_cloud=False, prefer_external=False)
    except NoURLAvailableError:
        return None
    return f"{base}{webhook.async_generate_path(webhook_id)}"


def pair_link(remote: str | None, local: str | None) -> str:
    """bedtimebridge://pair?remote=…&local=…; tapping it on the iPhone saves both."""
    query = {key: value for key, value in (("remote", remote), ("local", local)) if value}
    return f"{PAIR_URL}?{urlencode(query)}"


async def async_placeholders(hass: HomeAssistant, webhook_id: str) -> dict[str, str]:
    """Text for the pairing screens."""
    remote = await async_remote_url(hass, webhook_id)
    local = local_url(hass, webhook_id)
    return {
        "remote_url": remote or "Not available. Sign in to Home Assistant Cloud (Nabu Casa) or set an external URL, then open Configure again.",
        "local_url": local or "Not available",
        "pair_link": pair_link(remote, local),
    }
