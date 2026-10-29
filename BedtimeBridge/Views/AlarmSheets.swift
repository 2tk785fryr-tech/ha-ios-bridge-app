import SwiftUI

/// Pick a wake-up time and whether it's the first or last alarm of your usual series.
/// Used for a day off and for "wake at a different time" when skipping a morning.
struct WakeTimeSheet: View {
    let title: String
    let note: String
    let confirm: String
    let settings: BridgeSettings
    let done: (Date, WakeTimeAlarm) -> Void
    @State private var time = WakeTimeSheet.defaultTime
    @State private var wakeIs = WakeTimeAlarm.first
    @Environment(\.dismiss) private var dismiss

    /// Six hours from now on the next five minutes, like the old day-off shortcut.
    static var defaultTime: Date {
        let later = Date.now.addingTimeInterval(6 * 3600)
        let minutes = Calendar.current.component(.minute, from: later)
        return Calendar.current.date(byAdding: .minute, value: (5 - minutes % 5) % 5, to: later) ?? later
    }

    private var series: String {
        let wake = BedtimeCoordinator.nextOccurrence(ofTimeIn: time)
        let times = WakePlanner.alarmTimes(wakeTime: wake, count: settings.alarmCount, spacingMinutes: settings.alarmSpacingMinutes, wakeIs: wakeIs)
        return "Alarms at " + times.map(WakePlanner.format).joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            SettingsPage(title: title) {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("This time is the", selection: $wakeIs) {
                        ForEach(WakeTimeAlarm.allCases) { Text($0.displayName).tag($0) }
                    }
                } footer: {
                    Text(series + ". " + note)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm) {
                        done(time, wakeIs)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// A temporary wake-up: when, and what happens to the house alarm.
struct TemporaryAlarmSheet: View {
    let done: (Date, Bool) -> Void
    @State private var time = WakeTimeSheet.defaultTime
    @State private var disarmHouse = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Temporary alarm") {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("House alarm", selection: $disarmHouse) {
                        Text("Disarm, then re-arm").tag(true)
                        Text("Keep armed").tag(false)
                    }
                } footer: {
                    Text(disarmHouse
                         ? "One alarm, then back to bed. Stopping it disarms the house alarm and re-arms it once you've been back in bed a few minutes. Awake For Day, Sleep In and your regular alarms stay as they are."
                         : "One alarm for a call or anything you do from bed. The house alarm stays armed, and Awake For Day, Sleep In and your regular alarms stay as they are.")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        done(time, disarmHouse)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Temporary wake-ups beside the regular alarms, with the way to add or remove one.
struct TemporaryAlarmsCard: View {
    let alarms: [TemporaryAlarm]
    /// Each one's ring, like the regular alarms (v0.4.2 item 5).
    var ring: (TemporaryAlarm) -> AlarmBubble.Ring = { _ in .set }
    let add: () -> Void
    let remove: (UUID) -> Void
    /// Change a temporary alarm's time (tap it).
    var move: ((UUID, Date) -> Void)? = nil
    @State private var moving: TemporaryAlarm?
    @State private var newTime = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temporary alarms")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
            ForEach(alarms) { alarm in
                HStack(alignment: .top) {
                    AlarmBubbleView(bubble: AlarmBubble(time: alarm.time, ring: ring(alarm), isWake: false))
                        .frame(width: 84)
                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            newTime = alarm.time
                            moving = alarm
                        } label: {
                            Label(alarm.time.formatted(.dateTime.weekday(.abbreviated).hour().minute()), systemImage: "pencil")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                        .buttonStyle(.plain)
                        .disabled(move == nil)
                        .accessibilityHint("Change this alarm's time")
                        Text(alarm.disarmHouse ? "Disarms, then re-arms when you're back in bed" : "House alarm stays armed")
                            .font(.footnote)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Button { remove(alarm.id) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .accessibilityLabel("Remove temporary alarm")
                }
            }
            Button(action: add) {
                Label("Add a temporary alarm", systemImage: "alarm.waves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightfallCard()
        .sheet(item: $moving) { alarm in
            NavigationStack {
                SettingsPage(title: "Temporary alarm") {
                    Section {
                        DatePicker("Time", selection: $newTime, displayedComponents: .hourAndMinute)
                    } footer: {
                        Text(alarm.disarmHouse ? "Still disarms, then re-arms when you're back in bed." : "The house alarm stays armed.")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { moving = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            move?(alarm.id, newTime)
                            moving = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
