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
                SettingsLink(title: "Mornings", icon: "sunrise", value: "Get ready \(settings.getReadyMinutes) min") {
                    MorningsSettings(settings: $store.settings)
                }
                SettingsLink(title: "Home", icon: "house.fill", value: settings.homeAddress.isEmpty ? "Current location" : "Set") {
                    HomeSettings(settings: $store.settings)
                }
                SettingsLink(title: "Alarms", icon: "alarm", value: AlarmSeriesText.alarmsRow(style: settings.alarmStyle, snooze: settings.snoozeMinutes)) {
                    SettingsPage(title: "Alarms") { AlarmSettingsSection(settings: $store.settings) }
                }
                SettingsLink(title: "Nap", icon: "powersleep", value: settings.napEnabled ? "\(settings.napAlarmCount) alarms, \(settings.napSpacingMinutes) min apart" : "Off") {
                    NapSettings(settings: $store.settings)
                }
                SettingsLink(title: "Wind-down", icon: "moon.zzz", value: settings.windDownEnabled ? "Sleep goal \(DurationText.hours(settings.sleepGoalMinutes))" : "Off") {
                    WindDownSettings(settings: $store.settings)
                }
                SettingsLink(title: "Vacations", icon: "beach.umbrella", value: settings.leaveTitles.joined(separator: ", ")) {
                    LeaveSettings(settings: $store.settings)
                }
                SettingsLink(title: "Weekly summary", icon: "calendar.day.timeline.left", value: settings.weeklySummaryEnabled ? "On" : "Off") {
                    WeeklySummarySettings(settings: $store.settings)
                }
                SettingsLink(title: "Appointments", icon: "calendar.badge.clock",
                             value: settings.appointmentKeyword.isEmpty ? "Wake-up keyword: none" : "Wake-up keyword: \(settings.appointmentKeyword)") {
                    SettingsPage(title: "Appointments") {
                        AppointmentsSection(settings: $store.settings)
                        ResetPageSection { store.settings.resetToDefaults(SettingsPages.appointments) }
                    }
                }
                SettingsLink(title: "Drive time", icon: "car", value: settings.driveTimeSource.displayName) {
                    SettingsPage(title: "Drive time") {
                        DriveTimeSection(settings: $store.settings)
                        LeaveReminderSection(settings: $store.settings)
                        ResetPageSection(detail: "Only this page's settings go back to their defaults. API keys stay (Settings → Reset clears them).") {
                            store.settings.resetToDefaults(SettingsPages.driveTime)
                        }
                    }
                }
                SettingsLink(title: "Home Assistant", icon: "house", value: homeAssistantSummary(settings)) {
                    SettingsPage(title: "Home Assistant") {
                        HomeAssistantSection(settings: $store.settings)
                        ResetPageSection(detail: "Only this page's settings go back to their defaults. The pairing and token stay (Settings → Reset clears them).") {
                            store.settings.resetToDefaults(SettingsPages.homeAssistant)
                        }
                    }
                }
                SettingsLink(title: "Bad weather", icon: "cloud.rain", value: settings.checksWeather ? "Default +\(settings.weatherExtraMinutes) min" : "Off") {
                    SettingsPage(title: "Bad weather") {
                        WeatherSection(settings: $store.settings)
                        ResetPageSection {
                            store.settings.resetToDefaults(SettingsPages.weather)
                        }
                    }
                }
                SettingsLink(title: "Calendars", icon: "calendar", value: calendarSummary(settings)) {
                    CalendarsPage(settings: $store.settings)
                }
                SettingsLink(title: "Notifications", icon: "bell.badge", value: "") {
                    NotificationSettings(settings: $store.settings)
                }
                SettingsLink(title: "Shortcuts, controls and Siri", icon: "square.grid.2x2", value: "") {
                    ShortcutsSettings(settings: $store.settings)
                }
                SettingsLink(title: "App icon", icon: "app.badge", value: AppIconChoice.current.title) {
                    SettingsPage(title: "App icon") { AppIconSection() }
                }
                // v0.4.7 item 10.
                SettingsLink(title: "Clock", icon: "clock", value: store.settings.clockStyle.displayName) {
                    SettingsPage(title: "Clock") {
                        Section {
                            Picker(selection: $store.settings.clockStyle) {
                                ForEach(ClockStyle.allCases) { Text($0.displayName).tag($0) }
                            } label: {
                                WithDefault(text: "Times", defaultText: store.settings.clockStyle == .phone ? nil : ClockStyle.phone.displayName)
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } footer: {
                            Text("How times show in the app, the widgets and Live Activities, and in Home Assistant's notifications. Phone setting follows Settings → General → Date & Time.")
                        }
                    }
                }
            }

            Section {
                SettingsLink(title: "Reset", icon: "arrow.counterclockwise", value: "") {
                    ResetSettings(settings: $store.settings)
                }
            }

            ResetPageSection(detail: "Your shifts go back to the defaults (Days and Swings). The pages above keep theirs.") {
                store.settings.resetToDefaults(SettingsPages.main)
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

/// Settings → Mornings: get-ready time, arriving early and waking early enough.
private struct MorningsSettings: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "Mornings") {
            Section {
                DefaultStepper(value: $settings.getReadyMinutes, in: 0...240, step: 5, defaultValue: BridgeSettings().getReadyMinutes, note: { "\($0) min" }) { "Get ready: \($0) min" }
                DefaultStepper(value: $settings.workArrivalBufferMinutes, in: 0...60, step: 5, defaultValue: BridgeSettings().workArrivalBufferMinutes, note: { "\($0) min" }) { "Arrive at work early: \($0) min" }
                DefaultToggle(title: "Wake early enough to get ready", isOn: $settings.wakeEarlyToGetReady, defaultValue: BridgeSettings().wakeEarlyToGetReady)
            } header: {
                Text("Mornings")
            } footer: {
                Text("When a shift's event has a location, Tonight shows when to leave to arrive this early. If the drive or bad weather leaves less than the get-ready time, you're warned and can wake earlier for that night; with the switch on, shift alarms move earlier by themselves. Appointments always plan the get-ready time.")
            }

