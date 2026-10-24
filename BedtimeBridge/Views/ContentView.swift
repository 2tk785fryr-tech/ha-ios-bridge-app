import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var store
    @State private var plan: WakePlan?
    @State private var scheduled: [Date] = []
    @State private var errorMessage: String?
    @State private var isWorking = false

    private let coordinator = BedtimeCoordinator.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Tonight's plan") {
                    if let plan {
                        PlanSummary(plan: plan)
                    } else {
                        Text("Tap Preview to check your calendar.")
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Preview plan", systemImage: "eye") { run(schedule: false) }
                    Button("Plan and set alarms", systemImage: "alarm") { run(schedule: true) }
                }
                .disabled(isWorking)

                Section("Alarms set by this app") {
                    if store.settings.alarmStyle == .clock {
                        Text("Clock app mode: your shortcut creates the alarms.").foregroundStyle(.secondary)
                    } else if scheduled.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        ForEach(scheduled, id: \.self) { time in
                            Text(time.formatted(date: .abbreviated, time: .shortened))
                        }
                        Button("Cancel all", systemImage: "trash", role: .destructive) {
                            Task {
                                try? await coordinator.cancelAlarms(settings: store.settings)
                                refreshScheduled()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bedtime Bridge")
            .toolbar {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            .overlay { if isWorking { ProgressView() } }
            .onAppear(perform: refreshScheduled)
        }
    }

    private func run(schedule: Bool) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                plan = schedule
                    ? try await coordinator.planAndSchedule(settings: store.settings)
                    : try await coordinator.buildPlan(settings: store.settings)
            } catch {
                errorMessage = error.localizedDescription
            }
            refreshScheduled()
        }
    }

    private func refreshScheduled() {
        scheduled = coordinator.alarms.scheduledAlarmTimes()
    }
}

private struct PlanSummary: View {
    let plan: WakePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if plan.hasAlarm {
                Text(plan.alarmTimes.map(WakePlanner.format).joined(separator: " · "))
                    .font(.title2.bold())
            } else {
                Text("No alarm needed").font(.title2.bold())
            }
            Text(plan.reason).foregroundStyle(.secondary)
            Text("Sent to Home Assistant as: \(plan.cause)")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
            if let appointment = plan.appointment, plan.source == .shift {
                Text("\(appointment.title) doesn't need an earlier alarm.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(plan.warnings, id: \.self) { warning in
                Label(warning, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
