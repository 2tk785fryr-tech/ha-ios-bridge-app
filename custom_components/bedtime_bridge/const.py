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
# Leave-by backstop ladder (item 6): which shift types get one, and the calendar used to tell a
# first day back when there's no plan.
CONF_LADDER_SHIFT_TYPES = "ladder_shift_types"
# Item 8: turned on instead of the stop helper when the alarms are ended before they ring.
CONF_EARLY_HELPER = "early_wake_helper"
CONF_CALENDAR = "calendar_entity"
CONF_BED_SENSOR = "bed_sensor"
CONF_EXIT_LATCH = "exit_latch"
CONF_PHONE_COMMANDS = "phone_commands"
CONF_REARM_MINUTES = "rearm_minutes"
CONF_SLEEP_IN = "sleep_in_helper"
CONF_CURTAIN_OFFSET = "curtain_offset_minutes"
CONF_HOME_CHECKS = "home_check_entities"
CONF_AWAKE_HELPER = "awake_helper"
CONF_RERUN_MINUTES = "rerun_minutes"

# What Snooze/Stop on the phone do in Home Assistant.
WAKE_BOTH = "both"
WAKE_HELPERS = "helpers"
WAKE_EVENTS = "events"
WAKE_ACTIONS = [WAKE_BOTH, WAKE_HELPERS, WAKE_EVENTS]

# Suggested defaults, used only when these entities exist.
SUGGESTED = {
    CONF_CALENDAR: "calendar.calendar",
    CONF_SNOOZE_HELPER: "input_boolean.wake_fade",
    CONF_STOP_HELPER: "input_boolean.wake_mike",
    CONF_BEDTIME_HELPER: "input_boolean.bedtime_routine",
    CONF_BED_SENSOR: "binary_sensor.master_bedroom_bed_presence_bed_occupied_left",
    CONF_EXIT_LATCH: "input_boolean.bedroom_exited_today",
    CONF_SLEEP_IN: "input_boolean.sleep_in",
    CONF_AWAKE_HELPER: "input_boolean.awake_for_day",
    CONF_SHIFT_OVERRIDE: "input_select.select_shift_override",
    CONF_SHIFT_SENSOR: "sensor.current_shift",
    CONF_WEATHER: "weather.forecast_home",
}
# Checked for the away bedtime summary ("Everything at home is good"), when they exist.
SUGGESTED_HOME_CHECKS = [
    "cover.garage_garage_door_door",
    "binary_sensor.entryway_entryway_front_door_door",
    "binary_sensor.aqara_door_entryway_garage",
    "binary_sensor.aqara_door_and_window_sensor_door_4",
    "lock.front_door_lock",
]
DEFAULT_SHIFT_TYPES = "Days, Swings"
DEFAULT_LADDER_SHIFT_TYPES = ["Days"]
DEFAULT_CALENDAR = "calendar.calendar"
# Arrive-early buffer for the calendar leave-by until a plan has sent the app's own.
DEFAULT_WORK_BUFFER = 10
DEFAULT_REARM_MINUTES = 5
DEFAULT_RERUN_MINUTES = 15
DEFAULT_CURTAIN_OFFSET = 15
# Push messages a Shortcuts "When I receive a notification" automation on the phone runs a
# shortcut for (the house alarm lives on the phone, not in Home Assistant).
CMD_DISARM = "RUN_DISARM"
CMD_ARM = "RUN_ARM_STAY"
CMD_MORNING = "RUN_GOOD_MORNING"
# Same marker the bedtime nudge sends, so the existing phone automation runs bedtime.
CMD_BEDTIME = "RUN_BEDTIME"
# Item 3 back to bed: the phone puts back what Good Morning changed (MorningState, house alarm,
# Sleep Focus). Runs Back To Bed - App.
CMD_BACK_TO_BED = "RUN_BACK_TO_BED"
# Item 17 (v0.4.1): at each leave reminder the phone re-checks the drive (Check drive and remind).
CMD_LEAVE_CHECK = "RUN_LEAVE_CHECK"
COMMANDS = (CMD_DISARM, CMD_ARM, CMD_MORNING, CMD_BEDTIME, CMD_BACK_TO_BED, CMD_LEAVE_CHECK)
# Leave checks stop this long after leave-by.
LEAVE_CHECK_TAIL_MINUTES = 15
# Item 3 stops what's already running (until v0.5 fires the ladder itself): these automations
# are turned off (cancelling running actions) and straight back on, and these notification tags
# cleared.
CONF_RESTART_AUTOMATIONS = "restart_automations"
# Item 8 (v0.4.1): what the house backstop reads until the cutover, and the old template's rungs.
CONF_HOUSE_BACKSTOP = "house_backstop_source"
HOUSE_OLD = "old"
HOUSE_BRIDGE = "bridge"
CONF_OLD_RUNGS = "old_rung_sensors"
DEFAULT_OLD_RUNGS = ["sensor.wake_rung_early", "sensor.wake_rung_deadline", "sensor.wake_rung_late"]
EVENT_CHANGE_REFUSED = "morning_change_refused"
# A phone shortcut that reports Started but not Completed within this long is flagged.
CONF_COMPLETE_MINUTES = "command_complete_minutes"
DEFAULT_COMPLETE_MINUTES = 5
EVENT_COMMAND_INCOMPLETE = "command_incomplete"
# The phone set fewer alarms than it meant to (it reads back what AlarmKit holds).
EVENT_ALARMS_MISSING = "alarms_missing"
COMMAND_NAMES = {
    "RUN_DISARM": "Disarm",
    "RUN_ARM_STAY": "Arm Stay",
    "RUN_GOOD_MORNING": "Good Morning",
    "RUN_BEDTIME": "the bedtime shortcut",
    "RUN_BACK_TO_BED": "Back To Bed",
    "RUN_LEAVE_CHECK": "the leave check",
}
DEFAULT_RESTART_AUTOMATIONS = ["automation.wake_confirm_still_in_bed_after_alarm", "automation.wake_deadline_backstop"]
RESTART_NOTIFICATION_TAGS = ("wake_backstop", "wake_confirm")
COMMAND_TAG = "bedtime_bridge_command"
# Without getting back into bed by then (or before the regular alarms), it doesn't re-arm.
REARM_GIVE_UP_HOURS = 6
# Opens the app and re-plans (the app registers this URL scheme).
REPLAN_URL = "bedtimebridge://replan"

