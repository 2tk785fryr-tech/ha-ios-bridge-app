import SwiftUI

/// The weekly summary screen (v0.4.3 item 15): this week so far, and the 8 weeks before it,
/// cut at Settings → Weekly summary's day and time (v0.4.6 item 5).
struct WeeklySummaryView: View {
    let settings: BridgeSettings
    /// From the weekly notification: open on the week that just ended.
    var justEnded = false
    /// In Settings it's pushed onto the page's stack; from the notification it's a sheet.
    var inSheet = true
    @State private var weeks = WeeklySummaryView.saved
    @State private var index = 0
    @Environment(\.dismiss) private var dismiss

    /// The weeks from Home Assistant, or the single summary an older integration sends.
    private static var saved: [WeeklySummary] {
        let weeks = WeeklySummary.cachedWeeks
        return weeks.isEmpty ? WeeklySummary.cached.map { [$0] } ?? [] : weeks
    }

    var body: some View {
        if inSheet {
            NavigationStack {
                page.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        } else {
            page
        }
    }

    private var page: some View {
        SettingsPage(title: weeks.indices.contains(index) && weeks[index].current ? "This week so far" : "Your week") {
            if weeks.indices.contains(index) {
                let summary = weeks[index]
                Section {
                    HStack {
                        Button { index += 1 } label: { Image(systemName: "chevron.left") }
                            .disabled(index >= weeks.count - 1)
                            .accessibilityLabel("Earlier week")
                        Spacer()
                        Text(summary.rangeText ?? "")
                            .foregroundStyle(Theme.textMuted)
                        Spacer()
                        Button { index -= 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(index == 0)
                            .accessibilityLabel("Later week")
                    }
                    .buttonStyle(.borderless)
                }
                Section("Bedtime") {
                    LabeledContent("Went to bed", value: summary.bedLine ?? "Not tracked")
                    LabeledContent("Nights tracked", value: "\(summary.nightsTracked)")
                }
                Section("Mornings") {
                    LabeledContent("Mornings", value: "\(summary.mornings)")
                    LabeledContent("Snoozes a morning", value: summary.snoozesPerMorning.map { String(format: "%g", $0) } ?? "–")
                    LabeledContent("Backstops fired", value: "\(summary.backstopsFired)")
                    LabeledContent("Mornings changed", value: "\(summary.morningsChanged)")
                    ForEach(Array(summary.changeReasons.enumerated()), id: \.offset) { Text($0.element).foregroundStyle(Theme.textMuted) }
                }
                Section("Naps") {
                    LabeledContent("Naps", value: "\(summary.naps)")
                    if summary.napMinutes > 0 { LabeledContent("In all", value: NapPlanner.lengthName(summary.napMinutes)) }
                }
            } else {
                Section {
                    Text("No summary yet. Home Assistant keeps track of your week once it's paired.")
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .onAppear { index = WeeklySummary.startIndex(weeks, justEnded: justEnded) }
        .task {
            // A fresh reply carries this week so far.
            _ = await BedtimeCoordinator.shared.morningContext(firstAlarm: nil, settings: settings)
            let fresh = Self.saved
            let shown = weeks.indices.contains(index) ? weeks[index].from : nil
            weeks = fresh
            index = fresh.firstIndex { $0.from == shown } ?? WeeklySummary.startIndex(fresh, justEnded: justEnded)
        }
    }
}

/// Settings → Weekly summary: on/off, day and time.
struct WeeklySummarySettings: View {
    @Binding var settings: BridgeSettings
    private let d = BridgeSettings()
    private let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        SettingsPage(title: "Weekly summary") {
            Section {
                NavigationLink("See your week") { WeeklySummaryView(settings: settings, inSheet: false) }
            } footer: {
                Text("This week so far, and the 8 weeks before it. Weeks start on the day and at the time below.")
            }
            Section {
                DefaultToggle(title: "Weekly notification", isOn: $settings.weeklySummaryEnabled, defaultValue: d.weeklySummaryEnabled)
                Picker(selection: $settings.weeklySummaryWeekday) {
                    ForEach(0..<7, id: \.self) { Text(days[$0]).tag($0) }
                } label: {
                    WithDefault(text: "Day", defaultText: settings.weeklySummaryWeekday == d.weeklySummaryWeekday ? nil : days[d.weeklySummaryWeekday])
                }
                LabeledContent {
                    DatePicker("", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
                } label: {
                    WithDefault(text: "Time", defaultText: settings.weeklySummaryTime == d.weeklySummaryTime ? nil : "6:00 PM")
                }
            } footer: {
                Text("At the end of each week, a notification and a Home Assistant sensor with the week just ended: when you went to bed against the target, snoozes, backstops fired, mornings changed and naps. Tap it to see the summary.")
            }
            ResetPageSection { settings.resetToDefaults(SettingsPages.weekly) }
        }
    }

    private var time: Binding<Date> {
        Binding {
            let parts = settings.weeklySummaryTime.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: parts.first ?? 18, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.weeklySummaryTime = String(format: "%02d:%02d", c.hour ?? 18, c.minute ?? 0)
        }
    }
}
