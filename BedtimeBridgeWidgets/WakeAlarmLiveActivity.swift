import AlarmKit
import SwiftUI
import WidgetKit

@main
struct BedtimeBridgeWidgets: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        WakeAlarmLiveActivity()
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
                    if let cause = context.attributes.metadata?.cause, !cause.isEmpty {
                        Text(cause).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                SnoozeCountdown(state: context.state)
                    .font(.title.monospacedDigit().bold())
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Snoozing", systemImage: "zzz")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SnoozeCountdown(state: context.state).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.presentation.alert.title).font(.caption)
                }
            } compactLeading: {
                Image(systemName: "zzz").foregroundStyle(.orange)
            } compactTrailing: {
                SnoozeCountdown(state: context.state).monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "alarm").foregroundStyle(.orange)
            }
        }
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
