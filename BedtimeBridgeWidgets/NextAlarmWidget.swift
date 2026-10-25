import SwiftUI
import WidgetKit

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    let snapshot: NextAlarmSnapshot

    var nextAlarm: Date? { snapshot.nextAlarm(after: date) }
    var isSnoozing: Bool { snapshot.snoozedUntil.map { $0 > date } ?? false }
    var label: String { snapshot.label(after: date) }
}

struct NextAlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(
            date: .now,
            snapshot: NextAlarmSnapshot(alarmTimes: [.now.addingTimeInterval(8 * 3600)], cause: "Days", label: "Days shift")
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : NextAlarmEntry(date: .now, snapshot: .load()))
    }

    /// One entry now plus one as each alarm passes, so the widget moves on to the next alarm
    /// (or "No alarm") without waiting for the app. The app reloads it whenever alarms change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let snapshot = NextAlarmSnapshot.load()
        let now = Date.now
        let entries = ([now] + snapshot.changeDates(after: now)).map { NextAlarmEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextAlarm", provider: NextAlarmProvider()) { entry in
            NextAlarmView(entry: entry)
                // Lock Screen sizes are tinted by the system; the Home Screen size uses Nightfall.
                .containerBackground(Theme.surface, for: .widget)
        }
        .configurationDisplayName("Next Alarm")
        .description("Your next wake-up alarm and why it's set.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall])
    }
}

struct NextAlarmView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextAlarmEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            if let alarm = entry.nextAlarm {
                Label("\(time(alarm)) · \(entry.label)", systemImage: entry.isSnoozing ? "zzz" : "alarm")
            } else {
                Label("No alarm", systemImage: "alarm")
            }

        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: entry.isSnoozing ? "zzz" : "alarm")
                    .font(.caption)
                if let alarm = entry.nextAlarm {
                    Text(alarm, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.sora(fixed: 17, .semibold))
                        .minimumScaleFactor(0.6)
                } else {
                    Text("Off").font(.headline)
                }
            }
            .widgetAccentable()

        case .systemSmall:
            NightfallSmallView(entry: entry)

        default:
            VStack(alignment: .leading, spacing: 1) {
                if let alarm = entry.nextAlarm {
                    Label(time(alarm), systemImage: entry.isSnoozing ? "zzz" : "alarm")
                        .font(.sora(fixed: 17, .semibold))
                        .widgetAccentable()
                    Text(entry.isSnoozing ? "Snoozing · \(entry.label)" : entry.label)
                        .font(.caption)
                        .lineLimit(1)
                    if entry.snapshot.alarmStyle == "clock" {
                        Text("Clock app alarms").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        // "3 alarms set · Leave by 5:26 AM": that they're really set, not just planned.
                        Text([entry.snapshot.setSummary(after: entry.date), entry.snapshot.leaveBy.flatMap { $0 > entry.date ? "Leave by \(time($0))" : nil }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    Label("No alarm", systemImage: "alarm")
                        .font(.headline)
                    Text("Nothing set").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// Home Screen widget in the Nightfall style.
private struct NightfallSmallView: View {
    let entry: NextAlarmEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(entry.isSnoozing ? "Snoozing" : "Next alarm", systemImage: entry.isSnoozing ? "zzz" : "alarm")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
            if let alarm = entry.nextAlarm {
                Text(alarm, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.sora(fixed: 40, .light))
                    .foregroundStyle(Theme.accentText)
                    .minimumScaleFactor(0.7)
                Text(entry.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.shiftChip.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.shiftChip.background, in: Capsule())
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let leaveBy = entry.snapshot.leaveBy, leaveBy > entry.date {
                    Text("Leave by \(leaveBy.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.appointmentChip.text)
                } else if let summary = entry.snapshot.setSummary(after: entry.date) {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.good)
                }
            } else {
                Text("No alarm")
                    .font(.sora(fixed: 26, .light))
                    .foregroundStyle(Theme.textSoft)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
