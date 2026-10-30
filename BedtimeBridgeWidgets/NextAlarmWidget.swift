import SwiftUI
import WidgetKit

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    let snapshot: NextAlarmSnapshot

    var nextAlarm: Date? { snapshot.nextAlarm(after: date) }
    var isSnoozing: Bool { snapshot.snoozedUntil.map { $0 > date } ?? false }
    var label: String { snapshot.label(after: date) }
    /// Alarms done, leave-by still ahead (or just past): item 4.
    var leaveByOnly: Date? { snapshot.leaveByAfterAlarms(at: date) }
    /// Winding down (v0.4.3 item 5): go to bed, counted down.
    var bed: Date? { snapshot.bedCountdown(at: date) }
}

struct NextAlarmProvider: TimelineProvider {
    /// A typical Days morning, so the gallery shows every line: 3 alarms and a leave-by.
    func placeholder(in context: Context) -> NextAlarmEntry {
        let wake = Date.now.addingTimeInterval(8 * 3600)
        return NextAlarmEntry(
            date: .now,
            snapshot: NextAlarmSnapshot(
                alarmTimes: [-600, -300, 0].map { wake.addingTimeInterval($0) },
                cause: "Days",
                label: "Days shift",
                leaveBy: wake.addingTimeInterval(89 * 60)
            )
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
            if let bed = entry.bed {
                Label("Bed in \(Text(bed, style: .relative))", systemImage: "moon.zzz")
            } else if let alarm = entry.nextAlarm {
                Label("\(time(alarm)) · \(entry.label)", systemImage: entry.isSnoozing ? "zzz" : "alarm")
            } else if let leaveBy = entry.leaveByOnly {
                Label("Leave by \(time(leaveBy)) · \(entry.label)", systemImage: "car")
            } else {
                Label("No alarm", systemImage: "alarm")
            }

        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: entry.nextAlarm == nil && entry.leaveByOnly != nil ? "car" : entry.isSnoozing ? "zzz" : "alarm")
                    .font(.caption)
                if let alarm = entry.nextAlarm {
                    Text(alarm, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.sora(fixed: 17, .semibold))
                        .minimumScaleFactor(0.6)
                } else if let leaveBy = entry.leaveByOnly {
                    Text(leaveBy, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
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
            // Three short lines, each fitting the Lock Screen's narrow rectangle: the time with
            // how many alarms are set, why, and when to leave.
            VStack(alignment: .leading, spacing: 1) {
                if let bed = entry.bed {
                    // "Bed in 42 min · first alarm 4:20"
                    Label { Text("Bed in \(Text(bed, style: .relative))") } icon: { Image(systemName: "moon.zzz") }
                        .font(.sora(fixed: 17, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    if let first = entry.nextAlarm {
                        Text("First alarm \(time(first))").font(.caption).lineLimit(1)
                    }
                    Text("Winding down").font(.caption).foregroundStyle(.secondary)
                } else if let alarm = entry.nextAlarm {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Label(time(alarm), systemImage: entry.isSnoozing ? "zzz" : "alarm")
                            .font(.sora(fixed: 17, .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .widgetAccentable()
                        Spacer(minLength: 0)
                        // That they're really set, not just planned.
                        if entry.snapshot.alarmStyle != "clock", entry.snapshot.setCount(after: entry.date) > 0 {
                            Text("\(entry.snapshot.setCount(after: entry.date)) set")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                    Text(entry.isSnoozing ? "Snoozing · \(entry.label)" : entry.label)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let leaveBy = entry.snapshot.leaveBy, leaveBy > entry.date {
                        Text("Leave by \(time(leaveBy))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else if entry.snapshot.alarmStyle == "clock" {
                        Text("Clock app alarms").font(.caption2).foregroundStyle(.secondary)
                    }
                } else if let leaveBy = entry.leaveByOnly {
                    Label("Leave by \(time(leaveBy))", systemImage: "car")
                        .font(.sora(fixed: 17, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .widgetAccentable()
                    Text(entry.label)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(leaveBy > entry.date ? "Alarms done" : "Time to go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Label(entry.isSnoozing ? "Snoozing" : entry.nextAlarm == nil && entry.leaveByOnly != nil ? "Alarms done" : "Next alarm",
                  systemImage: entry.isSnoozing ? "zzz" : "alarm")
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
            } else if let leaveBy = entry.leaveByOnly {
                Text("Leave by")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.appointmentChip.text)
                Text(leaveBy, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.sora(fixed: 40, .light))
                    .foregroundStyle(Theme.accentText)
                    .minimumScaleFactor(0.7)
                Text(entry.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
                Spacer(minLength: 0)
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