# Settings the app reads back from Home Assistant: key -> (name, min, max, step).
# Ladder settings (item 6): key -> (name, min, max, step, default). Home Assistant owns these; the
# app can read them.
LADDER_SETTINGS = {
    "rung_early_minutes": ("Ladder early, minutes before leave-by", 10, 180, 5, 50),
    "rung_deadline_minutes": ("Ladder deadline, minutes before leave-by", 10, 180, 5, 35),
    "rung_late_minutes": ("Ladder late, minutes before leave-by", 5, 120, 5, 20),
    "first_day_back_minutes": ("First day back extra", 0, 60, 5, 15),
    "fallback_drive_minutes": ("Fallback drive time", 0, 120, 5, 35),
}

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
MSG_UP_CHECK = "up_check"
MSG_SKIPPED = "skipped"
MSG_UNSKIPPED = "unskipped"
MSG_TEMP_SNOOZED = "temporary_snoozed"
MSG_TEMP_STOPPED = "temporary_stopped"
MSG_HOME_CHECK = "home_check"
MSG_BEDTIME_UNDONE = "bedtime_undone"
# The phone ran the shortcut a command asked for (its last step reports back).
MSG_COMMAND_RAN = "command_ran"
# Item 3: the morning's alarms were moved or cancelled.
MSG_MORNING_CHANGED = "morning_changed"
EVENT_RERUN = "bedtime_rerun"
EVENT_REARMED = "temporary_rearmed"
# The bed sensor drops out for up to ~19 s while you're in it; "empty" must last longer.
BED_EMPTY_SECONDS = 60
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
