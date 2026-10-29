import AVFoundation
import EventKit
import SwiftUI

/// The settings you'll change most (shifts, home address) up top, and the rest grouped
/// into their own pages.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let settings = store.settings

        SettingsPage(title: "Settings") {
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
                Stepper("Get ready: \(store.settings.getReadyMinutes) min", value: $store.settings.getReadyMinutes, in: 0...240, step: 5)
                Stepper("Arrive at work early: \(store.settings.workArrivalBufferMinutes) min", value: $store.settings.workArrivalBufferMinutes, in: 0...60, step: 5)
                Toggle("Wake early enough to get ready", isOn: $store.settings.wakeEarlyToGetReady)
            } header: {
                Text("Mornings")
            } footer: {
                Text("When a shift's event has a location, Tonight shows when to leave to arrive this early. If the drive or bad weather leaves less than the get-ready time, you're warned and can wake earlier for that night; with the switch on, shift alarms move earlier by themselves. Appointments always plan the get-ready time.")
            }

            Section {
                HomeAddressField(address: $store.settings.homeAddress)
            } header: {
                Text("Home")
            } footer: {
                Text("Where drives to appointments start. Blank uses your current location (Apple Maps only).")
            }

            Section {
                SettingsLink(title: "Alarms", icon: "alarm", value: "\(settings.alarmCount) alarms, \(settings.alarmSpacingMinutes) min apart") {
                    SettingsPage(title: "Alarms") { AlarmSettingsSection(settings: $store.settings) }
                }
                SettingsLink(title: "Appointments", icon: "calendar.badge.clock", value: "Notes say \"\(settings.appointmentKeyword)\"") {
                    SettingsPage(title: "Appointments") { AppointmentsSection(settings: $store.settings) }
                }
                SettingsLink(title: "Drive time", icon: "car", value: settings.driveTimeSource.displayName) {
                    SettingsPage(title: "Drive time") {
                        DriveTimeSection(settings: $store.settings)
                        LeaveReminderSection(settings: $store.settings)
                    }
                }
                SettingsLink(title: "Home Assistant", icon: "house", value: homeAssistantSummary(settings)) {
                    SettingsPage(title: "Home Assistant") { HomeAssistantSection(settings: $store.settings) }
                }
                SettingsLink(title: "Bad weather", icon: "cloud.rain", value: settings.checksWeather ? "Default +\(settings.weatherExtraMinutes) min" : "Off") {
                    SettingsPage(title: "Bad weather") { WeatherSection(settings: $store.settings) }
                }
                SettingsLink(title: "Calendars", icon: "calendar", value: calendarSummary(settings)) {
                    CalendarsPage(settings: $store.settings)
                }
                SettingsLink(title: "App icon", icon: "app.badge", value: AppIconChoice.current.title) {
                    SettingsPage(title: "App icon") { AppIconSection() }
                }
            }
        }
    }

    private func homeAssistantSummary(_ settings: BridgeSettings) -> String {
        switch HomeAssistantLinks.current(settings) {
        case is IntegrationLink: "Paired"
        case is TokenLink: "Token"
        default: "Not set up"
        }
    }

    private func calendarSummary(_ settings: BridgeSettings) -> String {
        let count = settings.shiftCalendarIDs.union(settings.appointmentCalendarIDs).count
        return settings.shiftCalendarIDs.isEmpty && settings.appointmentCalendarIDs.isEmpty ? "All" : "\(count) chosen"
    }
}

/// A settings screen in the Nightfall style.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(Theme.surface)
                .listRowSeparatorTint(Theme.divider)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .navigationTitle(title)
    }
}

/// A row on the main page that opens a group, with its current state on the right.
private struct SettingsLink<Destination: View>: View {
    let title: String
    let icon: String
    let value: String
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            LabeledContent {
                Text(value).foregroundStyle(Theme.textMuted).lineLimit(1)
            } label: {
                Label(title, systemImage: icon)
            }
        }
    }
}

