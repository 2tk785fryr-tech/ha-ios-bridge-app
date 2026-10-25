import EventKit
import Foundation
import MapKit
import WidgetKit

/// Glues calendar, drive time, Home Assistant and alarms together. Used by the app UI,
/// the Shortcuts actions and the alarm buttons, so they all behave the same.
@MainActor
final class BedtimeCoordinator {
    static let shared = BedtimeCoordinator()

    let calendar = CalendarService()
    let travel = TravelTimeService()
    let alarms = AlarmScheduler()
    let leaveReminder = LeaveReminder()

    // MARK: Planning

    /// Works out tonight's wake-up without touching any alarms.
    func buildPlan(settings: BridgeSettings, now: Date = .now) async throws -> WakePlan {
        let made = try await makePlan(settings: settings, now: now)
        return adjustedForSkip(made.plan, settings: made.settings)
    }

    // MARK: Skipped morning

    private static let skippedMorningKey = "skippedMorning"

    /// A morning you turned the alarms off for ("something changed"), so bedtime planning
    /// doesn't set them again. Forgotten once that morning has passed.
    var skippedMorning: Date? {
        get {
            guard let day = UserDefaults.standard.object(forKey: Self.skippedMorningKey) as? Date,
                  day >= Calendar.current.startOfDay(for: .now) else { return nil }
            return day
        }
        set {
            UserDefaults.standard.set(newValue.map { Calendar.current.startOfDay(for: $0) }, forKey: Self.skippedMorningKey)
        }
    }

    private static let skipReplacementKey = "skipReplacement"