            // v0.4.6 item 2.
            Section {
                DefaultToggle(title: "Disarm, re-arm and good morning", isOn: $settings.noAlarmMorningEnabled, defaultValue: BridgeSettings().noAlarmMorningEnabled)
                if settings.noAlarmMorningEnabled {
                    LabeledContent {
                        DatePicker("", selection: earliest, displayedComponents: .hourAndMinute).labelsHidden()
                    } label: {
                        WithDefault(text: "Good morning from", defaultText: settings.noAlarmEarliest == BridgeSettings().noAlarmEarliest ? nil : "8:00 AM")
                    }
                    DefaultStepper(value: $settings.noAlarmUpMinutes, in: 5...60, step: 5, defaultValue: BridgeSettings().noAlarmUpMinutes, note: { "\($0) min" }) { "Up for: \($0) min" }
                    DefaultStepper(value: $settings.noAlarmWaitMinutes, in: 1...30, defaultValue: BridgeSettings().noAlarmWaitMinutes, note: { "\($0) min" }) { "Ask first, then go ahead after: \($0) min" }
                }
            } header: {
                Text("Mornings with no alarms")
            } footer: {
                Text("At home, on a morning with no alarms: out of bed, through the bedroom door and down the hall disarms the house (nothing else changes), and it re-arms once you're back in bed. From the time above, once you've been up this long or the phone comes off the charger, Home Assistant asks Up for the day?, and runs good morning (Sleep In off, Awake For Day on, Good Morning) if you don't answer. I'm awake in the bar, Siri or a control does it straight away.")
            }

            ResetPageSection { settings.resetToDefaults(SettingsPages.mornings) }
        }
    }

    private var earliest: Binding<Date> {
        Binding {
            let parts = settings.noAlarmEarliest.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: parts.first ?? 8, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.noAlarmEarliest = String(format: "%02d:%02d", c.hour ?? 8, c.minute ?? 0)
        }
    }
}

