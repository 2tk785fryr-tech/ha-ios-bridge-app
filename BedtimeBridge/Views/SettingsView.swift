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
            // v0.4.11 item 50: the main page in groups.
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
                ResetRow(title: "Reset shifts to Days and Swings", detail: "Your shifts go back to the defaults (Days and Swings). Other settings keep theirs.") {
                    store.settings.resetToDefaults(SettingsPages.main)
                }
            } header: {
                Text("Your schedule")
            } footer: {
                Text("A calendar event whose title contains a shift's word counts as that shift.")
            }

            Section {
                SettingsLink(title: "Remote days", icon: "house.and.flag", value: RemoteDaysText.summary(settings)) {
                    RemoteDaysSettings(settings: $store.settings)
                }
                SettingsLink(title: "Appointments", icon: "calendar.badge.clock",
                             value: settings.appointmentKeyword.isEmpty ? "Wake-up keyword: none" : "Wake-up keyword: \(settings.appointmentKeyword)") {
                    SettingsPage(title: "Appointments") {
                        AppointmentsSection(settings: $store.settings)
                        ResetPageSection { store.settings.resetToDefaults(SettingsPages.appointments) }
                    }
                }
                SettingsLink(title: "Vacations", icon: "beach.umbrella", value: settings.leaveTitles.joined(separator: ", ")) {
                    LeaveSettings(settings: $store.settings)
                }
                SettingsLink(title: "Calendars", icon: "calendar", value: calendarSummary(settings)) {
                    CalendarsPage(settings: $store.settings)
                }
            }

            Section("Mornings") {
                SettingsLink(title: "Mornings", icon: "sunrise", value: "Get ready \(settings.getReadyMinutes) min") {
                    MorningsSettings(settings: $store.settings)
                }
                SettingsLink(title: "Alarms", icon: "alarm", value: AlarmSeriesText.alarmsRow(style: settings.alarmStyle, snooze: settings.snoozeMinutes)) {
                    SettingsPage(title: "Alarms") { AlarmSettingsSection(settings: $store.settings) }
                }
                SettingsLink(title: "Nap", icon: "powersleep", value: settings.napEnabled ? "\(settings.napAlarmCount) alarms, \(settings.napSpacingMinutes) min apart" : "Off") {
                    NapSettings(settings: $store.settings)
                }
                SettingsLink(title: "Drive time", icon: "car", value: settings.driveTimeSource.displayName) {
                    DriveTimePage(settings: $store.settings)
                }
                SettingsLink(title: "Weather", icon: "cloud.sun", value: settings.checksWeather ? "Default +\(settings.weatherExtraMinutes) min" : "Off") {
                    SettingsPage(title: "Weather") {
                        WeatherSection(settings: $store.settings)
                        ResetPageSection {
                            store.settings.resetToDefaults(SettingsPages.weather)
                        }
                    }
                }
            }

            Section("Evenings") {
                SettingsLink(title: "Wind-down", icon: "moon.zzz", value: settings.windDownEnabled ? "Sleep goal \(DurationText.hours(settings.sleepGoalMinutes))" : "Off") {
                    WindDownSettings(settings: $store.settings)
                }
            }

            Section("Home Assistant") {
                SettingsLink(title: "Home Assistant", icon: "house", value: homeAssistantSummary(settings)) {
                    SettingsPage(title: "Home Assistant") {
                        HomeAssistantSection(settings: $store.settings)
                        ResetPageSection(detail: "Only this page's settings go back to their defaults. The pairing and token stay (Settings → Reset clears them).") {
                            store.settings.resetToDefaults(SettingsPages.homeAssistant)
                        }
                    }
                }
                SettingsLink(title: "Notifications", icon: "bell.badge", value: "") {
                    NotificationSettings(settings: $store.settings)
                }
            }

            Section("The app") {
                SettingsLink(title: "Shortcuts, controls and Siri", icon: "square.grid.2x2", value: "") {
                    ShortcutsSettings(settings: $store.settings)
                }
                // v0.4.11 item 55: moved from Alarms.
                SettingsLink(title: "When bar buttons show", icon: "rectangle.bottomthird.inset.filled", value: "") {
                    OptionWindowsSettings(settings: $store.settings)
                }
                SettingsLink(title: "Weekly summary", icon: "calendar.day.timeline.left", value: settings.weeklySummaryEnabled ? "On" : "Off") {
                    WeeklySummarySettings(settings: $store.settings)
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
                SettingsLink(title: "App icon", icon: "app.badge", value: AppIconChoice.current.title) {
                    SettingsPage(title: "App icon") { AppIconSection() }
                }
            }

            // v0.4.8 items 9 and 12.
            Section("About") {
                // v0.4.11 item 31.
                SettingsLink(title: "How to use Bedtime Bridge", icon: "book", value: "") {
                    TutorialView()
                }
                SettingsLink(title: "Testing reports", icon: "ladybug", value: TestingReports.enabled ? "On" : "Off") {
                    TestingReportsPage(settings: store.settings)
                }
                SettingsLink(title: "Testing checklist", icon: "checklist", value: "\(TestingChecklist.ticked.count) of \(TestingChecklist.Item.allCases.count)") {
                    TestingChecklistPage()
                }
                SettingsLink(title: "Reset", icon: "arrow.counterclockwise", value: "") {
                    ResetSettings(settings: $store.settings)
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

/// Settings → Mornings: get-ready time, arriving early and waking early enough.
/// v0.4.11 items 5, 10 and 11: how a remote shift is recognised, its get-ready time and its
/// backstops.
private struct RemoteDaysSettings: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "Remote days") {
            Section {
                DefaultToggle(title: "Location says I'm home", isOn: $settings.remoteByLocation,
                              defaultValue: BridgeSettings().remoteByLocation)
                    .info("The shift's location is Home, Remote, or your home address.")
                DefaultToggle(title: "No location means remote", isOn: $settings.remoteWhenNoLocation,
                              defaultValue: BridgeSettings().remoteWhenNoLocation)
                    .info("A shift with an empty location is worked from home. Off: it plans the drive to work as usual.")
                DefaultToggle(title: "Title has a remote word", isOn: $settings.remoteByKeyword,
                              defaultValue: BridgeSettings().remoteByKeyword)
                    .info("The shift's own word still has to match, so \"Days WFH\" is a Days shift worked from home.")
                if settings.remoteByKeyword {
                    TextField("Remote words", text: Binding(
                        get: { settings.remoteKeywords.joined(separator: ", ") },
                        set: { settings.remoteKeywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    ))
                    .textInputAutocapitalization(.never)
                }
            } header: {
                Text("A remote day")
            } footer: {
                Text("How a shift is recognised as worked from home. Office days keep their drive.")
            }
            Section {
                DefaultStepper(value: $settings.remoteGetReadyMinutes, in: 0...180, step: 5,
                               defaultValue: BridgeSettings().remoteGetReadyMinutes, note: { "\($0) min" }) { "Get ready: \($0) min" }
            } header: {
                Text("Mornings")
            } footer: {
                Text("A remote day wakes you this long before the shift starts and plans no drive, Leave by or leave reminders. Fixed-time shifts keep their time.")
            }
            Section {
                Picker(selection: $settings.remoteBackstops) {
                    ForEach(RemoteBackstops.Mode.allCases) { Text($0.displayName).tag($0) }
                } label: {
                    WithDefault(text: "Backstops", defaultText: settings.remoteBackstops == BridgeSettings().remoteBackstops ? nil : BridgeSettings().remoteBackstops.displayName.lowercased())
                }
                .info("Spread: at a quarter, half and three quarters of the time between the last alarm and the start (last alarm 6:00, start 6:30: 6:07, 6:15, 6:22). Never past the start.")
                if settings.remoteBackstops == .afterLastAlarm {
                    DefaultStepper(value: $settings.remoteEarlyMinutes, in: 1...120, defaultValue: BridgeSettings().remoteEarlyMinutes, note: { "\($0) min" }) { "Early: \($0) min after" }
                    DefaultStepper(value: $settings.remoteDeadlineMinutes, in: 1...120, defaultValue: BridgeSettings().remoteDeadlineMinutes, note: { "\($0) min" }) { "Deadline: \($0) min after" }
                    DefaultStepper(value: $settings.remoteLateMinutes, in: 1...120, defaultValue: BridgeSettings().remoteLateMinutes, note: { "\($0) min" }) { "Late: \($0) min after" }
                }
            } header: {
                Text("Backstops")
            } footer: {
                Text("A remote day's backstops come after the last alarm and before the shift starts.")
            }
            ResetPageSection(detail: "Only this page's settings go back to their defaults.") {
                settings.resetToDefaults(SettingsPages.remoteDays)
            }
        }
    }
}

private struct MorningsSettings: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "Mornings") {
            Section {
                DefaultStepper(value: $settings.getReadyMinutes, in: 0...240, step: 5, defaultValue: BridgeSettings().getReadyMinutes, note: { "\($0) min" }) { "Get ready: \($0) min" }
                    .info("How long you need between waking and leaving.")
                // v0.4.11 item 53: both arrive-early times on one page.
                DefaultStepper(value: $settings.workArrivalBufferMinutes, in: 0...60, step: 5, defaultValue: BridgeSettings().workArrivalBufferMinutes, note: { "\($0) min" }) { "Arrive early · shifts: \($0) min" }
                    .info("When a shift has a location, Tonight shows when to leave to get there this early.")
                DefaultStepper(value: $settings.arrivalBufferMinutes, in: 0...60, step: 5, defaultValue: BridgeSettings().arrivalBufferMinutes, note: { "\($0) min" }) { "Arrive early · appointments: \($0) min" }
                    .info("Wake time = start − this − drive time − get-ready time.")
                DefaultToggle(title: "Move alarms earlier when time is short", isOn: $settings.wakeEarlyToGetReady, defaultValue: BridgeSettings().wakeEarlyToGetReady)
                    .info("If the drive or bad weather leaves less than the get-ready time, you're warned and can wake earlier that night. On: shift alarms move earlier by themselves. Appointments always plan the get-ready time.")
            } header: {
                Text("Mornings")
            } footer: {
                Text("How long you need in the morning and how early you like to arrive.")
            }

