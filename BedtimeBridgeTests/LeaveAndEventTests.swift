import XCTest
@testable import BedtimeBridge

/// v0.4.3 items 12 (leave titles, Add leave) and 13 (Add a wake-up event).
final class LeaveAndEventTests: XCTestCase {
    private let calendar = Calendar.current
    private func day(_ d: Int, _ h: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }

    func testItem12TitlesMatchTrimmedAnyCase() {
        XCTAssertTrue(LeaveDays.isLeave(title: "  leave ", titles: ["Leave"]))
        XCTAssertTrue(LeaveDays.isLeave(title: "VACATION", titles: ["Leave", "Vacation"]))
        XCTAssertFalse(LeaveDays.isLeave(title: "Leave early", titles: ["Leave"]), "the whole title, not a word in it")
        XCTAssertFalse(LeaveDays.isLeave(title: "", titles: ["Leave"]))
        XCTAssertEqual(BridgeSettings().leaveTitles, ["Leave"])
    }

    func testItem12OneAllDayEventFirstThroughLastDay() {
        let dates = LeaveDays.eventDates(first: day(3, 14), last: day(7, 9))
        XCTAssertEqual(dates.start, day(3))
        XCTAssertEqual(dates.end, day(8).addingTimeInterval(-1), "through the end of the last day; the day after is excluded")
        let one = LeaveDays.eventDates(first: day(3), last: day(3))
        XCTAssertTrue(calendar.isDate(one.start, inSameDayAs: one.end), "a single day")
        XCTAssertTrue(LeaveDays.describe(title: "Leave", first: day(3), last: day(7), calendarName: "Work").contains("(5 days), all day, in Work"))
    }

    func testItem13AlwaysAWakeUpEvent() {
        let event = NewWakeUpEvent(title: "Ultrasound", day: day(4), start: day(1, 7), lengthMinutes: 60)
        XCTAssertEqual(event.startDate(), day(4, 7), "the start time on the chosen date")
        XCTAssertEqual(event.notes(keyword: "wake up"), "wake up", "the keyword is written into its notes")
        XCTAssertTrue(WakePlanner.notesRequestWakeUp(event.notes(keyword: "wake up"), keyword: "wake up"))
        XCTAssertTrue(BottomBar.menu(BottomBar.Inputs(), alarmStyleApp: true, morningKnown: false).contains(.addWakeUpEvent))
        XCTAssertTrue(BottomBar.menu(BottomBar.Inputs(), alarmStyleApp: true, morningKnown: false).contains(.addLeave))
    }
}

/// Drive times in Home Assistant (0.4.4): the phone's own reminders step aside only at home.
final class LocalLeaveReminderTests: XCTestCase {
    func testPhoneRemindersOnlyWhenHomeAssistantIsntChecking() {
        let settings = BridgeSettings()
        XCTAssertEqual(BedtimeCoordinator.localLeaveOffsets(settings, atHome: true, checksHere: true), [], "home and HA checks: HA notifies")
        XCTAssertEqual(BedtimeCoordinator.localLeaveOffsets(settings, atHome: false, checksHere: true), settings.leaveReminderOffsets, "away: the phone's own")
        XCTAssertEqual(BedtimeCoordinator.localLeaveOffsets(settings, atHome: nil, checksHere: true), settings.leaveReminderOffsets, "HA unreachable: the phone's own")
        XCTAssertEqual(BedtimeCoordinator.localLeaveOffsets(settings, atHome: true, checksHere: false), settings.leaveReminderOffsets, "phone mode: unchanged")
    }

    func testLeaveCheckNotificationIsOnTheNotificationsPage() {
        XCTAssertTrue(NotificationKind.leaveCheck.fromHomeAssistant)
        XCTAssertEqual(NotificationKind.leaveCheck.defaultLevel, .timeSensitive)
    }
}
