import SwiftUI

/// "No alarms tomorrow" (v0.4.3 item 3): the Sleep In switch, what happens to the backstops,
/// and the slide-and-hold at the commit step.
struct NoAlarmsSheet: View {
    let morning: Date
    /// A shift still on the calendar that morning: its backstops stay on.
    let shift: (cause: String, start: Date)?
    let confirm: (_ sleepIn: Bool) async -> Void

    @State private var sleepIn = true
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    static func backstopNote(shift: (cause: String, start: Date)?) -> String {
        guard let shift else { return "Nothing's on your calendar that morning, so the backstops are off too." }
        return "\(shift.cause) at \(WakePlanner.format(shift.start)) is still on your calendar, so the backstops stay on. Delete the shift or use Skip if you're not working."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Clears \(morning.formatted(.dateTime.weekday(.wide)))'s alarms. Temporary and nap alarms stay.")
                    Toggle("Sleep In", isOn: $sleepIn)
                } footer: {
                    Text("Sleep In keeps the curtains closed in the morning.")
                }
                Section {
                    Label(Self.backstopNote(shift: shift), systemImage: shift == nil ? "shield.slash" : "shield")
                        .font(.footnote)
                        .foregroundStyle(shift == nil ? Theme.textMuted : Theme.warning.text)
                }
                Section {
                    HoldSlider(label: "Slide and hold", holdLabel: { "Turning off in \($0)…" },
                               knobSymbol: "stop.fill", tint: Theme.danger, onHold: commit,
                               accessibilityHint: "Turns tomorrow's alarms off.")
                        .frame(height: 72)
                        .disabled(working)
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Undo on the main screen until bedtime runs.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("No alarms tomorrow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func commit() {
        working = true
        Task {
            await confirm(sleepIn)
            dismiss()
        }
    }
}