            // v0.4.6 item 2.
            Section {
                DefaultToggle(title: "Sleeping-in mornings", isOn: $settings.noAlarmMorningEnabled, defaultValue: BridgeSettings().noAlarmMorningEnabled)
                    .info("At home, on a morning with no alarms: out of bed and down the hall disarms the house (nothing else changes), and it re-arms once you're back in bed. I'm awake in the bar, Siri or a control runs good morning straight away.")
                if settings.noAlarmMorningEnabled {
                    LabeledContent {
                        DatePicker("", selection: earliest, displayedComponents: .hourAndMinute).labelsHidden()
                    } label: {
                        WithDefault(text: "Good morning from", defaultText: settings.noAlarmEarliest == BridgeSettings().noAlarmEarliest ? nil : "8:00 AM")
                    }
                    .info("The earliest Home Assistant asks Up for the day?. Also the time of the Morning weather row with no alarms, and when the in-bed bar ends.")
                    DefaultStepper(value: $settings.noAlarmUpMinutes, in: 5...60, step: 5, defaultValue: BridgeSettings().noAlarmUpMinutes, note: { "\($0) min" }) { "Up for: \($0) min" }
                        .info("Once you've been up this long (or the phone comes off the charger), Home Assistant asks Up for the day?.")
                    DefaultStepper(value: $settings.noAlarmWaitMinutes, in: 1...30, defaultValue: BridgeSettings().noAlarmWaitMinutes, note: { "\($0) min" }) { "Ask first, then go ahead after: \($0) min" }
                        .info("If you don't answer Up for the day?, good morning runs after this long: Sleep In off, Awake For Day on, Good Morning.")
                }
            } header: {
                Text("Mornings with no alarms")
            } footer: {
                Text("On a morning with no alarms, Home Assistant handles the house while you sleep in.")
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

/// Settings → Drive time, with the home address first (v0.4.11 item 54: Home moved in).
private struct DriveTimePage: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "Drive time") {
            Section {
                HomeAddressField(address: $settings.homeAddress)
            } header: {
                Text("Drives start from")
            } footer: {
                Text("Your home address, for every drive and the weather forecast. Blank uses your current location (Apple Maps only).")
            }
            DriveTimeSection(settings: $settings)
            LeaveReminderSection(settings: $settings)
            ResetPageSection(detail: "Only this page's settings go back to their defaults, the home address included. API keys stay (Settings → Reset clears them).") {
                settings.resetToDefaults(SettingsPages.driveTime)
            }
        }
    }
}

