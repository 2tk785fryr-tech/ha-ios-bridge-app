import AlarmKit
import SwiftUI
import WidgetKit

@main
struct BedtimeBridgeWidgets: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        WakeAlarmLiveActivity()
        BedtimeLiveActivity()
        NapControl()
        WindDownControl()
        TonightControl()
        ImAwakeControl()
        ReportControl()
    }
}

/// AlarmKit needs a Live Activity to show an alarm's countdown, which is how snooze
/// appears on the Lock Screen and in the Dynamic Island.
struct WakeAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeAlarmMetadata>.self) { context in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    if let cause = context.attributes.metadata?.cause, !cause.isEmpty {
                        Text("Snoozing · \(cause)").font(.caption).foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer()
                SnoozeCountdown(state: context.state)
                    .font(.sora(fixed: 30, .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accentText)
                StopButton(alarmID: context.state.alarmID)
            }
            .padding()
            .activityBackgroundTint(Theme.surface)
            .activitySystemActionForegroundColor(Theme.accentText)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Snoozing", systemImage: "zzz").foregroundStyle(Theme.accentIcon)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SnoozeCountdown(state: context.state).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.presentation.alert.title).font(.caption)
                        Spacer()
                        StopButton(alarmID: context.state.alarmID)
                    }
                }
            } compactLeading: {
                Image(systemName: "zzz").foregroundStyle(Theme.accentIcon)
            } compactTrailing: {
                SnoozeCountdown(state: context.state).monospacedDigit().foregroundStyle(Theme.accentText).frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "alarm").foregroundStyle(Theme.accentIcon)
            }
        }
    }
}

/// Opens the app's slide-to-stop screen. Widgets only take taps, so the slide that keeps a
/// sleepy tap from ending the snooze happens in the app; the ringing alarm's own Stop
/// comes from the system.
private struct StopButton: View {
    let alarmID: UUID

    var body: some View {
        Link(destination: URL(string: "bedtimebridge://stop?id=\(alarmID.uuidString)")!) {
            Label("Stop", systemImage: "stop.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accent, in: Capsule())
        }
        .accessibilityLabel("Stop alarm")
    }
}

private struct SnoozeCountdown: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...max(countdown.fireDate, .now), countsDown: true)
        default:
            Image(systemName: "alarm")
        }
    }
}