private struct AppointmentsSection: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        Section {
            TextField("Notes contain", text: $settings.appointmentKeyword)
            Stepper("Arrive early: \(settings.arrivalBufferMinutes) min", value: $settings.arrivalBufferMinutes, in: 0...60, step: 5)
            Toggle("Ask about missing locations", isOn: $settings.askAboutMissingLocations)
        } header: {
            Text("Appointments")
        } footer: {
            Text("Wake time = start − arrive-early buffer − drive time − get-ready time (on the main Settings page). Only used when it's earlier than your shift alarm. A \"wake up\" appointment without a location is planned with the fallback drive until you answer the notification about it.")
        }
    }
}

private struct LeaveReminderSection: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        Section {
            Toggle("Leave-by reminder", isOn: $settings.leaveReminderEnabled)
            if settings.leaveReminderEnabled {
                Stepper("\(settings.leaveReminderLeadMinutes) min before leave-by", value: $settings.leaveReminderLeadMinutes, in: 0...60, step: 5)
            }
            Stepper("Widget: leave-by until \(settings.widgetLeaveByMinutes) min after", value: $settings.widgetLeaveByMinutes, in: 0...120, step: 5)
        } footer: {
            Text("For shifts and appointments with a location. Set at bedtime; when you stop a Bedtime Bridge alarm, traffic is rechecked and the reminder moves if it changed. Once the alarms are done, the Lock Screen widget shows leave-by until this long after it.")
        }
    }
}

private struct DriveTimeSection: View {
    @Binding var settings: BridgeSettings
    @State private var googleKeySaved = !KeychainStore.apiKey(for: .google).isEmpty

    var body: some View {
        Section {
            Picker("Use", selection: $settings.driveTimeSource) {
                ForEach(DriveTimeSource.allCases) { Text($0.displayName).tag($0) }
            }
            if googleKeySaved || settings.driveTimeSource == .google {
                Picker("Google plans for", selection: $settings.googlePessimisticTraffic) {
                    Text("A typical day").tag(false)
                    Text("Worst case").tag(true)
                }
            }
            Stepper("If no drive time: \(settings.fallbackTravelMinutes) min", value: $settings.fallbackTravelMinutes, in: 0...180, step: 5)
            Toggle("Start from where I am when away", isOn: $settings.driveFromHereWhenAway)
        } header: {
            Text("Drive time")
        } footer: {
            Text(driveTimeFooter(for: settings.driveTimeSource))
        }

        Section {
            APIKeyField(source: .tomTom) { _ in }
            APIKeyField(source: .google) { googleKeySaved = $0 }
        } header: {
            Text("API keys")
        } footer: {
            Text("Each key is saved in your Keychain as soon as you paste it, whichever service you use. Every service with a key is asked each time and shown on the morning timeline; with a Google key, its worst case is always shown too. TomTom: developer.tomtom.com › Dashboard › Keys. Google: a Routes API key from Google Cloud.")
        }
    }
}

/// A drive-time service's key, saved to the Keychain on every change.
private struct APIKeyField: View {
    let source: DriveTimeSource
    let changed: (Bool) -> Void
    @State private var key: String

    init(source: DriveTimeSource, changed: @escaping (Bool) -> Void) {
        self.source = source
        self.changed = changed
        _key = State(initialValue: KeychainStore.apiKey(for: source))
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                SecureField("Paste key", text: $key)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Image(systemName: key.isEmpty ? "circle.dashed" : "checkmark.circle.fill")
                    .foregroundStyle(key.isEmpty ? Theme.textFaint : Theme.good)
                    .accessibilityLabel(key.isEmpty ? "Not saved" : "Saved")
            }
        } label: {
            Text(source.displayName)
        }
        .onChange(of: key) { _, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            KeychainStore.setAPIKey(trimmed, for: source)
            changed(!trimmed.isEmpty)
        }
    }
}

private struct CalendarsPage: View {
    @Binding var settings: BridgeSettings
    @State private var calendars: [EKCalendar] = []

