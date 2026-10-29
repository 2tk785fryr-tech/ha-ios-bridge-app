import LocalAuthentication
import SwiftUI

/// Item 3: move this morning's alarms later (or earlier) or cancel them. Opened with a
/// slide-and-hold; you pick a reason (which says whether only the alarms move or the whole
/// wake-up, v0.4.1 item 7) and the change, see everything it will change, then confirm with a
/// second 5-second hold and Face ID (passcode if Face ID fails).
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
    @State private var reasonID: UUID?
    /// Shift alarms only or the entire wake-up, when the reason says "Ask".
    @State private var askedScope: MorningChangeScope?
    @State private var note = ""
    @State private var context: MorningContext?

    /// This morning's own pattern (a Days morning: 3 alarms, 5 min apart, wake = last).
    private var pattern: SeriesPattern { BedtimeCoordinator.shared.seriesPattern(settings: settings) }
    private var reason: MorningReason? { settings.morningReasons.first { $0.id == reasonID } }
    private var scope: MorningChangeScope? {
        guard let reason else { return nil }
        return reason.scope == .ask ? askedScope : reason.scope
    }
    private var backstops: [String: Date] { context?.ladderArmed == true ? context?.backstops ?? [:] : [:] }

    private func make(_ choice: MorningChangeChoice) -> MorningChange {
        var change = MorningChange.make(choice, currentWake: currentWake, pattern: pattern)
        change.scope = scope == .alarms ? .alarms : .wakeUp
        return change
    }

    private var change: MorningChange? { choice.map(make) }

    /// Shift alarms only: the latest wake-up whose last alarm isn't after the late backstop.
    private var latestWake: Date? {
        guard scope == .alarms, let late = backstops["late"] else { return nil }
        return MorningChange.latestWake(notAfter: late, pattern: pattern)
    }

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Change this morning") {
                Section("Reason") {
                    Picker("Reason", selection: $reasonID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(settings.morningReasons) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    if reason?.scope == .ask {
                        Picker("What moves", selection: $askedScope) {
                            Text("Choose…").tag(MorningChangeScope?.none)
                            Text(MorningChangeScope.alarms.displayName).tag(MorningChangeScope?.some(.alarms))
                            Text(MorningChangeScope.wakeUp.displayName).tag(MorningChangeScope?.some(.wakeUp))
                        }
                    } else if let reason {
                        Text(reason.scope.displayName).foregroundStyle(Theme.textMuted)
                    }
                    TextField("Note (optional)", text: $note)
                }
                if let scope {
                    Section {
                        ForEach([30, 60, 120], id: \.self) { minutes in
                            option(.later(minutes: minutes), title: minutes < 60 ? "+\(minutes) min" : "+\(minutes / 60) hr")
                        }
                        option(.at(BedtimeCoordinator.nextOccurrence(ofTimeIn: pickedTime)), title: "Pick a time")
                        if case .at = choice {
                            DatePicker("Wake up at", selection: $pickedTime, in: ...(latestWake ?? .distantFuture), displayedComponents: .hourAndMinute)
                                .onChange(of: pickedTime) { choice = .at(BedtimeCoordinator.nextOccurrence(ofTimeIn: pickedTime)) }
                        }
                        option(.noAlarms, title: "No alarms")
                        if let change, case .afterDeadline(let deadline) = change.limit(backstops: backstops) {
                            Label("The last alarm is after the deadline backstop (\(WakePlanner.format(deadline))).", systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(Theme.warning.text)
                        }
                    } header: {
                        Text(wakeKnown ? "Wake-up now \(WakePlanner.format(currentWake))" : "From now")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(scope == .alarms
                                 ? "Shift alarms only: you sleep longer, the start stays. Leave-by and the deadline and late backstops stay; the early backstop moves after the new last alarm."
                                 : "Shift entire wake-up: the start is later. The alarms, leave-by and all three backstops move by the same amount.")
                            Text("New alarms keep this morning's pattern: \(pattern.count) alarms, \(pattern.spacingMinutes) min apart, wake-up is the \(pattern.wakeIs.displayName.lowercased()).")
                            if scope == .alarms, let late = backstops["late"], blockedChoices {
                                Text("Later than that would put the last alarm after the late backstop (\(WakePlanner.format(late))).")
                                Button("Shift the entire wake-up instead") {
                                    if reason?.scope == .ask { askedScope = .wakeUp }
                                }
                                .disabled(reason?.scope != .ask)
                                if reason?.scope != .ask {
                                    Text("This reason is set to shift alarms only; pick a reason that shifts the wake-up, or change it in Settings.")
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { context = await BedtimeCoordinator.shared.morningContext(firstAlarm: nil, settings: settings) }
            .onChange(of: scope) { choice = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    NavigationLink("Next") {
                        if let change {
                            ConfirmMorningChange(change: change, phase: phase, reason: reason?.name, note: note, settings: settings) {
                                done()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canContinue)
                }
            }
        }
    }

    private var canContinue: Bool {
        guard let change, scope != nil, change.isPossible(now: .now) else { return false }
        if case .afterLate = change.limit(backstops: backstops) { return false }
        return true
    }

    /// Some choice is disabled because it would pass the late backstop.
    private var blockedChoices: Bool {
        [MorningChangeChoice.later(minutes: 30), .later(minutes: 60), .later(minutes: 120)].contains { option in
            if case .afterLate = make(option).limit(backstops: backstops) { return true }
            return false
        }
    }

    private func option(_ option: MorningChangeChoice, title: String) -> some View {
        let preview = make(option)
        let selected = choice.map { same($0, option) } ?? false
        let blocked: Bool = {
            if case .afterLate = preview.limit(backstops: backstops) { return true }
            return false
        }()
        return Button {
            choice = option
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(blocked ? Theme.textFaint : Theme.text)
                    Text(blocked ? "Past the late backstop" : preview.alarmTimes.isEmpty ? "Alarms off for this morning" : "Alarms " + preview.alarmTimes.map(WakePlanner.format).joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accentText) }
            }
        }
        .disabled(!preview.isPossible(now: .now) || (blocked && !isPickATime(option)))
    }

    private func isPickATime(_ option: MorningChangeChoice) -> Bool {
        if case .at = option { return true }
        return false
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
                if !change.alarmTimes.isEmpty {
                    Text(change.scope == .alarms
                         ? "Shift alarms only: the start, leave-by and leave reminder stay."
                         : "Shift entire wake-up: leave-by and the leave reminder move \(change.delayMinutes) min too.")
                        .font(.footnote).foregroundStyle(Theme.accentText)
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
                Text(coordinator.changePhase(requested: phase) == .snoozing
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
            let moved = change.backstops(context.backstops, earlyGap: settings.earlyBackstopGapMinutes)
            Text(["early", "deadline", "late"].compactMap { rung in
                moved[rung].map { time in
                    let same = context.backstops[rung].map { abs($0.timeIntervalSince(time)) < 30 } ?? true
                    return "\(rung.capitalized) \(WakePlanner.format(time))\(same ? "" : " (was \(WakePlanner.format(context.backstops[rung]!)))")"
                }
            }.joined(separator: " · "))
                .foregroundStyle(Theme.text)
            if context.houseUsesOldTimes, !context.houseTimes.isEmpty {
                // Until the cutover the house backstop reads the old template (v0.4.1 item 6).
                Text("Until the cutover, your house backstop still fires at its old times: "
                     + ["early", "deadline", "late"].compactMap { rung in context.houseTimes[rung].map { "\(rung) \(WakePlanner.format($0))" } }.joined(separator: ", ")
                     + ". Only Bedtime Bridge's ladder above moves.")
                    .font(.footnote).foregroundStyle(Theme.warning.text)
            }
            if change.alarmTimes.isEmpty, context.ladderKind == "shift", let start = context.shiftStart {
                Text("Your calendar still shows the shift at \(WakePlanner.format(start)), so the backstops stay on. Delete the shift if you're not working.")
                    .font(.footnote).foregroundStyle(Theme.warning.text)
            } else if change.alarmTimes.isEmpty {
                Text("The backstops stay on.").font(.footnote).foregroundStyle(Theme.textMuted)
            } else if change.scope == .alarms {
                Text("Deadline and late stay; early follows the new last alarm.").font(.footnote).foregroundStyle(Theme.textMuted)
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
