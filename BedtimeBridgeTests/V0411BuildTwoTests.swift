import XCTest
@testable import BedtimeBridge

/// v0.4.11 items 24–31.
final class V0411BuildTwoTests: XCTestCase {
    private let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int, day: Int = 6) -> Date {
        newYork.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func estimate(_ service: DriveEstimate.Service, _ minutes: Int) -> DriveEstimate {
        DriveEstimate(service: service, seconds: Double(minutes) * 60)
    }

    // MARK: Item 24, Google worst case once

    func testItem24LeaveByLeavesOutGoogleWorstCaseWhenItHasItsOwnRow() {
        let all = [estimate(.apple, 31), estimate(.tomTom, 31), estimate(.googleTypical, 32), estimate(.googleWorst, 41)]
        let drive = MorningSteps.Drive(travelSeconds: 31 * 60, estimates: all)
        var input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30), location: "Work", drive: drive, wake: at(4, 30), bufferMinutes: 10)
        input.worstCase = MorningSteps.worstCase(start: at(6, 30), drive: drive, source: .apple, googleWorstPlanned: false,
                                                 arrival: .whenItStarts, bufferMinutes: 10)
        XCTAssertNotNil(input.worstCase)
        let leaveBy = MorningSteps.steps(input).first { $0.kind == .leaveBy }!
        XCTAssertEqual(leaveBy.detail?.components(separatedBy: "\n").last, "Apple 31 · TomTom 31 · Google 32 min")

        // Planned on Google's worst case: no row, so Leave by lists it.
        input.worstCase = MorningSteps.worstCase(start: at(6, 30), drive: drive, source: .google, googleWorstPlanned: true,
                                                 arrival: .whenItStarts, bufferMinutes: 10)
        XCTAssertNil(input.worstCase)
        let planned = MorningSteps.steps(input).first { $0.kind == .leaveBy }!
        XCTAssertEqual(planned.detail?.components(separatedBy: "\n").last, "Apple 31 · TomTom 31 · Google 32 · Google worst case 41 min")
    }

    // MARK: Item 25, the Sleep row

    func testItem25SleepSitsBetweenGoToBedAndWakeUpInTenthsOfAnHour() {
        var input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30, day: 7), location: "Work",
                                       drive: MorningSteps.Drive(travelSeconds: 31 * 60), wake: at(4, 30, day: 7), bufferMinutes: 10)
        input.windDown = at(21, 0)
        input.goToBed = at(21, 50)
        input.now = at(20, 0)
        let steps = MorningSteps.steps(input)
        XCTAssertEqual(Array(steps.map(\.title).prefix(4)), ["Wind-down", "Go to bed", "Sleep", "Wake up"])
        XCTAssertEqual(steps[2].value, "6.7 h")
        XCTAssertEqual(MorningSteps.sleepLength(from: at(22, 0), to: at(6, 0, day: 7)), "8.0 h")

        input.windDown = nil
        input.goToBed = nil
        XCTAssertFalse(MorningSteps.steps(input).contains { $0.kind == .sleep }, "no wind-down, no Sleep row")
    }

    func testItem25SleepIsNeverNextAndDimsWithGoToBed() {
        var input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30, day: 7), location: "Work",
                                       drive: MorningSteps.Drive(travelSeconds: 31 * 60), wake: at(4, 30, day: 7), bufferMinutes: 10)
        input.windDown = at(21, 0)
        input.goToBed = at(21, 50)
        input.alarms = [MorningSteps.AlarmMark(time: at(4, 30, day: 7), isWake: true, state: .set)]
        input.now = at(4, 0, day: 7)
        let steps = MorningSteps.steps(input)
        let sleep = steps.first { $0.kind == .sleep }!
        XCTAssertTrue(sleep.dimmed)
        XCTAssertFalse(sleep.next)
        XCTAssertEqual(steps.first { $0.next }?.kind, .wake)
    }

    // MARK: Item 26, fired

    func testItem26OnlyTheBackstopThatFiredIsTagged() {
        let context = MorningContext(ladderArmed: false, ladderStatus: "done", ladderKind: "shift",
                                     backstops: ["early": at(4, 55), "deadline": at(5, 10), "late": at(5, 25)],
                                     shiftStart: at(6, 30), houseSource: "bridge", firedRungs: ["deadline"])
        let info = BackstopInfo.make(context: context, leaveBy: at(5, 45), offsets: (50, 35, 20, 15), firstDayBack: false,
                                     morning: at(4, 20), calendar: newYork)!
        XCTAssertEqual(info.rungs.map(\.fired), [false, true, false], "a fired backstop stays on the morning after the ladder is done")
        var input = MorningSteps.Input(eventTitle: "Days starts", start: at(6, 30), location: "Work",
                                       drive: MorningSteps.Drive(travelSeconds: 31 * 60), wake: at(4, 30), bufferMinutes: 10)
        input.rungs = info.rungs
        XCTAssertEqual(MorningSteps.steps(input).filter(\.fired).map(\.title), ["Deadline backstop"])
        XCTAssertEqual(AlarmTimeline.steps(alarms: [at(4, 30)], wake: at(4, 30), temporary: [], rungs: info.rungs).filter(\.fired).map(\.title),
                       ["Deadline backstop"])

        let quiet = MorningContext(ladderArmed: true, ladderStatus: "armed", ladderKind: "shift", backstops: ["deadline": at(5, 10)],
                                   shiftStart: at(6, 30), houseSource: "bridge")
        XCTAssertFalse(BackstopInfo.make(context: quiet, leaveBy: nil, offsets: (50, 35, 20, 15), firstDayBack: false,
                                         morning: at(4, 20), calendar: newYork)!.rungs.contains(where: \.fired), "no event, no tag")
    }

    // MARK: Item 27, widgets in bed

    func testItem27WindDownLeavesTheWidgetsOnceBedtimeRanOrYoureInBed() {
        var state = WindDownState(status: .bedtime, windDown: at(21, 0), goToBed: at(21, 50))
        XCTAssertTrue(state.showsOnWidgets)
        state.bedtimeRan = true
        XCTAssertFalse(state.showsOnWidgets)
        let reply: [String: Any] = ["status": "winding_down", "wind_down": "2026-11-07T02:00:00Z", "go_to_bed": "2026-11-07T02:50:00Z",
                                    "went_to_bed": "2026-11-07T02:18:00Z"]
        let inBed = WindDownState(reply)
        XCTAssertNotNil(inBed.wentToBed)
        XCTAssertFalse(inBed.showsOnWidgets)
        XCTAssertTrue(WindDownState(["status": "scheduled", "wind_down": "2026-11-07T02:00:00Z"]).showsOnWidgets)
    }

    // MARK: Item 28, the bar's day

    func testItem28WithNothingSetTheBarNamesTomorrow() {
        let friday = at(16, 55)
        let saturday = friday.addingTimeInterval(86400).formatted(.dateTime.weekday(.wide))
        XCTAssertEqual(BarAction.dayName(morning: nil, now: friday), saturday)
        XCTAssertEqual(BarAction.dayName(morning: at(4, 20, day: 7), now: friday), saturday)
        // After midnight with an alarm that morning: still that day.
        XCTAssertEqual(BarAction.dayName(morning: at(4, 20, day: 7), now: at(0, 30, day: 7)), saturday)
    }

    // MARK: Item 29, nap lengths by voice

    func testItem29NapLengthsAreNamedAsTheyreSaid() {
        XCTAssertEqual(SiriReplies.napNames(20).first, "20 minutes")
        XCTAssertTrue(SiriReplies.napNames(20).contains("20 minute"))
        XCTAssertTrue(SiriReplies.napNames(20).contains("20 min"), "the short name stays as a synonym")
        XCTAssertEqual(SiriReplies.napNames(60).first, "an hour")
        XCTAssertEqual(SiriReplies.napNames(90).first, "an hour and a half")
        XCTAssertEqual(SiriReplies.napNames(120).first, "2 hours")
        for minutes in BridgeSettings().napLengths {
            XCTAssertEqual(SiriReplies.napMinutes(spoken: SiriReplies.napNames(minutes)[0]), minutes)
        }
    }

    func testItem29ALengthNotInTheListIsTakenAsSaid() {
        XCTAssertEqual(SiriReplies.napMinutes(spoken: "25 minutes"), 25)
        XCTAssertEqual(SiriReplies.napMinutes(spoken: "twenty minute"), 20)
        XCTAssertEqual(SiriReplies.napMinutes(spoken: "half an hour"), 30)
        XCTAssertEqual(SiriReplies.napMinutes(spoken: "1.5 hours"), 90)
        XCTAssertEqual(SiriReplies.napMinutes(spoken: "for 45 min"), 45)
        XCTAssertNil(SiriReplies.napMinutes(spoken: "banana"))
    }

    func testItem29ThePhraseListHasTheTakeANapPhrases() {
        let phrases = SiriPhrases.entries.flatMap(\.phrases)
        XCTAssertTrue(phrases.contains("Take a 20 minute nap with Bedtime Bridge"))
        XCTAssertTrue(phrases.contains("Take a nap with Bedtime Bridge"))
    }

    // MARK: Item 30, the other phrases

    func testItem30CancelAsksFirstAndSaysWhenNothingIsSet() {
        XCTAssertNil(SiriReplies.cancelQuestion([]))
        XCTAssertEqual(SiriReplies.cancelQuestion([at(4, 25), at(4, 20), at(4, 30)]),
                       "Turn off your 3 alarms? The first is at \(WakePlanner.format(at(4, 20))).")
        XCTAssertEqual(SiriReplies.cancelQuestion([at(4, 20)]), "Turn off your alarm at \(WakePlanner.format(at(4, 20)))?")
    }

    func testItem30PlanSaysWhatItSet() {
        let times = [at(4, 20), at(4, 25), at(4, 30)]
        XCTAssertEqual(SiriReplies.planReply(alarms: times, cause: "Days", set: true, day: "Saturday"),
                       "3 alarms set, first at \(WakePlanner.format(at(4, 20))) for Days.")
        XCTAssertEqual(SiriReplies.planReply(alarms: [], cause: "noalarm", set: true, day: "Saturday"),
                       "Nothing on your calendar for Saturday, so no alarms set.")
        XCTAssertEqual(SiriReplies.planReply(alarms: [at(6, 25)], cause: "calendar", set: true, day: "Saturday"),
                       "1 alarm set, first at \(WakePlanner.format(at(6, 25))) for an appointment.")
    }

    func testItem30OtherWaysToSayAnAmountOrNoLocation() {
        let hour = SleepLaterAmount.caseDisplayRepresentations[.hour]!
        XCTAssertTrue(hour.synonyms.map { String(localized: $0) }.contains("1 hour"))
        XCTAssertTrue(SleepLaterAmount.caseDisplayRepresentations[.thirty]!.synonyms.map { String(localized: $0) }.contains("half an hour"))
        XCTAssertTrue(SiriReplies.isNoLocation("Skip."))
        XCTAssertTrue(SiriReplies.isNoLocation("none"))
        XCTAssertFalse(SiriReplies.isNoLocation("Main St Dental"))
        let noAlarms = SiriPhrases.entries.first { $0.phrases.contains("No alarms tomorrow in Bedtime Bridge") }!
        XCTAssertFalse(noAlarms.does.contains("asks about Sleep In"))
        XCTAssertTrue(SiriPhrases.entries.flatMap(\.phrases).contains("Stop wind-down in Bedtime Bridge"))
    }

    // MARK: Item 31, the tutorial

    func testItem31PagesStartWithTheCalendarAndHomeAssistantCanBeSkipped() {
        let pages = Tutorial.pages
        XCTAssertEqual(pages.count, 14)
        XCTAssertEqual(pages.map(\.id), Array(0..<14))
        XCTAssertEqual(pages[1].title, "Put your work schedule in Apple Calendar")
        let homeAssistant = pages.firstIndex { $0.startsHomeAssistant }!
        XCTAssertEqual(pages[homeAssistant].title, "Home Assistant (optional)")
        XCTAssertEqual(Tutorial.afterSkippingHomeAssistant(), Tutorial.lastIndex)
        XCTAssertEqual(pages.last?.graphic, .checklist)
    }

    func testItem31OpensOnceOnAFreshInstallOnly() {
        XCTAssertTrue(Tutorial.showsOnLaunch(freshInstall: true, seen: false))
        XCTAssertFalse(Tutorial.showsOnLaunch(freshInstall: true, seen: true))
        XCTAssertFalse(Tutorial.showsOnLaunch(freshInstall: false, seen: false), "an existing install never gets it by itself")
        let defaults = UserDefaults(suiteName: "tutorial-test")!
        defaults.removePersistentDomain(forName: "tutorial-test")
        XCTAssertTrue(SettingsStore(defaults: defaults).freshInstall)
    }

    func testItem31TheChecklistTicksFromSettings() {
        var settings = BridgeSettings()
        settings.homeAddress = ""
        var items = Tutorial.checklist(settings: settings, shiftFound: nil, paired: false)
        XCTAssertEqual(items.map(\.title).first, "Allow calendar access")
        XCTAssertEqual(items.map(\.done), [false, true, true, false, false])
        XCTAssertTrue(items.last!.optional)
        settings.homeAddress = "1 Main St"
        settings.appointmentKeyword = ""
        items = Tutorial.checklist(settings: settings, shiftFound: true, paired: true)
        XCTAssertEqual(items.map(\.done), [true, true, false, true, true])
        XCTAssertEqual(items.first?.title, "A shift in your calendar this week")
    }

    // MARK: Item 32, in bed with no alarms

    func testItem32InBedNoAlarmsLastsUntilTheMorningUnlessAnAlarmWasStopped() {
        let ran = at(22, 47)
        XCTAssertTrue(OptionWindows.inBedNoAlarms(bedtimeRanAt: ran, lastStop: nil, alarmsSet: false, napping: false,
                                                  goodMorningFrom: "08:00", now: at(23, 4), calendar: newYork))
        XCTAssertTrue(OptionWindows.inBedNoAlarms(bedtimeRanAt: ran, lastStop: at(4, 30), alarmsSet: false, napping: false,
                                                  goodMorningFrom: "08:00", now: at(23, 4), calendar: newYork), "a stop before bedtime doesn't count")
        XCTAssertFalse(OptionWindows.inBedNoAlarms(bedtimeRanAt: ran, lastStop: nil, alarmsSet: false, napping: false,
                                                   goodMorningFrom: "08:00", now: at(8, 1, day: 7), calendar: newYork), "over at Good morning from")
        XCTAssertFalse(OptionWindows.inBedNoAlarms(bedtimeRanAt: ran, lastStop: nil, alarmsSet: true, napping: false,
                                                   goodMorningFrom: "08:00", now: at(23, 4), calendar: newYork))
        XCTAssertFalse(OptionWindows.inBedNoAlarms(bedtimeRanAt: at(21, 0), lastStop: at(4, 30, day: 7), alarmsSet: false, napping: false,
                                                   goodMorningFrom: "08:00", now: at(5, 0, day: 7), calendar: newYork), "a morning, not a night off")
        // A bedtime after midnight is for that same morning.
        XCTAssertEqual(OptionWindows.morning(after: at(1, 0, day: 7), goodMorningFrom: "08:00", calendar: newYork), at(8, 0, day: 7))
        XCTAssertEqual(OptionWindows.morning(after: ran, goodMorningFrom: "08:00", calendar: newYork), at(8, 0, day: 7))
    }

    func testItem32TheBarOffersNotReadyForBedAndPutsNapInTheMenu() {
        var i = BottomBar.Inputs(now: at(23, 4))
        i.inBedNoAlarms = true
        i.inBedDay = "Saturday"
        i.notReadyWindow = true
        i.napEnabled = true
        i.nothingFound = true
        let bar = BottomBar.make(i)
        XCTAssertEqual(bar, BottomBar(top: .status("In bed · no alarms Saturday", .accent), buttons: [.addTemporary, .previewPlan],
                                      actionRow: [.setAlarmsForTime], hold: .notReadyForBed))
        XCTAssertFalse(bar.buttons.contains(.nap) || bar.actionRow.contains(.nap))
        XCTAssertTrue(BottomBar.menu(i, alarmStyleApp: true, morningKnown: false).contains(.nap))
        XCTAssertFalse(BottomBar.menu(i, alarmStyleApp: true, morningKnown: false).contains(.notReadyForBed), "v0.4.11 item 45: the bar's slider")
        // Once the window closes: Nothing set, still no Nap in the bar.
        i.notReadyWindow = false
        XCTAssertEqual(BottomBar.make(i), BottomBar(top: .status("In bed · no alarms Saturday", .muted), buttons: [.addTemporary, .previewPlan],
                                                    actionRow: [.setAlarmsForTime]))
        // Bedtime didn't run: as before, Nap in the bar.
        i.inBedNoAlarms = false
        XCTAssertTrue(BottomBar.make(i).actionRow.contains(.nap))
    }

    func testItem32NotReadyForBedNeedsAlarmsOrANightOff() {
        XCTAssertTrue(OptionWindows.notReadyForBed(bedtimeRanAt: at(22, 47), alarmsSet: true, hours: 2, now: at(23, 4)))
        XCTAssertFalse(OptionWindows.notReadyForBed(bedtimeRanAt: at(22, 47), alarmsSet: true, hours: 2, now: at(0, 48, day: 7)))
    }

    // MARK: Item 33, the in-bed card

    func testItem33TheCardSaysBedtimeRanWhyAndSleepIn() {
        let card = InBedCard.content(bedtimeRan: at(22, 47), day: "Saturday", plan: nil, skipped: false, sleepIn: true,
                                     ladderStatus: "idle_uncovered", ladderReason: nil)
        XCTAssertEqual(card.title, "In bed · no alarms Saturday")
        XCTAssertEqual(card.lines, ["Bedtime ran at \(WakePlanner.format(at(22, 47))).", "Nothing on your calendar for Saturday.",
                                    "Sleep In is on.", "No backstops: nothing to cover.", "Added something for the morning? Tap Preview plan."])
        let unknown = InBedCard.content(bedtimeRan: at(22, 47), day: "Saturday", plan: nil, skipped: true, sleepIn: nil,
                                        ladderStatus: nil, ladderReason: nil)
        XCTAssertEqual(unknown.lines[1], "No alarms Saturday: you turned them off.")
        XCTAssertFalse(unknown.lines.contains { $0.hasPrefix("Sleep In") }, "Sleep In unknown: left out")
    }

    // MARK: Item 34, Morning weather with no alarms

    func testItem34TheNoAlarmForecastIsAtGoodMorningFromAndRefetchedWhenItChanges() {
        let (moment, time) = MorningForecast.moment(leaveBy: nil, wakeUp: nil, goodMorningFrom: "09:00", now: at(23, 4), calendar: newYork)
        XCTAssertEqual(moment, .goodMorning)
        XCTAssertEqual(time, at(9, 0, day: 7))
        XCTAssertTrue(NoAlarmWeather.fresh(fetched: at(23, 0), time: "08:00", settingTime: "08:00", forecastAt: at(8, 0, day: 7), now: at(23, 20)))
        XCTAssertFalse(NoAlarmWeather.fresh(fetched: at(23, 0), time: "08:00", settingTime: "09:00", forecastAt: at(8, 0, day: 7), now: at(23, 20)),
                       "a new Good morning from time fetches again")
        XCTAssertFalse(NoAlarmWeather.fresh(fetched: at(22, 0), time: "08:00", settingTime: "08:00", forecastAt: at(8, 0, day: 7), now: at(23, 4)),
                       "older than 30 min")
        XCTAssertNil(NoAlarmWeather.text(nil))
    }
}
