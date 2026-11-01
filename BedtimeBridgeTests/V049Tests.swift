import XCTest
@testable import BedtimeBridge

/// v0.4.9, by spec item.
final class V049Tests: XCTestCase {
    private let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Item 4, Stop on the banner for a nap

    func testItem4ANapAlarmStoppedFromTheBannerIsStillANap() {
        // The banner path: AlarmKit has already removed it, but it's in the nap as it was set.
        let nap = UUID()
        XCTAssertEqual(StopDescription.Kind.of(nap, cause: nil, test: nil, temporary: [], nap: [nap]), .nap)
        // And the alarm's own cause, if the saved list doesn't have it.
        XCTAssertEqual(StopDescription.Kind.of(UUID(), cause: AlarmCause.nap, test: nil, temporary: [], nap: []), .nap)
    }

    func testItem4TemporaryTestAndRegularAlarms() {
        let temporary = UUID(), test = UUID()
        XCTAssertEqual(StopDescription.Kind.of(temporary, cause: nil, test: test, temporary: [temporary], nap: []), .temporary)
        XCTAssertEqual(StopDescription.Kind.of(UUID(), cause: AlarmCause.temporary, test: nil, temporary: [], nap: []), .temporary)
        XCTAssertEqual(StopDescription.Kind.of(test, cause: nil, test: test, temporary: [], nap: []), .test)
        XCTAssertEqual(StopDescription.Kind.of(UUID(), cause: "Days", test: test, temporary: [temporary], nap: []), .series)
        XCTAssertEqual(StopDescription.Kind.of(UUID(), cause: nil, test: nil, temporary: [], nap: []), .series)
    }

    func testItem4AStopNeverEndsTomorrowsAlarms() {
        // 31 Oct: the nap alarm at 4:31 PM; tomorrow's 5:00 alarms are a later wake-up.
        let ringing = at(2026, 10, 31, 16, 31)
        XCTAssertTrue(StopDescription.laterWakeUp(at(2026, 11, 1, 5, 0), ringing: ringing))
        // The rest of this morning's series is still "the rest".
        let morning = at(2026, 11, 2, 4, 20)
        XCTAssertFalse(StopDescription.laterWakeUp(at(2026, 11, 2, 4, 40), ringing: morning))
        XCTAssertFalse(StopDescription.laterWakeUp(at(2026, 11, 2, 5, 20), ringing: morning))
    }

    // MARK: Item 5, the header with alarms off

    private var sunday: [Date] { [at(2026, 11, 1, 5, 0), at(2026, 11, 1, 5, 10), at(2026, 11, 1, 5, 20)] }

    func testItem5AllThreeCancelledTheEveningBeforeIsAlarmsOff() {
        let now = at(2026, 10, 31, 16, 40)
        let stoppedAt = at(2026, 10, 31, 16, 31)
        let off = AlarmBubble.make(morning: sunday, held: [], wake: nil, snoozedUntil: nil, stopped: true, now: now)
        let header = AlarmBubble.header(off, shortfall: nil, stoppedAt: stoppedAt, now: now)
        XCTAssertEqual(header.text, "Alarms off")
        XCTAssertEqual(header.kind, .notSet, "no green check")
    }

    func testItem5SomeLeft() {
        let now = at(2026, 10, 31, 20, 0)
        let bubbles = AlarmBubble.make(morning: sunday, held: [sunday[2]], wake: nil, snoozedUntil: nil, stopped: true, now: now)
        XCTAssertEqual(AlarmBubble.header(bubbles, shortfall: nil, stoppedAt: now, now: now).text, "1 of 3 alarms left")
    }

    func testItem5UpEarlyIsEndedEarly() {
        let now = at(2026, 11, 1, 4, 30)
        let off = AlarmBubble.make(morning: sunday, held: [], wake: nil, snoozedUntil: nil, stopped: true, now: now)
        let header = AlarmBubble.header(off, shortfall: nil, stoppedAt: now, now: now)
        XCTAssertEqual(header.text, "Ended early")
        XCTAssertEqual(header.kind, .notSet, "none rang, so no check")
    }