    var body: some View {
        SettingsPage(title: "Calendars") {
            Section("Shift calendars") {
                CalendarPicker(calendars: calendars, selection: $settings.shiftCalendarIDs)
            }
            Section("Appointment calendars") {
                CalendarPicker(calendars: calendars, selection: $settings.appointmentCalendarIDs)
            }
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
                AlarmSoundPicker(sound: $settings.alarmSound)
                Stepper("End early from \(settings.endAlarmsEarlyHours) h before", value: $settings.endAlarmsEarlyHours, in: 1...6)
                Picker("When I stop an alarm", selection: $settings.stopBehavior) {
                    ForEach(StopBehavior.allCases) { Text($0.displayName).tag($0) }
                }
                TestAlarmButton(settings: settings)
                NavigationLink("Change this morning") {
                    MorningChangeSettings(settings: $settings)
                }
            }
            Stepper("Look ahead \(settings.lookAheadHours) h", value: $settings.lookAheadHours, in: 6...72)
        } header: {
            Text("Alarms (appointments, day off)")
        } footer: {
            switch settings.alarmStyle {
            case .app:
                Text("Rings through Silent and Focus. Snooze and Stop tell Home Assistant directly (set it up below), because the Shortcuts \"alarm snoozed/stopped\" automations only see Clock app alarms. \"Keep the rest until I'm up\" cancels the later alarms only once Home Assistant sees the bedroom door opened or the bed empty for over a minute, so stopping the first alarm and dozing off still leaves the others. A new sound is used from the next time alarms are set.")
            case .clock:
                Text("The app works out the times and your shortcut creates Clock alarms from Wake Plan › Alarm Dates. Your snooze/stop automations keep working, but Apple fixes Clock snooze at 9 minutes.")
            }
        }
    }
}

/// Settings → Change this morning (v0.4.1 item 7): the reasons, what each moves, and the gap
/// the early backstop keeps after the new last alarm.
private struct MorningChangeSettings: View {
    @Binding var settings: BridgeSettings
    @State private var newReason = ""

    var body: some View {
        SettingsPage(title: "Change this morning") {
            Section {
                ForEach($settings.morningReasons) { $reason in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Reason", text: $reason.name)
                            .foregroundStyle(Theme.text)
                        Picker("Moves", selection: $reason.scope) {
                            ForEach(MorningChangeScope.allCases) { Text($0.displayName).tag($0) }
                        }
                        .font(.footnote)
                    }
                }
                .onDelete { settings.morningReasons.remove(atOffsets: $0) }
                .onMove { settings.morningReasons.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    TextField("Add a reason", text: $newReason)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newReason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Reasons")
            } footer: {
                Text("Picked when you change a morning's alarms, and logged in Home Assistant. Shift alarms only: you sleep longer and the start stays (leave-by and the deadline and late backstops stay). Shift entire wake-up: the start is later, and everything moves. Ask: choose each time.")
            }
            Section {
                Stepper("Early backstop: \(settings.earlyBackstopGapMinutes) min after the last alarm", value: $settings.earlyBackstopGapMinutes, in: 0...30)
            } footer: {
                Text("With Shift alarms only, the early backstop moves to this long after the new last alarm if it would otherwise come before it.")
            }
        }
        .toolbar { EditButton() }
    }

    private func add() {
        let name = newReason.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !settings.morningReasons.contains(where: { $0.name == name }) else { return }
        settings.morningReasons.append(MorningReason(name: name, scope: .ask))
        newReason = ""
    }
}

/// Which sound app alarms ring with, with a play button to hear it first.
private struct AlarmSoundPicker: View {
    @Binding var sound: AlarmSound
    @State private var player: AVAudioPlayer?

