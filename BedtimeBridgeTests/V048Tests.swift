import XCTest
@testable import BedtimeBridge

/// v0.4.8, by spec item.
final class V048Tests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    private func f(_ d: Date) -> String { WakePlanner.format(d) }
    private func at(_ minutes: Double) -> Date { first.addingTimeInterval(minutes * 60) }

    // MARK: Item 2, your own alarms kept and confirmed

    func testItem2QuestionListsYourAlarms() {
        let kept = [at(-20), at(-10), at(0)]
        XCTAssertEqual(OwnAlarmsKept.question(kept: kept, found: nil), "Keep your alarms at \(f(at(-20))), \(f(at(-10))) and \(f(at(0)))?")
        XCTAssertEqual(OwnAlarmsKept.list([at(0)]), f(at(0)))
        XCTAssertEqual(OwnAlarmsKept.list([at(0), at(10)]), "\(f(at(0))) and \(f(at(10)))")
    }

    func testItem2QuestionSaysWhenAShiftNeedsYouUpEarlier() {
        let kept = [at(-20), at(-10), at(0)]
        var shift = WakePlan(source: .shift, wakeTime: at(-270), alarmTimes: [at(-290), at(-280), at(-270)], reason: "Days")
        shift.shift = ShiftCandidate(title: "Days", start: at(-180), wakeMinutesBefore: 90, cause: "Days")
        XCTAssertEqual(OwnAlarmsKept.question(kept: kept, found: shift), "Your Days shift needs you up at \(f(at(-270))). Keep your alarms at \(f(at(0)))?")
        // A day off (no alarm found), or a plan later than yours: just the alarms.
        let none = WakePlan(source: .none, alarmTimes: [], reason: "No alarm")
        XCTAssertEqual(OwnAlarmsKept.question(kept: kept, found: none), "Keep your alarms at \(f(at(-20))), \(f(at(-10))) and \(f(at(0)))?")
    }

    // MARK: Item 3, own alarms never out of date; the up-early bar wins

    func testItem3OwnAlarmsNeverOfferReplan() {
        let own = PrimaryAction.make(alarmsSet: true, defaultTitle: "Set", changedThisMorning: nil, missingAlarms: false,
                                     calendarChanged: true, planChanged: true, ownAlarms: true)
        XCTAssertNil(own.buttonTitle)
        let planned = PrimaryAction.make(alarmsSet: true, defaultTitle: "Set", changedThisMorning: nil, missingAlarms: false,
                                         calendarChanged: true, planChanged: false)
        XCTAssertEqual(planned.buttonTitle, "Calendar changed: re-plan alarms")
    }

    func testItem3LastNightAt830TheUpEarlyBarWinsOverReplan() {
        // Own alarm at 10:00, no shift, 8:30 AM: the up-early window, even with a re-plan prompt.
        var i = BottomBar.Inputs(now: at(-90))
        i.alarmsSet = 1
        i.firstAlarm = first
        i.upEarlyWindow = true
        i.plansChanged = "Plan changed · re-plan"
        XCTAssertEqual(BottomBar.make(i), BottomBar(top: .status("1 alarm set · first at \(f(first))", .good), buttons: [.upEarly, .sleepLater]))
    }

    // MARK: Item 5, Good night bar and Change plan

    func testItem5GoodNightBar() {
        var i = BottomBar.Inputs(now: at(-6 * 60))
        i.alarmsSet = 3
        i.firstAlarm = first
        i.goodNight = true
        var bar = BottomBar.make(i)
        XCTAssertEqual(bar.top, .status("✓ 3 alarms set · first \(f(first))", .good))
        XCTAssertEqual(bar.hold, .goodNight)
        XCTAssertEqual(bar.buttons, [.changePlan, .addTemporary])
        XCTAssertFalse(bar.undoOffered)
        i.undo = "3 alarms set · Undo"
        i.alarmStyleApp = false
        bar = BottomBar.make(i)
        XCTAssertTrue(bar.undoOffered)
        XCTAssertEqual(bar.buttons, [.changePlan], "Temporary alarm only with the app's own alarms")
        XCTAssertTrue(BarAction.goodNight.isProtected, "it turns the lights off")
    }

    func testItem5AfterBedtimeAndInTheUpEarlyWindowNoGoodNight() {
        var i = BottomBar.Inputs(now: at(-6 * 60))
        i.alarmsSet = 3
        i.firstAlarm = first
        i.goodNight = false
        i.notReadyWindow = true
        XCTAssertNil(BottomBar.make(i).hold)
        i.goodNight = true
        i.notReadyWindow = false
        i.upEarlyWindow = true
        XCTAssertNil(BottomBar.make(i).hold)
    }

    func testItem5GoodNightUntilBedtimeRuns() {
        let set = at(-8 * 60)
        XCTAssertTrue(GoodNight.offered(alarmsSet: true, alarmsSetAt: set, bedtimeRanAt: nil))
        XCTAssertTrue(GoodNight.offered(alarmsSet: true, alarmsSetAt: set, bedtimeRanAt: set.addingTimeInterval(-86400)), "last night's bedtime")
        XCTAssertFalse(GoodNight.offered(alarmsSet: true, alarmsSetAt: set, bedtimeRanAt: set.addingTimeInterval(600)))
        XCTAssertFalse(GoodNight.offered(alarmsSet: false, alarmsSetAt: set, bedtimeRanAt: nil))
        // The bedtime shortcut's own plan, a minute after bedtime started, doesn't bring it back.
        XCTAssertFalse(GoodNight.countsAsBeforeBedtime(bedtimeRanAt: set, now: set.addingTimeInterval(60)))
        XCTAssertTrue(GoodNight.countsAsBeforeBedtime(bedtimeRanAt: set, now: set.addingTimeInterval(3600)))
    }

    func testItem5ChangePlanListInOrder() {
        var i = BottomBar.Inputs(now: at(-6 * 60))
        i.alarmsSet = 3
        i.undo = "3 alarms set · Undo"
        i.sleepLaterWindow = true
        XCTAssertEqual(BottomBar.changePlanItems(i), [.undo, .editAlarms, .setAlarmsForTime, .replan, .sleepLater, .noAlarmsTomorrow])
        i.undo = nil
        i.sleepLaterWindow = false
        XCTAssertEqual(BottomBar.changePlanItems(i), [.editAlarms, .setAlarmsForTime, .replan, .noAlarmsTomorrow])
        XCTAssertEqual(ChangePlanSheet.title(.editAlarms, day: "Saturday"), "Change times")
        XCTAssertEqual(ChangePlanSheet.subtitle(.undo, undoPutsBack: []), "Put back no alarms")
    }

    func testItem5GoodNightDialogs() {
        XCTAssertEqual(GoodNight.dialog(.sent), "Good night. Bedtime is starting.")
        XCTAssertTrue(GoodNight.dialog(.noHomeAssistant).contains("I'm Ready For Bed"))
    }

    // MARK: Item 6, Undo after your own alarms

    func testItem6UndoStatusAfterOwnAlarms() {
        let record = UndoRecord(kind: .set, previousTimes: [], previousWake: nil, previousSource: .none, previousReason: "",
                                previousCause: AlarmCause.none, previousCleared: nil, leftTimes: [at(0)], savedAt: at(-6 * 60))
        XCTAssertTrue(record.available(currentTimes: [at(0)], bedtimeRanAt: nil, now: at(-60)), "nothing before: Undo puts back none")
        XCTAssertFalse(record.available(currentTimes: [at(0)], bedtimeRanAt: at(-5 * 60), now: at(-60)), "gone once bedtime runs")
        XCTAssertEqual(record.status(alarmsSet: 1), "1 alarm set · Undo")
    }

    // MARK: Item 7, No alarms this morning

    func testItem7ThisMorningAfterMidnight() {
        let today = Date.now.formatted(.dateTime.weekday(.wide))
        let tomorrow = Date.now.addingTimeInterval(86400).formatted(.dateTime.weekday(.wide))
        XCTAssertEqual(BarAction.noAlarmsTomorrow.title(day: today), "No alarms this morning")
        XCTAssertEqual(BarAction.noAlarmsTomorrow.title(day: tomorrow), "No alarms tomorrow")
        let record = UndoRecord(kind: .noAlarms, previousTimes: [at(0)], previousWake: nil, previousSource: .manual, previousReason: "",
                                previousCause: AlarmCause.manual, previousCleared: nil, leftTimes: [], savedAt: at(-60))
        XCTAssertEqual(record.status(alarmsSet: 0, thisMorning: true), "No alarms this morning · Undo")
    }

    func testItem7InTheUpEarlyWindowUntilTheFirstAlarm() {
        var i = BottomBar.Inputs(now: at(-90))
        i.alarmsSet = 1
        i.firstAlarm = first
        i.upEarlyWindow = true
        XCTAssertTrue(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true).contains(.noAlarmsTomorrow))
        i.now = at(5)
        XCTAssertFalse(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true).contains(.noAlarmsTomorrow), "not once one has rung")
    }

    // MARK: Item 8 and 13, Siri

    func testItem8EverySiriShortcutIsOnThePhrasesPage() {
        XCTAssertEqual(SiriPhrases.entries.count, BedtimeBridgeShortcuts.appShortcuts.count)
        XCTAssertEqual(BedtimeBridgeShortcuts.appShortcuts.count, 10, "Apple allows 10; Good night took the second wind-down's slot (item 13)")
        XCTAssertTrue(SiriPhrases.entries.allSatisfy { $0.phrases.allSatisfy { $0.contains("Bedtime Bridge") } })
        let windDown = SiriPhrases.entries.first { $0.phrases.contains("Cancel wind-down in Bedtime Bridge") }
        XCTAssertTrue(windDown?.phrases.contains("Start wind-down in Bedtime Bridge") == true, "one entry for both")
    }

    // MARK: Item 4, Stop on the banner

    func testItem4StopScreenLink() {
        let id = UUID()
        XCTAssertEqual(BannerStop.stopURL(id).absoluteString, "bedtimebridge://stop?id=\(id.uuidString)")
    }

    // MARK: Items 9, 11 and 12, reports and the checklist

    func testItem9ReportBody() {
        let body = TestingReports.body(note: "Bar said re-plan", automatic: false, kind: nil, app: ["own_alarms": true], screenshot: Data([1, 2]))
        XCTAssertEqual(body["note"] as? String, "Bar said re-plan")
        XCTAssertEqual((body["app"] as? [String: Any])?["own_alarms"] as? Bool, true)
        XCTAssertEqual(body["screenshot"] as? String, Data([1, 2]).base64EncodedString())
        XCTAssertNotNil(body["activity"] as? [String])
        XCTAssertEqual((body["checklist"] as? [String: String])?.count, TestingChecklist.Item.allCases.count)
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: body))
    }

    func testItem9ActivityLogKeeps12Hours() {
        let now = at(0)
        let old = ActivityLog.Entry(time: now.addingTimeInterval(-13 * 3600), text: "old")
        let recent = ActivityLog.Entry(time: now.addingTimeInterval(-3600), text: "recent")
        XCTAssertEqual(ActivityLog.trimmed([old, recent], now: now), [recent])
    }

    func testItem11AutomaticReportsOncePerNight() {
        let kind = "test_\(UUID().uuidString)"
        let evening = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now)!
        XCTAssertEqual(TestingReports.night(evening), TestingReports.night(evening.addingTimeInterval(3 * 3600)), "11 PM and 2 AM are one night")
        XCTAssertTrue(TestingReports.claimAutomatic(kind, now: evening))
        XCTAssertFalse(TestingReports.claimAutomatic(kind, now: evening.addingTimeInterval(3 * 3600)))
        XCTAssertTrue(TestingReports.claimAutomatic(kind, now: evening.addingTimeInterval(24 * 3600)))
    }

    func testItem9ReportHeadsTheMenuWhileTesting() {
        var i = BottomBar.Inputs(now: at(-6 * 60))
        i.reporting = true
        XCTAssertEqual(BottomBar.menu(i, alarmStyleApp: true, morningKnown: false).first, .report)
        i.reporting = false
        XCTAssertFalse(BottomBar.menu(i, alarmStyleApp: true, morningKnown: false).contains(.report))
    }

    func testItem12ChecklistTicks() {
        let saved = TestingChecklist.ticked
        defer { TestingChecklist.ticked = saved }
        TestingChecklist.ticked = [:]
        TestingChecklist.tick(.goodNightSent, now: at(0))
        TestingChecklist.tick(.goodNightSent, now: at(60))
        XCTAssertEqual(TestingChecklist.ticked[TestingChecklist.Item.goodNightSent.rawValue], at(0), "the first time it was seen")
        XCTAssertEqual(TestingChecklist.report()[TestingChecklist.Item.widgetSizes.rawValue], "not yet")
        TestingChecklist.set(.goodNightSent, done: false)
        XCTAssertNil(TestingChecklist.ticked[TestingChecklist.Item.goodNightSent.rawValue])
    }

    // MARK: Item 14, bedtime health check

    func testItem14Issues() {
        let iso = ISO8601DateFormatter()
        let alarms = [at(-10), at(0)]
        let good: [String: Any] = ["alarm_times": alarms.map(iso.string(from:)), "ladder": "armed", "phone_commands": true, "push_token": true]
        XCTAssertEqual(BedtimeHealth.issues(reply: good, localAlarms: alarms, expectsBackstops: true), [])
        var bad = good
        bad["ladder"] = "idle_no_shift"
        bad["alarm_times"] = [iso.string(from: at(30))]
        XCTAssertEqual(BedtimeHealth.issues(reply: bad, localAlarms: alarms, expectsBackstops: true), ["Alarms differ from Home Assistant", "Backstops not armed"])
        XCTAssertEqual(BedtimeHealth.issues(reply: bad, localAlarms: alarms, expectsBackstops: false), ["Alarms differ from Home Assistant"])
        XCTAssertEqual(BedtimeHealth.issues(reply: nil, localAlarms: alarms, expectsBackstops: true), ["Home Assistant not reachable"])
    }

    func testItem14TheBarSaysWhatsOffAfterBedtime() {
        var i = BottomBar.Inputs(now: at(-6 * 60))
        i.alarmsSet = 3
        i.firstAlarm = first
        i.notReadyWindow = true
        i.healthIssue = "Backstops not armed"
        XCTAssertEqual(BottomBar.make(i).top, .status("⚠ Backstops not armed", .snoozing))
    }
}
