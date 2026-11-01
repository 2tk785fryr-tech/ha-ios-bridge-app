import SwiftUI

/// Settings → Wind-down (v0.4.3 item 5), defaults shown (item 8).
struct WindDownSettings: View {
    @Binding var settings: BridgeSettings
    private let d = BridgeSettings()

    var body: some View {
        SettingsPage(title: "Wind-down") {
            Section {
                DefaultToggle(title: "Wind-down", isOn: $settings.windDownEnabled, defaultValue: d.windDownEnabled)
                NavigationLink("Set up the phone side") { WindDownPhoneGuide() }
            } footer: {
                Text("Tonight's times come from tomorrow's first alarm. Home Assistant sends the warning, starts wind-down, says when it's time for bed and reminds you if you're still up. Turn it on once the phone side is set up.")
            }

            Section {
                DefaultStepper(title: "Sleep goal", value: $settings.sleepGoalMinutes, range: 240...600, step: 15,
                               defaultValue: d.sleepGoalMinutes, format: sleepGoal)
                DefaultStepper(title: "Wind-down", value: $settings.windDownMinutes, range: 30...120, step: 5,
                               defaultValue: d.windDownMinutes, format: DurationText.minutes)
                DefaultStepper(title: "Free time after getting home", value: $settings.freeAfterHomeMinutes, range: 0...90, step: 5,
                               defaultValue: d.freeAfterHomeMinutes, format: DurationText.minutes)
                DefaultStepper(title: "Minimum wind-down", value: $settings.minimumWindDownMinutes, range: 15...60, step: 5,
                               defaultValue: d.minimumWindDownMinutes, format: DurationText.minutes)
            } header: {
                Text("Times")
            } footer: {
                Text(example)
            }

            Section {
                DefaultStepper(title: "Warning before", value: $settings.windDownWarningMinutes, range: 0...30,
                               defaultValue: d.windDownWarningMinutes, format: { $0 == 0 ? "Off" : "\($0) min" })
                DefaultStepper(title: "\"Later\" button", value: $settings.windDownLaterMinutes, range: 5...60, step: 5,
                               defaultValue: d.windDownLaterMinutes, format: DurationText.minutes)
            } header: {
                Text("Warning")
            } footer: {
                Text("The warning has \"\(settings.windDownLaterMinutes) min later\" (moves wind-down, not go to bed) and \"Cancel tonight's wind-down\".")
            }

            Section {
                DefaultToggle(title: "Not-in-bed reminders", isOn: $settings.notInBedReminders, defaultValue: d.notInBedReminders)
                if settings.notInBedReminders {
                    DefaultStepper(title: "First after", value: $settings.reminderFirstMinutes, range: 5...60, step: 5,
                                   defaultValue: d.reminderFirstMinutes, format: DurationText.minutes)
                    DefaultStepper(title: "Every", value: $settings.reminderEveryMinutes, range: 5...30, step: 5,
                                   defaultValue: d.reminderEveryMinutes, format: DurationText.minutes)
                    DefaultStepper(title: "Stop after", value: $settings.reminderStopMinutes, range: 10...180, step: 10,
                                   defaultValue: d.reminderStopMinutes, format: DurationText.minutes)
                }
            } header: {
                Text("Still up")
            } footer: {
                Text("\"Still up · first alarm 4:20\" while the bedroom door isn't closed with the bed occupied. Only at home.")
            }

            Section {
                DefaultStepper(title: "Evening plan check", value: $settings.planCheckBeforeMinutes, range: 30...240, step: 15,
                               defaultValue: d.planCheckBeforeMinutes, format: { "\(DurationText.hours($0)) before" })
                LabeledContent {
                    DatePicker("", selection: fallbackTime, displayedComponents: .hourAndMinute).labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Without a shift, check at")
                        if settings.planCheckFallback != d.planCheckFallback { DefaultNote(text: "6:00 PM") }
                    }
                }
                DefaultToggle(title: "Wind-down for your own alarm on a day off", isOn: $settings.windDownOwnAlarm, defaultValue: d.windDownOwnAlarm)
                DefaultStepper(title: "\"Start wind-down now\" from", value: $settings.startWindDownHours, range: 1...6,
                               defaultValue: d.startWindDownHours, format: { "\($0) h before bed" })
            } header: {
                Text("Evening")
            } footer: {
                Text("Home Assistant asks the phone for tomorrow's plan (Preview tomorrow) before wind-down. If the phone doesn't answer, it uses the shift calendar alone and says appointments weren't checked.")
            }

            ResetPageSection { settings.resetToDefaults(SettingsPages.windDown) }
        }
    }

    private func sleepGoal(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "First alarm 4:20 → wind-down 8:50 PM, go to bed 9:50 PM."
    private var example: String {
        let first = Calendar.current.date(bySettingHour: 4, minute: 20, second: 0, of: Calendar.current.nextDay(after: .now))!
        let times = WindDownTimes.compute(firstAlarm: first, settings: settings)
        return "First alarm 4:20 AM → wind-down \(WakePlanner.format(times.windDown)), go to bed \(WakePlanner.format(times.goToBed)). Home late, wind-down waits for the free time and bedtime moves later rather than cutting wind-down below the minimum."
    }

    private var fallbackTime: Binding<Date> {
        Binding {
            let parts = settings.planCheckFallback.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: parts.first ?? 18, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.planCheckFallback = String(format: "%02d:%02d", c.hour ?? 18, c.minute ?? 0)
        }
    }
}

