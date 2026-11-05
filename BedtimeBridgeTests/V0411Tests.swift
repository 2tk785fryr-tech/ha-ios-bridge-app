import XCTest
@testable import BedtimeBridge

/// v0.4.11, by spec item.
final class V0411Tests: XCTestCase {
    private let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 3) -> Date {
        newYork.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }

    private func estimates(apple: Int? = 30, tomTom: Int? = nil, google: Int? = nil, googleWorst: Int? = nil) -> [DriveEstimate] {
        [(DriveEstimate.Service.apple, apple), (.tomTom, tomTom), (.googleTypical, google), (.googleWorst, googleWorst)]
            .compactMap { service, minutes in minutes.map { DriveEstimate(service: service, seconds: Double($0) * 60) } }
    }

    private func drive(_ estimates: [DriveEstimate], travel: Int = 30, weather: WeatherAdjustment? = nil, fallback: String? = nil) -> MorningSteps.Drive {
        MorningSteps.Drive(travelSeconds: Double(travel) * 60, estimates: estimates, fallbackReason: fallback, weather: weather)
    }

    // MARK: Item 1, Leave by worst case

    func testItem1TheWorstCaseIsTheStartMinusTheWorstDriveAndWeatherWithNoBuffer() {
        let snow = WeatherAdjustment(minutes: 15, reason: "snowy at 5:00 AM")
        let worst = MorningSteps.worstCase(start: at(6, 30), drive: drive(estimates(google: 32, googleWorst: 41), weather: snow),
                                           source: .apple, googleWorstPlanned: false, arrival: .whenItStarts, bufferMinutes: 10)
        XCTAssertEqual(worst?.time, at(5, 34), "6:30 − 41 − 15, no arrival buffer")
        XCTAssertEqual(worst?.note, "Leaving now gets you there right when it starts, not early.")
        XCTAssertEqual(worst?.drive, "Google worst case 41 min + 15 min for snowy at 5:00 AM")
    }

    func testItem1NoWorstCaseWithOneServiceAndNoGoogleKey() {
        XCTAssertNil(MorningSteps.worstCase(start: at(6, 30), drive: drive(estimates()), source: .apple, googleWorstPlanned: false,
                                            arrival: .whenItStarts, bufferMinutes: 10))
    }

    func testItem1WithoutGoogleTheLongestServiceIsTheWorstCase() {
        let worst = MorningSteps.worstCase(start: at(6, 30), drive: drive(estimates(apple: 30, tomTom: 38)), source: .longest,
                                           googleWorstPlanned: false, arrival: .whenItStarts, bufferMinutes: 10)
        XCTAssertEqual(worst?.time, at(5, 52))
        XCTAssertEqual(worst?.drive, "TomTom 38 min")
    }

    func testItem1EarlyLikeLeaveByTakesOffTheBufferAndSaysSo() {
        let worst = MorningSteps.worstCase(start: at(6, 30), drive: drive(estimates(google: 32, googleWorst: 41)), source: .apple,
                                           googleWorstPlanned: false, arrival: .early, bufferMinutes: 15)
        XCTAssertEqual(worst?.time, at(5, 34), "6:30 − 41 − the appointment's 15 min")
        XCTAssertEqual(worst?.note, "Leaving now gets you there 15 min early.")
    }

    func testItem1NotShownWhenLeaveByIsAlreadyGooglesWorstCase() {
        XCTAssertNil(MorningSteps.worstCase(start: at(6, 30), drive: drive(estimates(google: 32, googleWorst: 41)), source: .google,
                                            googleWorstPlanned: true, arrival: .whenItStarts, bufferMinutes: 10))
        XCTAssertNotNil(MorningSteps.worstCase(start: at(6, 30), drive: drive(estimates(google: 32, googleWorst: 41)), source: .google,
                                               googleWorstPlanned: false, arrival: .whenItStarts, bufferMinutes: 10),
                        "Google planning a typical day still shows it")
    }

    func testItem1NotShownWhenAnotherServiceIsLongerThanGooglesWorstCase() {
        XCTAssertNil(MorningSteps.worstCase(start: at(6, 30), drive: drive(estimates(apple: 30, tomTom: 45, google: 32, googleWorst: 41)),
                                            source: .longest, googleWorstPlanned: false, arrival: .whenItStarts, bufferMinutes: 10))
    }

    func testItem1NotShownWithNoDriveOrAnAssumedOne() {
        XCTAssertNil(MorningSteps.worstCase(start: at(6, 30), drive: nil, source: .apple, googleWorstPlanned: false,
                                            arrival: .whenItStarts, bufferMinutes: 10))
        XCTAssertNil(MorningSteps.worstCase(start: at(6, 30), drive: drive(estimates(google: 32, googleWorst: 41), fallback: "no signal"),
                                            source: .apple, googleWorstPlanned: false, arrival: .whenItStarts, bufferMinutes: 10))
    }

    func testItem1TheWorstCaseSitsInTimeOrderEvenBeforeLeaveBy() {
        // Leave by 5:50 (6:30 − 10 − 30); the worst case 5:49 (6:30 − 41) comes first.
        let d = drive(estimates(google: 32, googleWorst: 41))
        var input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30), location: "Work", drive: d, wake: at(4, 30), bufferMinutes: 10)
        input.worstCase = MorningSteps.worstCase(start: at(6, 30), drive: d, source: .apple, googleWorstPlanned: false,
                                                 arrival: .whenItStarts, bufferMinutes: 10)
        let kinds = MorningSteps.steps(input).map(\.kind)
        XCTAssertEqual(kinds, [.wake, .getReady, .leaveByWorst, .leaveBy, .arrive, .event])
        let worst = MorningSteps.steps(input).first { $0.kind == .leaveByWorst }
        XCTAssertEqual(worst?.title, "Leave by · worst case")
        XCTAssertEqual(worst?.detail, "Leaving now gets you there right when it starts, not early.\nGoogle worst case 41 min")
    }

    func testItem1UsuallyAfterLeaveBy() {
        let d = drive(estimates(google: 32, googleWorst: 36))
        var input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30), location: "Work", drive: d, wake: at(4, 30), bufferMinutes: 10)
        input.worstCase = MorningSteps.worstCase(start: at(6, 30), drive: d, source: .apple, googleWorstPlanned: false,
                                                 arrival: .whenItStarts, bufferMinutes: 10)
        XCTAssertEqual(MorningSteps.steps(input).map(\.kind), [.wake, .getReady, .leaveBy, .leaveByWorst, .arrive, .event])
    }

    func testItem1TheSettingDefaultsToWhenItStarts() {
        XCTAssertEqual(BridgeSettings().worstCaseArrival, .whenItStarts)
        XCTAssertTrue(SettingsPages.driveTime.contains("worstCaseArrival"))
    }

    // MARK: Item 2, Set alarms asks about bedtime during wind-down

    private func asks(_ status: WindDownState.Status, bedtimeRan: Bool = false, enabled: Bool = true, atHome: Bool? = true,
                      integration: Bool = true, bedtimeRanAt: Date? = nil) -> Bool {
        var state = WindDownState(status: status, windDown: at(21, 0, day: 2), goToBed: at(21, 30, day: 2))
        state.bedtimeRan = bedtimeRan
        return GoodNight.asksWithSet(windDown: state, windDownEnabled: enabled, atHome: atHome, integration: integration,
                                     bedtimeRanAt: bedtimeRanAt, now: at(21, 40, day: 2))
    }

    func testItem2AsksWhileWindingDownAndAtBedtime() {
        XCTAssertTrue(asks(.windingDown))
        XCTAssertTrue(asks(.bedtime))
    }

    func testItem2DoesntAskBeforeWindDownOrAfterBedtimeRan() {
        XCTAssertFalse(asks(.scheduled))
        XCTAssertFalse(asks(.off))
        XCTAssertFalse(asks(.cancelled))
        XCTAssertFalse(asks(.bedtime, bedtimeRan: true))
        XCTAssertFalse(asks(.bedtime, bedtimeRanAt: at(21, 35, day: 2)), "Good night ran since wind-down started")
        XCTAssertTrue(asks(.bedtime, bedtimeRanAt: at(22, 0, day: 1)), "last night's bedtime doesn't count")
    }

    func testItem2DoesntAskWithWindDownOffAwayOrWithoutTheIntegration() {
        XCTAssertFalse(asks(.windingDown, enabled: false))
        XCTAssertFalse(asks(.windingDown, atHome: false))
        XCTAssertTrue(asks(.windingDown, atHome: nil), "home unknown still asks")
        XCTAssertFalse(asks(.windingDown, integration: false))
    }

    // MARK: Items 3 and 4, the saved plan and preview

    private func shiftPlan() -> WakePlan {
        var shift = ShiftCandidate(title: "Days", start: at(6, 30), wakeMinutesBefore: 120, cause: "Days")
        shift.location = "Work"
        var plan = WakePlan(source: .shift, wakeTime: at(4, 30), alarmTimes: [at(4, 20), at(4, 25), at(4, 30)], reason: "Days shift at 6:30", shift: shift)
        plan.commute = Commute(travelSeconds: 31 * 60, driveEstimates: estimates(google: 32, googleWorst: 41))
        plan.madeAt = at(22, 42, day: 2)
        return plan
    }

    private func defaults() -> UserDefaults {
        let name = "V0411Tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testItem3TheSetPlanSurvivesARestart() {
        let store = defaults()
        let saved = SavedPlan(plan: shiftPlan(), asOf: at(22, 42, day: 2))
        SavedPlan.save(saved, key: "appliedPlan.v1", defaults: store)
        XCTAssertEqual(SavedPlan.load("appliedPlan.v1", defaults: store, now: at(2, 0)), saved, "read back after the app was closed")
        XCTAssertEqual(SavedPlan.load("appliedPlan.v1", defaults: store, now: at(2, 0))?.plan.commute?.driveEstimates.count, 3)
    }

    func testItem3ClearingAndANewSetReplaceIt() {
        let store = defaults()
        SavedPlan.save(SavedPlan(plan: shiftPlan(), asOf: at(22, 42, day: 2)), key: "appliedPlan.v1", defaults: store)
        var later = shiftPlan()
        later.alarmTimes = [at(4, 10)]
        SavedPlan.save(SavedPlan(plan: later, asOf: at(23, 0, day: 2)), key: "appliedPlan.v1", defaults: store)
        XCTAssertEqual(SavedPlan.load("appliedPlan.v1", defaults: store, now: at(2, 0))?.plan.alarmTimes, [at(4, 10)])
        SavedPlan.save(nil, key: "appliedPlan.v1", defaults: store)
        XCTAssertNil(SavedPlan.load("appliedPlan.v1", defaults: store, now: at(2, 0)), "No alarms, a skip or Clear")
    }

    func testItem3TheFooterSaysWhenWithTheDayOnlyWhenItIsntToday() {
        XCTAssertEqual(MorningSteps.asOf(at(22, 42, day: 2), now: at(23, 0, day: 2), calendar: newYork),
                       "As of \(WakePlanner.format(at(22, 42, day: 2))) · tap Preview to update")
        let day = at(22, 42, day: 1).formatted(.dateTime.weekday(.abbreviated))
        XCTAssertEqual(MorningSteps.asOf(at(22, 42, day: 1), now: at(2, 0, day: 2), calendar: newYork),
                       "As of \(day) \(WakePlanner.format(at(22, 42, day: 1))) · tap Preview to update")
    }

    func testItem3ItStaysUntilTheEventStartsOrTheMorningIsOverWhicheverIsLater() {
        let saved = SavedPlan(plan: shiftPlan(), asOf: at(22, 42, day: 2))
        // Late backstop 5:23 + 60 = 6:23; the shift at 6:30 is later.
        XCTAssertEqual(saved.showsUntil(lateBackstop: at(5, 23)), at(6, 30))
        XCTAssertTrue(saved.shows(lateBackstop: at(5, 23), now: at(6, 29)))
        XCTAssertFalse(saved.shows(lateBackstop: at(5, 23), now: at(6, 31)))
        // A backstop running late keeps it longer.
        XCTAssertEqual(saved.showsUntil(lateBackstop: at(5, 45)), at(6, 45))
    }

    func testItem3AfterAStopTheStoppedAlarmReadsStoppedAndTheNextStepIsMarked() {
        let bubbles = [AlarmBubble(time: at(4, 20), ring: .off, isWake: false),
                       AlarmBubble(time: at(4, 25), ring: .snoozing(until: at(4, 34)), isWake: false),
                       AlarmBubble(time: at(4, 30), ring: .set, isWake: true)]
        let marks = MorningSteps.marks(bubbles, stops: [at(4, 20): at(4, 21)], lastStop: at(4, 21), now: at(4, 27))
        XCTAssertEqual(marks.map(\.state), [.stopped(at: at(4, 21)), .snoozing(until: at(4, 34)), .set])

        var input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30), location: "Work",
                                       drive: drive(estimates(), travel: 31), wake: at(4, 30), bufferMinutes: 10)
        input.alarms = marks
        input.rungs = [BackstopInfo.Rung(name: "Early backstop", time: at(4, 55))]
        input.now = at(4, 27)
        let steps = MorningSteps.steps(input)
        XCTAssertEqual(steps.map(\.title), ["Alarm 1 of 3", "Alarm 2 of 3", "Wake up", "Get ready", "Early backstop", "Leave by", "Arrive", "Days starts"])
        XCTAssertEqual(steps[0].detail, "Stopped \(WakePlanner.format(at(4, 21)))")
        XCTAssertTrue(steps[0].dimmed)
        XCTAssertEqual(steps[1].detail, "Snoozing · rings \(WakePlanner.format(at(4, 34)))")
        XCTAssertFalse(steps[1].dimmed, "a snoozing alarm isn't past")
        XCTAssertEqual(steps.filter(\.next).map(\.title), ["Wake up"])
    }

    func testItem3OnceUpLeaveByIsNextAndAlarmsEndedWithoutRingingSayEnded() {
        let bubbles = [AlarmBubble(time: at(4, 20), ring: .off, isWake: false),
                       AlarmBubble(time: at(4, 25), ring: .off, isWake: false),
                       AlarmBubble(time: at(4, 30), ring: .off, isWake: true)]
        // Stopped at 4:21 with the rest ended: 4:25 and 4:30 never rang.
        let marks = MorningSteps.marks(bubbles, stops: [at(4, 20): at(4, 21)], lastStop: at(4, 21), now: at(5, 0))
        XCTAssertEqual(marks.map(\.state), [.stopped(at: at(4, 21)), .ended, .ended])
        var input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30), location: "Work",
                                       drive: drive(estimates(), travel: 31), wake: at(4, 30), bufferMinutes: 10)
        input.alarms = marks
        input.now = at(5, 0)
        let steps = MorningSteps.steps(input)
        XCTAssertEqual(steps.filter(\.next).map(\.kind), [.leaveBy])
        XCTAssertEqual(steps.first { $0.title == "Alarm 2 of 3" }?.detail, "Ended")
        XCTAssertFalse(steps.first { $0.kind == .getReady }!.dimmed, "getting ready until Leave by")
    }

    func testItem3BeforeTheMorningOneWakeUpStepAndNothingDimmed() {
        let bubbles = [AlarmBubble(time: at(4, 20), ring: .set, isWake: false), AlarmBubble(time: at(4, 30), ring: .set, isWake: true)]
        XCTAssertEqual(MorningSteps.marks(bubbles, stops: [:], lastStop: nil, now: at(23, 0, day: 2)), [])
        let input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30), location: "Work",
                                       drive: drive(estimates(), travel: 31), wake: at(4, 30), bufferMinutes: 10, now: at(23, 0, day: 2))
        let steps = MorningSteps.steps(input)
        XCTAssertEqual(steps.filter { $0.kind == .wake || $0.kind == .alarm }.count, 1)
        XCTAssertFalse(steps.contains { $0.dimmed || $0.next })
    }

    func testItem4APreviewSurvivesARestartAndGoesOnceItsMorningHasPassed() {
        let store = defaults()
        let preview = SavedPlan(plan: shiftPlan(), asOf: at(18, 2, day: 2))
        SavedPlan.save(preview, key: "previewPlan.v1", defaults: store)
        XCTAssertEqual(SavedPlan.load("previewPlan.v1", defaults: store, now: at(19, 0, day: 2)), preview)
        XCTAssertNil(SavedPlan.load("previewPlan.v1", defaults: store, now: at(8, 0, day: 4)), "the next day")
        XCTAssertEqual(MorningSteps.asOf(preview.asOf, now: at(19, 0, day: 2), calendar: newYork),
                       "As of \(WakePlanner.format(at(18, 2, day: 2))) · tap Preview to update")
    }

    func testItem4ThePlanCheckPreviewReplacesAnEarlierOne() {
        let store = defaults()
        SavedPlan.save(SavedPlan(plan: shiftPlan(), asOf: at(17, 0, day: 2)), key: "previewPlan.v1", defaults: store)
        var checked = shiftPlan()
        checked.madeAt = at(19, 0, day: 2)
        SavedPlan.save(SavedPlan(plan: checked, asOf: checked.madeAt!), key: "previewPlan.v1", defaults: store)
        XCTAssertEqual(SavedPlan.load("previewPlan.v1", defaults: store, now: at(19, 5, day: 2))?.asOf, at(19, 0, day: 2))
    }

    // MARK: Item 5, remote work days

    func testItem5EachMarkerOnItsOwnAndSwitchedOff() {
        var settings = BridgeSettings()
        settings.homeAddress = "12 Oak St, Springfield"
        XCTAssertTrue(WakePlanner.isRemote(title: "Days", location: "Home", settings: settings))
        XCTAssertTrue(WakePlanner.isRemote(title: "Days", location: "remote", settings: settings))
        XCTAssertTrue(WakePlanner.isRemote(title: "Days", location: "12 Oak St., Springfield, IL 62701, United States", settings: settings))
        XCTAssertFalse(WakePlanner.isRemote(title: "Days", location: "1 Hospital Way", settings: settings))
        XCTAssertTrue(WakePlanner.isRemote(title: "Days WFH", location: "1 Hospital Way", settings: settings))
        settings.remoteByLocation = false
        XCTAssertFalse(WakePlanner.isRemote(title: "Days", location: "Home", settings: settings))
        settings.remoteByKeyword = false
        XCTAssertFalse(WakePlanner.isRemote(title: "Days WFH", location: "", settings: settings))
    }

    func testItem5EmptyLocationOnlyWithThatSettingOn() {
        var settings = BridgeSettings()
        XCTAssertFalse(settings.remoteWhenNoLocation, "off by default")
        XCTAssertFalse(WakePlanner.isRemote(title: "Days", location: "  ", settings: settings))
        settings.remoteWhenNoLocation = true
        XCTAssertTrue(WakePlanner.isRemote(title: "Days", location: "", settings: settings))
    }

    func testItem5TheWakeUpIsTheStartMinusTheRemoteGetReadyTime() {
        let rule = ShiftRule(keyword: "Days", wakeMinutesBefore: 120, wakeIs: .last, alarmCount: 3, alarmSpacingMinutes: 5)
        var (shift, _) = ShiftCandidate.make(title: "Days WFH", start: at(6, 30), rule: rule)
        shift = shift.markingRemote(settings: BridgeSettings())
        XCTAssertTrue(shift.remote)
        XCTAssertEqual(shift.wakeTime, at(6, 0), "30 min by default")
        let office = ShiftCandidate.make(title: "Days", start: at(6, 30), rule: rule).0.markingRemote(settings: BridgeSettings())
        XCTAssertFalse(office.remote, "a hybrid week's office day keeps its commute")
        XCTAssertEqual(office.wakeTime, at(4, 30))
    }

    func testItem5AFixedTimeRuleKeepsItsTime() {
        var rule = ShiftRule(keyword: "Swings", wakeMinutesBefore: 60)
        rule.timing = .fixedTime
        rule.fixedHour = 8
        rule.fixedMinute = 0
        let (made, _) = ShiftCandidate.make(title: "Swings Remote", start: at(14, 0), rule: rule, calendar: newYork)
        let shift = made.markingRemote(settings: BridgeSettings())
        XCTAssertTrue(shift.remote)
        XCTAssertEqual(shift.wakeTime, at(8, 0))
    }

    func testItem5NoLeaveByAndHomeAssistantHearsRemote() {
        var shift = ShiftCandidate(title: "Days WFH", start: at(6, 30), wakeMinutesBefore: 30, cause: "Days")
        shift.remote = true
        let plan = WakePlan(source: .shift, wakeTime: at(6, 0), alarmTimes: [at(5, 50), at(5, 55), at(6, 0)], reason: "Days shift", shift: shift)
        XCTAssertNil(plan.leaveBy(settings: BridgeSettings()), "no trip, so no leave reminders or leave check")
        let payload = plan.homeAssistantPayload(settings: BridgeSettings())
        XCTAssertEqual(payload["remote"] as? Bool, true)
        XCTAssertNil(payload["leave_by"])
        XCTAssertEqual((payload["ladder"] as? [String: Any])?["remote"] as? Bool, true)
    }

    func testItem5YourMorningShowsBeReadyAndRemote() {
        var shift = ShiftCandidate(title: "Days WFH", start: at(6, 30), wakeMinutesBefore: 30, cause: "Days")
        shift.remote = true
        let input = MorningSteps.Input(eventTitle: "Days WFH starts", start: at(6, 30), location: "", eventDetail: "Remote", drive: nil,
                                       noDriveDetail: "Working from home, so no drive", wake: at(6, 0), bufferMinutes: 10,
                                       rungs: [BackstopInfo.Rung(name: "Late backstop", time: at(6, 10))])
        let steps = MorningSteps.steps(input)
        XCTAssertEqual(steps.map(\.kind), [.wake, .getReady, .backstop, .beReady, .event])
        XCTAssertEqual(steps.last?.detail, "Remote")
        XCTAssertFalse(steps.contains { $0.kind == .leaveBy || $0.kind == .leaveByWorst })
    }

    // MARK: Item 6, one Leave Live Activity after the last alarm

    func testItem6EndingOneAlarmWithAnotherSnoozingReportsTheSnoozedOne() {
        // 2 Nov 04:30:19: the 4:25 was snoozing to 4:34 when the 4:30 was ended.
        let left = StopDescription.left(wakeUp: [at(4, 34, day: 2)], later: [], now: at(4, 30, 19, day: 2))
        XCTAssertEqual(left, [at(4, 34, day: 2)], "not alarm_times: [] / noalarm")
        XCTAssertEqual(StopDescription.left(wakeUp: [], later: [], now: at(4, 44, day: 2)), [], "the last stop")
    }

    func testItem6TheMorningActivityStartsOnlyAfterTheLastAlarm() {
        XCTAssertFalse(MorningActivity.shows(firstDone: true, stopped: true, wakeUpAlarmsLeft: true))
        XCTAssertTrue(MorningActivity.shows(firstDone: true, stopped: true, wakeUpAlarmsLeft: false))
        XCTAssertFalse(MorningActivity.shows(firstDone: false, stopped: false, wakeUpAlarmsLeft: false), "before the morning")
    }

    func testItem6TwoStartsInARowLeaveOne() {
        let running: [(id: String, kind: BedtimeActivityAttributes.Kind)] = [("a", .morning), ("b", .morning), ("c", .windDown)]
        XCTAssertEqual(BedtimeActivities.duplicates(running, newest: ("b", .morning)), ["a"])
        XCTAssertEqual(BedtimeActivities.duplicates([("b", .morning)], newest: ("b", .morning)), [])
    }

    // MARK: Item 7, the leave-by line centred

    func testItem7TheStatusRowIsCentred() {
        var inputs = BottomBar.Inputs(now: at(4, 45))
        inputs.backToBedWindow = true
        inputs.leaveBy = at(5, 43)
        let bar = BottomBar.make(inputs)
        XCTAssertEqual(bar.top, .status("Alarms off · leave by \(WakePlanner.format(at(5, 43)))", .muted))
        XCTAssertTrue(bar.statusCentered)
        var withUndo = bar
        withUndo.undoOffered = true
        XCTAssertFalse(withUndo.statusCentered, "beside Undo it stays on the left")
    }

    // MARK: Item 8, the drive check says what changed and when it checks again

    func testItem8AOneMinuteChangeIsSaid() {
        let previous = LeaveReminder.Previous(leaveBy: at(5, 43), travelSeconds: 32 * 60, wasChecked: true)
        let text = LeaveReminder.message(leaveBy: at(5, 44), travelSeconds: 31 * 60, bedtimeSeconds: 31 * 60, previous: previous, now: at(5, 28))
        XCTAssertEqual(text, "Leave by \(WakePlanner.format(at(5, 44))) (was \(WakePlanner.format(at(5, 43)))) · 31 min drive, 1 min shorter than the last check")
    }

    func testItem8TheChangeFromBedtimeStaysAsItIs() {
        let previous = LeaveReminder.Previous(leaveBy: at(5, 40), travelSeconds: 30 * 60, wasChecked: true)
        let text = LeaveReminder.message(leaveBy: at(5, 36), travelSeconds: 34 * 60, bedtimeSeconds: 30 * 60, previous: previous, now: at(5, 20))
        XCTAssertEqual(text, "Leave by \(WakePlanner.format(at(5, 36))) (was \(WakePlanner.format(at(5, 40)))) · 34 min drive (4 min worse than planned), 4 min longer than the last check")
        let first = LeaveReminder.Previous(leaveBy: at(5, 40), travelSeconds: 30 * 60, wasChecked: false)
        XCTAssertFalse(LeaveReminder.message(leaveBy: at(5, 39), travelSeconds: 31 * 60, bedtimeSeconds: 30 * 60, previous: first, now: at(5, 20))
            .contains("last check"), "the first check has no last check to compare with")
    }

    func testItem8TheNextCheck() {
        // 15 and 0 min before leave-by. Leave-by moved to 5:43:57: the 15-min check is due again at 5:28:57.
        XCTAssertEqual(LeaveReminder.nextCheck(leaveBy: at(5, 43, 57), offsets: [15, 0], now: at(5, 28, 21)), "Checking the drive again now")
        XCTAssertEqual(LeaveReminder.nextCheck(leaveBy: at(5, 43, 21), offsets: [15, 0], now: at(5, 28, 25)),
                       "Next check \(WakePlanner.format(at(5, 43, 21)))")
        XCTAssertNil(LeaveReminder.nextCheck(leaveBy: at(5, 43), offsets: [15, 0], now: at(5, 43, 30)), "after the last one")
    }

    func testItem8TheNotificationBodyNamesTheNextCheck() {
        var trip = PendingTrip(title: "Days", location: "Work", start: at(6, 30), arriveBy: at(6, 20), plannedTravelSeconds: 31 * 60)
        trip.bedtimeTravelSeconds = 31 * 60
        trip.checkedAt = at(5, 28, 21)
        let previous = LeaveReminder.Previous(leaveBy: at(5, 48), travelSeconds: 32 * 60, wasChecked: true)
        let text = LeaveReminder.checkText(trip, previous: previous, checkOffsets: [15, 0], now: at(5, 34))
        XCTAssertEqual(text.body, "Days at \(WakePlanner.format(at(6, 30))). Next check \(WakePlanner.format(at(5, 49))).")
        XCTAssertEqual(LeaveReminder.checkNowID, "leave-check-now", "one notification, replaced on each check")
    }

    // MARK: Item 10, remote days' backstops

    func testItem10SpreadBetweenTheLastAlarmAndTheStart() {
        let times = RemoteBackstops.times(lastAlarm: at(6, 0), start: at(6, 30), mode: .spread, minutes: (10, 20, 30))
        XCTAssertEqual(times, ["early": at(6, 7), "deadline": at(6, 15), "late": at(6, 22)])
    }

    func testItem10MinutesAfterTheLastAlarmNeverPastTheStart() {
        let times = RemoteBackstops.times(lastAlarm: at(6, 0), start: at(6, 25), mode: .afterLastAlarm, minutes: (10, 20, 30))
        XCTAssertEqual(times, ["early": at(6, 10), "deadline": at(6, 20), "late": at(6, 25)])
    }

    func testItem10NoGapNoBackstops() {
        XCTAssertEqual(RemoteBackstops.times(lastAlarm: at(8, 0), start: at(8, 0), mode: .spread, minutes: (10, 20, 30)), [:])
    }

    func testItem10TheRemotePlanSendsItsTimesToHomeAssistant() {
        var shift = ShiftCandidate(title: "Days WFH", start: at(6, 30), wakeMinutesBefore: 30, cause: "Days")
        shift.remote = true
        let plan = WakePlan(source: .shift, wakeTime: at(6, 0), alarmTimes: [at(5, 50), at(5, 55), at(6, 0)], reason: "Days shift", shift: shift)
        let ladder = plan.homeAssistantPayload(settings: BridgeSettings())["ladder"] as? [String: Any]
        let times = ladder?["remote_times"] as? [String: String]
        XCTAssertEqual(times?.keys.sorted(), ["deadline", "early", "late"])
        XCTAssertEqual(times?["deadline"].flatMap { ISO8601DateFormatter().date(from: $0) }, at(6, 15))
    }

    // MARK: Item 11, the Remote days page

    func testItem11ThePageResetsTogether() {
        var settings = BridgeSettings()
        settings.remoteGetReadyMinutes = 45
        settings.remoteBackstops = .afterLastAlarm
        settings.remoteKeywords = ["Home office"]
        settings.getReadyMinutes = 50
        settings.resetToDefaults(SettingsPages.remoteDays)
        XCTAssertEqual(settings.remoteGetReadyMinutes, 30)
        XCTAssertEqual(settings.remoteBackstops, .spread)
        XCTAssertEqual(settings.remoteKeywords, ["WFH", "Remote"])
        XCTAssertEqual(settings.getReadyMinutes, 50, "other pages keep theirs")
        XCTAssertFalse(SettingsPages.main.contains("remoteGetReadyMinutes"), "off the main page")
    }

    func testItem11TheRowsSummary() {
        var settings = BridgeSettings()
        XCTAssertEqual(RemoteDaysText.summary(settings), "Home, WFH, Remote · 30 min")
        settings.remoteByLocation = false
        settings.remoteByKeyword = false
        XCTAssertEqual(RemoteDaysText.summary(settings), "Off")
    }

    // MARK: Item 9, the app follows a wind-down move

    func testItem9TheAppReadsTheNewWindDownTime() {
        // Home Assistant's silent push names this signal; the reply's wind-down replaces the old.
        XCTAssertEqual(WindDownState.changedSignal, "wind_down_changed")
        let moved = WindDownState(["status": "scheduled", "wind_down": "2026-11-03T02:05:00Z", "go_to_bed": "2026-11-03T02:50:00Z"])
        XCTAssertEqual(moved.windDown, ISO8601DateFormatter().date(from: "2026-11-03T02:05:00Z"))
        XCTAssertEqual(moved.status, .scheduled)
    }

    // MARK: Item 13, Start wind-down after a cancel

    func testItem13CancelledOffersStartUntilGoToBed() {
        let cancelled = WindDownState(status: .cancelled, windDown: at(20, 50), goToBed: at(21, 50))
        XCTAssertTrue(cancelled.canStartNow(hours: 2, now: at(21, 0)))
        XCTAssertFalse(cancelled.canStartNow(hours: 2, now: at(21, 50)), "not once go to bed has come")
        var inputs = BottomBar.Inputs(now: at(21, 0))
        inputs.windDown = cancelled
        let bar = BottomBar.make(inputs)
        XCTAssertEqual(bar.top, .status("Wind-down off tonight · bed \(WakePlanner.format(at(21, 50)))", .muted))
        XCTAssertEqual(bar.buttons.first, .startWindDown)
        XCTAssertTrue(BottomBar.menu(inputs, alarmStyleApp: true, morningKnown: true).contains(.startWindDown))
    }

    // MARK: Item 15, Arrive's time on the right

    func testItem15ArrivesValueEndsWithItsTime() {
        let input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30), location: "Work",
                                       drive: drive(estimates(), travel: 31), wake: at(4, 30), bufferMinutes: 10)
        let arrive = MorningSteps.steps(input).first { $0.kind == .arrive }
        XCTAssertEqual(arrive?.value, "10 min early · \(WakePlanner.format(at(6, 20)))")
    }

    // MARK: Item 17, the Dynamic Island countdown

    func testItem17CompactCountdownIsMinutesAndSecondsOverAnHour() {
        XCTAssertEqual(CompactCountdown.label(58), "0:58")
        XCTAssertEqual(CompactCountdown.label(9 * 60 + 58), "9:58")
        XCTAssertEqual(CompactCountdown.label(59 * 60 + 58), "59:58")
        XCTAssertEqual(CompactCountdown.label(65 * 60), "65:00", "not 1:05:00")
    }

    // MARK: Item 18, Wake up later

    func testItem18WakeUpLaterEverywhere() {
        XCTAssertEqual(BarAction.sleepLater.title(day: "Tuesday"), "Wake up later…")
        XCTAssertEqual(QuickAction.sleepLater.title, "Wake up later")
        let phrases = SiriPhrases.groups.flatMap(\.entries).flatMap(\.phrases)
        XCTAssertTrue(phrases.contains("Wake up later with Bedtime Bridge"))
        XCTAssertFalse(phrases.contains("Sleep later with Bedtime Bridge"), "the list shows the new phrase")
    }

    // MARK: Item 19, the drive's weather on the widgets

    private func forecast(_ moment: MorningForecast.Moment, at time: Date, _ condition: String = "rainy") -> MorningForecast {
        MorningForecast(moment: moment, at: time, condition: condition, temperature: 41, unit: "°F")
    }

    private func weatherPlan(forecast: MorningForecast?, wake: MorningForecast? = nil, extra: Int? = nil) -> WakePlan {
        var plan = WakePlan(source: .shift, wakeTime: at(4, 30), alarmTimes: [at(4, 20)], reason: "Days shift")
        plan.forecast = forecast
        plan.wakeForecast = wake
        plan.weather = extra.map { WeatherAdjustment(minutes: $0, reason: "rain at 5 AM") }
        return plan
    }

    func testItem19TheDrivesWeather() {
        let us = Locale(identifier: "en_US")
        let weather = WidgetWeather.from(weatherPlan(forecast: forecast(.commute, at: at(5, 43))), hasDrive: true, locale: us)
        XCTAssertEqual(weather?.symbol, "cloud.rain.fill")
        XCTAssertEqual(weather?.line(format: WakePlanner.format), "Rain · 41° at \(WakePlanner.format(at(5, 43)))")
        XCTAssertEqual(weather?.conditionAndTime(format: WakePlanner.format), "Rain · \(WakePlanner.format(at(5, 43)))")
        XCTAssertNil(weather?.extraText)
    }

    func testItem19ExtraWeatherTimeIsShown() {
        let weather = WidgetWeather.from(weatherPlan(forecast: forecast(.commute, at: at(5, 43)), extra: 15), hasDrive: true)
        XCTAssertEqual(weather?.extraText, "+15 min")
    }

    func testItem19NoDriveUsesTheFirstAlarm() {
        let plan = weatherPlan(forecast: forecast(.commute, at: at(5, 43)), wake: forecast(.wakeUp, at: at(4, 20), "sunny"))
        let weather = WidgetWeather.from(plan, hasDrive: false)
        XCTAssertEqual(weather?.at, at(4, 20))
        XCTAssertEqual(weather?.condition, "Sunny")
    }

    func testItem19NoForecastNoWeather() {
        XCTAssertNil(WidgetWeather.from(weatherPlan(forecast: nil), hasDrive: true))
    }

    // MARK: Item 20, past leave time and on your way

    func testItem20TheMorningHeadline() {
        var state = BedtimeActivityAttributes.ContentState(kind: .morning, leaveBy: at(5, 43))
        XCTAssertEqual(MorningHeadline.of(state, stale: false, now: at(5, 30)), .leaveIn(at(5, 43)))
        XCTAssertEqual(MorningHeadline.of(state, stale: false, now: at(5, 45)), .pastLeaveTime(at(5, 43)))
        XCTAssertEqual(MorningHeadline.of(state, stale: true, now: at(5, 40)), .pastLeaveTime(at(5, 43)), "stale is past")
        state.departed = at(5, 41)
        state.eventStart = at(6, 30)
        XCTAssertEqual(MorningHeadline.of(state, stale: true, now: at(5, 45)), .onYourWay(start: at(6, 30)))
    }
}
