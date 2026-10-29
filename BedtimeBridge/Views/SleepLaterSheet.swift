import SwiftUI

/// Sleep later from Tonight before bed (v0.4.1 item 12): the alarms move later in this morning's
/// pattern, like Shift alarms only (leave-by and the deadline and late backstops stay, the early
/// one follows). One slide-and-hold, no Face ID; nothing in the house changes.
struct SleepLaterSheet: View {
    let settings: BridgeSettings
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice: MorningChangeChoice?
    @State private var pickedTime = Date.now.addingTimeInterval(8 * 3600)
    @State private var reason: String?
    @State private var context: MorningContext?
    @State private var message: String?
    @State private var attempt = 0
    private let coordinator = BedtimeCoordinator.shared

    private var currentWake: Date { coordinator.currentWake(settings: settings) ?? .now }
    private var pattern: SeriesPattern { coordinator.seriesPattern(settings: settings) }

    private func make(_ choice: MorningChangeChoice) -> MorningChange {
        var change = MorningChange.make(choice, currentWake: currentWake, pattern: pattern)
        change.scope = .alarms
        return change
    }

    /// The limit: not after the late backstop; with no backstops, not after leave-by minus the
    /// get-ready time.
    private func limit(_ change: MorningChange) -> MorningChange.Limit {
        if let backstops = context?.backstops, context?.ladderArmed == true, !backstops.isEmpty {
            return change.limit(backstops: backstops)
        }
        return change.limit(leaveBy: NextAlarmSnapshot.load().leaveBy, getReadyMinutes: settings.getReadyMinutes)
    }

    private var eightHours: Date {
        let later = Date.now.addingTimeInterval(8 * 3600)
        let minutes = Calendar.current.component(.minute, from: later)
        return Calendar.current.date(byAdding: .minute, value: (5 - minutes % 5) % 5, to: later) ?? later
    }

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Sleep later") {
                Section {
                    ForEach([30, 60, 120], id: \.self) { minutes in
                        option(.later(minutes: minutes), title: minutes < 60 ? "+\(minutes) min" : "+\(minutes / 60) hr")
                    }
                    option(.at(eightHours), title: "8 hours from now")
                    option(.at(BedtimeCoordinator.nextOccurrence(ofTimeIn: pickedTime)), title: "Pick a time")
                    if case .at(let date) = choice, date != eightHours {
                        DatePicker("Wake up at", selection: $pickedTime, displayedComponents: .hourAndMinute)
                            .onChange(of: pickedTime) { choice = .at(BedtimeCoordinator.nextOccurrence(ofTimeIn: pickedTime)) }
                    }
                } header: {
                    Text("Wake-up now \(WakePlanner.format(currentWake))")
                } footer: {
                    Text("The alarms move later and keep this morning's pattern. Leave-by and the deadline and late backstops stay; the early backstop follows the last alarm. Nothing in the house changes.")
                }
                Section("Reason (optional)") {
                    Picker("Reason", selection: $reason) {
                        Text("None").tag(String?.none)
                        ForEach(settings.morningReasons) { Text($0.name).tag(String?.some($0.name)) }
                    }
                }
                Section {
                    HoldSlider(
                        label: "Slide and hold to sleep later",
                        holdLabel: { "Moving the alarms in \($0)…" },
                        knobSymbol: "clock.fill",
                        tint: Theme.accent,
                        onHold: confirm,
                        accessibilityHint: "Moves tonight's alarms later."
                    )
                    .id(attempt)
                    .disabled(!canConfirm)
                    .listRowBackground(Color.clear)
                    if let message { Text(message).font(.footnote).foregroundStyle(Theme.danger) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { context = await coordinator.morningContext(firstAlarm: nil, settings: settings) }
        }
    }

    private var canConfirm: Bool {
        guard let choice else { return false }
        let change = make(choice)
        if case .afterLate = limit(change) { return false }
        return change.isPossible(now: .now)
    }

    private func option(_ option: MorningChangeChoice, title: String) -> some View {
        let preview = make(option)
        let limit = limit(preview)
        let blocked: Bool = { if case .afterLate = limit { return true }; return false }()
        let selected: Bool = {
            switch (choice, option) {
            case (.at(let a), .at(let b)): return a == b || (b != eightHours && a != eightHours)
            default: return choice == option
            }
        }()
        return Button { choice = option } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(blocked ? Theme.textFaint : Theme.text)
                    Group {
                        switch limit {
                        case .afterLate(let latest): Text("Past \(WakePlanner.format(latest)), the latest the last alarm can be")
                        case .afterDeadline(let deadline): Text("Alarms \(preview.alarmTimes.map(WakePlanner.format).joined(separator: ", ")) · after the deadline backstop (\(WakePlanner.format(deadline)))")
                        case .ok: Text("Alarms " + preview.alarmTimes.map(WakePlanner.format).joined(separator: ", "))
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accentText) }
            }
        }
        .disabled(blocked || !preview.isPossible(now: .now))
    }

    private func confirm() {
        guard let choice else { return }
        Task { @MainActor in
            do {
                try await coordinator.sleepLater(make(choice), reason: reason, settings: settings)
                done()
                dismiss()
            } catch {
                message = error.localizedDescription
                attempt += 1
            }
        }
    }
}

/// On Tonight while the alarms are set and none has rung: Sleep later, and Back to planned alarms.
struct SleepLaterCard: View {
    let settings: BridgeSettings
    let canGoBack: Bool
    let changed: () -> Void
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { open = true } label: {
                Label("Sleep later…", systemImage: "moon.zzz")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
            }
            if canGoBack {
                Button {
                    Task {
                        try? await BedtimeCoordinator.shared.backToPlannedAlarms(settings: settings)
                        changed()
                    }
                } label: {
                    Label("Back to planned alarms", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightfallCard()
        .sheet(isPresented: $open) { SleepLaterSheet(settings: settings, done: changed) }
    }
}