/// Settings → Home: where drives start.
private struct HomeSettings: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "Home") {
            Section {
                HomeAddressField(address: $settings.homeAddress)
            } header: {
                Text("Home")
            } footer: {
                Text("Where drives to appointments start. Blank uses your current location (Apple Maps only).")
            }

            ResetPageSection(detail: "The home address is cleared; drives start from your current location (Apple Maps only).") {
                settings.resetToDefaults(SettingsPages.home)
            }
        }
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
    @State private var markedCount: Int?

    var body: some View {
        Section {
            LabeledContent("Wake-up keyword") {
                TextField("wake up", text: $settings.appointmentKeyword)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
            }
            if settings.appointmentKeyword.trimmingCharacters(in: .whitespaces).isEmpty {
                Label("With no keyword, no appointment gets an alarm; only shifts do.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.warning.text)
            }
            if let markedCount {
                Text(markedCount == 1 ? "1 upcoming event is marked \(settings.appointmentKeyword)" : "\(markedCount) upcoming events are marked \(settings.appointmentKeyword)")
                    .foregroundStyle(Theme.textMuted)
            }
            NavigationLink("Mark events in Upcoming events") { UpcomingEventsView() }
        } header: {
            Text("Wake-up keyword")
        } footer: {
            Text("Put this word or phrase in an event's notes and the app will wake you for that event. Events without it are ignored for alarms. Work shifts don't need it: they're found by their title (Days, Swings). Example: \"Notes: wake up · bring insurance card\". It matches anywhere in the notes, in any case. You can also set it for each event from Upcoming events.")
        }
        Section {
            DefaultStepper(value: $settings.arrivalBufferMinutes, in: 0...60, step: 5, defaultValue: BridgeSettings().arrivalBufferMinutes, note: { "\($0) min" }) { "Arrive early: \($0) min" }
            DefaultToggle(title: "Ask about missing locations", isOn: $settings.askAboutMissingLocations, defaultValue: BridgeSettings().askAboutMissingLocations)
        } header: {
            Text("Appointments")
        } footer: {
            Text("Wake time = start − arrive-early buffer − drive time − get-ready time (on the main Settings page). On a work morning, a marked appointment that starts before your shift ends is used instead of the shift (you're going in late); one after the shift ends isn't. A marked appointment without a location is planned with the fallback drive until you answer the notification about it.")
        }
        .task(id: settings.appointmentKeyword) { markedCount = BedtimeCoordinator.shared.markedUpcomingCount(settings: settings) }
    }
}

private struct LeaveReminderSection: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        Section {
            DefaultToggle(title: "Leave-by reminder", isOn: $settings.leaveReminderEnabled, defaultValue: BridgeSettings().leaveReminderEnabled)
            if settings.leaveReminderEnabled {
                NavigationLink {
                    LeaveRemindersPicker(offsets: $settings.leaveReminderOffsets)
                } label: {
                    LabeledContent("Leave reminders", value: LeaveRemindersPicker.summary(settings.leaveReminderOffsets))
                }
            }
            DefaultStepper(value: $settings.widgetLeaveByMinutes, in: 0...120, step: 5, defaultValue: BridgeSettings().widgetLeaveByMinutes, note: { "\($0) min" }) { "Widget: leave-by until \($0) min after" }
        } footer: {
            Text("For shifts and appointments with a location. Each reminder re-checks traffic: Home Assistant sends RUN_LEAVE_CHECK at its time and Check Drive and Remind notifies with the fresh drive. The drive is also re-checked when you stop an alarm and when you open the app. Reminders set at bedtime arrive 2 min late, marked \"not re-checked\", if no fresh check came. They stop 15 min after leave-by. Once the alarms are done, the Lock Screen widget shows leave-by until this long after it.")
        }
    }
}

