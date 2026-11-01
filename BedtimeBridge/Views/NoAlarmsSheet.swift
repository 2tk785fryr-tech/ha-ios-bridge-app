import SwiftUI

/// "No alarms Sunday" (v0.4.3 item 3; v0.4.10 item 10, Skip merged in): the alarms stay off
/// until you undo it, the Sleep In switch, Wake at a different time, what happens to the
/// backstops, and the slide-and-hold at the commit step.
struct NoAlarmsSheet: View {
    let morning: Date
    /// A shift still on the calendar that morning: its failsafe goes off too.
    let shift: (cause: String, start: Date)?
    /// Wake at a different time instead (Skip's other choice).
    var differentTime: (() -> Void)? = nil
    let confirm: (_ sleepIn: Bool) async -> Void

    @State private var sleepIn = true
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    private var day: String { morning.formatted(.dateTime.weekday(.wide)) }

    static func backstopNote(shift: (cause: String, start: Date)?) -> String {
        guard let shift else { return "Nothing's on your calendar that morning, so the backstops are off too." }
        return "As if \(shift.cause) at \(WakePlanner.format(shift.start)) weren't there: the wake failsafe and backstops are off that morning."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Clears \(day)'s alarms, and bedtime planning won't set them again. Temporary and nap alarms stay.")
                    Toggle("Sleep In", isOn: $sleepIn)
                } footer: {
                    Text("Sleep In keeps the curtains closed in the morning.")
                }
                if let differentTime {
                    Section {
                        Button("Wake at a different time…", systemImage: "clock") {
                            dismiss()
                            differentTime()
                        }
                    }
                }
                Section {
                    Label(Self.backstopNote(shift: shift), systemImage: shift == nil ? "shield.slash" : "shield")
                        .font(.footnote)
                        .foregroundStyle(shift == nil ? Theme.textMuted : Theme.warning.text)
                }
                Section {
                    HoldSlider(label: "Slide and hold", holdLabel: { "Turning off in \($0)…" },
                               knobSymbol: "stop.fill", tint: Theme.danger, onHold: commit,
                               accessibilityHint: "Turns \(day)'s alarms off.")
                        .frame(height: 72)
                        .disabled(working)
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Undo on the main screen.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("No alarms \(day)")
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
