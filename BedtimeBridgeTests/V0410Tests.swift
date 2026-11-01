import XCTest
@testable import BedtimeBridge

/// v0.4.10, by spec item.
final class V0410Tests: XCTestCase {
    private let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 1) -> Date {
        newYork.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: Item 1, Stop on the banner and the alarm next to it

    func testItem1TheBannerStopFoldsIntoTheNextAlarmInsteadOfAddingOne() {
        // 1 Nov 08:09:12: the snoozed 8:00 is stopped on the banner; a 9-min snooze would ring
        // at 08:18:12, and the 8:10 rings first.
        let eightTen = StopDescription.Upcoming(id: UUID(), set: at(8, 10), rings: at(8, 10))
        let eightTwenty = StopDescription.Upcoming(id: UUID(), set: at(8, 20), rings: at(8, 20))
        XCTAssertEqual(StopDescription.foldsInto(snoozeAt: at(8, 18, 12), upcoming: [eightTwenty, eightTen]), eightTen,
                       "no 4th alarm at 08:18")
    }

    func testItem1WithNothingSoonerTheSnoozeAlarmIsStillSet() {
        let eightTwenty = StopDescription.Upcoming(id: UUID(), set: at(8, 20), rings: at(8, 20))
        XCTAssertNil(StopDescription.foldsInto(snoozeAt: at(8, 18, 12), upcoming: [eightTwenty]))
        XCTAssertNil(StopDescription.foldsInto(snoozeAt: at(8, 18), upcoming: []), "the last alarm")
    }

    func testItem1ASnoozingAlarmCountsAtItsSnoozeEnd() {
        // The 8:10 snoozed to 8:19 rings after an 8:18 snooze: no fold.
        let snoozed = StopDescription.Upcoming(id: UUID(), set: at(8, 10), rings: at(8, 19, 17))
        XCTAssertNil(StopDescription.foldsInto(snoozeAt: at(8, 18, 12), upcoming: [snoozed]))
    }

    func testItem1TheStopScreenNamesTheAlarmBySetTimeAndListsWhatsLeft() {
        let series = [at(8, 0), at(8, 10), at(8, 20)]
        let left = [StopDescription.Upcoming(id: UUID(), set: at(8, 20), rings: at(8, 20)),
                    StopDescription.Upcoming(id: UUID(), set: at(8, 10), rings: at(8, 19, 17))]
        let stop = StopDescription.make(kind: .series, alarmTime: at(8, 0), series: series, remaining: [at(8, 10), at(8, 20)],
                                        snoozes: 2, left: left)
        XCTAssertEqual(stop.title, "The \(WakePlanner.format(at(8, 0))) alarm · alarm 1 of 3 · 2nd snooze")
        XCTAssertEqual(stop.left, ["\(WakePlanner.format(at(8, 10))) → rings \(WakePlanner.format(at(8, 19, 17)))",
                                   WakePlanner.format(at(8, 20))])
        XCTAssertTrue(stop.canEndAll)
    }

    func testItem1FoldedSaysWhichAlarmIsNext() {
        let next = StopDescription.Upcoming(id: UUID(), set: at(8, 10), rings: at(8, 10))
        let stop = StopDescription.make(kind: .series, alarmTime: at(8, 0), series: [at(8, 0), at(8, 10), at(8, 20)], remaining: [at(8, 10), at(8, 20)],
                                        snoozes: 1, left: [next], foldedInto: next, now: at(8, 9, 12))
        XCTAssertEqual(stop.detail, "Next: the \(WakePlanner.format(at(8, 10))) alarm, in 1 min")
    }

    func testItem1Ordinals() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22].map(StopDescription.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"])
    }

    func testItem1NoSnoozeKeepsTheShortTitle() {
        let series = [at(8, 0), at(8, 10), at(8, 20)]
        let stop = StopDescription.make(kind: .series, alarmTime: series[1], series: series, remaining: [series[2]])
        XCTAssertEqual(stop.title, "\(WakePlanner.format(series[1])) · alarm 2 of 3")
    }

    // MARK: Items 2 and 3, only the Stop screen ends a ring

    func testItem3TheStopBehaviorSettingIsGone() throws {
        // An old saved value still decodes, and nothing reads it.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(BridgeSettings())) as? [String: Any])
        json["stopBehavior"] = "cancelRest"
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNoThrow(try JSONDecoder().decode(BridgeSettings.self, from: data))
        XCTAssertFalse(SettingsPages.alarms.contains("stopBehavior"))
    }

    // MARK: Item 4, no re-plan prompt in the morning

    func testItem4NoReplanPromptFromTheUpEarlyWindow() {
        let morning = PrimaryAction.make(alarmsSet: true, defaultTitle: "Plan", changedThisMorning: nil, missingAlarms: false,
                                         calendarChanged: true, planChanged: true, thisMorning: true)
        XCTAssertNil(morning.buttonTitle)
        let evening = PrimaryAction.make(alarmsSet: true, defaultTitle: "Plan", changedThisMorning: nil, missingAlarms: false,
                                         calendarChanged: false, planChanged: true)
        XCTAssertEqual(evening.buttonTitle, "Plan changed: update alarms")
    }

    // MARK: Item 5, Back to bed and another morning's backstops

    func testItem5BackToBedOnSundayLeavesOutMondaysBackstops() {
        var context = MorningContext(ladderArmed: true, backstops: ["early": at(5, 40, day: 2), "late": at(6, 10, day: 2)])
        context.shiftStart = at(6, 30, day: 2)
        XCTAssertEqual(context.backstops(forMorning: at(8, 30), calendar: newYork), [:], "Monday's ladder isn't Sunday's")
        XCTAssertEqual(context.backstops(forMorning: at(4, 20, day: 2), calendar: newYork).count, 2)
        context.ladderArmed = false
        XCTAssertEqual(context.backstops(forMorning: at(4, 20, day: 2), calendar: newYork), [:])
    }

    // MARK: Item 6, a forecast for your own alarms

    func testItem6OwnAlarmsTakeTheForecastAtTheFirstAlarm() {
        // No leave-by: the moment is the first alarm, 8:00 on 1 Nov.
        let (moment, when) = MorningForecast.moment(leaveBy: nil, wakeUp: at(8, 0), goodMorningFrom: "08:00", now: at(22, 27, day: 0))
        XCTAssertEqual(moment, .wakeUp)
        XCTAssertEqual(when, at(8, 0))
        let hours = [ForecastHour(start: at(7, 0), condition: "rainy", temperature: 40), ForecastHour(start: at(8, 0), condition: "rainy", temperature: 41)]
        XCTAssertEqual(MorningForecast.pick(hours: hours, at: when, moment: moment, unit: "°F")?.temperature, 41)
    }

    // MARK: Item 7, Preview with your own alarms set

    func testItem7PreviewSaysWhatsAlreadySet() {
        let line = AlarmReasonText.alreadySet([at(8, 20), at(8, 0), at(8, 10)])
        XCTAssertEqual(line?.lead, "You already have alarms set at ")
        XCTAssertEqual(line?.times, [at(8, 0), at(8, 10), at(8, 20)].map(WakePlanner.format).joined(separator: ", "))
        XCTAssertEqual(line?.tail, ". You can still change or cancel them.")
        XCTAssertEqual(AlarmReasonText.alreadySet([at(8, 0)])?.tail, ". You can still change or cancel it.")
        XCTAssertNil(AlarmReasonText.alreadySet([]))
    }

    // MARK: Item 13, editing and deleting a report

    private func report(_ note: String, automatic: Bool = false, time: String = "2026-11-01T07:07:39-05:00") -> TestingReports.Saved {
        let body = try! JSONSerialization.data(withJSONObject: ["note": note, "time": time])
        return TestingReports.Saved(time: .now, note: note, automatic: automatic, kind: nil, body: body, sent: true)
    }

    func testItem13TheListIsYourLast20NewestFirst() {
        let all = (0..<25).map { report("r\($0)") } + [report("auto", automatic: true)]
        let listed = TestingReports.listed(all)
        XCTAssertEqual(listed.count, 20)
        XCTAssertEqual(listed.first?.note, "r24")
        XCTAssertFalse(listed.contains { $0.automatic }, "automatic reports aren't yours to edit or delete")
    }

    func testItem13TheRequestsNameTheReport() {
        let r = report("Typo")
        let edit = TestingReports.changeRequest(for: r, note: "Fixed")
        XCTAssertEqual(edit["edits"] as? String, r.id.uuidString)
        XCTAssertEqual(edit["note"] as? String, "Fixed")
        XCTAssertEqual(edit["time"] as? String, "2026-11-01T07:07:39-05:00", "reports from before 0.4.10 match by time")
        let delete = TestingReports.changeRequest(for: r, note: nil)
        XCTAssertEqual(delete["deletes"] as? String, r.id.uuidString)
        XCTAssertNil(delete["note"])
    }

    func testItem13AnEditChangesTheSavedBodyToo() throws {
        let changed = TestingReports.withNote(report("Typo"), "Fixed")
        XCTAssertEqual(changed.note, "Fixed")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: changed.body) as? [String: Any])
        XCTAssertEqual(body["note"] as? String, "Fixed")
    }

    func testItem13ANewReportCarriesItsID() {
        let id = UUID()
        let body = TestingReports.body(note: "x", automatic: false, kind: nil, app: [:], screenshot: nil, id: id)
        XCTAssertEqual(body["report_id"] as? String, id.uuidString)
    }

    // MARK: Items 8–10, one place for each thing; the bar's rows

    private func barInputs(now: Date) -> BottomBar.Inputs {
        var i = BottomBar.Inputs(now: now)
        i.alarmsSet = 3
        i.firstAlarm = at(8, 0)
        return i
    }

    func testItem9EachWindowHasTheStatusOneSliderAndButtons() {
        var early = barInputs(now: at(6, 52))
        early.upEarlyWindow = true
        XCTAssertEqual(BottomBar.make(early).hold, .upEarly)
        var snoozing = barInputs(now: at(8, 12))
        snoozing.snoozing = true
        let snooze = BottomBar.make(snoozing)
        XCTAssertEqual(snooze.hold, .endAlarms, "the hold ends them all")
        XCTAssertEqual(snooze.slide, .endThisAlarm, "the slide ends this one")
        var back = BottomBar.Inputs(now: at(8, 24))
        back.backToBedWindow = true
        XCTAssertEqual(BottomBar.make(back).hold, .backToBed)
        var night = barInputs(now: at(0, 10))
        night.notReadyWindow = true
        XCTAssertEqual(BottomBar.make(night).hold, .notReadyForBed)
        for bar in [BottomBar.make(early), snooze, BottomBar.make(back), BottomBar.make(night)] {
            XCTAssertTrue((2...3).contains(bar.buttons.count), "\(bar.buttons)")
            if case .status = bar.top {} else { XCTFail("the status sits on top") }
        }
    }

    func testItem10MenuNeverListsBothNoAlarmsAndSkipOrEditAndChange() {
        var before = barInputs(now: at(21, 0, day: 0))
        before.goodNight = true
        var after = barInputs(now: at(0, 10))
        after.notReadyWindow = true
        var early = barInputs(now: at(6, 52))
        early.upEarlyWindow = true
        for i in [before, after, early] {
            let menu = BottomBar.menu(i, alarmStyleApp: true, morningKnown: true)
            XCTAssertFalse(menu.contains(.skip))
            XCTAssertFalse(menu.contains(.editAlarms) && menu.contains(.changeMorning), "\(menu)")
        }
        XCTAssertTrue(BottomBar.menu(before, alarmStyleApp: true, morningKnown: true).contains(.editAlarms))
        XCTAssertTrue(BottomBar.menu(after, alarmStyleApp: true, morningKnown: true).contains(.changeMorning))
    }

    func testItem10OneNoAlarmsNamedByItsDay() {
        XCTAssertEqual(BarAction.noAlarmsTomorrow.title(day: "Sunday"), "No alarms Sunday")
    }

    // MARK: Item 11, Your morning for every alarm

    func testItem11OwnAlarmsGiveOneStepPerAlarmWithTemporaryAndBackstops() {
        let temporary = TemporaryAlarm(id: UUID(), time: at(6, 30), disarmHouse: false)
        let tomorrowsTemporary = TemporaryAlarm(id: UUID(), time: at(6, 30, day: 2), disarmHouse: true)
        let steps = AlarmTimeline.steps(alarms: [at(8, 20), at(8, 0), at(8, 10)], wake: at(8, 0),
                                        temporary: [temporary, tomorrowsTemporary],
                                        rungs: [BackstopInfo.Rung(name: "Early", time: at(8, 25))])
        XCTAssertEqual(steps.map(\.kind), [.temporary, .wake, .alarm, .alarm, .backstop])
        XCTAssertEqual(steps.map(\.title), ["Temporary alarm", "Wake up", "Alarm 2 of 3", "Alarm 3 of 3", "Early"])
        XCTAssertEqual(steps.first?.detail, "House stays armed")
    }

    func testItem11NoBackstopsSaysWhyAtTheBottom() {
        // Shown under the steps: "No backstops Sunday · armed for Monday 6:30".
        let line = BackstopInfo.otherMorning(shown: at(8, 0), ladder: at(6, 30, day: 2), armed: true, calendar: newYork)
        XCTAssertTrue(line.hasPrefix("No backstops Sunday · armed for Monday"), line)
    }

    // MARK: Item 12, the weather pill

    func testItem12ThePillShowsTheForecastAtTheFirstAlarm() {
        let rain = MorningForecast(moment: .wakeUp, at: at(8, 0), condition: "rainy", temperature: 41, unit: "°F")
        XCTAssertEqual(rain.pillText(locale: Locale(identifier: "en_US")), "41° · Rain")
        XCTAssertEqual(MorningForecast.symbol("rainy"), "cloud.rain.fill")
        XCTAssertEqual(AlarmReasonText.wakeWeather(rain, firstAlarm: at(8, 0)), rain)
        XCTAssertNil(AlarmReasonText.wakeWeather(rain, firstAlarm: at(8, 30)), "another morning's forecast")
        XCTAssertNil(AlarmReasonText.wakeWeather(nil, firstAlarm: at(8, 0)), "no forecast, nothing shows")
    }

    // MARK: Item 14, Preview after a Change this morning

    func testItem14TheChangedThisMorningMarkEndsAtThatMorningsNoon() {
        // 1 Nov 08:25 Back to bed: still this morning at 11:59, gone at 12:00 and in the evening.
        XCTAssertTrue(MorningChange.markApplies(setAt: at(8, 25), now: at(11, 59), calendar: newYork))
        XCTAssertFalse(MorningChange.markApplies(setAt: at(8, 25), now: at(12, 0), calendar: newYork))
        XCTAssertFalse(MorningChange.markApplies(setAt: at(8, 25), now: at(16, 0), calendar: newYork), "Preview works in the afternoon")
        // A change at 23:00 is for the next morning.
        XCTAssertTrue(MorningChange.markApplies(setAt: at(23, 0, day: 0), now: at(8, 0), calendar: newYork))
        XCTAssertFalse(MorningChange.markApplies(setAt: nil, now: at(8, 0), calendar: newYork), "a mark from before 0.4.10")
    }

    // MARK: Item 15, Nap orange

    func testItem15NapAndNappingsButtonsAreNapStyled() {
        XCTAssertTrue(BarAction.nap.napStyled)
        XCTAssertTrue(BarAction.endNap.napStyled)
        XCTAssertTrue(BarAction.changeNap.napStyled)
        XCTAssertFalse(BarAction.previewPlan.napStyled)
        var i = BottomBar.Inputs(now: at(16, 0))
        i.evening = true
        i.napEnabled = true
        i.tomorrowLabel = "Days shift 6:30"
        XCTAssertTrue(BottomBar.make(i).buttons.contains(.nap), "the bar from 1 Nov's afternoon offers Nap")
    }

    // MARK: Item 16, nothing set yet

    func testItem16NothingSetSaysSoWithBothSetButtonsOnTop() {
        var i = BottomBar.Inputs(now: at(16, 0))
        i.evening = true
        i.napEnabled = true
        i.tomorrowLabel = "Days shift \(WakePlanner.format(at(6, 30, day: 2)))"
        i.planReady = (3, at(4, 30, day: 2))
        let bar = BottomBar.make(i)
        XCTAssertEqual(bar.top, .status("Days shift \(WakePlanner.format(at(6, 30, day: 2))) · no alarms set", .muted))
        XCTAssertEqual(bar.actionRow, [.setAlarms, .setAlarmsForTime])
        XCTAssertEqual(bar.setTitle, "Set 3 · up \(WakePlanner.format(at(4, 30, day: 2)))")
        XCTAssertEqual(bar.buttons, [.previewPlan, .nap])
        i.tomorrowLabel = nil
        i.planReady = nil
        XCTAssertEqual(BottomBar.make(i).top, .status("No alarms set", .muted))
        XCTAssertEqual(BottomBar.make(i).setTitle, "Set alarms")
    }

    func testItem16TheLabelNamesTheShiftOrAppointment() {
        var shift = WakePlan(source: .shift, wakeTime: at(4, 30, day: 2), alarmTimes: [at(4, 20, day: 2)], reason: "")
        shift.shift = ShiftCandidate(title: "Days", start: at(6, 30, day: 2), wakeMinutesBefore: 120, cause: "Days")
        XCTAssertEqual(AlarmReasonText.tomorrowLabel(shift), "Days shift \(WakePlanner.format(at(6, 30, day: 2)))")
        XCTAssertNil(AlarmReasonText.tomorrowLabel(nil))
        XCTAssertNil(AlarmReasonText.tomorrowLabel(WakePlan(source: .manual, wakeTime: nil, alarmTimes: [], reason: "")))
    }

    // MARK: Item 17, Pick a time fits

    func testItem17TheSetTitlesAreShort() {
        var i = BottomBar.Inputs(now: at(16, 0))
        i.evening = true
        XCTAssertEqual(BottomBar.make(i).setTitle, "Set alarms")
        i.planReady = (3, at(4, 30, day: 2))
        XCTAssertEqual(BottomBar.make(i).setTitle, "Set 3 · up \(WakePlanner.format(at(4, 30, day: 2)))")
    }

    // MARK: Item 18, No alarms takes Nap's place in the evening

    func testItem18FromTheEveningCheckNoAlarmsReplacesNap() {
        var i = BottomBar.Inputs(now: at(17, 30))
        i.evening = true
        i.napEnabled = true
        i.tomorrowLabel = "Days shift 6:30"
        XCTAssertEqual(BottomBar.make(i).buttons, [.previewPlan, .nap])
        i.eveningCheckPassed = true
        XCTAssertEqual(BottomBar.make(i).buttons, [.previewPlan, .noAlarmsTomorrow])
        XCTAssertTrue(BottomBar.menu(i, alarmStyleApp: true, morningKnown: true).contains(.nap), "Nap is in ⋯")
        i.tomorrowLabel = nil
        XCTAssertEqual(BottomBar.make(i).buttons, [.previewPlan, .nap], "nothing tomorrow to turn off")
    }

    func testItem18TheCheckIsTheWindDownSetting() {
        // Wind-down at 8:30 PM, check 2 h before: 6:30 PM. Without a wind-down: 6:00 PM.
        XCTAssertEqual(BottomBar.eveningCheck(windDown: at(20, 30), beforeMinutes: 120, fallback: "18:00", now: at(12, 0), calendar: newYork), at(18, 30))
        XCTAssertEqual(BottomBar.eveningCheck(windDown: nil, beforeMinutes: 120, fallback: "18:00", now: at(12, 0), calendar: newYork), at(18, 0))
    }
}