/// Settings → Leave reminders: any of At leave time, 5…30 min before (item 17).
private struct LeaveRemindersPicker: View {
    @Binding var offsets: [Int]

    static func name(_ minutes: Int) -> String { minutes == 0 ? "At leave time" : "\(minutes) min before" }

    static func summary(_ offsets: [Int]) -> String {
        offsets.isEmpty ? "None" : offsets.sorted(by: >).map { $0 == 0 ? "at leave time" : "\($0) min" }.joined(separator: ", ")
    }

    var body: some View {
        SettingsPage(title: "Leave reminders") {
            Section {
                ForEach(BridgeSettings.leaveReminderChoices.reversed(), id: \.self) { minutes in
                    Toggle(Self.name(minutes), isOn: Binding(
                        get: { offsets.contains(minutes) },
                        set: { on in
                            offsets.removeAll { $0 == minutes }
                            if on { offsets.append(minutes) }
                            offsets.sort(by: >)
                        }
                    ))
                }
            } footer: {
                Text("Each one re-checks the drive and tells you when to leave. Later reminders follow the new leave-by.")
            }
        }
    }
}

private struct DriveTimeSection: View {
    @Binding var settings: BridgeSettings
    @State private var googleKeySaved = !KeychainStore.apiKey(for: .google).isEmpty

