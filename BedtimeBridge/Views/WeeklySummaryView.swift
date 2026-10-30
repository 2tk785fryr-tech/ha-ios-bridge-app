import SwiftUI

/// The weekly summary screen (v0.4.3 item 15), opened from the Sunday notification.
struct WeeklySummaryView: View {
    let settings: BridgeSettings
    @State private var summary = WeeklySummary.cached
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Your week") {
                if let summary {
                    if let from = summary.from, let to = summary.to {
                        Section {
                            Text("\(from.formatted(.dateTime.month(.abbreviated).day())) – \(to.formatted(.dateTime.month(.abbreviated).day()))")
                                .foregroundStyle(Theme.textMuted)
                        }
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
                        Text("No summary yet. Home Assistant sends one each week once it has a week of history.")
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                // A fresh reply carries the latest summary.
                _ = await BedtimeCoordinator.shared.morningContext(firstAlarm: nil, settings: settings)
                summary = WeeklySummary.cached
            }
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
                DefaultToggle(title: "Weekly summary", isOn: $settings.weeklySummaryEnabled, defaultValue: d.weeklySummaryEnabled)
                if settings.weeklySummaryEnabled {
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
                }
            } footer: {
                Text("A notification and a Home Assistant sensor with your week: when you went to bed against the target, snoozes, backstops fired, mornings changed and naps. Tap it to see the summary.")
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