/// A settings screen in the Nightfall style.
/// v0.4.11 item 31: the Settings page a tutorial page's Take me there opens.
struct TutorialSettingsPage: View {
    @Environment(SettingsStore.self) private var store
    let link: Tutorial.Link

    var body: some View {
        @Bindable var store = store
        switch link {
        case .shifts: SettingsView()
        case .alarms: SettingsPage(title: "Alarms") { AlarmSettingsSection(settings: $store.settings) }
        case .appointments: SettingsPage(title: "Appointments") { AppointmentsSection(settings: $store.settings) }
        case .remoteDays: RemoteDaysSettings(settings: $store.settings)
        case .vacations: LeaveSettings(settings: $store.settings)
        case .calendars: CalendarsPage(settings: $store.settings)
        case .home, .driveTime: DriveTimePage(settings: $store.settings)
        case .homeAssistant: SettingsPage(title: "Home Assistant") { HomeAssistantSection(settings: $store.settings) }
        }
    }
}

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
            .info("It matches anywhere in the notes, in any case. Example: \"Notes: wake up · bring insurance card\". Shifts don't need it: they're found by their title.")
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
            Text("Put this word in an event's notes and the app wakes you for it. Events without it get no alarm.")
        }
        Section {
            DefaultToggle(title: "Ask about missing locations", isOn: $settings.askAboutMissingLocations, defaultValue: BridgeSettings().askAboutMissingLocations)
                .info("A marked appointment without a location is planned with the fallback drive until you answer the notification about it.")
        } header: {
            Text("Appointments")
        } footer: {
            Text("On a work morning, a marked appointment before your shift ends is used instead of the shift (you're going in late). Arrive-early time is in Settings → Mornings.")
        }
        .task(id: settings.appointmentKeyword) { markedCount = BedtimeCoordinator.shared.markedUpcomingCount(settings: settings) }
    }
}

