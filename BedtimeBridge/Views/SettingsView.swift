import EventKit
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var calendars: [EKCalendar] = []
    @State private var apiKey = ""

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                ForEach($store.settings.shiftRules) { $rule in
                    HStack {
                        TextField("Title contains", text: $rule.keyword)
                        Stepper("\(rule.wakeMinutesBefore) min", value: $rule.wakeMinutesBefore, in: 0...240, step: 5)
                            .fixedSize()
                    }
                }
                .onDelete { store.settings.shiftRules.remove(atOffsets: $0) }
                Button("Add shift type", systemImage: "plus") {
                    store.settings.shiftRules.append(ShiftRule(keyword: "", wakeMinutesBefore: 60))
                }
            } header: {
                Text("Shifts")
            } footer: {
                Text("A calendar event whose title contains the word counts as a shift. The first alarm goes off this long before it starts.")
            }

            Section {
                TextField("Notes contain", text: $store.settings.appointmentKeyword)
                Stepper("Get ready: \(store.settings.getReadyMinutes) min", value: $store.settings.getReadyMinutes, in: 0...240, step: 5)
                Stepper("Arrive early: \(store.settings.arrivalBufferMinutes) min", value: $store.settings.arrivalBufferMinutes, in: 0...60, step: 5)
            } header: {
                Text("Appointments")
            } footer: {
                Text("Wake time = start − arrive-early buffer − drive time − get-ready time. Only used when it's earlier than your shift alarm.")
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

            Section("Shift calendars") {
                CalendarPicker(calendars: calendars, selection: $store.settings.shiftCalendarIDs)
            }
            Section("Appointment calendars") {
                CalendarPicker(calendars: calendars, selection: $store.settings.appointmentCalendarIDs)
            }
        }
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

private struct AlarmSettingsSection: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        Section {
            Picker("Alarms", selection: $settings.alarmStyle) {
                ForEach(AlarmStyle.allCases) { Text($0.displayName).tag($0) }
            }
            Stepper("\(settings.alarmCount) alarms", value: $settings.alarmCount, in: 1...10)
            Stepper("\(settings.alarmSpacingMinutes) min apart", value: $settings.alarmSpacingMinutes, in: 1...60)
            if settings.alarmStyle == .app {
                Stepper("Snooze: \(settings.snoozeMinutes) min", value: $settings.snoozeMinutes, in: 1...30)
                Toggle("Stop cancels the rest", isOn: $settings.stopCancelsRemaining)
            }
            Stepper("Look ahead \(settings.lookAheadHours) h", value: $settings.lookAheadHours, in: 6...72)
        } header: {
            Text("Alarms")
        } footer: {
            switch settings.alarmStyle {
            case .app:
                Text("Rings through Silent and Focus. Snooze and Stop tell Home Assistant directly (set it up below), because the Shortcuts \"alarm snoozed/stopped\" automations only see Clock app alarms.")
            case .clock:
                Text("The app works out the times and your shortcut creates Clock alarms from Wake Plan › Alarm Dates. Your snooze/stop automations keep working, but Apple fixes Clock snooze at 9 minutes.")
            }
        }
    }
}

private struct HomeAssistantSection: View {
    @Binding var settings: BridgeSettings
    @State private var token = KeychainStore.secret(KeychainStore.homeAssistantAccount)
    @State private var testResult: String?

    var body: some View {
        Section {
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
            Button("Test connection") { Task { await test() } }
            if let testResult {
                Text(testResult).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Home Assistant")
        } footer: {
            Text("Make the token in Home Assistant under your profile › Security. The next-alarm sensor is created by the app; it reads unavailable after an HA restart until the next update.")
        }
    }

    private func test() async {
        guard let client = HomeAssistantClient.configured(settings) else {
            testResult = "Add a URL and token first."
            return
        }
        do {
            let override = try await client.state(of: settings.shiftOverrideEntity)
            testResult = "Connected. Shift override is \(override.state)."
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
