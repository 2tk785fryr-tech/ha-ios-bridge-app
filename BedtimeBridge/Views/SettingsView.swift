import EventKit
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var calendars: [EKCalendar] = []
    @State private var apiKey = ""

    var body: some View {
        @Bindable var store = store

        Form {
            Group {
            Section {
                ForEach($store.settings.shiftRules) { $rule in
                    NavigationLink {
                        ShiftRuleEditor(rule: $rule, general: store.settings)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.keyword.isEmpty ? "New shift" : rule.keyword)
                            Text(ShiftRuleEditor.summary(rule, general: store.settings))
                                .font(.footnote)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                .onDelete { store.settings.shiftRules.remove(atOffsets: $0) }
                Button("Add shift type", systemImage: "plus") {
                    store.settings.shiftRules.append(ShiftRule(keyword: ""))
                }
            } header: {
                Text("Shifts")
            } footer: {
                Text("A calendar event whose title contains the word counts as a shift. Each shift has its own timing and alarm series.")
            }

            Section {
                TextField("Notes contain", text: $store.settings.appointmentKeyword)
                Stepper("Get ready: \(store.settings.getReadyMinutes) min", value: $store.settings.getReadyMinutes, in: 0...240, step: 5)
                Stepper("Arrive early: \(store.settings.arrivalBufferMinutes) min", value: $store.settings.arrivalBufferMinutes, in: 0...60, step: 5)
                Toggle("Ask about missing locations", isOn: $store.settings.askAboutMissingLocations)
            } header: {
                Text("Appointments")
            } footer: {
                Text("Wake time = start − arrive-early buffer − drive time − get-ready time. Only used when it's earlier than your shift alarm. A \"wake up\" appointment without a location is planned with the fallback drive until you answer the notification about it.")
            }

            Section {
                Picker("Service", selection: $store.settings.driveTimeSource) {
                    ForEach(DriveTimeSource.allCases) { Text($0.displayName).tag($0) }
                }
                if store.settings.driveTimeSource.needsAPIKey {
                    SecureField("\(store.settings.driveTimeSource.displayName) API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { _, key in
                            KeychainStore.setAPIKey(key, for: store.settings.driveTimeSource)
                        }
                }
                if store.settings.driveTimeSource == .google {
                    Toggle("Plan for heavy traffic", isOn: $store.settings.googlePessimisticTraffic)
                }
                TextField("Home address", text: $store.settings.homeAddress, axis: .vertical)
                Stepper("If no drive time: \(store.settings.fallbackTravelMinutes) min", value: $store.settings.fallbackTravelMinutes, in: 0...180, step: 5)
            } header: {
                Text("Drive time")
            } footer: {
                Text(driveTimeFooter(for: store.settings.driveTimeSource))
            }

            AlarmSettingsSection(settings: $store.settings)
            HomeAssistantSection(settings: $store.settings)
            WeatherSection(settings: $store.settings)

            Section {
                Toggle("Leave-by reminder", isOn: $store.settings.leaveReminderEnabled)
                if store.settings.leaveReminderEnabled {
                    Stepper("\(store.settings.leaveReminderLeadMinutes) min before leave-by", value: $store.settings.leaveReminderLeadMinutes, in: 0...60, step: 5)
                }
            } footer: {
                Text("Appointment mornings only. Set at bedtime; when you stop a Bedtime Bridge alarm, traffic is rechecked and the reminder moves if it changed.")
            }

            AppIconSection()

            Section("Shift calendars") {
                CalendarPicker(calendars: calendars, selection: $store.settings.shiftCalendarIDs)
            }
            Section("Appointment calendars") {
                CalendarPicker(calendars: calendars, selection: $store.settings.appointmentCalendarIDs)
            }
            }
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.divider)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .navigationTitle("Settings")
        .onAppear { apiKey = KeychainStore.apiKey(for: store.settings.driveTimeSource) }
        .onChange(of: store.settings.driveTimeSource) { _, source in
            apiKey = KeychainStore.apiKey(for: source)
        }
        .task {
            let service = BedtimeCoordinator.shared.calendar
            try? await service.ensureAccess()
            calendars = service.eventCalendars()
        }
    }
}

/// One shift type: when to wake for it, and its own alarm series.
struct ShiftRuleEditor: View {
    @Binding var rule: ShiftRule
    let general: BridgeSettings

