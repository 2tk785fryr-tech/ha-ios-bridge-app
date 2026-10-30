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
                // What matters now (snooze screen, the morning, otherwise Tonight), or always
                // Tonight (v0.4.3 item 16).
                .widgetURL(URL(string: entry.snapshot.widgetTapAlwaysTonight == true ? "bedtimebridge://tonight" : "bedtimebridge://now"))
        }
        .configurationDisplayName("Next Alarm")
        .description("Your next wake-up alarm and why it's set.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline,
                            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
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
                    Text(alarm, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute().locale(ClockStyle.locale))
                        .font(.sora(fixed: 17, .semibold))
                        .minimumScaleFactor(0.6)
                } else if let leaveBy = entry.leaveByOnly {
                    Text(leaveBy, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute().locale(ClockStyle.locale))
                        .font(.sora(fixed: 17, .semibold))
                        .minimumScaleFactor(0.6)
                } else {
                    Text("Off").font(.headline)
                }
            }
            .widgetAccentable()

        case .systemSmall:
            NightfallSmallView(entry: entry)

        case .systemMedium:
            NightfallMediumView(entry: entry)

        case .systemLarge:
            NightfallLargeView(entry: entry, columns: false)

        case .systemExtraLarge:
            NightfallLargeView(entry: entry, columns: true)

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
        date.clockTime()
    }
}

