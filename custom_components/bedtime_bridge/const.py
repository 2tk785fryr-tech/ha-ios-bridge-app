"""Constants for Bedtime Bridge."""

DOMAIN = "bedtime_bridge"
EVENT = "bedtime_bridge"

CONF_WEBHOOK_ID = "webhook_id"
CONF_WAKE_ACTION = "wake_action"
CONF_SNOOZE_HELPER = "snooze_helper"
CONF_STOP_HELPER = "stop_helper"
CONF_SHIFT_OVERRIDE = "shift_override_entity"
CONF_SHIFT_SENSOR = "shift_sensor_entity"
CONF_WEATHER = "weather_entity"
CONF_SHIFT_TYPES = "shift_types"
CONF_PRESENCE = "presence_entities"
CONF_HOME_ONLY = "home_only"
CONF_BEDTIME_HELPER = "bedtime_helper"
CONF_NOTIFY = "notify_service"
CONF_REPLAN_ALERT = "replan_alert"
CONF_SAFETY_CAUSES = "safety_net_causes"
CONF_SAFETY_MINUTES = "safety_net_minutes"

# What Snooze/Stop on the phone do in Home Assistant.
WAKE_BOTH = "both"
WAKE_HELPERS = "helpers"
WAKE_EVENTS = "events"
WAKE_ACTIONS = [WAKE_BOTH, WAKE_HELPERS, WAKE_EVENTS]

# Suggested defaults, used only when these entities exist.
SUGGESTED = {
    CONF_SNOOZE_HELPER: "input_boolean.wake_fade",
    CONF_STOP_HELPER: "input_boolean.wake_mike",
    CONF_BEDTIME_HELPER: "input_boolean.bedtime_routine",
    CONF_SHIFT_OVERRIDE: "input_select.select_shift_override",
    CONF_SHIFT_SENSOR: "sensor.current_shift",
    CONF_WEATHER: "weather.forecast_home",
}
DEFAULT_SHIFT_TYPES = "Days, Swings"
DEFAULT_SAFETY_CAUSES = ["calendar"]
DEFAULT_SAFETY_MINUTES = 15
# Opens the app and re-plans (the app registers this URL scheme).
REPLAN_URL = "bedtimebridge://replan"

# Settings the app reads back from Home Assistant: key -> (name, min, max, step).
SETTINGS = {
    "get_ready_minutes": ("Get-ready time", 0, 240, 5),
    "arrival_buffer_minutes": ("Arrive early", 0, 60, 5),
    "snooze_minutes": ("Snooze length", 1, 30, 1),
    "weather_extra_minutes": ("Bad-weather extra time", 0, 60, 5),
    "leave_reminder_minutes": ("Leave-by reminder lead", 0, 60, 5),
}
SHIFT_LEAD_PREFIX = "shift_lead:"

# Webhook message types sent by the app.
MSG_CONTEXT = "context"
MSG_FORECAST = "forecast"
MSG_PLANNED = "planned"
MSG_SNOOZED = "snoozed"
MSG_STOPPED = "stopped"
MSG_CANCELLED = "cancelled"
MSG_LEAVE_BY = "leave_by"
MSG_BEDTIME = "bedtime"
MSG_PLAN_FAILED = "plan_failed"
EVENT_PLAN_OUTDATED = "plan_outdated"

# Presence states that count as home. Anything unknown/unavailable also counts as home, so a
# glitching tracker never silently skips your morning routine while you're in bed.
HOME_STATES = {"home", "on"}
UNKNOWN_STATES = {"unknown", "unavailable"}


def signal_update(entry_id: str) -> str:
    """Dispatcher signal fired when the bridge state changes."""
    return f"{DOMAIN}_update_{entry_id}"


def shift_types(text: str | None) -> list[str]:
    """'Days, Swings' -> ['Days', 'Swings']."""
    return [part.strip() for part in (text or "").split(",") if part.strip()]