    var body: some View {
        Form {
            Group {
                Section {
                    TextField("Title contains, e.g. Days", text: $rule.keyword)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Matched against calendar event titles, and sent to Home Assistant as the alarm cause.")
                }

                Section("Timing") {
                    Picker("Alarm time", selection: $rule.timing) {
                        Text("Before the shift").tag(ShiftRule.Timing.beforeShift)
                        Text("Fixed time").tag(ShiftRule.Timing.fixedTime)
                    }
                    .pickerStyle(.segmented)
                    switch rule.timing {
                    case .beforeShift:
                        Stepper("\(rule.wakeMinutesBefore) min before it starts", value: $rule.wakeMinutesBefore, in: 0...300, step: 5)
                    case .fixedTime:
                        DatePicker("Time", selection: fixedTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Toggle("Use my usual series", isOn: usesGeneralSeries)
                    if !usesGeneralSeries.wrappedValue {
                        Picker("Set time is the", selection: Binding(get: { rule.wakeIs ?? general.wakeTimeIs }, set: { rule.wakeIs = $0 })) {
                            ForEach(WakeTimeAlarm.allCases) { Text($0.displayName).tag($0) }
                        }
                        Stepper("\(rule.alarmCount ?? general.alarmCount) alarms", value: Binding(get: { rule.alarmCount ?? general.alarmCount }, set: { rule.alarmCount = $0 }), in: 1...10)
                        Stepper("\(rule.alarmSpacingMinutes ?? general.alarmSpacingMinutes) min apart", value: Binding(get: { rule.alarmSpacingMinutes ?? general.alarmSpacingMinutes }, set: { rule.alarmSpacingMinutes = $0 }), in: 1...60)
                    }
                } header: {
                    Text("Alarm series")
                } footer: {
                    Text(Self.example(rule, general: general))
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle(rule.keyword.isEmpty ? "Shift" : rule.keyword)
    }

    private var fixedTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: rule.fixedHour, minute: rule.fixedMinute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            rule.fixedHour = parts.hour ?? 8
            rule.fixedMinute = parts.minute ?? 0
        }
    }

    private var usesGeneralSeries: Binding<Bool> {
        Binding {
            rule.wakeIs == nil && rule.alarmCount == nil && rule.alarmSpacingMinutes == nil
        } set: { usesGeneral in
            if usesGeneral {
                rule.wakeIs = nil
                rule.alarmCount = nil
                rule.alarmSpacingMinutes = nil
            } else {
                rule.wakeIs = general.wakeTimeIs
                rule.alarmCount = general.alarmCount
                rule.alarmSpacingMinutes = general.alarmSpacingMinutes
            }
        }
    }

    /// "First alarm 8:00 AM, 3 alarms 10 min apart" / "Up 60 min before, last of 3"
    static func summary(_ rule: ShiftRule, general: BridgeSettings) -> String {
        let wakeIs = rule.wakeIs ?? general.wakeTimeIs
        let count = rule.alarmCount ?? general.alarmCount
        let spacing = rule.alarmSpacingMinutes ?? general.alarmSpacingMinutes
        let which = wakeIs == .first ? "First" : "Last"
        let when: String
        switch rule.timing {
        case .beforeShift: when = "\(rule.wakeMinutesBefore) min before the shift"
        case .fixedTime:
            let time = Calendar.current.date(bySettingHour: rule.fixedHour, minute: rule.fixedMinute, second: 0, of: .now) ?? .now
            when = WakePlanner.format(time)
        }
        return "\(which) alarm \(when) · \(count) alarms, \(spacing) min apart"
    }

    /// The series for an example shift, so the effect is visible while editing.
    static func example(_ rule: ShiftRule, general: BridgeSettings) -> String {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let start = calendar.date(bySettingHour: rule.timing == .fixedTime ? 14 : 6, minute: 30, second: 0, of: .now) ?? .now
        let (shift, warning) = ShiftCandidate.make(title: rule.keyword, start: start, rule: rule)
        let times = WakePlanner.alarmTimes(
            wakeTime: shift.wakeTime,
            count: rule.alarmCount ?? general.alarmCount,
            spacingMinutes: rule.alarmSpacingMinutes ?? general.alarmSpacingMinutes,
            wakeIs: rule.wakeIs ?? general.wakeTimeIs
        )
        let line = "Shift at \(WakePlanner.format(start)) → alarms " + times.map(WakePlanner.format).joined(separator: ", ")
        return warning.map { line + "\n" + $0 } ?? line
    }
}

private struct AlarmSettingsSection: View {
    @Binding var settings: BridgeSettings

    /// e.g. "Up at 5:30 → alarms 5:10, 5:20, 5:30"
    private var seriesExample: String {
        let wake = Calendar.current.date(bySettingHour: 5, minute: 30, second: 0, of: .now) ?? .now
        let times = WakePlanner.alarmTimes(wakeTime: wake, count: settings.alarmCount, spacingMinutes: settings.alarmSpacingMinutes, wakeIs: settings.wakeTimeIs)
        return "Up at 5:30 → alarms " + times.map(WakePlanner.format).joined(separator: ", ")
    }

    var body: some View {
        Section {
            Picker("Alarms", selection: $settings.alarmStyle) {
                ForEach(AlarmStyle.allCases) { Text($0.displayName).tag($0) }
            }
            Stepper("\(settings.alarmCount) alarms", value: $settings.alarmCount, in: 1...10)
            Stepper("\(settings.alarmSpacingMinutes) min apart", value: $settings.alarmSpacingMinutes, in: 1...60)
            Picker("Set time is the", selection: $settings.wakeTimeIs) {
                ForEach(WakeTimeAlarm.allCases) { Text($0.displayName).tag($0) }
            }
            Text(seriesExample)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            if settings.alarmStyle == .app {
                Stepper("Snooze: \(settings.snoozeMinutes) min", value: $settings.snoozeMinutes, in: 1...30)
                Picker("When I stop an alarm", selection: $settings.stopBehavior) {
                    ForEach(StopBehavior.allCases) { Text($0.displayName).tag($0) }
                }
                TestAlarmButton(settings: settings)
            }
            Stepper("Look ahead \(settings.lookAheadHours) h", value: $settings.lookAheadHours, in: 6...72)
        } header: {
            Text("Alarms (appointments, day off)")
        } footer: {
            switch settings.alarmStyle {
            case .app:
                Text("Rings through Silent and Focus. Snooze and Stop tell Home Assistant directly (set it up below), because the Shortcuts \"alarm snoozed/stopped\" automations only see Clock app alarms. \"Keep the rest until I'm up\" cancels the later alarms only once Home Assistant sees the bedroom door opened or the bed empty for over a minute, so stopping the first alarm and dozing off still leaves the others.")
            case .clock:
                Text("The app works out the times and your shortcut creates Clock alarms from Wake Plan › Alarm Dates. Your snooze/stop automations keep working, but Apple fixes Clock snooze at 9 minutes.")
            }
        }
    }
}

/// Rings in two minutes and runs the real snooze/stop routines in Home Assistant.
private struct TestAlarmButton: View {
    let settings: BridgeSettings
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Test alarm in 2 minutes", systemImage: "alarm.waves.left.and.right") {
                Task {
                    do {
                        let time = try await BedtimeCoordinator.shared.scheduleTestAlarm(settings: settings)
                        status = "Rings at \(WakePlanner.format(time)). Snooze, then Stop: your real routines will run (if you're home)."
                    } catch {
                        status = error.localizedDescription
                    }
                }
            }
            if let status {
                Text(status).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

private struct HomeAssistantSection: View {
    @Binding var settings: BridgeSettings
    @State private var webhook = KeychainStore.secret(HomeAssistantLinks.webhookAccount)
    @State private var localWebhook = KeychainStore.secret(HomeAssistantLinks.localWebhookAccount)
    @State private var token = KeychainStore.secret(KeychainStore.homeAssistantAccount)
    @State private var testResult: String?

    private var usesIntegration: Bool {
        !webhook.trimmingCharacters(in: .whitespaces).isEmpty || !localWebhook.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Section {
            SecureField("Anywhere address (Nabu Casa) or pairing link", text: $webhook)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: webhook) { _, value in
                    // Pasting the whole pairing link fills in both addresses.
                    if let link = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                       HomeAssistantLinks.pair(with: link) {
                        webhook = KeychainStore.secret(HomeAssistantLinks.webhookAccount)
                        localWebhook = KeychainStore.secret(HomeAssistantLinks.localWebhookAccount)
                        return
                    }
                    KeychainStore.setSecret(value, account: HomeAssistantLinks.webhookAccount)
                }
            SecureField("Home address (local, optional)", text: $localWebhook)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: localWebhook) { _, value in
                    KeychainStore.setSecret(value, account: HomeAssistantLinks.localWebhookAccount)
                }
            if !usesIntegration {
                TextField("URL, e.g. http://homeassistant.local:8123", text: $settings.homeAssistantURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Long-lived access token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: token) { _, value in
                        KeychainStore.setSecret(value, account: KeychainStore.homeAssistantAccount)
                    }
                EntityField(title: "On snooze, turn on", text: $settings.snoozeHelper)
                EntityField(title: "On stop, turn on", text: $settings.stopHelper)
                EntityField(title: "Shift override", text: $settings.shiftOverrideEntity)
                EntityField(title: "Shift sensor", text: $settings.shiftSensorEntity)
                EntityField(title: "Next-alarm sensor", text: $settings.nextAlarmSensor)
                EntityField(title: "Bedtime routine", text: $settings.bedtimeHelper)
                EntityField(title: "You", text: $settings.presenceEntity)
                EntityField(title: "Bed sensor", text: $settings.bedSensor)
                EntityField(title: "Left the bedroom", text: $settings.exitLatch)
                Toggle("Only run routines when home", isOn: $settings.homeOnly)
            }
            Button("Test connection") { Task { await test() } }
            if let testResult {
                Text(testResult).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Home Assistant")
        } footer: {
            if usesIntegration {
                Text("Using the Bedtime Bridge integration. The anywhere address is tried first, then the home one. Tap the pairing link on the integration's setup screen (in the Home Assistant app) to fill both in. Helpers, events, \"only when home\", the shift override and weather entity are chosen in Home Assistant (Settings › Devices & services › Bedtime Bridge › Configure), and times you change there override these settings.")
            } else {
                Text("Recommended: install the Bedtime Bridge integration in Home Assistant and paste the address it shows above. Without it, the app uses a long-lived token (profile › Security) and writes a sensor that reads unavailable after an HA restart until the next update.")
            }
        }
    }

    private func test() async {
        guard let link = HomeAssistantLinks.current(settings) else {
            testResult = "Add the integration address, or a URL and token."
            return
        }
        do {
            let context = try await link.context(settings: settings)
            let via = usesIntegration ? "the integration" : "token"
            testResult = "Connected via \(via). Shift override is \(context.shiftOverride ?? "not set")."
        } catch {
            testResult = error.localizedDescription
        }
    }
}

private struct WeatherSection: View {
    @Binding var settings: BridgeSettings

    private static let conditions = [
        "rainy", "pouring", "lightning-rainy", "lightning", "fog", "windy", "snowy", "snowy-rainy", "hail", "exceptional",
    ]

    var body: some View {
        Section {
            Stepper("Extra time: \(settings.weatherExtraMinutes) min", value: $settings.weatherExtraMinutes, in: 0...60, step: 5)
            if settings.weatherExtraMinutes > 0 {
                EntityField(title: "Weather", text: $settings.weatherEntity)
                ForEach(Self.conditions, id: \.self) { condition in
                    Toggle(condition, isOn: Binding(
                        get: { settings.badWeatherConditions.contains(condition) },
                        set: { on in
                            if on { settings.badWeatherConditions.insert(condition) } else { settings.badWeatherConditions.remove(condition) }
                        }
                    ))
                }
                Toggle("Any rain or snow at freezing", isOn: $settings.addTimeWhenFreezing)
            }
        } header: {
            Text("Bad weather")
        } footer: {
            Text("If the hourly forecast between your first alarm and when you need to be there matches a ticked condition, the alarm moves earlier by the extra time. Appointment drives get the extra time added. Needs Home Assistant.")
        }
    }
}

private struct EntityField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        LabeledContent(title) {
            TextField("entity_id", text: $text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout.monospaced())
        }
    }
}

private func driveTimeFooter(for source: DriveTimeSource) -> String {
    switch source {
    case .apple:
        "Free, no key. Asks Apple Maps for the traffic it expects when you'd arrive. A blank home address uses your current location."
    case .tomTom:
        "Uses TomTom's typical traffic for your arrival time. Needs a home address and a key from developer.tomtom.com."
    case .google:
        "Google only plans from a departure time, so the app tries a few departure times until the trip lands on time. Heavy traffic plans for a bad day, not a typical one. Needs a home address and a Routes API key."
    }
}

/// Nothing ticked means every calendar is searched.
private struct CalendarPicker: View {
    let calendars: [EKCalendar]
    @Binding var selection: Set<String>

    var body: some View {
        if calendars.isEmpty {
            Text("Allow calendar access to choose calendars.").foregroundStyle(.secondary)
        }
        ForEach(calendars, id: \.calendarIdentifier) { calendar in
            Button {
                if selection.contains(calendar.calendarIdentifier) {
                    selection.remove(calendar.calendarIdentifier)
                } else {
                    selection.insert(calendar.calendarIdentifier)
                }
            } label: {
                HStack {
                    Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 10, height: 10)
                    Text(calendar.title).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(calendar.calendarIdentifier) {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        if !calendars.isEmpty {
            Text(selection.isEmpty ? "Searching all calendars" : "Searching \(selection.count) selected")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
