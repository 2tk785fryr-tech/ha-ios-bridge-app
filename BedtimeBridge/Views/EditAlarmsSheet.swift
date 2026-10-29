import SwiftUI

/// Edit, add or remove single alarms that are still ahead (v0.4.1 item 13). Always Shift alarms
/// only: the deadline and late backstops never move, no alarm may be after the late backstop, and
/// the early backstop follows the last alarm.
struct EditAlarmsSheet: View {
    let settings: BridgeSettings
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var times: [Date] = BedtimeCoordinator.shared.editableAlarms()
    @State private var context: MorningContext?
    @State private var message: String?
    @State private var saving = false
    private let coordinator = BedtimeCoordinator.shared

    private var late: Date? { context?.ladderArmed == true ? context?.backstops["late"] : nil }
    private var problem: String? {
        if times.contains(where: { $0 <= .now }) { return "An alarm is in the past." }
        if let late, let last = times.max(), last > late {
            return "An alarm is after the late backstop (\(WakePlanner.format(late))). Move it earlier, or change the whole wake-up instead."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Edit alarms") {
                Section {
                    ForEach(times.indices, id: \.self) { index in
                        DatePicker("Alarm \(index + 1)", selection: Binding(get: { times[index] }, set: { times[index] = BedtimeCoordinator.nextOccurrence(ofTimeIn: $0) }),
                                   displayedComponents: .hourAndMinute)
                    }
                    .onDelete { times.remove(atOffsets: $0) }
                    Button("Add an alarm", systemImage: "plus") {
                        let next = (times.max() ?? Date.now.addingTimeInterval(3600)).addingTimeInterval(5 * 60)
                        times.append(next)
                    }
                } footer: {
                    Text("Only alarms still ahead. The deadline and late backstops stay where they are; the early backstop follows the last alarm" + (late.map { "; no alarm can be after \(WakePlanner.format($0))" } ?? "") + ".")
                }
                if let shown = problem ?? message {
                    Section { Text(shown).font(.footnote).foregroundStyle(Theme.danger) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(problem != nil || saving)
                }
            }
            .task { context = await coordinator.morningContext(firstAlarm: nil, settings: settings) }
        }
    }

    private func save() {
        saving = true
        Task { @MainActor in
            do {
                try await coordinator.editAlarms(times.sorted(), settings: settings)
                done()
                dismiss()
            } catch {
                message = error.localizedDescription
                saving = false
            }
        }
    }
}