    func testItem5RangAndStoppedStillCountsAsSet() {
        // Every alarm rang and was stopped: the header holds through the morning.
        let now = at(2026, 11, 1, 6, 0)
        let off = AlarmBubble.make(morning: sunday, held: [], wake: nil, snoozedUntil: nil, stopped: true, now: now)
        let header = AlarmBubble.header(off, shortfall: nil, stoppedAt: at(2026, 11, 1, 5, 21), now: now)
        XCTAssertEqual(header.text, "3 alarms set")
        XCTAssertEqual(header.kind, .set)
    }

    // MARK: Item 6, another morning's backstops

    private func mondayLadder() -> MorningContext {
        var context = MorningContext(ladderArmed: true, ladderStatus: "armed", backstops: ["early": at(2026, 11, 2, 5, 40)],
                                     shiftStart: at(2026, 11, 2, 6, 30), appointment: nil, curtainsOpenAt: nil)
        context.firstDayBack = true
        context.houseSource = "bridge"
        return context
    }

    func testItem6MondaysBackstopsArentShownForSunday() {
        let info = BackstopInfo.make(context: mondayLadder(), leaveBy: nil, offsets: (50, 35, 20, 15), firstDayBack: false,
                                     morning: at(2026, 11, 1, 5, 0), calendar: newYork)
        XCTAssertEqual(info?.rungs, [])
        XCTAssertNil(info?.firstDayBackMinutes, "no First day back")
        XCTAssertTrue(info?.status.hasPrefix("No backstops Sunday · armed for Monday") == true, info?.status ?? "")
    }

    func testItem6MondaysBackstopsOnMonday() {
        let info = BackstopInfo.make(context: mondayLadder(), leaveBy: nil, offsets: (50, 35, 20, 15), firstDayBack: false,
                                     morning: at(2026, 11, 2, 4, 20), calendar: newYork)
        XCTAssertEqual(info?.rungs.count, 1)
        XCTAssertEqual(info?.status, "Backstops armed")
        XCTAssertEqual(info?.firstDayBackMinutes, 15)
    }

    // MARK: Item 3, the nap on the widget

    private func napping() -> NextAlarmSnapshot {
        var snapshot = NextAlarmSnapshot()
        snapshot.alarmTimes = sunday
        snapshot.label = "Day off"
        snapshot.napAlarms = [at(2026, 10, 31, 16, 30), at(2026, 10, 31, 16, 40)]
        return snapshot
    }

    func testItem3TheNapLeadsTheWidget() {
        let snapshot = napping()
        let now = at(2026, 10, 31, 16, 5)
        XCTAssertEqual(snapshot.nextAlarm(after: now), at(2026, 10, 31, 16, 30))
        XCTAssertEqual(snapshot.label(after: now), "Nap")
        XCTAssertEqual(snapshot.morningAfterNap(at: now), sunday[0])
        XCTAssertEqual(snapshot.steps(after: now).prefix(2).map(\.kind), [.nap, .nap], "the nap's alarms first")
    }

    func testItem3SnoozingANap() {
        var snapshot = napping()
        snapshot.snoozedUntil = at(2026, 10, 31, 16, 39)
        let now = at(2026, 10, 31, 16, 32)
        XCTAssertEqual(snapshot.napNext(at: now), at(2026, 10, 31, 16, 39))
        XCTAssertEqual(snapshot.label(after: now), "Nap")
    }

    func testItem3BackToTheMorningOnceTheNapEnds() {
        var snapshot = napping()
        snapshot.napAlarms = nil
        let now = at(2026, 10, 31, 16, 45)
        XCTAssertEqual(snapshot.nextAlarm(after: now), sunday[0])
        XCTAssertEqual(snapshot.label(after: now), "Day off")
        // And if "nap ended" never came, an hour after its last alarm.
        XCTAssertFalse(napping().isNapping(at: at(2026, 10, 31, 17, 41)))
        XCTAssertEqual(NextAlarmSnapshot.napUpAt(napping().napAlarms ?? [], now: at(2026, 10, 31, 16, 35)), at(2026, 10, 31, 16, 40))
    }

    // MARK: Item 7, daylight saving time

    func testItem7TomorrowIsTheNextDayWhenTheClocksGoForward() {
        // 11:30 PM Saturday 13 Mar 2027: 24 hours on is Monday, the next day is Sunday.
        let saturday = at(2027, 3, 13, 23, 30)
        let next = newYork.nextDay(after: saturday)
        XCTAssertEqual(newYork.component(.day, from: next), 14)
        XCTAssertEqual(newYork.component(.hour, from: next), 23)
        XCTAssertEqual(newYork.component(.day, from: saturday.addingTimeInterval(86400)), 15, "the old way")
    }