/// "Set up the phone side": shortcuts that copy Health's wind-down, with a Wind Down Focus.
struct WindDownPhoneGuide: View {
    var body: some View {
        SettingsPage(title: "Phone side") {
            Section {
                Text("Make a custom Focus called \"Wind Down\" (Settings → Focus → +). Allow your people (Seth), phone calls and the Home Assistant app, and turn on Dim Lock Screen. Use a custom Focus, not Sleep: the bedtime shortcut turns on Sleep Focus, which replaces it, since only one Focus can be on.")
            } header: {
                Text("1. Wind Down Focus")
            }
            Section {
                step("Report Shortcut Ran: RUN_WIND_DOWN, Started")
                step("Set Focus: Wind Down on")
                step("Set Brightness: 30%")
                step("Set Night Shift: on")
                step("Set Reduce White Point: on")
                step("Report Shortcut Ran: RUN_WIND_DOWN, Completed")
            } header: {
                Text("2. Wind Down On (RUN_WIND_DOWN)")
            }
            Section {
                step("Report Shortcut Ran: RUN_CANCEL_WIND_DOWN, Started")
                step("Set Focus: Wind Down off")
                step("Set Reduce White Point: off")
                step("Set Night Shift: off (or leave it to its schedule)")
                step("No brightness step: auto-brightness takes over")
                step("Report Shortcut Ran: RUN_CANCEL_WIND_DOWN, Completed")
            } header: {
                Text("3. Wind Down Off (RUN_CANCEL_WIND_DOWN)")
            } footer: {
                Text("No Dark Mode step: Appearance is Automatic, and Shortcuts can't set it back to Automatic.")
            }
            Section {
                step("Bedtime Bridge: Preview Tomorrow (sets no alarms)")
                step("Report Shortcut Ran: RUN_PLAN_PREVIEW, Completed")
            } header: {
                Text("4. Preview Tomorrow (RUN_PLAN_PREVIEW)")
            }
            Section {
                Text("For each shortcut: Shortcuts → Automation → + → Notification → App: Home Assistant, Message contains the command (RUN_WIND_DOWN, RUN_CANCEL_WIND_DOWN, RUN_PLAN_PREVIEW) → Run Immediately, Notify When Run off.")
            } header: {
                Text("5. Automations")
            } footer: {
                Text("Turn on Send phone commands in the integration's options. Test that Wind Down Off leaves auto-brightness and automatic Appearance working.")
            }
        }
    }

    private func step(_ text: String) -> some View {
        Label(text, systemImage: "chevron.right.circle").font(.subheadline)
    }
}
