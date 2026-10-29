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
    CONF_AWAKE_HELPER,
    CONF_NAP_HELPER,
    CONF_BED_SENSOR,
    CONF_BEDTIME_HELPER,
    CONF_CURTAIN_OFFSET,
    CONF_EXIT_LATCH,
    CONF_HOME_CHECKS,
    CONF_HOME_ONLY,
    CONF_NOTIFY,
    CONF_PHONE_COMMANDS,
    CONF_PRESENCE,
    CONF_REARM_MINUTES,
    CONF_REPLAN_ALERT,
    CONF_RERUN_MINUTES,
    CONF_CALENDAR,
    CONF_COMPLETE_MINUTES,
    CONF_HOUSE_BACKSTOP,
    CONF_OLD_RUNGS,
    CONF_EARLY_HELPER,
    CONF_RESTART_AUTOMATIONS,
    CONF_LADDER_SHIFT_TYPES,
    CONF_SHIFT_OVERRIDE,
    CONF_SHIFT_SENSOR,
    CONF_SHIFT_TYPES,
    CONF_SLEEP_IN,
    CONF_SNOOZE_HELPER,
    CONF_STOP_HELPER,
    CONF_WAKE_ACTION,
    CONF_WEATHER,
    CONF_WEBHOOK_ID,
    DEFAULT_CURTAIN_OFFSET,
    DEFAULT_REARM_MINUTES,
    DEFAULT_RERUN_MINUTES,
    DEFAULT_COMPLETE_MINUTES,
    DEFAULT_OLD_RUNGS,
    HOUSE_BRIDGE,
    HOUSE_OLD,
    DEFAULT_LADDER_SHIFT_TYPES,
    DEFAULT_RESTART_AUTOMATIONS,
    DEFAULT_SHIFT_TYPES,
    DOMAIN,
    SUGGESTED,
    SUGGESTED_HOME_CHECKS,
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
    CONF_EARLY_HELPER,
    CONF_SHIFT_OVERRIDE,
    CONF_SHIFT_SENSOR,
    CONF_WEATHER,
    CONF_SHIFT_TYPES,
    CONF_LADDER_SHIFT_TYPES,
    CONF_CALENDAR,
    CONF_RESTART_AUTOMATIONS,
    CONF_HOUSE_BACKSTOP,
    CONF_OLD_RUNGS,
    CONF_NOTIFY,
    CONF_REPLAN_ALERT,
    CONF_BED_SENSOR,
    CONF_EXIT_LATCH,
    CONF_PHONE_COMMANDS,
    CONF_COMPLETE_MINUTES,
    CONF_REARM_MINUTES,
    CONF_SLEEP_IN,
    CONF_CURTAIN_OFFSET,
    CONF_HOME_CHECKS,
    CONF_AWAKE_HELPER,
    CONF_RERUN_MINUTES,
    CONF_NAP_HELPER,
]


def _suggested_phone(hass: HomeAssistant) -> str | None:
    """The iPhone's mobile_app notify service, ahead of any Mac or iPad on the account
    (mobile_app_michaels_macbook_pro sorts before mobile_app_mikes_iphone)."""
    services = sorted(s for s in hass.services.async_services_for_domain("notify") if s.startswith("mobile_app_"))
    for hint in ("iphone", "phone"):
        if match := next((s for s in services if hint in s), None):
            return match
    return services[0] if services else None