    func testItem7TheDaysThemselves() {
        let forward = newYork.dayRange(of: at(2027, 3, 14, 12))
        XCTAssertEqual(forward.end.timeIntervalSince(forward.start), 23 * 3600)
        let back = newYork.dayRange(of: at(2026, 11, 1, 12))
        XCTAssertEqual(back.end.timeIntervalSince(back.start), 25 * 3600)
        XCTAssertEqual(newYork.component(.day, from: back.end), 2)
    }

    func testItem7A5AMAlarmPlannedTheEveningBefore() {
        // Set for a clock time on the day, so 5:00 is 5:00 after either change.
        for (evening, day) in [(at(2026, 10, 31, 21), at(2026, 11, 1, 12)), (at(2027, 3, 13, 21), at(2027, 3, 14, 12))] {
            let alarm = newYork.date(bySettingHour: 5, minute: 0, second: 0, of: day)!
            XCTAssertEqual(newYork.component(.hour, from: alarm), 5)
            XCTAssertGreaterThan(alarm, evening)
        }
        XCTAssertEqual(at(2026, 11, 1, 5).timeIntervalSince(at(2026, 10, 31, 21)), 9 * 3600, "an hour longer night")
        XCTAssertEqual(at(2027, 3, 14, 5).timeIntervalSince(at(2027, 3, 13, 21)), 7 * 3600, "an hour shorter")
    }

    // MARK: Item 8, a morning cancelled before it rang

    func testItem8CancelledTheEveningBeforeClearsTheMorning() {
        let now = at(2026, 10, 31, 21, 11)
        let off = AlarmBubble.make(morning: sunday, held: [], wake: nil, snoozedUntil: nil, stopped: true, now: now)
        XCTAssertFalse(AlarmBubble.stillShowing(off, stoppedAt: at(2026, 10, 31, 16, 31), now: now))
    }

    func testItem8RangAndStoppedStaysUntilTheMorningIsOver() {
        let now = at(2026, 11, 1, 5, 30)
        let off = AlarmBubble.make(morning: sunday, held: [], wake: nil, snoozedUntil: nil, stopped: true, now: now)
        XCTAssertTrue(AlarmBubble.stillShowing(off, stoppedAt: at(2026, 11, 1, 5, 21), now: now))
        // Stopped at the first with the rest cancelled: that one rang, so it stays too.
        XCTAssertTrue(AlarmBubble.stillShowing(off, stoppedAt: at(2026, 11, 1, 5, 2), now: now))
    }

    func testItem8OneOfThreeCancelledStillShowsTheOthers() {
        let now = at(2026, 10, 31, 21, 0)
        let bubbles = AlarmBubble.make(morning: sunday, held: [sunday[1], sunday[2]], wake: nil, snoozedUntil: nil, stopped: false, now: now)
        XCTAssertTrue(AlarmBubble.stillShowing(bubbles, stoppedAt: nil, now: now))
    }

    // MARK: Item 9, Preview with nothing tomorrow

    func testItem9APreviewThatFoundNothingOffersNoAlarmsTomorrow() {
        var i = BottomBar.Inputs()
        i.now = at(2026, 10, 31, 21, 11)
        i.evening = true
        i.alarmStyleApp = true
        i.nothingFound = true
        i.previewedNothing = true
        let bar = BottomBar.make(i)
        XCTAssertEqual(bar.top, .status("Nothing set for tonight", .muted))
        XCTAssertEqual(bar.buttons, [.noAlarmsTomorrow, .previewPlan])
        XCTAssertEqual(bar.actionRow.first, .setAlarmsForTime)
    }

    func testItem9TheCardNamesTheDay() {
        XCTAssertEqual(AlarmReasonText.nothingOn(now: at(2026, 10, 31, 21, 11), calendar: newYork), "Nothing on Sunday")
        XCTAssertEqual(AlarmReasonText.nothingOn(now: at(2026, 11, 1, 2, 0), calendar: newYork), "Nothing on Sunday", "before 4 AM it's this morning")
    }
}
