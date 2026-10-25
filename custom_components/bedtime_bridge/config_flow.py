"""Config flow: choose what Snooze/Stop do, which entities to read, then pair the phone."""

from __future__ import annotations

from typing import Any

import voluptuous as vol

from homeassistant.components import webhook
from homeassistant.config_entries import ConfigEntry, ConfigFlow, ConfigFlowResult, OptionsFlow
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import selector

from .pairing import async_placeholders

from .const import shift_types as parse_shift_types
from .const import (
    CONF_BED_SENSOR,
    CONF_BEDTIME_HELPER,
    CONF_EXIT_LATCH,
    CONF_HOME_ONLY,
    CONF_NOTIFY,
    CONF_PRESENCE,
    CONF_REPLAN_ALERT,
    CONF_SAFETY_CAUSES,
    CONF_SAFETY_MINUTES,
    CONF_SHIFT_OVERRIDE,
    CONF_SHIFT_SENSOR,
    CONF_SHIFT_TYPES,
    CONF_SNOOZE_HELPER,
    CONF_STOP_HELPER,
    CONF_WAKE_ACTION,
    CONF_WEATHER,
    CONF_WEBHOOK_ID,
    DEFAULT_SAFETY_CAUSES,
    DEFAULT_SAFETY_MINUTES,
    DEFAULT_SHIFT_TYPES,
    DOMAIN,
    SUGGESTED,
    WAKE_ACTIONS,
    WAKE_BOTH,
)

HELPER_DOMAINS = ["input_boolean", "script", "automation", "switch", "scene"]
OPTION_KEYS = [
    CONF_PRESENCE,
    CONF_HOME_ONLY,
    CONF_BEDTIME_HELPER,
    CONF_WAKE_ACTION,
    CONF_SNOOZE_HELPER,
    CONF_STOP_HELPER,
    CONF_SHIFT_OVERRIDE,
    CONF_SHIFT_SENSOR,
    CONF_WEATHER,
    CONF_SHIFT_TYPES,
    CONF_SAFETY_CAUSES,
    CONF_SAFETY_MINUTES,
    CONF_NOTIFY,
    CONF_REPLAN_ALERT,
    CONF_BED_SENSOR,
    CONF_EXIT_LATCH,
]