    var body: some View {
        Section {
            Picker(selection: $settings.driveTimeSource) {
                ForEach(DriveTimeSource.allCases) { Text($0.displayName).tag($0) }
            } label: {
                WithDefault(text: "Use", defaultText: settings.driveTimeSource == BridgeSettings().driveTimeSource ? nil : BridgeSettings().driveTimeSource.displayName)
            }
            if googleKeySaved || settings.driveTimeSource == .google {
                Picker(selection: $settings.googlePessimisticTraffic) {
                    Text("A typical day").tag(false)
                    Text("Worst case").tag(true)
                } label: {
                    WithDefault(text: "Google plans for", defaultText: settings.googlePessimisticTraffic == BridgeSettings().googlePessimisticTraffic ? nil : (BridgeSettings().googlePessimisticTraffic ? "worst case" : "a typical day"))
                }
            }
            DefaultStepper(value: $settings.fallbackTravelMinutes, in: 0...180, step: 5, defaultValue: BridgeSettings().fallbackTravelMinutes, note: { "\($0) min" }) { "If no drive time: \($0) min" }
            DefaultToggle(title: "Start from where I am when away", isOn: $settings.driveFromHereWhenAway, defaultValue: BridgeSettings().driveFromHereWhenAway)
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
            Section {
                Picker(selection: $settings.newEventsCalendarID) {
                    Text("The calendar holding the shifts").tag("")
                    ForEach(calendars.filter(\.allowsContentModifications), id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
                } label: {
                    WithDefault(text: "Calendar for new events", defaultText: settings.newEventsCalendarID.isEmpty ? nil : "the shifts' calendar")
                }
            } footer: {
                Text("Where Add leave and Add a wake-up event save.")
            }
            ResetPageSection(detail: "Shifts and appointments are searched in every calendar again.") { settings.resetToDefaults(SettingsPages.calendars) }
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
                    Toggle("Same as appointment & event alarms", isOn: usesGeneralSeries)
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

/// Settings → Alarms (v0.4.3 item 6: Your own alarms has its own page; Test alarm at the bottom).
private struct AlarmSettingsSection: View {
    @Binding var settings: BridgeSettings
    private let d = BridgeSettings()

    var body: some View {
        Section {
            Picker(selection: $settings.alarmStyle) {
                ForEach(AlarmStyle.allCases) { Text($0.displayName).tag($0) }
            } label: {
                WithDefault(text: "Alarms", defaultText: settings.alarmStyle == d.alarmStyle ? nil : d.alarmStyle.displayName)
            }
            // v0.4.7 item 7: the two alarm series, each on its own page, at the top.
            NavigationLink {
                AppointmentAlarmSettings(settings: $settings)
            } label: {
                LabeledContent("Appointment & event alarms", value: AlarmSeriesText.summary(count: settings.alarmCount, spacing: settings.alarmSpacingMinutes))
            }
            if settings.alarmStyle == .app {
                NavigationLink {
                    OwnAlarmSettings(settings: $settings)
                } label: {
                    LabeledContent("Your own alarms", value: AlarmSeriesText.summary(count: settings.ownAlarmCount, spacing: settings.ownAlarmSpacingMinutes))
                }
            }
            if settings.alarmStyle == .app {
                DefaultStepper(value: $settings.snoozeMinutes, in: 1...30, defaultValue: d.snoozeMinutes, note: { "\($0) min" }) { "Snooze: \($0) min" }
                AlarmSoundPicker(sound: $settings.alarmSound)
                Picker(selection: $settings.stopBehavior) {
                    ForEach(StopBehavior.allCases) { Text($0.displayName).tag($0) }
                } label: {
                    WithDefault(text: "When I stop an alarm", defaultText: settings.stopBehavior == d.stopBehavior ? nil : d.stopBehavior.displayName.lowercased())
                }
                NavigationLink("When options show") {
                    OptionWindowsSettings(settings: $settings)
                }
                NavigationLink("Change this morning") {
                    MorningChangeSettings(settings: $settings)
                }
            }
            DefaultStepper(value: $settings.lookAheadHours, in: 6...72, defaultValue: d.lookAheadHours, note: { "\($0) h" }) { "Look ahead \($0) h" }
        } header: {
            Text("Alarms")
        } footer: {
            switch settings.alarmStyle {
            case .app:
                Text("Rings through Silent and Focus. Snooze and Stop tell Home Assistant directly (set it up below), because the Shortcuts \"alarm snoozed/stopped\" automations only see Clock app alarms. \"Keep the rest until I'm up\" cancels the later alarms only once Home Assistant sees the bedroom door opened or the bed empty for over a minute, so stopping the first alarm and dozing off still leaves the others. A new sound is used from the next time alarms are set.")
            case .clock:
                Text("The app works out the times and your shortcut creates Clock alarms from Wake Plan › Alarm Dates. Your snooze/stop automations keep working, but Apple fixes Clock snooze at 9 minutes.")
            }
        }
        Section {
            DefaultToggle(title: "Plug in your phone", isOn: $settings.chargeWarningEnabled, defaultValue: d.chargeWarningEnabled)
            if settings.chargeWarningEnabled {
                DefaultStepper(value: $settings.chargeWarningThreshold, in: 5...80, step: 5, defaultValue: d.chargeWarningThreshold, note: { "\($0)%" }) { "Under \($0)% and not charging" }
            }
        } footer: {
            Text("At bedtime (and at go to bed with wind-down on), a reminder to plug in, and once more after 10 minutes if it's still not charging.")
        }
        ResetPageSection {
            settings.resetToDefaults(SettingsPages.alarms)
        }
        if settings.alarmStyle == .app {
            Section {
                TestAlarmButton(settings: settings)
            }
        }
    }
}

/// Settings → Nap (v0.4.2 item 3).
private struct NapSettings: View {
    @Binding var settings: BridgeSettings
    @State private var newLength = 15

    var body: some View {
        SettingsPage(title: "Nap") {
            Section {
                DefaultToggle(title: "Nap", isOn: $settings.napEnabled, defaultValue: BridgeSettings().napEnabled)
            } footer: {
                Text("Shows the Nap button. A nap's alarms behave like temporary alarms: no wake routines, Good Morning or backstops, and your other alarms stay.")
            }
            if settings.napEnabled {
                Section {
                    Stepper("\(settings.napAlarmCount) alarm\(settings.napAlarmCount == 1 ? "" : "s")", value: $settings.napAlarmCount, in: 1...5)
                    DefaultStepper(value: $settings.napSpacingMinutes, in: 1...30, defaultValue: BridgeSettings().napSpacingMinutes, note: { "\($0) min" }) { "\($0) min apart" }
                } header: {
                    Text("Alarms")
                }
                Section {
                    DefaultStepper(value: $settings.napReadyWithAddressMinutes, in: 0...120, step: 5, defaultValue: BridgeSettings().napReadyWithAddressMinutes, note: { "\($0) min" }) { "Events with an address: \($0) min" }
                    DefaultStepper(value: $settings.napReadyNoAddressMinutes, in: 0...120, step: 5, defaultValue: BridgeSettings().napReadyNoAddressMinutes, note: { "\($0) min" }) { "Events without an address: \($0) min" }
                } header: {
                    Text("Get-ready buffer")
                } footer: {
                    Text("Your last nap alarm must leave this long before you leave for a shift or an event with an address (after the drive time now and arriving early), or before an event without one, where you may just get up and stay home.")
                }
                Section {
                    ForEach(settings.napLengths, id: \.self) { minutes in
                        Text(NapPlanner.lengthName(minutes))
                    }
                    .onDelete { settings.napLengths.remove(atOffsets: $0) }
                    HStack {
                        Stepper(NapPlanner.lengthName(newLength), value: $newLength, in: 5...600, step: 5)
                        Button("Add") {
                            if !settings.napLengths.contains(newLength) {
                                settings.napLengths.append(newLength)
                                settings.napLengths.sort()
                            }
                        }
                    }
                } header: {
                    Text("Quick choices")
                } footer: {
                    Text("Swipe to remove one. Other… on the nap screen picks any length.")
                }
            }
            ResetPageSection { settings.resetToDefaults(SettingsPages.nap) }
        }
    }
}

/// When each situational option shows (v0.4.2 item 7).
private struct OptionWindowsSettings: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "When options show") {
            Section {
                DefaultStepper(value: $settings.endAlarmsEarlyHours, in: 1...12, defaultValue: BridgeSettings().endAlarmsEarlyHours, note: { "\($0) h" }) { "I'm up early / End this morning's alarms: from \($0) h before the first alarm" }
                DefaultStepper(value: $settings.notReadyForBedHours, in: 1...12, defaultValue: BridgeSettings().notReadyForBedHours, note: { "\($0) h" }) { "Not ready for bed: for \($0) h after bedtime ran" }
                DefaultStepper(value: $settings.backToBedHours, in: 1...12, defaultValue: BridgeSettings().backToBedHours, note: { "\($0) h" }) { "Back to bed: until \($0) h after the wake-up or the last stop, whichever is later" }
                LabeledContent("Sleep later", value: "until the first alarm")
                DefaultStepper(value: $settings.startWindDownHours, in: 1...6, defaultValue: BridgeSettings().startWindDownHours, note: { "\($0) h" }) { "Start wind-down now: from \($0) h before go to bed" }
            } footer: {
                Text("These decide when each option shows in the bottom bar, the ⋯ menu and the cards.")
            }
            ResetPageSection { settings.resetToDefaults(SettingsPages.optionWindows) }
        }
    }
}

/// Settings → Alarms → Your own alarms (v0.4.3 item 6): used whenever alarms are made by hand,
/// with the backstops for your own alarm folded in.
/// Settings → Alarms → Appointment & event alarms (v0.4.7 item 7): the series appointments, events
/// and shifts without their own series use.
private struct AppointmentAlarmSettings: View {
    @Binding var settings: BridgeSettings
    private let d = BridgeSettings()