/// Home Screen widget in the Nightfall style.
private struct NightfallSmallView: View {
    let entry: NextAlarmEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(entry: entry)
            if let bed = entry.bed {
                Text(bed, style: .relative)
                    .font(.sora(fixed: 30, .light))
                    .foregroundStyle(Theme.accentText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("until bed").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSoft)
                Spacer(minLength: 0)
                if let first = entry.nextAlarm {
                    Text("First alarm \(first.clockTime())")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            } else if let alarm = entry.nextAlarm {
                Text(alarm, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute().locale(ClockStyle.locale))
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
                    Text("Leave by \(leaveBy.clockTime())")
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
                Text(leaveBy, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute().locale(ClockStyle.locale))
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


// MARK: Bigger sizes

/// "Next alarm", "Snoozing", "Winding down" or "Alarms done", over the big time.
private struct WidgetHeading: View {
    let entry: NextAlarmEntry

    var body: some View {
        let (text, symbol): (String, String) = if entry.bed != nil { ("Winding down", "moon.zzz") }
            else if entry.isSnoozing { ("Snoozing", "zzz") }
            else if entry.nextAlarm == nil && entry.leaveByOnly != nil { ("Alarms done", "car") }
            else { ("Next alarm", "alarm") }
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(entry.isSnoozing ? Theme.snoozing : Theme.textMuted)
    }
}

/// The big time: go to bed's countdown, the next alarm, leave-by, or "No alarm".
private struct WidgetBigTime: View {
    let entry: NextAlarmEntry
    var size: CGFloat = 46

    var body: some View {
        if let bed = entry.bed {
            Text(bed, style: .relative)
                .font(.sora(fixed: size * 0.7, .light))
                .foregroundStyle(Theme.accentText)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        } else if let time = entry.nextAlarm ?? entry.leaveByOnly {
            Text(time, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute().locale(ClockStyle.locale))
                .font(.sora(fixed: size, .light))
                .foregroundStyle(Theme.accentText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        } else {
            Text("No alarm")
                .font(.sora(fixed: size * 0.6, .light))
                .foregroundStyle(Theme.textSoft)
        }
    }
}

private struct WidgetChip: View {
    let entry: NextAlarmEntry

    var body: some View {
        if let label = entry.snapshot.chipLabel(at: entry.date) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.shiftChip.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.shiftChip.background, in: Capsule())
                .lineLimit(1)
        }
    }
}

/// One timeline line: an icon, what it is, and when.
private struct WidgetStepRow: View {
    let step: NextAlarmSnapshot.Step
    var large = false

    private var symbol: String {
        switch step.kind {
        case .windDown: "moon.zzz"
        case .goToBed: "bed.double"
        case .alarm: "alarm"
        case .wakeUp: "sun.max"
        case .temporary: "alarm.waves.left.and.right"
        case .snooze: "zzz"
        case .leaveBy: "car"
        }
    }

    private var tint: Color {
        switch step.kind {
        case .leaveBy: Theme.leaveBy
        case .snooze: Theme.snoozing
        case .wakeUp: Theme.accentText
        default: Theme.textSoft
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(large ? .subheadline : .caption)
                .foregroundStyle(tint)
                .frame(width: large ? 20 : 16)
            Text(step.title)
                .font((large ? Font.subheadline : .caption).weight(step.kind == .wakeUp || step.kind == .leaveBy ? .semibold : .regular))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(step.time, format: .dateTime.hour().minute().locale(ClockStyle.locale).locale(ClockStyle.locale))
                .font((large ? Font.subheadline : .caption).monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}

/// "3 alarms set", "Clock app alarms" or "Nothing set".
private struct WidgetStatus: View {
    let entry: NextAlarmEntry

    var body: some View {
        if entry.snapshot.alarmStyle == "clock", entry.nextAlarm != nil {
            Label("Clock app alarms", systemImage: "clock").foregroundStyle(Theme.textMuted)
        } else if let summary = entry.snapshot.setSummary(after: entry.date) {
            Label(summary, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
        } else {
            Label("Nothing set", systemImage: "moon.stars").foregroundStyle(Theme.textMuted)
        }
    }
}

/// Medium: the next alarm big on the left; the next four things on the right.
private struct NightfallMediumView: View {
    let entry: NextAlarmEntry

    var body: some View {
        let steps = Array(entry.snapshot.steps(after: entry.date).prefix(4))
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeading(entry: entry)
                WidgetBigTime(entry: entry, size: 44)
                WidgetChip(entry: entry)
                Spacer(minLength: 0)
                WidgetStatus(entry: entry).font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                if steps.isEmpty {
                    Text("Nothing else tonight").font(.caption).foregroundStyle(Theme.textMuted)
                } else {
                    ForEach(Array(steps.enumerated()), id: \.offset) { WidgetStepRow(step: $0.element) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Large (and extra large in two columns): the reason, the big time, and the whole night and
/// morning as a timeline.
private struct NightfallLargeView: View {
    let entry: NextAlarmEntry
    let columns: Bool

    private var title: String {
        let hour = Calendar.current.component(.hour, from: entry.date)
        return hour < 12 && hour >= 4 ? "This morning" : "Tonight"
    }

    var body: some View {
        let steps = Array(entry.snapshot.steps(after: entry.date).prefix(columns ? 10 : 8))
        let summary = VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.sora(fixed: 22, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                WidgetChip(entry: entry)
            }
            WidgetHeading(entry: entry)
            WidgetBigTime(entry: entry, size: 64)
            if let reason = entry.snapshot.reason, !reason.isEmpty, entry.nextAlarm != nil {
                Text(reason).font(.footnote).foregroundStyle(Theme.textSoft).lineLimit(2)
            }
        }
        let timeline = VStack(alignment: .leading, spacing: 9) {
            if steps.isEmpty {
                Text("Nothing set for tonight. Open the app to plan.").font(.footnote).foregroundStyle(Theme.textMuted)
            } else {
                ForEach(Array(steps.enumerated()), id: \.offset) { WidgetStepRow(step: $0.element, large: true) }
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            if columns {
                HStack(alignment: .top, spacing: 24) {
                    summary.frame(maxWidth: .infinity, alignment: .leading)
                    timeline.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                summary
                Divider().overlay(Theme.divider)
                timeline
            }
            Spacer(minLength: 0)
            WidgetStatus(entry: entry).font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