    var body: some View {
        HStack {
            Picker("Sound", selection: $sound) {
                ForEach(AlarmSound.allCases) { Text($0.displayName).tag($0) }
            }
            if sound.fileName != nil {
                Button {
                    toggle()
                } label: {
                    Image(systemName: player?.isPlaying == true ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(player?.isPlaying == true ? "Stop preview" : "Play preview")
            }
        }
        .onChange(of: sound) { stop() }
        .onDisappear { stop() }
    }

    private func toggle() {
        if player?.isPlaying == true { return stop() }
        guard let name = sound.fileName,
              let url = Bundle.main.url(forResource: name, withExtension: nil) else { return }
        // Heard even with the ring switch on silent, like the alarm itself.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    private func stop() {
        player?.stop()
        player = nil
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

    /// Paired with the integration, which reads the forecast from its own weather setting.
    private var usesIntegration: Bool { HomeAssistantLinks.current(settings) is IntegrationLink }

    private var sourceFooter: String {
        switch settings.weatherSource {
        case .homeAssistant where usesIntegration:
            "From the weather entity picked in Home Assistant: Settings › Devices & services › Bedtime Bridge › Configure › Weather."
        case .homeAssistant:
            "From this Home Assistant weather entity, e.g. weather.forecast_home. Needs Home Assistant set up."
        case .openMeteo:
            "Free, no key or Home Assistant needed: the hourly forecast for your home address (your current location if it's blank). Weather data by Open-Meteo.com."
        }
    }

    /// Home Assistant's condition names, and what to call them here.
    private static let conditions: [(key: String, name: String)] = [
        ("snowy", "Snow"), ("snowy-rainy", "Sleet"), ("hail", "Hail"), ("pouring", "Heavy rain"),
        ("lightning-rainy", "Thunderstorms"), ("rainy", "Rain"), ("lightning", "Lightning"),
        ("fog", "Fog"), ("windy", "Wind"), ("exceptional", "Severe weather"),
    ]

    var body: some View {
        Section {
            Stepper("Default extra time: \(settings.weatherExtraMinutes) min", value: $settings.weatherExtraMinutes, in: 0...60, step: 5)
            Picker("Forecast from", selection: $settings.weatherSource) {
                ForEach(WeatherSource.allCases) { Text($0.displayName).tag($0) }
            }
            if settings.weatherSource == .homeAssistant {
                if usesIntegration {
                    LabeledContent("Weather entity", value: "Chosen in Home Assistant")
                } else {
                    EntityField(title: "Weather entity", text: $settings.weatherEntity)
                }
            }
        } header: {
            Text("Bad weather")
        } footer: {
            Text(sourceFooter + " The forecast covers your first alarm until you need to be there; a matching condition moves the alarm and your leave-by earlier.")
        }

        Section {
            ForEach(Self.conditions, id: \.key) { condition in
                amountPicker(condition.name, key: condition.key, ticked: Binding(
                    get: { settings.badWeatherConditions.contains(condition.key) },
                    set: { on in
                        if on { settings.badWeatherConditions.insert(condition.key) } else { settings.badWeatherConditions.remove(condition.key) }
                    }
                ))
            }
            amountPicker("Rain or snow at freezing", key: PlanAdjustments.freezing, ticked: $settings.addTimeWhenFreezing)
        } header: {
            Text("Extra time for")
        } footer: {
            Text("Each condition uses the default or its own amount. If several turn up, the largest one is used, not the total.")
        }
    }

    /// One condition: off, the default, or its own minutes.
    private func amountPicker(_ title: String, key: String, ticked: Binding<Bool>) -> some View {
        Picker(title, selection: Binding<WeatherAmount>(
            get: {
                guard ticked.wrappedValue else { return .off }
                return settings.weatherConditionMinutes[key].map(WeatherAmount.minutes) ?? .standard
            },
            set: { amount in
                ticked.wrappedValue = amount != .off
                if case .minutes(let minutes) = amount {
                    settings.weatherConditionMinutes[key] = minutes
                } else {
                    settings.weatherConditionMinutes[key] = nil
                }
            }
        )) {
            Text("Off").tag(WeatherAmount.off)
            Text("Default (\(settings.weatherExtraMinutes) min)").tag(WeatherAmount.standard)
            ForEach(Array(stride(from: 5, through: 60, by: 5)), id: \.self) { minutes in
                Text("\(minutes) min").tag(WeatherAmount.minutes(minutes))
            }
        }
    }
}

private enum WeatherAmount: Hashable {
    case off
    case standard
    case minutes(Int)
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
        "Free, no key. Asks Apple Maps for the traffic it expects when you'd arrive."
    case .tomTom:
        "Uses TomTom's typical traffic for your arrival time. Needs a home address and a TomTom key."
    case .google:
        "Google only plans from a departure time, so the app tries a few departure times until the trip lands on time. Needs a home address and a Google key."
    case .longest:
        "Asks Apple Maps and every service with a key below, and plans with the longest drive, so you're never late because one service was optimistic. Google counts with the day it plans for."
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