    var body: some View {
        SettingsPage(title: "Appointment & event alarms") {
            Section {
                DefaultStepper(value: $settings.alarmCount, in: 1...10, defaultValue: d.alarmCount) { "\($0) alarms" }
                DefaultStepper(value: $settings.alarmSpacingMinutes, in: 1...60, defaultValue: d.alarmSpacingMinutes, note: { "\($0) min" }) { "\($0) min apart" }
                Picker(selection: $settings.wakeTimeIs) {
                    ForEach(WakeTimeAlarm.allCases) { Text($0.displayName).tag($0) }
                } label: {
                    WithDefault(text: "Wake-up time is the", defaultText: settings.wakeTimeIs == d.wakeTimeIs ? nil : d.wakeTimeIs.displayName.lowercased())
                }
            } footer: {
                Text(AlarmSeriesText.example(count: settings.alarmCount, spacing: settings.alarmSpacingMinutes, wakeIs: settings.wakeTimeIs)
                     + ". Used for \"wake up\" appointments and events, and for shifts set to the same as these.")
            }
            ResetPageSection { settings.resetToDefaults(SettingsPages.appointmentAlarms) }
        }
    }
}

private struct OwnAlarmSettings: View {
    @Binding var settings: BridgeSettings
    private let d = BridgeSettings()