private struct LeaveReminderSection: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        Section {
            // v0.4.11 item 61: one row for the switch and the list.
            NavigationLink {
                LeaveRemindersPicker(enabled: $settings.leaveReminderEnabled, offsets: $settings.leaveReminderOffsets)
            } label: {
                LabeledContent("Leave reminders", value: settings.leaveReminderEnabled ? LeaveRemindersPicker.summary(settings.leaveReminderOffsets) : "Off")
            }
            .info("For shifts and appointments with a location. The drive is also re-checked when you stop an alarm and when you open the app. A reminder that couldn't be re-checked arrives 2 min late, marked \"not re-checked\". They stop 15 min after leave-by.")
            DefaultStepper(value: $settings.widgetLeaveByMinutes, in: 0...120, step: 5, defaultValue: BridgeSettings().widgetLeaveByMinutes, note: { "\($0) min" }) { "Lock Screen shows Leave by until: \($0) min after" }
                .info("Once the alarms are done, the Lock Screen widget shows your leave-by time until this long after it.")
        } footer: {
            Text("Each reminder re-checks traffic first.")
        }
    }
}

/// Settings → Leave reminders: any of At leave time, 5…30 min before (item 17).
private struct LeaveRemindersPicker: View {
    @Binding var enabled: Bool
    @Binding var offsets: [Int]

