import ActivityKit
import SwiftUI
import WidgetKit

/// Wind-down, morning and nap Live Activities (v0.4.3 items 5 and 14, v0.4.9 item 3), on the Lock
/// Screen and in the Dynamic Island. Countdowns tick on their own; the app updates the rest when
/// it runs.
struct BedtimeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BedtimeActivityAttributes.self) { context in
            LockScreenView(state: context.state, title: context.attributes.title, stale: context.isStale)
                .padding()
                .activityBackgroundTint(Theme.surface)
                .activitySystemActionForegroundColor(Theme.accentText)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.shortName, systemImage: state.symbol)
                        .foregroundStyle(Theme.accentIcon)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(to: state.countdownTarget)
                        .font(.sora(fixed: 22, .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accentText)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Details(state: state).font(.caption)
                }
            } compactLeading: {
                Image(systemName: state.symbol).foregroundStyle(Theme.accentIcon)
            } compactTrailing: {
                // Compact: the countdown and, in the morning, the drive minutes. v0.4.11 item 17:
                // always in full (minutes and seconds, 65:00 over an hour), centred on the line.
                HStack(spacing: 4) {
                    Countdown(to: state.countdownTarget, showsHours: false, past: state.kind == .morning && state.departed == nil ? "late" : "now")
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44, alignment: .trailing)
                    if state.kind == .morning, state.departed == nil, let drive = state.driveMinutes {
                        Text("\(drive)m").foregroundStyle(Theme.textMuted)
                    }
                }
                .font(.caption)
                .frame(maxHeight: .infinity, alignment: .center)
            } minimal: {
                Image(systemName: state.symbol).foregroundStyle(Theme.accentIcon)
            }
        }
    }
}

private extension BedtimeActivityAttributes.ContentState {
    var symbol: String {
        switch kind {
        case .windDown: "moon.zzz"
        case .morning: "car"
        case .nap: snoozedUntil.map { $0 > .now } == true ? "zzz" : "powersleep"
        }
    }

    var shortName: String {
        switch kind {
        case .windDown: "Bed"
        case .morning: "Leave"
        case .nap: "Nap"
        }
    }

    /// Nap: the snooze if one is running, otherwise when it's up.
    var countdownTarget: Date? {
        switch kind {
        case .windDown: goToBed
        case .morning: departed != nil ? eventStart : leaveBy
        case .nap: snoozedUntil.flatMap { $0 > .now ? $0 : nil } ?? firstAlarm
        }
    }
}

/// End nap: opens the app on the bar's slide-and-hold (v0.4.9 item 3).
private struct EndNapLink: View {
    var body: some View {
        Link(destination: URL(string: "bedtimebridge://endnap")!) {
            Label("End nap", systemImage: "stop.circle")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.accent.opacity(0.25), in: Capsule())
        }
    }
}

private struct Countdown: View {
    let to: Date?
    var showsHours = true
    var past = "now"

    var body: some View {
        if let to, to > .now {
            Text(timerInterval: Date.now...to, countsDown: true, showsHours: showsHours)
                .accessibilityLabel(CompactCountdown.label(to.timeIntervalSinceNow))
        } else {
            Text(past)
        }
    }
}

private func clock(_ date: Date) -> String { date.clockTime() }

private struct LockScreenView: View {
    let state: BedtimeActivityAttributes.ContentState
    let title: String
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if state.kind == .windDown, let bed = state.goToBed {
                    Text("Bed in \(Text(bed, style: .relative))").font(.headline)
                } else if state.kind == .nap, let snoozed = state.snoozedUntil, snoozed > .now {
                    Text("Snoozing · rings \(clock(snoozed))").font(.headline)
                } else if state.kind == .nap, let up = state.firstAlarm {
                    Text("Napping · up at \(clock(up))").font(.headline)
                } else if state.kind == .morning, let headline = MorningHeadline.of(state, stale: stale) {
                    // v0.4.11 item 20: past Leave by, it says so; once you've left, On your way.
                    switch headline {
                    case .leaveIn(let leave):
                        Text("Leave in \(Text(leave, style: .relative)) · \(clock(leave))").font(.headline)
                    case .pastLeaveTime(let leave):
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Past leave time · \(clock(leave))").font(.headline).foregroundStyle(Theme.amber)
                            Text("\(Text(leave, style: .relative)) late").font(.subheadline).foregroundStyle(Theme.amber)
                        }
                    case .onYourWay(let start):
                        Text("On your way" + (start.map { " · \(title) \(clock($0))" } ?? "")).font(.headline).foregroundStyle(Theme.good)
                    }
                } else if let leave = state.leaveBy {
                    Text("Leave in \(Text(leave, style: .relative)) · \(clock(leave))").font(.headline)
                }
                Spacer()
                if state.kind == .nap {
                    Countdown(to: state.countdownTarget).font(.headline.monospacedDigit()).frame(maxWidth: 80)
                }
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
            case .nap:
                EndNapLink()
            }
        }
    }
}
