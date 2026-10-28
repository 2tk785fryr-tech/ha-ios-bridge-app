import LocalAuthentication
import SwiftUI

/// Item 3: move this morning's alarms later (or earlier) or cancel them. Opened with a
/// slide-and-hold; you pick the change and a reason, see everything it will change, then confirm
/// with a second 5-second hold and Face ID (passcode if Face ID fails).
struct ChangeMorningFlow: View {
    let phase: MorningChangePhase
    let currentWake: Date
    var wakeKnown = true
    let settings: BridgeSettings
    /// Called once the change is made.
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice: MorningChangeChoice?
    @State private var pickedTime = Date.now.addingTimeInterval(2 * 3600)
    @State private var reason: String?
    @State private var note = ""

    private var change: MorningChange? {
        choice.map { MorningChange.make($0, currentWake: currentWake, settings: settings) }
    }

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Change this morning") {
                Section {
                    ForEach([30, 60, 120], id: \.self) { minutes in
                        option(.later(minutes: minutes), title: minutes < 60 ? "+\(minutes) min" : "+\(minutes / 60) hr")
                    }
                    option(.at(BedtimeCoordinator.nextOccurrence(ofTimeIn: pickedTime)), title: "Pick a time")
                    if case .at = choice {
                        DatePicker("Wake up at", selection: $pickedTime, displayedComponents: .hourAndMinute)
                            .onChange(of: pickedTime) { choice = .at(BedtimeCoordinator.nextOccurrence(ofTimeIn: pickedTime)) }
                    }
                    option(.noAlarms, title: "No alarms")
                } header: {
                    Text(wakeKnown ? "Wake-up now \(WakePlanner.format(currentWake))" : "From now")
                } footer: {
                    Text("New alarms use your usual number, spacing and \"wake time is the \(settings.wakeTimeIs.displayName.lowercased())\".")
                }
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        Text("Choose…").tag(String?.none)
                        ForEach(settings.morningChangeReasons, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    NavigationLink("Next") {
                        if let change {
                            ConfirmMorningChange(change: change, phase: phase, reason: reason, note: note, settings: settings) {
                                done()
                                dismiss()
                            }
                        }
                    }
                    .disabled(change == nil || reason == nil || change?.isPossible(now: .now) == false)
                }
            }
        }
    }

    private func option(_ option: MorningChangeChoice, title: String) -> some View {
        let preview = MorningChange.make(option, currentWake: currentWake, settings: settings)
        let selected = choice.map { same($0, option) } ?? false
        return Button {
            choice = option
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Theme.text)
                    Text(preview.alarmTimes.isEmpty ? "Alarms off for this morning" : "Alarms " + preview.alarmTimes.map(WakePlanner.format).joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accentText) }
            }
        }
        .disabled(!preview.isPossible(now: .now))
    }

    private func same(_ a: MorningChangeChoice, _ b: MorningChangeChoice) -> Bool {
        switch (a, b) {
        case (.at, .at): true
        default: a == b
        }
    }
}

/// Every change listed, then a second slide-and-hold and Face ID.
private struct ConfirmMorningChange: View {
    let change: MorningChange
    let phase: MorningChangePhase
    let reason: String?
    let note: String
    let settings: BridgeSettings
    let finished: () -> Void
    @State private var context: MorningContext?
    @State private var loaded = false
    @State private var sleepIn = true
    @State private var message: String?
    @State private var attempt = 0
    @State private var working = false
    private let coordinator = BedtimeCoordinator.shared