    static func name(_ minutes: Int) -> String { minutes == 0 ? "At leave time" : "\(minutes) min before" }

    static func summary(_ offsets: [Int]) -> String {
        offsets.isEmpty ? "None" : offsets.sorted(by: >).map { $0 == 0 ? "at leave time" : "\($0) min" }.joined(separator: ", ")
    }

    var body: some View {
        SettingsPage(title: "Leave reminders") {
            Section {
                DefaultToggle(title: "Leave reminders", isOn: $enabled, defaultValue: BridgeSettings().leaveReminderEnabled)
            }
            if enabled {
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
}

private struct DriveTimeSection: View {
    @Binding var settings: BridgeSettings
    @State private var googleKeySaved = !KeychainStore.apiKey(for: .google).isEmpty

    var body: some View {
        Section {
            Picker(selection: $settings.driveTimeSource) {
                ForEach(DriveTimeSource.allCases) { Text($0.displayName).tag($0) }
            } label: {
                WithDefault(text: "Drive times from", defaultText: settings.driveTimeSource == BridgeSettings().driveTimeSource ? nil : BridgeSettings().driveTimeSource.displayName)
            }
            .info(driveTimeFooter(for: settings.driveTimeSource))
            if googleKeySaved || settings.driveTimeSource == .google {
                Picker(selection: $settings.googlePessimisticTraffic) {
                    Text("A typical day").tag(false)
                    Text("Worst case").tag(true)
                } label: {
                    WithDefault(text: "Google plans for", defaultText: settings.googlePessimisticTraffic == BridgeSettings().googlePessimisticTraffic ? nil : (BridgeSettings().googlePessimisticTraffic ? "worst case" : "a typical day"))
                }
            }
            // v0.4.11 item 1: Your morning's Leave by · worst case.
            Picker(selection: $settings.worstCaseArrival) {
                ForEach(WorstCaseArrival.allCases) { Text($0 == .whenItStarts ? "The start" : "Arriving early").tag($0) }
            } label: {
                WithDefault(text: "Worst-case Leave by aims for", defaultText: settings.worstCaseArrival == BridgeSettings().worstCaseArrival ? nil : (BridgeSettings().worstCaseArrival == .whenItStarts ? "the start" : "arriving early"))
            }
            .info("Your morning shows Leave by · worst case, the latest you can leave on a bad-traffic day. The start: you get there right as it starts. Arriving early: it takes off the same arrive-early time as Leave by.")
            DefaultStepper(value: $settings.fallbackTravelMinutes, in: 0...180, step: 5, defaultValue: BridgeSettings().fallbackTravelMinutes, note: { "\($0) min" }) { "Drive time when none is found: \($0) min" }
            DefaultToggle(title: "Start from where I am when away", isOn: $settings.driveFromHereWhenAway, defaultValue: BridgeSettings().driveFromHereWhenAway)
                .info("Away from home overnight (Home Assistant says so), drives start from where the phone is.")
        } header: {
            Text("Drive time")
        } footer: {
            Text("Where drive times come from and what to plan for.")
        }

        Section {
            APIKeyField(source: .tomTom) { _ in }
                .info("developer.tomtom.com › Dashboard › Keys.")
            APIKeyField(source: .google) { googleKeySaved = $0 }
                .info("A Routes API key from Google Cloud. With a Google key, its worst case is always shown on the timeline too.")
        } header: {
            Text("API keys")
        } footer: {
            Text("Saved in your Keychain as soon as you paste one. Every service with a key is asked each time and shown on the morning timeline.")
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
            Section("Shift calendars (none ticked = all)") {
                CalendarPicker(calendars: calendars, selection: $settings.shiftCalendarIDs)
            }
            Section("Appointment calendars (none ticked = all)") {
                CalendarPicker(calendars: calendars, selection: $settings.appointmentCalendarIDs)
            }
            // v0.4.11 item 60: moved from Alarms (Look ahead).
            Section {
                DefaultStepper(value: $settings.lookAheadHours, in: 6...72, defaultValue: BridgeSettings().lookAheadHours, note: { "\($0) h" }) { "Search this far ahead: \($0) h" }
                    .info("How far ahead the calendar is searched for tomorrow's shift or wake-up event.")
            }
            Section {
                Picker(selection: $settings.newEventsCalendarID) {
                    Text("The calendar holding the shifts").tag("")
                    ForEach(calendars.filter(\.allowsContentModifications), id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
                } label: {
                    WithDefault(text: "Calendar for new events", defaultText: settings.newEventsCalendarID.isEmpty ? nil : "the shifts' calendar")
                }
            } footer: {
                Text("Where Add vacation and Add a wake-up event save.")
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
                    .info("Before the shift: the alarms are worked out from when the shift starts. Fixed time: the same time whatever the start, e.g. a 14:30 shift you always get up at 8:00 for.")
                    switch rule.timing {
                    case .beforeShift:
                        Stepper("\(rule.wakeMinutesBefore) min before it starts", value: $rule.wakeMinutesBefore, in: 0...300, step: 5)
                    case .fixedTime:
                        DatePicker("Time", selection: fixedTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Toggle("Use the default alarm series", isOn: usesGeneralSeries)
                        .info("The default series is in Settings → Alarms → Default alarm series. It's also used for wake-up appointments and events.")
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
            // v0.4.11 item 55: Alarms ring from: This app / Clock app.
            Picker(selection: $settings.alarmStyle) {
                ForEach(AlarmStyle.allCases) { Text($0 == .app ? "This app" : "Clock app").tag($0) }
            } label: {
                WithDefault(text: "Alarms ring from", defaultText: settings.alarmStyle == d.alarmStyle ? nil : "this app")
            }
            .info(settings.alarmStyle == .app
                  ? "Rings through Silent and Focus. Snooze and Stop tell Home Assistant directly, because the Shortcuts \"alarm snoozed/stopped\" automations only see Clock app alarms."
                  : "The app works out the times and your shortcut creates Clock alarms from Wake Plan › Alarm Dates. Your snooze/stop automations keep working, but Apple fixes Clock snooze at 9 minutes.")
            // v0.4.7 item 7: the two alarm series, each on its own page, at the top.
            NavigationLink {
                AppointmentAlarmSettings(settings: $settings)
            } label: {
                LabeledContent("Default alarm series", value: AlarmSeriesText.summary(count: settings.alarmCount, spacing: settings.alarmSpacingMinutes))
            }
            .info("Used for wake-up appointments and events, and for shifts set to use the default series.")
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
                    .info("A new sound is used from the next time alarms are set.")
                NavigationLink("Reasons for changing alarms") {
                    MorningChangeSettings(settings: $settings)
                }
            }
        } header: {
            Text("Alarms")
        } footer: {
            Text("How your alarms ring and how many there are.")
        }
        if settings.alarmStyle == .app {
            Section {
                TestAlarmButton(settings: settings)
            }
        }
        ResetPageSection {
            settings.resetToDefaults(SettingsPages.alarms)
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
                DefaultToggle(title: "Show Nap", isOn: $settings.napEnabled, defaultValue: BridgeSettings().napEnabled)
                    .info("A nap's alarms behave like temporary alarms: no wake routines, Good Morning or backstops, and your other alarms stay.")
            } footer: {
                Text("Short naps with a few alarms of their own.")
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
                    HStack {
                        Text("Up before you leave")
                        InfoButton(text: "Your last nap alarm leaves this long before you leave for a shift or an event with an address (after the drive and arriving early), or before an event without one, where you may just get up and stay home.")
                    }
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
struct OptionWindowsSettings: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "When bar buttons show") {
            Section {
                DefaultStepper(value: $settings.endAlarmsEarlyHours, in: 1...12, defaultValue: BridgeSettings().endAlarmsEarlyHours, note: { "\($0) h" }) { "End this morning's alarms: from \($0) h before the first alarm" }
                DefaultStepper(value: $settings.notReadyForBedHours, in: 1...12, defaultValue: BridgeSettings().notReadyForBedHours, note: { "\($0) h" }) { "Not ready for bed: for \($0) h after bedtime ran" }
                DefaultStepper(value: $settings.backToBedHours, in: 1...12, defaultValue: BridgeSettings().backToBedHours, note: { "\($0) h" }) { "Back to bed: until \($0) h after the wake-up or the last stop, whichever is later" }
                LabeledContent("Wake up later", value: "until the first alarm")
            } footer: {
                Text("When each button shows in the bottom bar, the ⋯ menu and the cards. Start wind-down now is set on Wind-down.")
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
        SettingsPage(title: "Default alarm series") {
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
                DefaultStepper(value: $settings.newAlarmHoursAhead, in: 1...12, defaultValue: d.newAlarmHoursAhead, note: { "\($0) h" }) { "The time picker starts at: now + \($0) h" }
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
                Text("Used when you set alarms yourself: a day off with no events, skipping to your own time, or picking a new wake-up in the morning. The time is rounded up (15 min: 6:54 → 7:00).")
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
                DefaultToggle(title: "Full backstops (off: gentle)", isOn: $settings.ownBackstopsFull, defaultValue: d.ownBackstopsFull)
                    .info("Gentle: a push and the early light ramp; no critical sound, no speakers.")
            } header: {
                Text("Backstops")
            } footer: {
                Text("Where you set the alarm there's a switch for that morning's backstops.")
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
        SettingsPage(title: "Reasons for changing alarms") {
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
                // v0.4.11 item 63: almost nobody needs these.
                DisclosureGroup("Without the integration (advanced)") {
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
                EntityField(title: "Your person entity", text: $settings.presenceEntity, defaultValue: BridgeSettings().presenceEntity)
                    .info("Your person or device tracker, so routines only run when you're home.")
                EntityField(title: "Bed sensor", text: $settings.bedSensor, defaultValue: BridgeSettings().bedSensor)
                EntityField(title: "Left-the-bedroom sensor", text: $settings.exitLatch, defaultValue: BridgeSettings().exitLatch)
                    .info("Turns on once you've left the bedroom in the morning, so later alarms can be cancelled.")
                DefaultToggle(title: "Only run routines when home", isOn: $settings.homeOnly, defaultValue: BridgeSettings().homeOnly)
                }
            }
            Button("Test connection") { Task { await test() } }
            if let testResult {
                Text(testResult).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Home Assistant")
        } footer: {
            if usesIntegration {
                Text("Tap the pairing link in Home Assistant to fill both addresses. Helpers and sensors are chosen in Home Assistant (Settings › Devices & services › Bedtime Bridge › Configure).")
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
            // v0.4.11 item 62: the source first.
            Picker(selection: $settings.weatherSource) {
                ForEach(WeatherSource.allCases) { Text($0.displayName).tag($0) }
            } label: {
                WithDefault(text: "Forecast from", defaultText: settings.weatherSource == BridgeSettings().weatherSource ? nil : BridgeSettings().weatherSource.displayName)
            }
            .info(sourceFooter)
            DefaultStepper(value: $settings.weatherExtraMinutes, in: 0...60, step: 5, defaultValue: BridgeSettings().weatherExtraMinutes, note: { "\($0) min" }) { "Default extra time: \($0) min" }
                .info("How much earlier the alarm and leave-by move for a bad-weather condition set to Default below.")
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
            Text("Weather")
        } footer: {
            Text("The forecast from your first alarm until you need to be there. Bad weather moves the alarm and leave-by earlier.")
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
