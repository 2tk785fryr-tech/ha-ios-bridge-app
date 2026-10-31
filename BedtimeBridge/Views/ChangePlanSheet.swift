import SwiftUI

/// Change plan (v0.4.8 item 5): every way to change tonight's alarms on one sheet. Each choice
/// opens its own screen or slide-and-hold; nothing changes here.
struct ChangePlanSheet: View {
    let items: [BarAction]
    let times: [Date]
    let day: String
    /// What Undo would put back (empty: no alarms).
    let undoPutsBack: [Date]
    let choose: (BarAction) -> Void

    @Environment(\.dismiss) private var dismiss

    static func title(_ action: BarAction, day: String) -> String {
        switch action {
        case .editAlarms: "Change times"
        case .replan: "Plan from the calendar again"
        default: action.title(day: day)
        }
    }

    static func subtitle(_ action: BarAction, undoPutsBack: [Date]) -> String {
        switch action {
        case .undo: undoPutsBack.isEmpty ? "Put back no alarms" : "Put back \(OwnAlarmsKept.list(undoPutsBack.sorted()))"
        case .editAlarms: "Move or remove one"
        case .setAlarmsForTime: "Your own alarms' series"
        case .replan: "Preview, then set"
        case .sleepLater: "Move them later"
        case .noAlarmsTomorrow: "Ends them and their backstops; asks about Sleep In"
        default: ""
        }
    }

    private func symbol(_ action: BarAction) -> String {
        switch action {
        case .undo: "arrow.uturn.backward"
        case .editAlarms: "clock.badge"
        case .setAlarmsForTime: "alarm"
        case .replan: "calendar"
        case .sleepLater: "zzz"
        case .noAlarmsTomorrow: "bell.slash"
        default: "circle"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { action in
                        let ending = action == .noAlarmsTomorrow
                        Button { choose(action) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: symbol(action))
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(ending ? Theme.danger : action.isProtected ? Theme.amber : Theme.accentText)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.title(action, day: day))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(ending ? Theme.danger : Theme.text)
                                    Text(Self.subtitle(action, undoPutsBack: undoPutsBack))
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textMuted)
                                }
                                Spacer()
                                if action.isProtected {
                                    Image(systemName: "hand.draw").foregroundStyle(Theme.amber.opacity(0.7))
                                }
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    if !times.isEmpty {
                        Text("\(times.count == 1 ? "1 alarm" : "\(times.count) alarms") · \(OwnAlarmsKept.list(times.sorted()))")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Change plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