    /// Your own time for the skipped morning, kept until it has passed.
    var skipReplacement: SkipReplacement? {
        get {
            guard skippedMorning != nil,
                  let data = UserDefaults.standard.data(forKey: Self.skipReplacementKey),
                  let replacement = try? JSONDecoder().decode(SkipReplacement.self, from: data),
                  replacement.wake > .now else { return nil }
            return replacement
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.skipReplacementKey)
        }
    }

    /// Skipping the night before means that morning's wake-up doesn't exist: its alarms go,
    /// Home Assistant turns the wake failsafe off for a skipped shift, and later plans don't
    /// bring it back. Then you either sleep in or get your own alarms. Temporary alarms stay.
    /// (Stopping alarms in the morning is different and always keeps the failsafe.)
    func skipMorning(_ plan: WakePlan?, morning: Date, then choice: SkipChoice, settings phoneSettings: BridgeSettings) async throws -> WakePlan? {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        skippedMorning = morning
        skipReplacement = nil
        var skipped: [String: Any] = ["morning": Self.iso(morning), "sleep_in": choice == .sleepIn]
        if plan?.source == .shift, let shift = plan?.shift {
            skipped["shift"] = shift.cause
            skipped["shift_start"] = Self.iso(shift.start)
        }
        // Sent before anything else, so the failsafe is off before the alarms are.
        await report(.skipped, data: skipped, settings: settings)
        try alarms.cancelAll(keeping: keptAlarms)
        leaveReminder.clear()
        updateWidget { $0 = NextAlarmSnapshot(alarmStyle: settings.alarmStyle.rawValue, temporaryAlarms: temporaryAlarms.map(\.time)) }
        lastCause = AlarmCause.none
        guard case .wakeAt(let time, let wakeIs) = choice else { return nil }
        let replacement = SkipReplacement(wake: Self.nextOccurrence(ofTimeIn: time), wakeIs: wakeIs)
        skipReplacement = replacement
        let manual = manualPlan(replacement, settings: settings)
        try await apply(manual, settings: settings)
        return manual
    }

    /// Undoes the skip and plans again, so the alarms (and the failsafe) come back if they
    /// still apply.
    func unskipMorning(settings: BridgeSettings) async throws -> WakePlan {
        await report(.unskipped, data: [:], settings: settings.applying(HomeAssistantLinks.cachedSettings))
        skippedMorning = nil
        skipReplacement = nil
        return try await planAndSchedule(settings: settings)
    }

    /// A skipped morning plans nothing, or your own time if you picked one.
    private func adjustedForSkip(_ plan: WakePlan, settings: BridgeSettings) -> WakePlan {
        if let replacement = skipReplacement { return manualPlan(replacement, settings: settings) }
        return PlanAdjustments.skipping(plan, morning: skippedMorning)
    }

    private func manualPlan(_ replacement: SkipReplacement, settings: BridgeSettings) -> WakePlan {
        let times = WakePlanner.alarmTimes(
            wakeTime: replacement.wake,
            count: settings.alarmCount,
            spacingMinutes: settings.alarmSpacingMinutes,
            wakeIs: replacement.wakeIs
        )
        var plan = WakePlan(source: .manual, wakeTime: replacement.wake, alarmTimes: times, reason: "Your own time")
        if skippedMorning != nil {
            plan.reason = "Your own time; the planned wake-up was skipped"
        }
        return plan
    }

    // MARK: Undo bedtime

    /// Up again after bedtime ran: the regular alarms go (temporary ones stay), and Home
    /// Assistant disarms the house, puts Awake For Day back on and Sleep In off. Once you're
    /// back in bed it runs bedtime again. Unlike a skip, the next plan sets alarms as usual.
    func undoBedtime(settings phoneSettings: BridgeSettings) async throws {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        try alarms.cancelAll(keeping: keptAlarms)
        leaveReminder.clear()
        updateWidget { $0 = NextAlarmSnapshot(alarmStyle: settings.alarmStyle.rawValue, temporaryAlarms: temporaryAlarms.map(\.time)) }
        lastCause = AlarmCause.none
        await report(.bedtimeUndone, data: [:], settings: settings)
    }

    // MARK: Away bedtime

    /// Bedtime away from home: your alarms, tomorrow's weather where you are, and whether
    /// home is all right. Changes nothing (no disarming, no routine, no Sleep In).
    func awaySummary(houseAlarm: String?, signOff: String, settings phoneSettings: BridgeSettings) async -> String {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        let alarms = scheduledAlarmTimes().filter { $0 > .now }
        let temporary = temporaryAlarms.map(\.time).filter { $0 > .now }
        let wakeDay = alarms.min() ?? (Calendar.current.component(.hour, from: .now) < 5 ? Date.now : Date.now.addingTimeInterval(86400))
        var weather: AwaySummary.Weather?
        if let here = try? await CurrentLocation.fetch(), let hours = try? await OpenMeteoForecast().hourly(at: here) {
            weather = AwaySummary.weather(from: hours, wakeDay: wakeDay)
        }
        let issues = await HomeAssistantLinks.current(settings)?.homeIssues(settings: settings)
        return AwaySummary.text(alarms: alarms, temporary: temporary, weather: weather, houseAlarm: houseAlarm, homeIssues: issues, signOff: signOff)
    }

    // MARK: Temporary alarms

    private static let temporaryKey = "temporaryAlarms.v1"

    /// Temporary wake-ups still to ring (or ringing), earliest first.
    var temporaryAlarms: [TemporaryAlarm] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.temporaryKey),
                  let saved = try? JSONDecoder().decode([TemporaryAlarm].self, from: data) else { return [] }
            let live = Set(alarms.scheduledAlarms().map(\.id))
            return saved.filter { live.contains($0.id) }.sorted { $0.time < $1.time }
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.temporaryKey)
        }
    }

    /// Alarms that replacing or cancelling the regular series must leave alone.
    private var keptAlarms: Set<UUID> {
        Set(temporaryAlarms.map(\.id)).union([testAlarmID].compactMap { $0 })
    }

    /// One extra alarm beside the regular ones. A time already past today means tomorrow.
    func setTemporaryAlarm(at time: Date, disarmHouse: Bool, settings phoneSettings: BridgeSettings) async throws -> TemporaryAlarm {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        let when = Self.nextOccurrence(ofTimeIn: time)
        let id = try await alarms.scheduleSingle(at: when, title: "Temporary wake-up", cause: AlarmCause.temporary, snoozeMinutes: settings.snoozeMinutes)
        let alarm = TemporaryAlarm(id: id, time: when, disarmHouse: disarmHouse)
        temporaryAlarms = temporaryAlarms + [alarm]
        updateWidget { $0.temporaryAlarms = temporaryAlarms.map(\.time) }
        return alarm
    }

    func cancelTemporaryAlarm(_ id: UUID) {
        alarms.cancel(id)
        temporaryAlarms = temporaryAlarms.filter { $0.id != id }
        updateWidget { $0.temporaryAlarms = temporaryAlarms.map(\.time) }
    }

    /// Plans and sets alarms. If planning fails (calendar access off, an error), it falls
    /// back to Home Assistant's next shift; if that isn't available either, it tells HA the
    /// plan failed (so the missing-plan blueprint can warn you) and rethrows.
    func planAndSchedule(settings: BridgeSettings) async throws -> WakePlan {
        let result: (WakePlan, BridgeSettings)
        do {
            result = try await makePlan(settings: settings, now: .now)
        } catch {
            guard let fallback = await fallbackPlan(settings: settings, error: error) else {
                await report(.planFailed, data: ["error": error.localizedDescription], settings: settings)
                throw error
            }
            result = fallback
        }
        let plan = adjustedForSkip(result.0, settings: result.1)
        try await apply(plan, settings: result.1)
        return plan
    }

    /// The work alarm from Home Assistant's next shift, for when the calendar can't be read.
    private func fallbackPlan(settings phoneSettings: BridgeSettings, error: Error) async -> (WakePlan, BridgeSettings)? {
        guard let link = HomeAssistantLinks.current(phoneSettings),
              let context = try? await link.context(settings: phoneSettings),
              let start = context.nextShiftStart else { return nil }
        let settings = phoneSettings.applying(context.settings)
        let now = Date.now
        guard start < now.addingTimeInterval(Double(settings.lookAheadHours) * 3600) else { return nil }
        let type = context.nextShiftType ?? ""
        let matched = settings.shiftRules.first { $0.keyword.caseInsensitiveCompare(type) == .orderedSame }
        // Unknown type: the earliest-waking minutes-before rule, so it errs early.
        let rule = matched ?? ShiftRule(
            keyword: type.isEmpty ? "Days" : type,
            wakeMinutesBefore: settings.shiftRules.map(\.wakeMinutesBefore).max() ?? 60
        )
        let shift = ShiftCandidate.make(title: type.isEmpty ? "Shift" : type, start: start, rule: rule).0
        var plan = WakePlanner.plan(shift: shift, appointments: [], settings: settings, now: now)
        guard plan.hasAlarm else { return nil }
        plan.atHome = context.atHome
        plan.warnings.insert(
            "Couldn't read your calendar (\(error.localizedDescription)), so this uses Home Assistant's next shift. Appointments weren't checked.",
            at: 0
        )
        return (plan, settings)
    }

    /// Returns the plan and the settings it was made with (the phone's settings with any
    /// adjusted in Home Assistant laid over them).
    private func makePlan(settings phoneSettings: BridgeSettings, now: Date) async throws -> (plan: WakePlan, settings: BridgeSettings) {
        try await calendar.ensureAccess()
        let link = HomeAssistantLinks.current(phoneSettings)
        var extraWarnings: [String] = []

        var context: HomeAssistantContext?
        if let link {
            do {
                context = try await link.context(settings: phoneSettings)
            } catch {
                extraWarnings.append("Couldn't reach Home Assistant: \(error.localizedDescription)")
            }
        }
        let settings = phoneSettings.applying(context?.settings ?? HomeAssistantLinks.cachedSettings)
        let end = now.addingTimeInterval(Double(settings.lookAheadHours) * 3600)

        let found = calendar.events(from: now, to: end, calendarIDs: settings.shiftCalendarIDs)
            .lazy
            .compactMap { event -> (ShiftCandidate, String?)? in
                guard let rule = WakePlanner.matchingRule(forTitle: event.title ?? "", rules: settings.shiftRules) else { return nil }
                var (candidate, warning) = ShiftCandidate.make(title: event.title ?? rule.keyword, start: event.startDate, rule: rule)
                candidate.location = event.location ?? ""
                candidate.latitude = event.structuredLocation?.geoLocation?.coordinate.latitude
                candidate.longitude = event.structuredLocation?.geoLocation?.coordinate.longitude
                return (candidate, warning)
            }
            .first
        var shift = found?.0
        extraWarnings += [found?.1].compactMap { $0 }

        if let context {
            let result = PlanAdjustments.applyShiftOverride(context.shiftOverride, to: shift, rules: settings.shiftRules)
            shift = result.shift
            extraWarnings += [result.warning].compactMap { $0 }
            let override = context.shiftOverride ?? "auto"
            if override.caseInsensitiveCompare("auto") == .orderedSame {
                extraWarnings += [PlanAdjustments.shiftMismatchWarning(calendarShift: shift, haNextShiftStart: context.nextShiftStart, lookAheadEnd: end)].compactMap { $0 }
            }
        }

        // Away (Home Assistant says so): drives start from where you are, not from home.
        startsFromHere = settings.driveFromHereWhenAway && context?.atHome == false
        if startsFromHere {
            extraWarnings.append("You're away, so drives start from where you are.")
        }
        let appointments = await appointmentCandidates(from: now, to: end, settings: settings)

        var plan = WakePlanner.plan(shift: shift, appointments: appointments, settings: settings, now: now)

        // Weather depends on the plan (wake-up until arrival), so check it second and re-plan.
        if settings.checksWeather, let window = travelWindow(for: plan),
           let source = weatherForecast(settings: settings, link: context == nil ? nil : link) {
            do {
                let (forecast, unit) = try await source()
                let freezing: Double? = settings.addTimeWhenFreezing ? ((unit ?? "°F").contains("C") ? 0 : 32) : nil
                if let adjustment = PlanAdjustments.weather(
                    forecast: forecast,
                    window: window,
                    conditions: settings.badWeatherConditions,
                    freezingAt: freezing,
                    extraMinutes: settings.weatherExtraMinutes,
                    minutes: settings.weatherConditionMinutes
                ) {
                    plan = WakePlanner.plan(shift: shift, appointments: appointments, settings: settings, now: now, weather: adjustment)
                }
            } catch {
                extraWarnings.append("Couldn't check the weather: \(error.localizedDescription)")
            }
        }

        // Shift alarms keep their rule's timing; the drive only says when to leave.
        if plan.source == .shift, let shift = plan.shift, !shift.location.trimmingCharacters(in: .whitespaces).isEmpty {
            plan.commute = await commute(to: shift, settings: settings)
            // Bad weather slows the drive to work too, as it does an appointment's.
            if let weather = plan.weather { plan.commute?.travelSeconds += Double(weather.minutes) * 60 }
            if settings.wakeEarlyToGetReady, let short = plan.getReadyShortfall(settings: settings), short.earlierWake > now {
                plan = plan.waking(at: short.earlierWake)
                extraWarnings.append("Alarm moved to \(WakePlanner.format(short.earlierWake)) so you have \(settings.getReadyMinutes) min to get ready before leaving at \(WakePlanner.format(short.leaveBy)).")
            }
        }

        plan.atHome = context?.atHome
        if context?.atHome == false {
            extraWarnings.append("You're not home, so Home Assistant won't run your wake-up or bedtime routines.")
        }
        plan.warnings = extraWarnings + plan.warnings
        return (plan, settings)
    }

    /// Tonight only: the plan's alarms moved to `wake` (earlier, to have time to get ready).
    func wakeEarlier(_ plan: WakePlan, to wake: Date, settings phoneSettings: BridgeSettings) async throws -> WakePlan {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        var moved = plan.waking(at: wake)
        moved.warnings.insert("Alarm moved to \(WakePlanner.format(wake)) for tonight, so you have time to get ready.", at: 0)
        try await apply(moved, settings: settings)
        return moved
    }

    /// For the day-off path: you pick the time, the app sets the usual alarm series.
    /// For the day-off path: you pick the time, the app sets the usual alarm series. The
    /// time is the first or last alarm (`wakeIs`, or Settings' choice when nil).
    func scheduleManual(wakeTime: Date, wakeIs: WakeTimeAlarm? = nil, settings phoneSettings: BridgeSettings) async throws -> WakePlan {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        let wake = Self.nextOccurrence(ofTimeIn: wakeTime)
        let replacement = SkipReplacement(wake: wake, wakeIs: wakeIs ?? settings.wakeTimeIs)
        var plan = manualPlan(replacement, settings: settings)
        if let skipped = skippedMorning, Calendar.current.isDate(skipped, inSameDayAs: wake) {
            // Your own time for a skipped morning: the skip (and its failsafe-off) stands.
            skipReplacement = replacement
        } else {
            skippedMorning = nil
            plan.reason = "Day off alarm"
        }
        try await apply(plan, settings: settings)
        return plan
    }

    func cancelAlarms(settings: BridgeSettings) async throws {
        try alarms.cancelAll(keeping: keptAlarms)
        leaveReminder.clear()
        updateWidget { $0 = NextAlarmSnapshot(alarmStyle: settings.alarmStyle.rawValue, temporaryAlarms: temporaryAlarms.map(\.time)) }
        lastCause = AlarmCause.none
        await report(.cancelled, data: [:], settings: settings)
    }

    /// Sets (or clears) alarms, the leave-by reminder and the HA sensor for a plan.
    private func apply(_ plan: WakePlan, settings: BridgeSettings) async throws {
        if plan.hasAlarm, settings.alarmStyle == .app {
            try await alarms.replaceAlarms(
                with: plan.alarmTimes,
                title: alarmTitle(for: plan),
                cause: plan.cause,
                snoozeMinutes: settings.snoozeMinutes,
                keeping: keptAlarms
            )
        } else {
            // No alarm, or the shortcut is making Clock alarms: don't leave old app alarms ringing.
            try alarms.cancelAll(keeping: keptAlarms)
        }

        if settings.leaveReminderEnabled, let trip = Self.trip(for: plan, settings: settings) {
            await leaveReminder.schedule(trip, leadMinutes: settings.leaveReminderLeadMinutes)
        } else {
            leaveReminder.clear()
        }

        // Ask about appointments saved without a location: by notification, so the bedtime
        // shortcut (which runs with nobody tapping) never waits on an answer.
        if settings.askAboutMissingLocations {
            await LocationQuestions.ask(about: plan.missingLocations)
        }

        updateWidget { snapshot in
            snapshot = NextAlarmSnapshot(
                alarmTimes: plan.alarmTimes,
                cause: plan.cause,
                label: plan.label,
                leaveBy: plan.leaveBy(settings: settings),
                alarmStyle: settings.alarmStyle.rawValue,
                temporaryAlarms: temporaryAlarms.map(\.time),
                wakeTime: plan.wakeTime,
                reason: plan.reason
            )
        }

        lastCause = plan.cause
        var payload = plan.homeAssistantPayload(settings: settings)
        payload["app_settings"] = settings.homeAssistantSettings
        await report(.planned, data: payload, settings: settings)
    }

    /// The morning's drive, for the leave-by reminder: an appointment with a place, or a
    /// shift whose event has one.
    private static func trip(for plan: WakePlan, settings: BridgeSettings) -> PendingTrip? {
        switch plan.source {
        case .appointment:
            guard let appointment = plan.appointment, appointment.hasLocation else { return nil }
            return PendingTrip(
                title: appointment.title,
                location: appointment.location,
                start: appointment.start,
                arriveBy: appointment.arriveBy(bufferMinutes: settings.arrivalBufferMinutes),
                plannedTravelSeconds: appointment.travelSeconds,
                latitude: appointment.latitude,
                longitude: appointment.longitude
            )
        case .shift:
            guard let shift = plan.shift, let commute = plan.commute else { return nil }
            return PendingTrip(
                title: shift.title,
                location: shift.location,
                start: shift.start,
                arriveBy: shift.start.addingTimeInterval(-Double(settings.workArrivalBufferMinutes) * 60),
                plannedTravelSeconds: commute.travelSeconds,
                latitude: commute.latitude,
                longitude: commute.longitude
            )
        case .manual, .none:
            return nil
        }
    }

    // MARK: Missing locations

    private static let noLocationKey = "noLocationNeededEventIDs"

    /// Events you said don't need a location (a call, working from home).
    private var noLocationNeeded: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.noLocationKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.noLocationKey) }
    }

    func markNoLocationNeeded(_ appointment: AppointmentCandidate) {
        guard let id = appointment.eventID else { return }
        markNoLocationNeeded(eventID: id)
    }

    func markNoLocationNeeded(eventID: String) {
        noLocationNeeded.insert(eventID)
        LocationQuestions.clear(eventID: eventID)
    }

    func isNoLocationNeeded(eventID: String) -> Bool {
        noLocationNeeded.contains(eventID)
    }

    /// Undoes "No location needed", so the next plan asks about it again.
    func clearNoLocationNeeded(eventID: String) {
        noLocationNeeded.remove(eventID)
    }

    private static let noWakeUpKey = "noWakeUpNeededOccurrences"

    /// Upcoming events you've said don't need a wake-up, so the list stops flagging them.
    /// Keyed per occurrence, since a repeating event's occurrences share one identifier.
    private var noWakeUpNeeded: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.noWakeUpKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.noWakeUpKey) }
    }

    func isNoWakeUpNeeded(occurrence: String) -> Bool {
        noWakeUpNeeded.contains(occurrence)
    }

    func setNoWakeUpNeeded(_ ignored: Bool, occurrence: String) {
        if ignored { noWakeUpNeeded.insert(occurrence) } else { noWakeUpNeeded.remove(occurrence) }
    }

    func setNoLocationNeeded(_ ignored: Bool, eventID: String) {
        if ignored { markNoLocationNeeded(eventID: eventID) } else { clearNoLocationNeeded(eventID: eventID) }
    }

    /// Saves the location on the calendar event, so the next plan gets a real drive time.
    func addLocation(_ location: String, to appointment: AppointmentCandidate) throws {
        guard let id = appointment.eventID else { return }
        try addLocation(location, eventID: id)
    }

    func addLocation(_ location: String, eventID: String) throws {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try calendar.setLocation(trimmed, eventID: eventID)
        LocationQuestions.clear(eventID: eventID)
    }

    // MARK: Test alarm

    private static let testAlarmKey = "testAlarmID"

    private var testAlarmID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.testAlarmKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.testAlarmKey) }
    }

    /// One alarm in two minutes that runs your real snooze and stop routines, so the whole
    /// chain (alarm → app → Home Assistant → lights) can be checked in the afternoon.
    /// Tonight's alarms and plan are left alone.
    func scheduleTestAlarm(settings phoneSettings: BridgeSettings) async throws -> Date {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        if let old = testAlarmID { alarms.cancel(old) }
        let time = Date.now.addingTimeInterval(120)
        testAlarmID = try await alarms.scheduleTest(at: time, snoozeMinutes: settings.snoozeMinutes)
        return time
    }

    /// The regular series (the test alarm and temporary wake-ups left out).
    func scheduledAlarmTimes() -> [Date] {
        let kept = keptAlarms
        return alarms.scheduledAlarms().filter { !kept.contains($0.id) }.map(\.date)
    }

    // MARK: Alarm buttons (app alarms only)

    func alarmSnoozed(id: UUID, settings phoneSettings: BridgeSettings) async {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        alarms.snooze(id)
        if id == testAlarmID {
            await report(.snoozed, data: ["test": true], settings: settings)
            return
        }
        if temporaryAlarms.contains(where: { $0.id == id }) {
            // Quiet: no wake ramp, nothing in the house changes for a temporary alarm.
            let ringsAgain = Date.now.addingTimeInterval(Double(settings.snoozeMinutes) * 60)
            updateWidget { $0.snoozedUntil = ringsAgain }
            await report(.temporarySnoozed, data: ["rings_again": Self.iso(ringsAgain)], settings: settings)
            return
        }
        let ringsAgain = Date.now.addingTimeInterval(Double(settings.snoozeMinutes) * 60)
        updateWidget { snapshot in
            snapshot.snoozedUntil = ringsAgain
            snapshot.alarmTimes = scheduledAlarmTimes()
        }
        await report(.snoozed, data: [
            "rings_again": Self.iso(ringsAgain),
            "alarm_time": Self.iso(ringsAgain),
            "alarm_cause": lastCause,
            "alarm_times": scheduledAlarmTimes().map(Self.iso),
        ], settings: settings)
    }

    func alarmStopped(id: UUID, settings phoneSettings: BridgeSettings) async {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        alarms.stop(id)
        if id == testAlarmID {
            testAlarmID = nil
            await report(.stopped, data: ["test": true], settings: settings)
            return
        }
        if let temporary = temporaryAlarms.first(where: { $0.id == id }) {
            // Back to bed afterwards: Awake For Day, Sleep In and the regular alarms stay.
            // Home Assistant disarms (and re-arms once you're back in bed) if you chose that.
            temporaryAlarms = temporaryAlarms.filter { $0.id != id }
            updateWidget { snapshot in
                snapshot.snoozedUntil = nil
                snapshot.temporaryAlarms = temporaryAlarms.map(\.time)
            }
            await report(.temporaryStopped, data: [
                "house_alarm": temporary.houseAlarm,
                "alarm_times": scheduledAlarmTimes().filter { $0 > .now }.map(Self.iso),
            ], settings: settings)
            return
        }
        switch settings.stopBehavior {
        case .cancelRest:
            alarms.cancelAll(except: id, keeping: keptAlarms)
        case .keepAll:
            break
        case .keepUntilUp:
            // Only once HA confirms you're up. Still in bed, HA unreachable or no sensors:
            // the later alarms stay as your phone's own backstop.
            if await HomeAssistantLinks.current(settings)?.isUp(settings: settings) == true {
                alarms.cancelAll(except: id, keeping: keptAlarms)
            }
        }
        let remaining = scheduledAlarmTimes().filter { $0 > .now }
        updateWidget { snapshot in
            snapshot.snoozedUntil = nil
            snapshot.alarmTimes = remaining
        }
        if remaining.isEmpty { lastCause = AlarmCause.none }
        var stopped: [String: Any] = ["alarm_times": remaining.map(Self.iso), "alarm_cause": lastCause]
        stopped["alarm_time"] = remaining.first.map(Self.iso)
        await report(.stopped, data: stopped, settings: settings)

        if settings.leaveReminderEnabled, leaveReminder.pendingTrip != nil,
           let provider = try? travel.provider(for: settings),
           let origin = try? await origin(settings: settings) {
            await leaveReminder.recheck(using: provider, origin: origin, travel: travel, leadMinutes: settings.leaveReminderLeadMinutes)
            updateWidget { $0.leaveBy = leaveReminder.pendingTrip?.leaveBy }
            if let trip = leaveReminder.pendingTrip {
                await report(.leaveBy, data: [
                    "leave_by": Self.iso(trip.leaveBy),
                    "drive_minutes": Int((trip.plannedTravelSeconds / 60).rounded()),
                ], settings: settings)
            }
        }
    }

    // MARK: Bedtime and Clock app alarms

    /// Starts the bedtime routine in Home Assistant unless you're away.
    /// Returns whether it started, so the shortcut can branch.
    func startBedtime(settings: BridgeSettings) async throws -> (started: Bool, atHome: Bool) {
        guard let link = HomeAssistantLinks.current(settings) else { throw BridgeError.homeAssistantNotSetUp }
        return try await link.startBedtime(settings: settings)
    }

    /// Clock app mode: the Shortcuts "Alarm is snoozed/stopped" automations call this instead
    /// of flipping the helpers through HomeKit, so the home check and events still apply.
    func clockAlarmEvent(_ event: BridgeEvent, settings phoneSettings: BridgeSettings) async {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        var data: [String: Any] = ["alarm_cause": lastCause]
        if event == .snoozed {
            let ringsAgain = Date.now.addingTimeInterval(9 * 60)  // Clock app snooze is fixed by Apple
            data["rings_again"] = Self.iso(ringsAgain)
            updateWidget { $0.snoozedUntil = ringsAgain }
        } else {
            updateWidget { $0.snoozedUntil = nil }
        }
        await report(event, data: data, settings: settings)
    }

    // MARK: Other

    func drivingMinutes(to destination: String, arrivingAt arrival: Date, settings: BridgeSettings) async throws -> Int {
        let origin = try await travel.origin(homeAddress: settings.homeAddress)
        let target = try await travel.destination(locationText: destination, coordinates: nil)
        let seconds = try await travel.provider(for: settings).drivingTime(from: origin, to: target, arrivingBy: arrival)
        return Int((seconds / 60).rounded())
    }

    /// Shortcuts' "Ask for Input" with a time often returns today's date; a time that has
    /// already passed today means tomorrow morning.
    nonisolated static func nextOccurrence(ofTimeIn date: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        guard date <= now else { return date }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? date
    }

    // MARK: Private

    private static let lastCauseKey = "lastAlarmCause"

    /// Cause of the alarms currently set, remembered for snooze/stop updates in the morning.
    private var lastCause: String {
        get { UserDefaults.standard.string(forKey: Self.lastCauseKey) ?? AlarmCause.none }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastCauseKey) }
    }

    private static let startsFromHereKey = "drivesStartFromHere"

    /// The last plan was made away from home, so drives (and the morning recheck) start
    /// from where the phone is.
    private var startsFromHere: Bool {
        get { UserDefaults.standard.bool(forKey: Self.startsFromHereKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.startsFromHereKey) }
    }

    private func origin(settings: BridgeSettings) async throws -> MKMapItem {
        try await travel.origin(homeAddress: settings.homeAddress, fromHere: startsFromHere)
    }

    private func appointmentCandidates(from now: Date, to end: Date, settings: BridgeSettings) async -> [AppointmentCandidate] {
        let allEvents = calendar.events(from: now, to: end, calendarIDs: settings.appointmentCalendarIDs)
            .filter { WakePlanner.notesRequestWakeUp($0.notes, keyword: settings.appointmentKeyword) }
        let hasPlace = { (event: EKEvent) in !(event.location ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

        // No location: if you've said it needs none, no drive. Otherwise plan the fallback
        // drive (so it errs early) and ask by notification, which never blocks the shortcut.
        let skipAsking = noLocationNeeded
        var candidates: [AppointmentCandidate] = allEvents.filter { !hasPlace($0) }.map { event in
            let confirmed = skipAsking.contains(event.eventIdentifier ?? "")
            return AppointmentCandidate(
                title: event.title ?? "Appointment",
                start: event.startDate,
                location: "",
                travelSeconds: confirmed ? 0 : Double(settings.fallbackTravelMinutes) * 60,
                eventID: event.eventIdentifier,
                hasLocation: false,
                askAboutLocation: !confirmed
            )
        }

        let events = allEvents.filter(hasPlace)
        guard !events.isEmpty else { return candidates }

        // A missing origin or API key becomes the fallback reason on each appointment.
        let route: Result<(MKMapItem, DriveTimeComparison), Error>
        do {
            route = .success((try await origin(settings: settings), try travel.provider(for: settings)))
        } catch {
            route = .failure(error)
        }

        for event in events {
            candidates.append(await appointmentCandidate(for: event, route: route, settings: settings))
        }
        return candidates
    }

    private func appointmentCandidate(
        for event: EKEvent,
        route: Result<(MKMapItem, DriveTimeComparison), Error>,
        settings: BridgeSettings
    ) async -> AppointmentCandidate {
        var candidate = AppointmentCandidate(
            title: event.title ?? "Appointment",
            start: event.startDate,
            location: event.location ?? "",
            travelSeconds: Double(settings.fallbackTravelMinutes) * 60,
            eventID: event.eventIdentifier
        )
        do {
            let (origin, provider) = try route.get()
            let destination = try await travel.destination(locationText: candidate.location, coordinates: event.structuredLocation?.geoLocation)
            candidate.latitude = destination.location.coordinate.latitude
            candidate.longitude = destination.location.coordinate.longitude
            let drive = try await provider.compare(
                from: origin,
                to: destination,
                arrivingBy: candidate.arriveBy(bufferMinutes: settings.arrivalBufferMinutes)
            )
            candidate.travelSeconds = drive.seconds
            candidate.driveEstimates = drive.estimates
        } catch {
            candidate.fallbackReason = error.localizedDescription
        }
        return candidate
    }

    /// The forecast fetch for the chosen source, or nil when it can't be reached
    /// (Home Assistant chosen but not connected).
    private func weatherForecast(settings: BridgeSettings, link: HomeAssistantLink?) -> (() async throws -> (hours: [ForecastHour], temperatureUnit: String?))? {
        switch settings.weatherSource {
        case .homeAssistant:
            guard let link else { return nil }
            return { try await link.forecast(settings: settings) }
        case .openMeteo:
            return { [travel] in
                let place = try await Self.weatherLocation(homeAddress: settings.homeAddress, travel: travel)
                return (try await OpenMeteoForecast().hourly(at: place), "°C")
            }
        }
    }

    /// Home, for the forecast: the home address, or where the phone is when that's blank.
    private static func weatherLocation(homeAddress: String, travel: TravelTimeService) async throws -> CLLocation {
        let item = try await travel.origin(homeAddress: homeAddress)
        return item.isCurrentLocation ? try await CurrentLocation.fetch() : item.location
    }

    /// The drive from home to the shift's location, arriving the work buffer early.
    private func commute(to shift: ShiftCandidate, settings: BridgeSettings) async -> Commute {
        let arriveBy = shift.start.addingTimeInterval(-Double(settings.workArrivalBufferMinutes) * 60)
        var commute = Commute(travelSeconds: Double(settings.fallbackTravelMinutes) * 60)
        do {
            let provider = try travel.provider(for: settings)
            let origin = try await origin(settings: settings)
            let saved = shift.latitude.flatMap { lat in shift.longitude.map { CLLocation(latitude: lat, longitude: $0) } }
            let destination = try await travel.destination(locationText: shift.location, coordinates: saved)
            commute.latitude = destination.location.coordinate.latitude
            commute.longitude = destination.location.coordinate.longitude
            let drive = try await provider.compare(from: origin, to: destination, arrivingBy: arriveBy)
            commute.travelSeconds = drive.seconds
            commute.driveEstimates = drive.estimates
        } catch {
            commute.fallbackReason = error.localizedDescription
        }
        return commute
    }

    /// From the first alarm until you need to be there: the hours worth checking the weather for.
    private func travelWindow(for plan: WakePlan) -> ClosedRange<Date>? {
        guard let first = plan.firstAlarm else { return nil }
        // A fixed-time shift alarm doesn't move for weather (see WakePlanner).
        if plan.source == .shift, plan.shift?.fixedWake != nil { return nil }
        let arrival = plan.source == .appointment ? plan.appointment?.start : plan.shift?.start
        guard let arrival, arrival > first else { return nil }
        return first...arrival
    }

    /// Saves what the Lock Screen widget shows and asks WidgetKit to redraw it.
    private func updateWidget(_ change: (inout NextAlarmSnapshot) -> Void) {
        var snapshot = NextAlarmSnapshot.load()
        change(&snapshot)
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func alarmTitle(for plan: WakePlan) -> String {
        switch plan.source {
        case .shift: "Wake up for \(plan.shift?.cause ?? "work")"
        case .appointment: "Wake up for \(plan.appointment?.title ?? "your appointment")"
        case .manual, .none: "Wake up"
        }
    }

    /// Tells Home Assistant. Best effort: HA being down never stops alarms from being set.
    private func report(_ event: BridgeEvent, data: [String: Any], settings: BridgeSettings) async {
        guard let link = HomeAssistantLinks.current(settings) else { return }
        try? await link.report(event, data: data, settings: settings)
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