def _schema(hass: HomeAssistant, current: dict[str, Any]) -> vol.Schema:
    """Same fields for setup and options. Suggests your existing entities when they exist."""

    def suggested(key: str) -> dict[str, Any]:
        if key in current:
            return {"suggested_value": current[key]} if current[key] else {}
        entity_id = SUGGESTED.get(key)
        return {"suggested_value": entity_id} if entity_id and hass.states.get(entity_id) else {}

    def entity(domains: list[str]) -> selector.EntitySelector:
        return selector.EntitySelector(selector.EntitySelectorConfig(domain=domains))

    def presence_suggestion() -> dict[str, Any]:
        if CONF_PRESENCE in current:
            return {"suggested_value": current[CONF_PRESENCE]} if current[CONF_PRESENCE] else {}
        people = hass.states.async_entity_ids("person")
        return {"suggested_value": people[:1]} if people else {}

    home_only = current.get(CONF_HOME_ONLY)
    replan_alert = current.get(CONF_REPLAN_ALERT)
    shift_names = parse_shift_types(current.get(CONF_SHIFT_TYPES) or DEFAULT_SHIFT_TYPES)
    cause_options = ["calendar", "automade", *shift_names]

    def notify_suggestion() -> dict[str, Any]:
        if CONF_NOTIFY in current:
            return {"suggested_value": current[CONF_NOTIFY]} if current[CONF_NOTIFY] else {}
        phones = sorted(s for s in hass.services.async_services_for_domain("notify") if s.startswith("mobile_app_"))
        return {"suggested_value": f"notify.{phones[0]}"} if phones else {}
    return vol.Schema(
        {
            vol.Optional(CONF_PRESENCE, description=presence_suggestion()): selector.EntitySelector(
                selector.EntitySelectorConfig(domain=["person", "device_tracker", "binary_sensor"], multiple=True)
            ),
            vol.Required(CONF_HOME_ONLY, default=True if home_only is None else home_only): selector.BooleanSelector(),
            vol.Optional(CONF_BEDTIME_HELPER, description=suggested(CONF_BEDTIME_HELPER)): entity(HELPER_DOMAINS),
            vol.Required(CONF_WAKE_ACTION, default=current.get(CONF_WAKE_ACTION) or WAKE_BOTH): selector.SelectSelector(
                selector.SelectSelectorConfig(options=WAKE_ACTIONS, translation_key=CONF_WAKE_ACTION)
            ),
            vol.Optional(CONF_SNOOZE_HELPER, description=suggested(CONF_SNOOZE_HELPER)): entity(HELPER_DOMAINS),
            vol.Optional(CONF_STOP_HELPER, description=suggested(CONF_STOP_HELPER)): entity(HELPER_DOMAINS),
            vol.Optional(CONF_SHIFT_OVERRIDE, description=suggested(CONF_SHIFT_OVERRIDE)): entity(["input_select", "select"]),
            vol.Optional(CONF_SHIFT_SENSOR, description=suggested(CONF_SHIFT_SENSOR)): entity(["sensor"]),
            vol.Optional(CONF_WEATHER, description=suggested(CONF_WEATHER)): entity(["weather"]),
            vol.Required(CONF_SHIFT_TYPES, default=current.get(CONF_SHIFT_TYPES) or DEFAULT_SHIFT_TYPES): selector.TextSelector(),
            vol.Optional(
                CONF_SAFETY_CAUSES, default=current.get(CONF_SAFETY_CAUSES) or DEFAULT_SAFETY_CAUSES
            ): selector.SelectSelector(selector.SelectSelectorConfig(options=cause_options, multiple=True, custom_value=True)),
            vol.Required(
                CONF_SAFETY_MINUTES, default=current.get(CONF_SAFETY_MINUTES) or DEFAULT_SAFETY_MINUTES
            ): selector.NumberSelector(selector.NumberSelectorConfig(min=5, max=60, step=5, unit_of_measurement="min")),
            vol.Optional(CONF_NOTIFY, description=notify_suggestion()): selector.TextSelector(),
            vol.Optional(CONF_BED_SENSOR, description=suggested(CONF_BED_SENSOR)): entity(["binary_sensor"]),
            vol.Optional(CONF_EXIT_LATCH, description=suggested(CONF_EXIT_LATCH)): entity(["input_boolean", "binary_sensor"]),
            vol.Required(CONF_REPLAN_ALERT, default=True if replan_alert is None else replan_alert): selector.BooleanSelector(),
        }
    )


class BedtimeBridgeConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    def __init__(self) -> None:
        self._options: dict[str, Any] = {}
        self._webhook_id = ""

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        await self.async_set_unique_id(DOMAIN)
        self._abort_if_unique_id_configured()
        if user_input is not None:
            self._options = user_input
            self._webhook_id = webhook.async_generate_id()
            return await self.async_step_pair()
        return self.async_show_form(step_id="user", data_schema=_schema(self.hass, {}))

    async def async_step_pair(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Shows the address to paste into the app before the entry exists."""
        if user_input is not None:
            return self.async_create_entry(
                title="Bedtime Bridge", data={CONF_WEBHOOK_ID: self._webhook_id}, options=self._options
            )
        return self.async_show_form(
            step_id="pair",
            data_schema=vol.Schema({}),
            description_placeholders=await async_placeholders(self.hass, self._webhook_id),
        )

    @staticmethod
    @callback
    def async_get_options_flow(config_entry: ConfigEntry) -> OptionsFlow:
        return BedtimeBridgeOptionsFlow()


class BedtimeBridgeOptionsFlow(OptionsFlow):
    async def async_step_init(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        if user_input is not None:
            return self.async_create_entry(data=user_input)
        return self.async_show_form(
            step_id="init",
            # Every key present (None when cleared), so a helper you removed isn't suggested again.
            data_schema=_schema(self.hass, {key: self.config_entry.options.get(key) for key in OPTION_KEYS}),
            description_placeholders=await async_placeholders(self.hass, self.config_entry.data[CONF_WEBHOOK_ID]),
        )