    var body: some View {
        SettingsPage(title: "Your own alarms") {
            Section {
                DefaultStepper(value: $settings.newAlarmHoursAhead, in: 1...12, defaultValue: d.newAlarmHoursAhead, note: { "\($0) h" }) { "Start new alarms this far from now: \($0) h" }
                Picker(selection: $settings.ownAlarmRoundingMinutes) {
                    Text("Exact").tag(0)
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                } label: {
                    WithDefault(text: "Round the time to", defaultText: settings.ownAlarmRoundingMinutes == d.ownAlarmRoundingMinutes ? nil : "\(d.ownAlarmRoundingMinutes) min")
                }
                if settings.ownAlarmRoundingMinutes > 0 {
                    DefaultToggle(title: "Picker shows only those times", isOn: $settings.ownAlarmPickerSnaps, defaultValue: d.ownAlarmPickerSnaps)
                }
            } header: {
                Text("Time")
            } footer: {
                Text("The time starts \(settings.newAlarmHoursAhead) h from now, rounded up (15 min: 6:54 → 7:00, 7:02 → 7:15). Exact: the picker allows any minute.")
            }
            Section {
                DefaultStepper(value: $settings.ownAlarmCount, in: 1...10, defaultValue: d.ownAlarmCount) { "\($0) alarms" }
                DefaultStepper(value: $settings.ownAlarmSpacingMinutes, in: 1...60, defaultValue: d.ownAlarmSpacingMinutes, note: { "\($0) min" }) { "\($0) min apart" }
                Picker(selection: $settings.ownAlarmWakeIs) {
                    ForEach(WakeTimeAlarm.allCases) { Text($0.displayName).tag($0) }
                } label: {
                    WithDefault(text: "The time is the", defaultText: settings.ownAlarmWakeIs == d.ownAlarmWakeIs ? nil : d.ownAlarmWakeIs.displayName.lowercased())
                }
            } header: {
                Text("Alarms")
            }
            Section {
                DefaultToggle(title: "On by default on a day off", isOn: $settings.ownBackstopsDayOff, defaultValue: d.ownBackstopsDayOff)
                DefaultToggle(title: "On by default on leave", isOn: $settings.ownBackstopsLeave, defaultValue: d.ownBackstopsLeave)
                DefaultStepper(value: $settings.ownEarlyMinutes, in: 0...120, step: 5, defaultValue: d.ownEarlyMinutes, note: { "\($0) min" }) { "Early: \($0) min after the last alarm" }
                DefaultStepper(value: $settings.ownDeadlineMinutes, in: 5...180, step: 5, defaultValue: d.ownDeadlineMinutes, note: { "\($0) min" }) { "Deadline: \($0) min after" }
                DefaultStepper(value: $settings.ownLateMinutes, in: 10...240, step: 5, defaultValue: d.ownLateMinutes, note: { "\($0) min" }) { "Late: \($0) min after" }
                if !settings.ownOffsetsValid {
                    Text("Early must come before deadline, and deadline before late; until then Home Assistant uses 15, 30 and 45.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                }
                DefaultToggle(title: "Use the full backstop actions", isOn: $settings.ownBackstopsFull, defaultValue: d.ownBackstopsFull)
            } header: {
                Text("Backstops")
            } footer: {
                Text("Where you set the alarm there's a switch for that morning. Off: no backstops. Gentle (full off): a push and the early light ramp; no critical sound, no speakers.")
            }
            Section {
            } footer: {
                Text("Used when you set alarms yourself: a day off with no events, skipping to your own time, or picking a new wake-up in the morning.")
            }
            ResetPageSection {
                settings.resetToDefaults(SettingsPages.ownAlarms)
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
                DefaultStepper(value: $settings.earlyBackstopGapMinutes, in: 0...30, defaultValue: BridgeSettings().earlyBackstopGapMinutes, note: { "\($0) min" }) { "Early backstop: \($0) min after the last alarm" }
            } footer: {
                Text("With Shift alarms only, the early backstop moves to this long after the new last alarm if it would otherwise come before it.")
            }
            ResetPageSection { settings.resetToDefaults(SettingsPages.morningChange) }
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
            Picker(selection: $sound) {
                ForEach(AlarmSound.allCases) { Text($0.displayName).tag($0) }
            } label: {
                WithDefault(text: "Sound", defaultText: sound == BridgeSettings().alarmSound ? nil : BridgeSettings().alarmSound.displayName)
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
                EntityField(title: "On snooze, turn on", text: $settings.snoozeHelper, defaultValue: BridgeSettings().snoozeHelper)
                EntityField(title: "On stop, turn on", text: $settings.stopHelper, defaultValue: BridgeSettings().stopHelper)
                EntityField(title: "Shift override", text: $settings.shiftOverrideEntity, defaultValue: BridgeSettings().shiftOverrideEntity)
                EntityField(title: "Shift sensor", text: $settings.shiftSensorEntity, defaultValue: BridgeSettings().shiftSensorEntity)
                EntityField(title: "Next-alarm sensor", text: $settings.nextAlarmSensor, defaultValue: BridgeSettings().nextAlarmSensor)
                EntityField(title: "Bedtime routine", text: $settings.bedtimeHelper, defaultValue: BridgeSettings().bedtimeHelper)
                EntityField(title: "You", text: $settings.presenceEntity, defaultValue: BridgeSettings().presenceEntity)
                EntityField(title: "Bed sensor", text: $settings.bedSensor, defaultValue: BridgeSettings().bedSensor)
                EntityField(title: "Left the bedroom", text: $settings.exitLatch, defaultValue: BridgeSettings().exitLatch)
                DefaultToggle(title: "Only run routines when home", isOn: $settings.homeOnly, defaultValue: BridgeSettings().homeOnly)
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
        case .apple:
            "Apple Weather's hourly forecast for your home address (your current location if it's blank). No key or Home Assistant needed."
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
            DefaultStepper(value: $settings.weatherExtraMinutes, in: 0...60, step: 5, defaultValue: BridgeSettings().weatherExtraMinutes, note: { "\($0) min" }) { "Default extra time: \($0) min" }
            Picker(selection: $settings.weatherSource) {
                ForEach(WeatherSource.allCases) { Text($0.displayName).tag($0) }
            } label: {
                WithDefault(text: "Forecast from", defaultText: settings.weatherSource == BridgeSettings().weatherSource ? nil : BridgeSettings().weatherSource.displayName)
            }
            if settings.weatherSource == .apple {
                AppleWeatherAttribution()
            }
            if settings.weatherSource == .homeAssistant {
                if usesIntegration {
                    LabeledContent("Weather entity", value: "Chosen in Home Assistant")
                } else {
                    EntityField(title: "Weather entity", text: $settings.weatherEntity, defaultValue: BridgeSettings().weatherEntity)
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
    /// Shown in grey when the entity differs from it (v0.4.3 item 8).
    var defaultValue: String? = nil

    var body: some View {
        LabeledContent {
            TextField("entity_id", text: $text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout.monospaced())
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let defaultValue, defaultValue != text { DefaultNote(text: defaultValue) }
            }
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
