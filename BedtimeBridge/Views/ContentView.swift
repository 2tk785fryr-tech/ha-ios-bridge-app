import SwiftUI

/// "Tonight": the plan, the alarm series and the two main actions, in the Nightfall style.
struct ContentView: View {
    @Environment(SettingsStore.self) private var store
    @State private var plan: WakePlan?
    @State private var scheduled: [Date] = []
    @State private var errorMessage: String?
    @State private var isWorking = false

    private let coordinator = BedtimeCoordinator.shared

    /// Phone settings with any times adjusted in Home Assistant, as the last plan used them.
    private var settings: BridgeSettings { store.settings.applying(HomeAssistantLinks.cachedSettings) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let plan {
                        PlanCard(plan: plan)
                        if let weather = plan.weather {
                            WarningBanner(text: "+\(weather.minutes) min for \(weather.reason)", systemImage: "cloud.rain")
                        }
                        if plan.source == .appointment, let appointment = plan.appointment, let wake = plan.wakeTime {
                            MorningTimeline(appointment: appointment, wake: wake, bufferMinutes: settings.arrivalBufferMinutes)
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

                    if store.settings.alarmStyle == .app, !scheduled.isEmpty {
                        ScheduledAlarmsCard(times: scheduled) {
                            Task {
                                try? await coordinator.cancelAlarms(settings: store.settings)
                                refreshScheduled()
                            }
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
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide)).uppercased() + " NIGHT")
                    .font(.footnote.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.textMuted)
                Text("Tonight")
                    .font(.sora(30, .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
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
            return "Set \(settings.alarmCount) alarms, up by \(WakePlanner.format(wake))"
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

private struct MorningTimeline: View {
    let appointment: AppointmentCandidate
    let wake: Date
    let bufferMinutes: Int

    var body: some View {
        let leaveBy = appointment.leaveBy(bufferMinutes: bufferMinutes)
        let arrive = appointment.arriveBy(bufferMinutes: bufferMinutes)
        let readyMinutes = Int(leaveBy.timeIntervalSince(wake) / 60)
        let driveMinutes = Int((appointment.travelSeconds / 60).rounded())

        VStack(alignment: .leading, spacing: 0) {
            Text("Your morning")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
                .padding(.bottom, 12)
            TimelineStep(title: "Wake up", value: WakePlanner.format(wake), dot: .filled(Theme.accent), bold: true)
            TimelineStep(title: "Get ready", value: "\(readyMinutes) min", dot: .ring(Theme.accent))
            if !appointment.hasLocation {
                TimelineStep(title: "Be ready", value: WakePlanner.format(arrive), detail: "No location, so no drive", dot: .filled(Theme.leaveBy), bold: true, highlight: Theme.appointmentChip.text)
                TimelineStep(title: appointment.title, value: WakePlanner.format(appointment.start), dot: .filled(Theme.text), bold: true, isLast: true)
            } else {
            TimelineStep(
                title: "Leave by",
                value: WakePlanner.format(leaveBy),
                detail: "\(driveMinutes) min drive with expected traffic",
                dot: .filled(Theme.leaveBy),
                bold: true,
                highlight: Theme.appointmentChip.text
            )
            TimelineStep(title: "Arrive", value: "\(WakePlanner.format(arrive)) · \(bufferMinutes) min early", dot: .ring(Theme.leaveBy))
            TimelineStep(
                title: appointment.title,
                value: WakePlanner.format(appointment.start),
                detail: appointment.location,
                dot: .filled(Theme.text),
                bold: true,
                isLast: true
            )
            }
        }
        .nightfallCard(padding: 20)
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
            Text("Planned with no drive. Was it supposed to have one?")
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
        case .app: "\(settings.snoozeMinutes) min" + (settings.stopCancelsRemaining ? " · Stop ends the series" : "")
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
        guard settings.weatherExtraMinutes > 0, link != nil else { return "Not checked" }
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

private struct ScheduledAlarmsCard: View {
    let times: [Date]
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set on this iPhone")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
            Text(times.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }.joined(separator: " · "))
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
            Button(role: .destructive, action: cancel) {
                Label("Cancel all", systemImage: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .frame(minHeight: 44)
            }
        }
        .nightfallCard()
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
