"""v0.4.6 integration tests, by spec item."""

from datetime import datetime, timedelta

from homeassistant.util import dt as dt_util

from custom_components.bedtime_bridge import weekly

from .test_ladder import TZ, calendar_days, ladder, local  # noqa: F401
from .test_v043 import at
from .test_webhook import send

SUNDAY_6PM = {"enabled": True, "weekday": 6, "time": "18:00"}


def _tz():
    return dt_util.get_time_zone(TZ)


# MARK: Item 5, weekly summary: this week so far, and earlier weeks


async def test_item5_cutoff_is_the_settings_day_and_time(hass):
    await hass.config.async_set_time_zone(TZ)
    # Friday 30 Oct 2026: the last cut-off was Sunday 25 Oct, 6 PM.
    now = datetime(2026, 10, 30, 9, 0, tzinfo=_tz())
    assert dt_util.as_local(weekly.last_cutoff(SUNDAY_6PM, now)) == datetime(2026, 10, 25, 18, 0, tzinfo=_tz())
    # At the cut-off itself, the new week starts.
    sunday = datetime(2026, 11, 1, 18, 0, tzinfo=_tz())
    assert weekly.last_cutoff(SUNDAY_6PM, sunday) == dt_util.as_utc(sunday)
    # Wednesday 7:30 AM, even with the notification off.
    wednesday = {"enabled": False, "weekday": 2, "time": "07:30"}
    assert dt_util.as_local(weekly.last_cutoff(wednesday, now)) == datetime(2026, 10, 28, 7, 30, tzinfo=_tz())


async def test_item5_this_week_so_far_then_earlier_weeks(hass):
    await hass.config.async_set_time_zone(TZ)
    now = datetime(2026, 10, 30, 9, 0, tzinfo=_tz())
    history = []
    # This week (since Sun 25 Oct 6 PM): two mornings and a nap.
    weekly.record(history, "morning", datetime(2026, 10, 27, 5, 0, tzinfo=_tz()), snoozes=1)
    weekly.record(history, "morning", datetime(2026, 10, 29, 5, 0, tzinfo=_tz()), snoozes=3)
    weekly.record(history, "nap", datetime(2026, 10, 28, 14, 0, tzinfo=_tz()), minutes=20)
    # The week before (18 – 25 Oct): one morning, one change, and one right at the cut-off.
    weekly.record(history, "morning", datetime(2026, 10, 20, 5, 0, tzinfo=_tz()), snoozes=0)
    weekly.record(history, "change", datetime(2026, 10, 21, 22, 0, tzinfo=_tz()), reason="Snow delay")
    weekly.record(history, "change", datetime(2026, 10, 25, 18, 0, tzinfo=_tz()), reason="At the cut-off")
    # Three weeks back (4 – 11 Oct); the two weeks between have nothing and are left out.
    weekly.record(history, "morning", datetime(2026, 10, 6, 5, 0, tzinfo=_tz()), snoozes=2)
    nights = [{"go_to_bed": datetime(2026, 10, 26, 22, 0, tzinfo=_tz()).isoformat(), "minutes_off": 8}]

    weeks = weekly.weeks(history, nights, SUNDAY_6PM, now)
    assert [w["current"] for w in weeks] == [True, False, False]
    this, last, older = weeks
    assert dt_util.as_local(dt_util.parse_datetime(this["from"])) == datetime(2026, 10, 25, 18, 0, tzinfo=_tz())
    assert this["mornings"] == 2 and this["naps"] == 1 and this["nights_tracked"] == 1
    # The change at the cut-off belongs to this week, not the one before.
    assert this["change_reasons"] == ["At the cut-off"]
    assert dt_util.as_local(dt_util.parse_datetime(last["from"])) == datetime(2026, 10, 18, 18, 0, tzinfo=_tz())
    assert dt_util.as_local(dt_util.parse_datetime(last["to"])) == datetime(2026, 10, 25, 18, 0, tzinfo=_tz())
    assert last["mornings"] == 1 and last["change_reasons"] == ["Snow delay"]
    assert dt_util.as_local(dt_util.parse_datetime(older["from"])) == datetime(2026, 10, 4, 18, 0, tzinfo=_tz())


async def test_item5_at_most_eight_earlier_weeks(hass):
    await hass.config.async_set_time_zone(TZ)
    now = datetime(2026, 10, 30, 9, 0, tzinfo=_tz())
    history = []
    for back in range(12):
        weekly.record(history, "morning", now - timedelta(days=7 * back), snoozes=0)
    weeks = weekly.weeks(history, [], SUNDAY_6PM, now)
    assert len(weeks) == 1 + 8
    assert weekly.KEEP_DAYS >= 7 * 9


async def test_item5_reply_carries_the_weeks_and_the_notification_the_week_that_ended(hass, ladder, hass_client_no_auth, freezer):
    await ladder()
    await send(hass_client_no_auth, {"type": "context", "data": {"weekly_summary": SUNDAY_6PM}})
    await send(hass_client_no_auth, {"type": "nap_started", "data": {"alarm_times": [local("21:00", day=27).isoformat()], "minutes": 20}})
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    weeks = reply["weekly_summaries"]
    assert weeks[0]["current"] is True and weeks[0]["naps"] == 1
    # Sunday 1 Nov, 6 PM: the summary sent is the week that just ended (25 Oct – 1 Nov).
    await at(hass, freezer, datetime(2026, 11, 1, 18, 0, tzinfo=_tz()))
    reply = await send(hass_client_no_auth, {"type": "context", "data": {}})
    sent = reply["weekly_summary"]
    assert dt_util.as_local(dt_util.parse_datetime(sent["from"])) == datetime(2026, 10, 25, 18, 0, tzinfo=_tz())
    assert sent["naps"] == 1
    # And a new week has started, with nothing in it yet.
    assert reply["weekly_summaries"][0]["current"] is True and reply["weekly_summaries"][0]["naps"] == 0
    assert reply["weekly_summaries"][1]["naps"] == 1
