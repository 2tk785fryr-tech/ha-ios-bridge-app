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
    CONF_APNS_KEY,
    CONF_APNS_KEY_ID,
    CONF_BEDROOM_DOOR,
    CONF_DRIVE_SOURCE,
    CONF_GOOGLE_KEY,
    CONF_HALLWAY_SENSORS,
    CONF_MAPS_KEY,
    CONF_MAPS_KEY_ID,
    CONF_TOMTOM_KEY,
    CONF_PHONE_BATTERY,
    CONF_PHONE_BATTERY_STATE,
    CONF_WIND_DOWN_HELPER,
    CONF_WIND_DOWN_NOTIFY,
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
    SUGGESTED_HALLWAY,
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
    CONF_WIND_DOWN_HELPER,
    CONF_BEDROOM_DOOR,
    CONF_WIND_DOWN_NOTIFY,
    CONF_PHONE_BATTERY,
    CONF_PHONE_BATTERY_STATE,
    CONF_APNS_KEY,
    CONF_APNS_KEY_ID,
    CONF_DRIVE_SOURCE,
    CONF_MAPS_KEY,
    CONF_MAPS_KEY_ID,
    CONF_TOMTOM_KEY,
    CONF_GOOGLE_KEY,
    CONF_HALLWAY_SENSORS,
]


def _suggested_phone(hass: HomeAssistant) -> str | None:
    """The iPhone's mobile_app notify service, ahead of any Mac or iPad on the account
    (mobile_app_michaels_macbook_pro sorts before mobile_app_mikes_iphone)."""
    services = sorted(s for s in hass.services.async_services_for_domain("notify") if s.startswith("mobile_app_"))
    for hint in ("iphone", "phone"):
        if match := next((s for s in services if hint in s), None):
            return match
    return services[0] if services else None


# Configure is a menu of these pages, each its own small form (v0.4.7 item 9). Every option is on
# exactly one page.
PAGES: dict[str, list[str]] = {
    "you": [CONF_PRESENCE, CONF_HOME_ONLY, CONF_HOME_CHECKS],
    "wake": [CONF_WAKE_ACTION, CONF_SNOOZE_HELPER, CONF_STOP_HELPER, CONF_EARLY_HELPER, CONF_SLEEP_IN, CONF_AWAKE_HELPER],
    "bedroom": [CONF_BED_SENSOR, CONF_BEDROOM_DOOR, CONF_HALLWAY_SENSORS, CONF_EXIT_LATCH, CONF_REARM_MINUTES, CONF_RERUN_MINUTES],
    "bedtime": [CONF_BEDTIME_HELPER, CONF_WIND_DOWN_HELPER, CONF_NAP_HELPER, CONF_WIND_DOWN_NOTIFY],
    "shifts": [CONF_SHIFT_OVERRIDE, CONF_SHIFT_SENSOR, CONF_SHIFT_TYPES, CONF_CALENDAR, CONF_WEATHER, CONF_CURTAIN_OFFSET],
    "phone": [CONF_NOTIFY, CONF_PHONE_COMMANDS, CONF_REPLAN_ALERT, CONF_PHONE_BATTERY, CONF_PHONE_BATTERY_STATE, CONF_COMPLETE_MINUTES],
    "backstops": [CONF_HOUSE_BACKSTOP, CONF_OLD_RUNGS, CONF_RESTART_AUTOMATIONS, CONF_LADDER_SHIFT_TYPES],
    "keys": [CONF_APNS_KEY, CONF_APNS_KEY_ID, CONF_DRIVE_SOURCE, CONF_MAPS_KEY, CONF_MAPS_KEY_ID, CONF_TOMTOM_KEY, CONF_GOOGLE_KEY],
}
# Adding the integration asks only these; the rest start from their defaults and suggestions.
SETUP_KEYS = [CONF_PRESENCE, CONF_HOME_ONLY, CONF_NOTIFY, CONF_PHONE_COMMANDS, CONF_WAKE_ACTION, CONF_SHIFT_TYPES]


def _subset(schema: vol.Schema, keys: list[str]) -> vol.Schema:
    return vol.Schema({marker: value for marker, value in schema.schema.items() if marker.schema in keys})


