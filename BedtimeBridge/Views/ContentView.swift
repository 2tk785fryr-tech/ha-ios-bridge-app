import EventKit
import SwiftUI

/// "Tonight": the plan, the alarm series and the two main actions, in the Nightfall style.
struct ContentView: View {
    @Environment(SettingsStore.self) private var store
    @State private var plan: WakePlan?
    @State private var scheduled: [Date] = []
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var pairingMessage: String?
    @State private var needsALookCount: Int?
    @State private var skippedMorning: Date?
    @State private var stoppingAlarm: SnoozedAlarm?
    @State private var skipReplacement: SkipReplacement?
    @State private var temporaryAlarms: [TemporaryAlarm] = []
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case temporary, dayOff, skipToTime
        var id: String { rawValue }
    }

    private let coordinator = BedtimeCoordinator.shared

    /// Phone settings with any times adjusted in Home Assistant, as the last plan used them.
    private var settings: BridgeSettings { store.settings.applying(HomeAssistantLinks.cachedSettings) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let skippedMorning {
                        SkippedMorningCard(morning: skippedMorning, replacement: skipReplacement, undo: unskip)
                    }

                    if let count = needsALookCount, count > 0 {
                        NavigationLink {
                            UpcomingEventsView()
                        } label: {
                            UpcomingEventsBanner(count: count)
                        }
                        .buttonStyle(.plain)
                    }

                    if let plan {
                        PlanCard(plan: plan)
                        if let weather = plan.weather {
                            WarningBanner(text: "+\(weather.minutes) min for \(weather.reason)", systemImage: "cloud.rain")
                        }
                        if plan.source == .appointment, let appointment = plan.appointment, let wake = plan.wakeTime {
                            MorningTimeline(appointment: appointment, weather: plan.weather, wake: wake, bufferMinutes: settings.arrivalBufferMinutes)
                        }
                        if let short = plan.getReadyShortfall(settings: settings), short.earlierWake > .now {
                            GetReadyCard(minutes: short.minutes, wanted: settings.getReadyMinutes, leaveBy: short.leaveBy, earlierWake: short.earlierWake) {
                                wakeEarlier(plan, to: short.earlierWake)
                            }
                        }
                        if plan.source == .shift, let shift = plan.shift, let commute = plan.commute, let wake = plan.wakeTime {
                            MorningTimeline(shift: shift, commute: commute, weather: plan.weather, wake: wake, bufferMinutes: settings.workArrivalBufferMinutes, getReadyGoal: settings.getReadyMinutes)
                        }
                        ForEach(plan.missingLocations, id: \.eventID) { appointment in
                            MissingLocationCard(appointment: appointment) { location in
                                Task { await addLocation(location, to: appointment) }
                            } noLocationNeeded: {
                                coordinator.markNoLocationNeeded(appointment)
                                self.plan?.missingLocations.removeAll { $0.eventID == appointment.eventID }
                            }
                        }
                    } else {
                        EmptyPlanCard(scheduled: scheduled)
                    }

                    if let errorMessage {
                        WarningBanner(text: errorMessage, systemImage: "exclamationmark.triangle", tint: Theme.danger)
                    }

                    StatusCard(settings: settings, plan: plan)

                    if let plan, !plan.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(plan.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "info.circle")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.warning.text)
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    if skippedMorning == nil, let morning = scheduled.first ?? plan?.firstAlarm {
                        ScheduledAlarmsCard(times: store.settings.alarmStyle == .app ? scheduled : [], morning: morning, isShift: plan?.source == .shift) {
                            skip(morning, then: .sleepIn)
                        } differentTime: {
                            sheet = .skipToTime
                        }
                    } else if skippedMorning == nil, scheduled.isEmpty, plan?.hasAlarm != true {
                        DayOffCard { sheet = .dayOff }
                    }

                    if store.settings.alarmStyle == .app {
                        TemporaryAlarmsCard(alarms: temporaryAlarms) {
                            sheet = .temporary
                        } remove: { id in
                            coordinator.cancelTemporaryAlarm(id)
                            refreshScheduled()
                        }
                    }

                    if let plan {
                        Text("alarm_cause → \(plan.cause)")
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textFaint)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { actions }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: refreshScheduled)
            // bedtimebridge://replan, from Home Assistant's "plan out of date" and
            // "missing plan" notifications.
            .onOpenURL { url in
                if url.host == "replan" { run(schedule: true) }
                // bedtimebridge://pair?…, tapped on the integration's pairing screen.
                if url.host == "pair" {
                    pairingMessage = HomeAssistantLinks.pair(with: url)
                        ? "Paired with Home Assistant."
                        : "That pairing link didn't contain an address."
                }
                // bedtimebridge://stop?id=…, from Stop on the snooze countdown.
                if url.host == "stop",
                   let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value.flatMap(UUID.init) {
                    stoppingAlarm = SnoozedAlarm(id: id)
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .temporary:
                    TemporaryAlarmSheet { time, disarm in setTemporary(time, disarmHouse: disarm) }
                case .dayOff:
                    WakeTimeSheet(
                        title: "Day off alarm",
                        note: "Uses your usual number of alarms and spacing.",
                        confirm: "Set",
                        settings: settings
                    ) { time, wakeIs in setDayOff(time, wakeIs: wakeIs) }
                case .skipToTime:
                    WakeTimeSheet(
                        title: "Wake at a different time",
                        note: "Replaces the planned wake-up. For a shift, the wake failsafe is off for that morning.",
                        confirm: "Set",
                        settings: settings
                    ) { time, wakeIs in
                        if let morning = scheduled.first ?? plan?.firstAlarm { skip(morning, then: .wakeAt(time, wakeIs)) }
                    }
                }
            }
            .fullScreenCover(item: $stoppingAlarm) { alarm in
                SlideToStopView {
                    await coordinator.alarmStopped(id: alarm.id, settings: store.settings)
                    refreshScheduled()
                }
            }
            .alert(pairingMessage ?? "", isPresented: Binding(get: { pairingMessage != nil }, set: { if !$0 { pairingMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nightName)
                    .font(.footnote.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.textMuted)
                Text("Tonight")
                    .font(.sora(30, .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            NavigationLink {
                UpcomingEventsView()
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.accentIcon)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel("Upcoming events")
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.accentIcon)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    /// "SATURDAY NIGHT", still Saturday at 1:30 AM after a swing shift.
    private var nightName: String {
        let night = Calendar.current.component(.hour, from: .now) < 5
            ? Date.now.addingTimeInterval(-6 * 3600)
            : Date.now
        return night.formatted(.dateTime.weekday(.wide)).uppercased() + " NIGHT"
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { run(schedule: true) } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "alarm")
                    }
                    Text(primaryTitle)
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Button { run(schedule: false) } label: {
                Text("Preview plan")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }
        }
        .disabled(isWorking)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.ground)
    }

    private var primaryTitle: String {
        if let wake = plan?.wakeTime, plan?.hasAlarm == true {
            return "Set \(plan?.alarmTimes.count ?? settings.alarmCount) alarms, up by \(WakePlanner.format(wake))"
        }
        return "Plan and set alarms"
    }

    private func run(schedule: Bool) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                plan = schedule
                    ? try await coordinator.planAndSchedule(settings: store.settings)
                    : try await coordinator.buildPlan(settings: store.settings)
            } catch {
                errorMessage = error.localizedDescription
            }
            refreshScheduled()
        }
    }

    private func refreshScheduled() {
        scheduled = coordinator.scheduledAlarmTimes()
        skippedMorning = coordinator.skippedMorning
        skipReplacement = coordinator.skipReplacement
        temporaryAlarms = coordinator.temporaryAlarms
        refreshUpcoming()
    }

    /// The night before: that morning's wake-up doesn't happen (failsafe off for a shift), and
    /// you sleep in or wake at your own time. Later plans don't bring it back.
    private func skip(_ morning: Date, then choice: SkipChoice) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                let replacement = try await coordinator.skipMorning(plan, morning: morning, then: choice, settings: store.settings)
                plan = replacement ?? plan.map { PlanAdjustments.skipping($0, morning: morning) }
            } catch {
                errorMessage = error.localizedDescription
            }
            refreshScheduled()
        }
    }

    private func setDayOff(_ time: Date, wakeIs: WakeTimeAlarm) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                plan = try await coordinator.scheduleManual(wakeTime: time, wakeIs: wakeIs, settings: store.settings)
            } catch {
                errorMessage = error.localizedDescription
            }
            refreshScheduled()
        }
    }

    private func setTemporary(_ time: Date, disarmHouse: Bool) {
        errorMessage = nil
        Task {
            do {
                _ = try await coordinator.setTemporaryAlarm(at: time, disarmHouse: disarmHouse, settings: store.settings)
            } catch {
                errorMessage = error.localizedDescription
            }
            refreshScheduled()
        }
    }

    /// Tonight only: sets the alarms earlier so there's time to get ready.
    private func wakeEarlier(_ current: WakePlan, to wake: Date) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                plan = try await coordinator.wakeEarlier(current, to: wake, settings: store.settings)
            } catch {
                errorMessage = error.localizedDescription
            }
            refreshScheduled()
        }
    }

    private func unskip() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                plan = try await coordinator.unskipMorning(settings: store.settings)
            } catch {
                errorMessage = error.localizedDescription
                // The skip is gone either way, so show what the plan is now.
                plan = try? await coordinator.buildPlan(settings: store.settings)
            }
            refreshScheduled()
        }
    }

    /// Counted only once calendar access is allowed, so opening the app never prompts for it.
    private func refreshUpcoming() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            needsALookCount = nil
            return
        }
        needsALookCount = UpcomingEvent.load(from: coordinator.calendar, settings: store.settings).filter(\.needsALook).count
    }

    /// Saves the place on the calendar event, then plans again with a real drive time.
    private func addLocation(_ location: String, to appointment: AppointmentCandidate) async {
        do {
            try coordinator.addLocation(location, to: appointment)
            run(schedule: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: Plan card

private struct PlanCard: View {
    let plan: WakePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(plan.hasAlarm ? "Wake-up time" : "Tomorrow")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                if plan.hasAlarm { CauseChip(plan: plan) }
            }

            if let wake = plan.wakeTime ?? plan.firstAlarm {
                BigTime(date: wake)
            } else {
                Text("No alarm needed")
                    .font(.sora(34, .light, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.accentText)
            }

            Text(plan.reason)
                .font(.subheadline)
                .foregroundStyle(Theme.textSoft)

            if plan.alarmTimes.count > 1 {
                HStack(spacing: 8) {
                    // The highlighted pill is the wake-up time: last by default, or first.
                    ForEach(Array(plan.alarmTimes.enumerated()), id: \.offset) { _, time in
                        let isWake = time == plan.wakeTime
                        Text(time.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                            .font(.system(size: 15, weight: isWake ? .bold : .semibold))
                            .foregroundStyle(isWake ? .white : Theme.textSoft)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(isWake ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .nightfallCard(radius: 28, padding: 24)
    }
}

private struct BigTime: View {
    let date: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(.sora(fixed: 88, .light))
                .tracking(-2)
                .foregroundStyle(Theme.accentText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))).filter { $0.isLetter })
                .font(.sora(fixed: 24, .medium))
                .foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CauseChip: View {
    let plan: WakePlan

    var body: some View {
        let colors = plan.source == .appointment ? Theme.appointmentChip : Theme.shiftChip
        Label(plan.label, systemImage: icon)
            .font(.footnote.weight(.bold))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colors.background, in: Capsule())
    }

    private var icon: String {
        switch plan.source {
        case .shift: "briefcase"
        case .appointment: "calendar"
        case .manual: "hand.tap"
        case .none: "moon"
        }
    }
}

private struct EmptyPlanCard: View {
    let scheduled: [Date]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accentIcon)
            if let first = scheduled.first {
                Text("Alarms set from \(WakePlanner.format(first))")
                    .font(.sora(22, .semibold, relativeTo: .title2))
                    .foregroundStyle(Theme.text)
                Text("Preview to see why, or plan again if your calendar changed.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSoft)
            } else {
                Text("Nothing planned yet")
                    .font(.sora(22, .semibold, relativeTo: .title2))
                    .foregroundStyle(Theme.text)
                Text("Preview to check your shifts and \"wake up\" appointments.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSoft)
            }
        }
        .nightfallCard(radius: 28, padding: 24)
    }
}

// MARK: Appointment timeline

/// Wake → get ready → leave → arrive → start, for an appointment or a shift with a place.
private struct MorningTimeline: View {
    let title: String
    let start: Date
    let location: String
    /// False for an appointment with no location: no drive, just be ready.
    let hasLocation: Bool
    let travelSeconds: TimeInterval
    let estimates: [DriveEstimate]
    let fallbackReason: String?
    /// Extra time for bad weather, already included in `travelSeconds`.
    let weather: WeatherAdjustment?
    let wake: Date
    let bufferMinutes: Int
    /// The get-ready time from Settings; less than this is flagged.
    var getReadyGoal = 0

    init(appointment: AppointmentCandidate, weather: WeatherAdjustment?, wake: Date, bufferMinutes: Int) {
        title = appointment.title
        start = appointment.start
        location = appointment.location
        hasLocation = appointment.hasLocation
        travelSeconds = appointment.travelSeconds
        estimates = appointment.driveEstimates
        fallbackReason = appointment.fallbackReason
        self.weather = weather
        self.wake = wake
        self.bufferMinutes = bufferMinutes
    }

    init(shift: ShiftCandidate, commute: Commute, weather: WeatherAdjustment?, wake: Date, bufferMinutes: Int, getReadyGoal: Int) {
        title = "\(shift.title) starts"
        start = shift.start
        location = shift.location
        hasLocation = true
        travelSeconds = commute.travelSeconds
        estimates = commute.driveEstimates
        fallbackReason = commute.fallbackReason
        self.weather = weather
        self.wake = wake
        self.bufferMinutes = bufferMinutes
        self.getReadyGoal = getReadyGoal
    }

    var body: some View {
        let arrive = start.addingTimeInterval(-Double(bufferMinutes) * 60)
        let leaveBy = arrive.addingTimeInterval(-travelSeconds)
        let readyMinutes = Int(leaveBy.timeIntervalSince(wake) / 60)
        let driveMinutes = Int((travelSeconds / 60).rounded())

        VStack(alignment: .leading, spacing: 0) {
            Text("Your morning")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
                .padding(.bottom, 12)
            TimelineStep(title: "Wake up", value: WakePlanner.format(wake), dot: .filled(Theme.accent), bold: true)
            if !hasLocation {
                TimelineStep(title: "Get ready", value: "\(Int(arrive.timeIntervalSince(wake) / 60)) min", dot: .ring(Theme.accent))
                TimelineStep(title: "Be ready", value: WakePlanner.format(arrive), detail: "No location, so no drive", dot: .filled(Theme.leaveBy), bold: true, highlight: Theme.appointmentChip.text)
                TimelineStep(title: title, value: WakePlanner.format(start), dot: .filled(Theme.text), bold: true, isLast: true)
            } else {
                TimelineStep(
                    title: "Get ready",
                    value: readyMinutes >= 0 ? "\(readyMinutes) min" : "\(-readyMinutes) min short",
                    dot: .ring(readyMinutes >= getReadyGoal ? Theme.accent : Theme.danger),
                    highlight: readyMinutes >= getReadyGoal ? nil : Theme.warning.text
                )
                TimelineStep(
                    title: "Leave by",
                    value: WakePlanner.format(leaveBy),
                    detail: driveDetail(minutes: driveMinutes),
                    dot: .filled(Theme.leaveBy),
                    bold: true,
                    highlight: Theme.appointmentChip.text
                )
                TimelineStep(title: "Arrive", value: "\(WakePlanner.format(arrive)) · \(bufferMinutes) min early", dot: .ring(Theme.leaveBy))
                TimelineStep(title: title, value: WakePlanner.format(start), detail: location, dot: .filled(Theme.text), bold: true, isLast: true)
            }
        }
        .nightfallCard(padding: 20)
    }

    /// "32 min drive with expected traffic + 30 min for snowy at 5:00 AM\nApple 28 · TomTom 30 · Google 29 · Google worst case 41 min"
    private func driveDetail(minutes: Int) -> String {
        let weatherMinutes = weather?.minutes ?? 0
        let drive = minutes - weatherMinutes
        let weatherNote = weather.map { " + \($0.minutes) min for \($0.reason)" } ?? ""
        if let fallbackReason {
            return "\(drive) min assumed: no drive time (\(fallbackReason))" + weatherNote
        }
        let line = "\(drive) min drive with expected traffic" + weatherNote
        guard estimates.count > 1 else { return line }
        let parts = estimates.map { "\($0.service.displayName) \(Int(($0.seconds / 60).rounded()))" }
        return line + "\n" + parts.joined(separator: " · ") + " min"
    }
}

private struct TimelineStep: View {
    enum Dot {
        case filled(Color)
        case ring(Color)
    }

    let title: String
    let value: String
    var detail: String? = nil
    let dot: Dot
    var bold = false
    var highlight: Color? = nil
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Group {
                    switch dot {
                    case .filled(let color): Circle().fill(color)
                    case .ring(let color): Circle().strokeBorder(color, lineWidth: 2)
                    }
                }
                .frame(width: 12, height: 12)
                .padding(.top, 4)
                if !isLast {
                    Rectangle().fill(Theme.border).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).fontWeight(bold ? .semibold : .regular)
                    Spacer()
                    Text(value).foregroundStyle(highlight ?? (bold ? Theme.textSoft : Theme.textMuted))
                }
                .font(.system(size: 15))
                .foregroundStyle(highlight ?? Theme.text)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Missing location

/// A "wake up" appointment with no location: was it saved without one?
private struct MissingLocationCard: View {
    let appointment: AppointmentCandidate
    let save: (String) -> Void
    let noLocationNeeded: () -> Void
    @State private var location = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(appointment.title) at \(WakePlanner.format(appointment.start)) has no location", systemImage: "mappin.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Planned with a drive to be safe. Was it supposed to have a location?")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            TextField("Address or place name", text: $location)
                .textContentType(.fullStreetAddress)
                .padding(12)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(Theme.text)
            HStack(spacing: 10) {
                Button { save(location) } label: {
                    Text("Save and re-plan")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(location.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(action: noLocationNeeded) {
                    Text("No location needed")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }
            }
        }
        .nightfallCard()
    }
}

// MARK: Status and alarms

private struct StatusCard: View {
    let settings: BridgeSettings
    let plan: WakePlan?

    var body: some View {
        VStack(spacing: 0) {
            StatusRow(icon: "timer", title: "Snooze", value: snoozeText)
            Divider().overlay(Theme.divider)
            StatusRow(icon: "house", title: "Home Assistant", value: haText, valueColor: haColor, dot: haColor)
            Divider().overlay(Theme.divider)
            StatusRow(icon: "cloud", title: "Morning weather", value: weatherText)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var snoozeText: String {
        switch settings.alarmStyle {
        case .app:
            switch settings.stopBehavior {
            case .keepUntilUp: "\(settings.snoozeMinutes) min · rest stay until you're up"
            case .cancelRest: "\(settings.snoozeMinutes) min · Stop ends the series"
            case .keepAll: "\(settings.snoozeMinutes) min"
            }
        case .clock: "Clock app · 9 min"
        }
    }

    private var link: HomeAssistantLink? { HomeAssistantLinks.current(settings) }

    private var haText: String {
        let link = link
        let away = plan?.atHome == false ? " · away" : ""
        if link is IntegrationLink { return "Paired" + away }
        if link is TokenLink { return "Token" + away }
        return "Not set up"
    }

    private var haColor: Color {
        if link == nil { return Theme.textMuted }
        return plan?.atHome == false ? Theme.warning.text : Theme.good
    }

    private var weatherText: String {
        guard settings.checksWeather, settings.weatherSource == .openMeteo || link != nil else { return "Not checked" }
        if let weather = plan?.weather { return "+\(weather.minutes) min, \(weather.reason)" }
        return plan == nil ? "Checked when you plan" : "No extra time"
    }
}

private struct StatusRow: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = Theme.textMuted
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Theme.accentIcon)
                .frame(width: 22)
            Text(title).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(value).foregroundStyle(valueColor).multilineTextAlignment(.trailing)
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// "Only 40 min to get ready" with the way to fix it for tonight.
private struct GetReadyCard: View {
    let minutes: Int
    let wanted: Int
    let leaveBy: Date
    let earlierWake: Date
    let wakeEarlier: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                minutes > 0
                    ? "Only \(minutes) min to get ready before you leave at \(WakePlanner.format(leaveBy))"
                    : "You'd need to leave at \(WakePlanner.format(leaveBy)), before your alarm",
                systemImage: "exclamationmark.triangle"
            )
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.warning.text)
            Text("You've set \(wanted) min to get ready. Waking at \(WakePlanner.format(earlierWake)) gives you that. To always do it, turn on Wake early enough to get ready in Settings.")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            Button(action: wakeEarlier) {
                Text("Set alarms to wake at \(WakePlanner.format(earlierWake))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(Theme.warning.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.warning.border, lineWidth: 1))
    }
}

/// The alarm whose snooze the slide-to-stop screen ends.
private struct SnoozedAlarm: Identifiable {
    let id: UUID
}

/// The alarms set on this iPhone, and skipping that morning when plans change.
private struct ScheduledAlarmsCard: View {
    let times: [Date]
    let morning: Date
    let isShift: Bool
    let sleepIn: () -> Void
    let differentTime: () -> Void
    @State private var confirming = false

    private var day: String { morning.formatted(.dateTime.weekday(.wide)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !times.isEmpty {
                Text("Set on this iPhone")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                Text(times.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }.joined(separator: " · "))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
            }
            Button(role: .destructive) { confirming = true } label: {
                Label("Skip \(day)'s wake-up", systemImage: "bell.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .frame(minHeight: 44)
            }
            .confirmationDialog("Skip \(day)'s wake-up?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Sleep in", role: .destructive, action: sleepIn)
                Button("Wake at a different time…", action: differentTime)
            } message: {
                Text(isShift
                     ? "As if the shift weren't there: these alarms go and the wake failsafe is off for \(day) morning. Temporary alarms stay. You can undo it here."
                     : "These alarms go and bedtime planning won't set them again for \(day) morning. Temporary alarms stay. You can undo it here.")
            }
        }
        .nightfallCard()
    }
}

/// No alarm planned: set one for a day off.
private struct DayOffCard: View {
    let setTime: () -> Void

    var body: some View {
        Button(action: setTime) {
            Label("Set alarms for a time", systemImage: "alarm")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .nightfallCard()
    }
}

/// Shown while a morning's alarms are turned off, with the way back.
private struct SkippedMorningCard: View {
    let morning: Date
    let replacement: SkipReplacement?
    let undo: () -> Void

    private var detail: String {
        guard let replacement else { return "Sleeping in. Bedtime planning won't set alarms for that morning." }
        return "Your own alarms instead, up by \(WakePlanner.format(replacement.wake)) (\(replacement.wakeIs.displayName.lowercased()))."
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accentIcon)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(morning.formatted(.dateTime.weekday(.wide)))'s wake-up skipped")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 4)
            Button("Undo", action: undo)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentText)
        }
        .nightfallCard()
    }
}

/// "There are 3 events in the next week without a location or a wake-up."
private struct UpcomingEventsBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1
                     ? "There is 1 event in the next week without a location or a wake-up."
                     : "There are \(count) events in the next week without a location or a wake-up.")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add them now, or ignore the ones that don't need it.")
                    .font(.footnote)
                    .opacity(0.8)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Theme.warning.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.warning.border, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

private struct WarningBanner: View {
    let text: String
    let systemImage: String
    var tint: Color = Theme.warning.text

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 14))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warning.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.warning.border, lineWidth: 1))
    }
}