    var body: some View {
        SettingsPage(title: "Confirm") {
            Section("Alarms") {
                if change.alarmTimes.isEmpty {
                    Text("No alarms this morning").foregroundStyle(Theme.text)
                } else {
                    Text(change.alarmTimes.map(WakePlanner.format).joined(separator: " · ")).foregroundStyle(Theme.text)
                    Text(change.delayMinutes >= 0 ? "\(change.delayMinutes) min later" : "\(-change.delayMinutes) min earlier")
                        .font(.footnote).foregroundStyle(Theme.textMuted)
                }
            }
            Section("Backstops") {
                backstops
            }
            Section("Sleep In") {
                if change.alarmTimes.isEmpty {
                    Toggle("Sleep In", isOn: $sleepIn)
                } else if let on = change.sleepIn(curtainsOpenAt: context?.curtainsOpenAt) {
                    Text(on ? "On: the first alarm is after the curtains open (\(WakePlanner.format(context!.curtainsOpenAt!)))"
                            : "Off: the first alarm is before the curtains open (\(WakePlanner.format(context!.curtainsOpenAt!)))")
                        .foregroundStyle(Theme.text)
                } else {
                    Text(loaded ? "Home Assistant sets it from the new alarms." : "Checking…").foregroundStyle(Theme.textMuted)
                }
            }
            Section {
                Text(phase == .snoozing
                     ? "The snooze light fades back down."
                     : "The house goes back to bedtime: Home Assistant runs the bedtime routine, and your phone re-arms the house and turns Sleep Focus on.")
                    .font(.footnote).foregroundStyle(Theme.textMuted)
                if let reason { Text("Reason: \(reason)\(note.isEmpty ? "" : " · \(note)")").font(.footnote).foregroundStyle(Theme.textMuted) }
                HoldSlider(
                    label: working ? "Changing…" : "Slide and hold to confirm",
                    holdLabel: { "Confirming in \($0)…" },
                    knobSymbol: "checkmark",
                    tint: Theme.accent,
                    onHold: confirm,
                    accessibilityHint: "Then Face ID or your passcode."
                )
                .id(attempt)
                .listRowBackground(Color.clear)
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.danger) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            context = await coordinator.morningContext(firstAlarm: change.alarmTimes.min(), settings: settings)
            loaded = true
        }
    }

    @ViewBuilder private var backstops: some View {
        if !loaded {
            Text("Checking…").foregroundStyle(Theme.textMuted)
        } else if let context, context.ladderArmed {
            let moved = change.backstops(context.backstops)
            Text(["early", "deadline", "late"].compactMap { rung in moved[rung].map { "\(rung.capitalized) \(WakePlanner.format($0))" } }.joined(separator: " · "))
                .foregroundStyle(Theme.text)
            if change.alarmTimes.isEmpty, context.ladderKind == "shift", let start = context.shiftStart {
                Text("Your calendar still shows the shift at \(WakePlanner.format(start)), so the backstops stay on. Delete the shift if you're not working.")
                    .font(.footnote).foregroundStyle(Theme.warning.text)
            } else if change.alarmTimes.isEmpty {
                Text("The backstops stay on.").font(.footnote).foregroundStyle(Theme.textMuted)
            } else {
                Text("They move with the wake-up.").font(.footnote).foregroundStyle(Theme.textMuted)
            }
        } else if context != nil {
            Text("No backstops this morning.").foregroundStyle(Theme.textMuted)
        } else {
            Text("Couldn't reach Home Assistant; it will move them when it gets the change.").foregroundStyle(Theme.textMuted)
        }
    }

    private func confirm() {
        Task { @MainActor in
            let auth = LAContext()
            auth.localizedCancelTitle = "Don't change"
            do {
                // Face ID (with attention, per the iPhone's setting), passcode if it fails.
                guard try await auth.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Change this morning's alarms") else { throw LAError(.authenticationFailed) }
            } catch {
                message = "Not changed: \(error.localizedDescription)"
                attempt += 1
                return
            }
            working = true
            do {
                try await coordinator.changeMorning(change, phase: phase, sleepIn: sleepIn, reason: reason, note: note, settings: settings)
                finished()
            } catch {
                message = error.localizedDescription
                working = false
                attempt += 1
            }
        }
    }
}

/// Opens the change flow with a slide-and-hold: on the snooze screen while snoozing, on Tonight
/// as Back to bed after you're up.
struct ChangeMorningEntry: View {
    let title: String
    let detail: String
    let phase: MorningChangePhase
    let settings: BridgeSettings
    let done: () -> Void
    @State private var open = false
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            Text(detail).font(.footnote).foregroundStyle(Theme.textMuted)
            HoldSlider(
                label: "Slide and hold to change",
                holdLabel: { "Opening in \($0)…" },
                knobSymbol: "calendar.badge.clock",
                tint: Theme.accent,
                onHold: { open = true },
                accessibilityHint: "Move this morning's alarms later or cancel them."
            )
            .id(attempt)
        }
        .sheet(isPresented: $open, onDismiss: { attempt += 1 }) {
            // Without a known series (it was lost), changes count from now.
            let wake = BedtimeCoordinator.shared.currentWake(settings: settings)
            ChangeMorningFlow(phase: phase, currentWake: wake ?? .now, wakeKnown: wake != nil, settings: settings, done: done)
        }
    }
}