def _starting_options(hass: HomeAssistant, schema: vol.Schema) -> dict[str, Any]:
    """Every option's default, and its suggestion where the entity exists, as the full form
    would have saved them."""
    options: dict[str, Any] = {}
    for marker in schema.schema:
        default = marker.default() if callable(getattr(marker, "default", None)) and marker.default is not vol.UNDEFINED else None
        suggestion = (marker.description or {}).get("suggested_value") if isinstance(marker.description, dict) else None
        value = suggestion if suggestion not in (None, "", []) else default
        if value is not None:
            options[marker.schema] = value
    return options


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
    def hallway_suggestion() -> dict[str, Any]:
        if CONF_HALLWAY_SENSORS in current:
            return {"suggested_value": current[CONF_HALLWAY_SENSORS]} if current[CONF_HALLWAY_SENSORS] else {}
        found = [e for e in SUGGESTED_HALLWAY if hass.states.get(e)]
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
            vol.Optional(CONF_WIND_DOWN_HELPER, description=suggested(CONF_WIND_DOWN_HELPER)): entity(["input_boolean"]),
            vol.Optional(CONF_BEDROOM_DOOR, description=suggested(CONF_BEDROOM_DOOR)): entity(["binary_sensor"]),
            vol.Optional(CONF_HALLWAY_SENSORS, description=hallway_suggestion()): selector.EntitySelector(
                selector.EntitySelectorConfig(domain=["binary_sensor"], multiple=True)
            ),
            vol.Optional(CONF_WIND_DOWN_NOTIFY, description=suggested(CONF_WIND_DOWN_NOTIFY)): selector.TextSelector(),
            vol.Optional(CONF_PHONE_BATTERY, description=suggested(CONF_PHONE_BATTERY)): entity(["sensor"]),
            vol.Optional(CONF_PHONE_BATTERY_STATE, description=suggested(CONF_PHONE_BATTERY_STATE)): entity(["sensor"]),
            vol.Optional(CONF_APNS_KEY, description=suggested(CONF_APNS_KEY)): selector.TextSelector(
                selector.TextSelectorConfig(multiline=True, type=selector.TextSelectorType.PASSWORD)
            ),
            vol.Optional(CONF_APNS_KEY_ID, description=suggested(CONF_APNS_KEY_ID)): selector.TextSelector(),
            vol.Required(CONF_DRIVE_SOURCE, default=current.get(CONF_DRIVE_SOURCE) or "phone"): selector.SelectSelector(
                selector.SelectSelectorConfig(options=["phone", "apple", "tomtom", "google", "longest"], translation_key=CONF_DRIVE_SOURCE)
            ),
            vol.Optional(CONF_MAPS_KEY, description=suggested(CONF_MAPS_KEY)): selector.TextSelector(
                selector.TextSelectorConfig(multiline=True, type=selector.TextSelectorType.PASSWORD)
            ),
            vol.Optional(CONF_MAPS_KEY_ID, description=suggested(CONF_MAPS_KEY_ID)): selector.TextSelector(),
            vol.Optional(CONF_TOMTOM_KEY, description=suggested(CONF_TOMTOM_KEY)): selector.TextSelector(
                selector.TextSelectorConfig(type=selector.TextSelectorType.PASSWORD)
            ),
            vol.Optional(CONF_GOOGLE_KEY, description=suggested(CONF_GOOGLE_KEY)): selector.TextSelector(
                selector.TextSelectorConfig(type=selector.TextSelectorType.PASSWORD)
            ),
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
        full = _schema(self.hass, {})
        if user_input is not None:
            self._options = {**_starting_options(self.hass, full), **{key: None for key in SETUP_KEYS}, **user_input}
            self._webhook_id = webhook.async_generate_id()
            return await self.async_step_pair()
        return self.async_show_form(step_id="user", data_schema=_subset(full, SETUP_KEYS))

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
    """A menu of pages (v0.4.7 item 9); each page saves its own options."""

    async def async_step_init(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return self.async_show_menu(
            step_id="init",
            menu_options=list(PAGES),
            description_placeholders=await async_placeholders(self.hass, self.config_entry.data[CONF_WEBHOOK_ID]),
        )

    async def _page(self, page: str, user_input: dict[str, Any] | None) -> ConfigFlowResult:
        current = dict(self.config_entry.options)
        if user_input is not None:
            # A field cleared on this page stays cleared; other pages keep theirs.
            return self.async_create_entry(data={**current, **{key: None for key in PAGES[page]}, **user_input})
        # Only what the entry has stored: cleared fields (None) stay empty, options it has never
        # had get a suggestion.
        return self.async_show_form(step_id=page, data_schema=_subset(_schema(self.hass, current), PAGES[page]))

    async def async_step_you(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return await self._page("you", user_input)

    async def async_step_wake(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return await self._page("wake", user_input)

    async def async_step_bedroom(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return await self._page("bedroom", user_input)

    async def async_step_bedtime(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return await self._page("bedtime", user_input)

    async def async_step_shifts(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return await self._page("shifts", user_input)

    async def async_step_phone(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return await self._page("phone", user_input)

    async def async_step_backstops(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return await self._page("backstops", user_input)

    async def async_step_keys(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return await self._page("keys", user_input)