def _with_cleared_keys(user_input: dict[str, Any]) -> dict[str, Any]:
    """Store a cleared optional field as None, so it stays cleared. Options the entry has never
    stored (e.g. added by an update) are absent, and Configure suggests a value for them."""
    return {**{key: None for key in OPTION_KEYS}, **user_input}


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
    phone_commands = current.get(CONF_PHONE_COMMANDS)

    def home_checks_suggestion() -> dict[str, Any]:
        if CONF_HOME_CHECKS in current:
            return {"suggested_value": current[CONF_HOME_CHECKS]} if current[CONF_HOME_CHECKS] else {}
        found = [e for e in SUGGESTED_HOME_CHECKS if hass.states.get(e)]
        return {"suggested_value": found} if found else {}
    shift_names = parse_shift_types(current.get(CONF_SHIFT_TYPES) or DEFAULT_SHIFT_TYPES)

    def restart_suggestion() -> dict[str, Any]:
        if CONF_RESTART_AUTOMATIONS in current:
            return {"suggested_value": current[CONF_RESTART_AUTOMATIONS]}
        found = [e for e in DEFAULT_RESTART_AUTOMATIONS if hass.states.get(e)]
        return {"suggested_value": found} if found else {}

    def notify_suggestion() -> dict[str, Any]:
        if CONF_NOTIFY in current:
            return {"suggested_value": current[CONF_NOTIFY]} if current[CONF_NOTIFY] else {}
        phone = _suggested_phone(hass)
        return {"suggested_value": f"notify.{phone}"} if phone else {}
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
            vol.Optional(CONF_EARLY_HELPER, description=suggested(CONF_EARLY_HELPER)): entity(HELPER_DOMAINS),
            vol.Optional(CONF_SHIFT_OVERRIDE, description=suggested(CONF_SHIFT_OVERRIDE)): entity(["input_select", "select"]),
            vol.Optional(CONF_SHIFT_SENSOR, description=suggested(CONF_SHIFT_SENSOR)): entity(["sensor"]),
            vol.Optional(CONF_WEATHER, description=suggested(CONF_WEATHER)): entity(["weather"]),
            vol.Required(CONF_SHIFT_TYPES, default=current.get(CONF_SHIFT_TYPES) or DEFAULT_SHIFT_TYPES): selector.TextSelector(),
            vol.Optional(
                CONF_LADDER_SHIFT_TYPES, default=current.get(CONF_LADDER_SHIFT_TYPES) or DEFAULT_LADDER_SHIFT_TYPES
            ): selector.SelectSelector(selector.SelectSelectorConfig(options=shift_names, multiple=True, custom_value=True)),
            vol.Optional(CONF_CALENDAR, description=suggested(CONF_CALENDAR)): entity(["calendar"]),
            vol.Optional(CONF_RESTART_AUTOMATIONS, description=restart_suggestion()): selector.EntitySelector(
                selector.EntitySelectorConfig(domain=["automation"], multiple=True)
            ),
            vol.Required(CONF_HOUSE_BACKSTOP, default=current.get(CONF_HOUSE_BACKSTOP) or HOUSE_OLD): selector.SelectSelector(
                selector.SelectSelectorConfig(options=[HOUSE_OLD, HOUSE_BRIDGE], translation_key=CONF_HOUSE_BACKSTOP)
            ),
            vol.Optional(CONF_OLD_RUNGS, default=current.get(CONF_OLD_RUNGS) or DEFAULT_OLD_RUNGS): selector.EntitySelector(
                selector.EntitySelectorConfig(domain=["sensor"], multiple=True)
            ),
            vol.Optional(CONF_NOTIFY, description=notify_suggestion()): selector.TextSelector(),
            vol.Optional(CONF_BED_SENSOR, description=suggested(CONF_BED_SENSOR)): entity(["binary_sensor"]),
            vol.Optional(CONF_EXIT_LATCH, description=suggested(CONF_EXIT_LATCH)): entity(["input_boolean", "binary_sensor"]),
            vol.Required(CONF_REPLAN_ALERT, default=True if replan_alert is None else replan_alert): selector.BooleanSelector(),
            vol.Required(CONF_PHONE_COMMANDS, default=bool(phone_commands)): selector.BooleanSelector(),
            vol.Required(
                CONF_COMPLETE_MINUTES, default=current.get(CONF_COMPLETE_MINUTES) or DEFAULT_COMPLETE_MINUTES
            ): selector.NumberSelector(selector.NumberSelectorConfig(min=1, max=30, step=1, unit_of_measurement="min")),
            vol.Required(
                CONF_REARM_MINUTES, default=current.get(CONF_REARM_MINUTES) or DEFAULT_REARM_MINUTES
            ): selector.NumberSelector(selector.NumberSelectorConfig(min=1, max=30, step=1, unit_of_measurement="min")),
            vol.Optional(CONF_SLEEP_IN, description=suggested(CONF_SLEEP_IN)): entity(["input_boolean"]),
            vol.Optional(CONF_AWAKE_HELPER, description=suggested(CONF_AWAKE_HELPER)): entity(["input_boolean"]),
            vol.Optional(CONF_NAP_HELPER, description=suggested(CONF_NAP_HELPER)): entity(["input_boolean"]),
            vol.Required(
                CONF_RERUN_MINUTES, default=current.get(CONF_RERUN_MINUTES) or DEFAULT_RERUN_MINUTES
            ): selector.NumberSelector(selector.NumberSelectorConfig(min=1, max=60, step=1, unit_of_measurement="min")),
            vol.Optional(CONF_HOME_CHECKS, description=home_checks_suggestion()): selector.EntitySelector(
                selector.EntitySelectorConfig(domain=["cover", "lock", "binary_sensor"], multiple=True)
            ),
            vol.Required(
                CONF_CURTAIN_OFFSET, default=current.get(CONF_CURTAIN_OFFSET) or DEFAULT_CURTAIN_OFFSET
            ): selector.NumberSelector(selector.NumberSelectorConfig(min=0, max=120, step=5, unit_of_measurement="min")),
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
            self._options = _with_cleared_keys(user_input)
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
            return self.async_create_entry(data=_with_cleared_keys(user_input))
        return self.async_show_form(
            step_id="init",
            # Only what the entry has stored: cleared fields (None) stay empty, options it has
            # never had get a suggestion.
            data_schema=_schema(self.hass, dict(self.config_entry.options)),
            description_placeholders=await async_placeholders(self.hass, self.config_entry.data[CONF_WEBHOOK_ID]),
        )
