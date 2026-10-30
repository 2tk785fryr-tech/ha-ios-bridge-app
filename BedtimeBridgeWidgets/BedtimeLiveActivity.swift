import ActivityKit
import SwiftUI
import WidgetKit

/// Wind-down and morning Live Activities (v0.4.3 items 5 and 14), on the Lock Screen and in the
/// Dynamic Island. Countdowns tick on their own; the app updates the rest when it runs.
struct BedtimeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BedtimeActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding()
                .activityBackgroundTint(Theme.surface)
                .activitySystemActionForegroundColor(Theme.accentText)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.kind == .windDown ? "Bed" : "Leave", systemImage: state.kind == .windDown ? "moon.zzz" : "car")
                        .foregroundStyle(Theme.accentIcon)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(to: state.kind == .windDown ? state.goToBed : state.leaveBy)
                        .font(.sora(fixed: 22, .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accentText)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Details(state: state).font(.caption)
                }
            } compactLeading: {
                Image(systemName: state.kind == .windDown ? "moon.zzz" : "car").foregroundStyle(Theme.accentIcon)
            } compactTrailing: {
                // Compact: the countdown and, in the morning, the drive minutes.
                HStack(spacing: 4) {
                    Countdown(to: state.kind == .windDown ? state.goToBed : state.leaveBy)
                        .monospacedDigit()
                        .frame(maxWidth: 48)
                    if state.kind == .morning, let drive = state.driveMinutes { Text("\(drive)m").foregroundStyle(Theme.textMuted) }
                }
                .font(.caption2)
            } minimal: {
                Image(systemName: state.kind == .windDown ? "moon.zzz" : "car").foregroundStyle(Theme.accentIcon)
            }
        }
    }
}

private struct Countdown: View {
    let to: Date?

    var body: some View {
        if let to, to > .now {
            Text(timerInterval: Date.now...to, countsDown: true)
        } else {
            Text("now")
        }
    }
}

private func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

private struct LockScreenView: View {
    let state: BedtimeActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if state.kind == .windDown, let bed = state.goToBed {
                    Text("Bed in \(Text(bed, style: .relative))").font(.headline)
                } else if let leave = state.leaveBy {
                    Text("Leave in \(Text(leave, style: .relative)) · \(clock(leave))").font(.headline)
                }
                Spacer()
            }
            .foregroundStyle(Theme.text)
            Details(state: state)
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
    }
}

private struct Details: View {
    let state: BedtimeActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch state.kind {
            case .windDown:
                if let first = state.firstAlarm { Text("First alarm \(clock(first))") }
            case .morning:
                if let drive = state.driveMinutes {
                    Text("Drive \(drive) min" + (state.worstCaseMinutes.map { " · worst case \($0) min" } ?? ""))
                }
                if let drive = state.driveWeather { Text(drive) }
                if let day = state.dayWeather { Text(day) }
                if let name = state.nextBackstopName, let at = state.nextBackstop, at > .now {
                    Text("\(name) backstop \(clock(at))")
                }
            }
        }
    }
}
