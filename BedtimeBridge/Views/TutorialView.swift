import SwiftUI

/// v0.4.11 item 31: How to use Bedtime Bridge. One page at a time with Previous and Next (or a
/// swipe), page dots, Skip on every page and Done on the last. Opened from Settings → About, and
/// once by itself on a fresh install.
struct TutorialView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var open: Tutorial.Link?
    /// Called when it closes (Skip or Done), after it's marked as seen.
    var finished: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $index) {
                ForEach(Tutorial.pages) { page in
                    ScrollView {
                        TutorialPageView(page: page, open: { open = $0 })
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                    .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: index)

            controls
        }
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle("How to use Bedtime Bridge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip") { finish() }
            }
        }
        .navigationDestination(item: $open) { link in TutorialSettingsPage(link: link) }
    }

    private var controls: some View {
        let page = Tutorial.pages[index]
        return VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(Tutorial.pages) { p in
                    Circle()
                        .fill(p.id == index ? Theme.accentIcon : Theme.border)
                        .frame(width: p.id == index ? 8 : 6, height: p.id == index ? 8 : 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Page \(index + 1) of \(Tutorial.pages.count)")
            HStack(spacing: 12) {
                if index > 0 {
                    button("Previous", filled: false) { index -= 1 }
                }
                if page.startsHomeAssistant {
                    button("Skip Home Assistant", filled: false) { index = Tutorial.afterSkippingHomeAssistant() }
                }
                if index < Tutorial.lastIndex {
                    button("Next", filled: true) { index += 1 }
                } else {
                    button("Done", filled: true) { finish() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.ground)
    }

    private func button(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(filled ? .white : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(filled ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(filled ? .clear : Theme.buttonOutline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        Tutorial.seen = true
        finished()
        dismiss()
    }
}

/// One page: the drawing, the title, the words and its Take me there buttons.
private struct TutorialPageView: View {
    @Environment(SettingsStore.self) private var store
    let page: Tutorial.Page
    let open: (Tutorial.Link) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TutorialGraphic(graphic: page.graphic, open: open)
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border, lineWidth: 1))
                .accessibilityHidden(page.graphic != .checklist)
            Text(page.title)
                .font(.custom("Sora-SemiBold", size: 24, relativeTo: .title2))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(page.text)
                .font(.body)
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            if !page.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(page.bullets, id: \.self) { bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.accentIcon).frame(width: 6, height: 6).offset(y: -2)
                            Text(bullet).foregroundStyle(Theme.textSoft).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            ForEach(page.links) { link in
                Button { open(link) } label: {
                    Label(page.links.count > 1 ? "Take me to \(link.title)" : "Take me there", systemImage: "arrow.right.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: Drawings

/// The pages' drawings, in the app's own style (no screenshots, so they don't go stale).
private struct TutorialGraphic: View {
    let graphic: Tutorial.Graphic
    let open: (Tutorial.Link) -> Void

    var body: some View {
        switch graphic {
        case .welcome: welcome
        case .calendarWeek: calendarWeek
        case .shiftTitles: shiftTitles
        case .shiftTiming: shiftTiming
        case .alarmSeries: alarmSeries
        case .appointment: appointment
        case .remote: remote
        case .vacation: vacation
        case .calendars: calendars
        case .evening: evening
        case .morning: morning
        case .homeAssistant: homeAssistant
        case .pairing: pairing
        case .checklist: TutorialChecklist(open: open)
        }
    }

    private var welcome: some View {
        HStack(spacing: 14) {
            EventBlock(title: "Days", time: "6:30 – 15:00", color: Theme.shiftChip)
                .frame(width: 110)
            Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(Theme.textMuted)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["4:20", "4:25", "4:30"], id: \.self) { time in
                    Label(time, systemImage: "alarm.fill")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accentText)
                }
            }
        }
    }

    private var calendarWeek: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(["Mon", "Tue", "Wed", "Thu", "Fri"].enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 6) {
                        Text(day).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textMuted)
                        if index == 3 {
                            Spacer().frame(height: 54)
                        } else {
                            EventBlock(title: index == 2 ? "Swings" : "Days", time: index == 2 ? "14:30" : "6:30",
                                       color: Theme.shiftChip, compact: true)
                                .frame(height: 54)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            DetailCard(rows: [("Title", "Days"), ("Starts", "Mon 6:30"), ("Ends", "Mon 15:00"), ("Location", "1 Plant Rd, Springfield")])
        }
    }

    private var shiftTitles: some View {
        VStack(alignment: .leading, spacing: 10) {
            TitleCheck(title: "Days", ok: true, note: "Days")
            TitleCheck(title: "days OT", ok: true, note: "Days")
            TitleCheck(title: "Days – cover for Sam", ok: true, note: "Days")
            TitleCheck(title: "Day", ok: false, note: "no shift")
        }
    }

    private var shiftTiming: some View {
        VStack(alignment: .leading, spacing: 18) {
            MiniTimeline(caption: "Days · 2 hours before", marks: [("Wake up", "4:30", Theme.accent), ("Starts", "6:30", Theme.text)])
            MiniTimeline(caption: "Swings · always 8:00", marks: [("Wake up", "8:00", Theme.accent), ("Starts", "14:30", Theme.text)])
        }
    }

    private var alarmSeries: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(["4:20", "4:25", "4:30"].enumerated()), id: \.offset) { index, time in
                    VStack(spacing: 6) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: index == 2 ? 30 : 22))
                            .foregroundStyle(index == 2 ? Theme.accentIcon : Theme.textMuted)
                        Text(time).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                        Text(index == 2 ? "Wake up" : "Alarm \(index + 1)").font(.caption).foregroundStyle(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Wake-up is the last alarm · 3 alarms, 5 min apart")
                .font(.caption).foregroundStyle(Theme.textFaint)
        }
    }

    private var appointment: some View {
        VStack(spacing: 14) {
            DetailCard(rows: [("Title", "Dentist"), ("Starts", "Thu 8:00"), ("Location", "Main St Dental"), ("Notes", "wake up")],
                       highlight: "Notes")
            VStack(alignment: .leading, spacing: 0) {
                TimelineDot(title: "Wake up", value: "6:25", color: Theme.accent)
                TimelineDot(title: "Get ready", value: "60 min", color: Theme.accent, ring: true)
                TimelineDot(title: "Leave by", value: "7:25", color: Theme.leaveBy)
                TimelineDot(title: "Arrive", value: "10 min early", color: Theme.leaveBy, ring: true)
                TimelineDot(title: "Dentist", value: "8:00", color: Theme.text, last: true)
            }
        }
    }

    private var remote: some View {
        HStack(spacing: 14) {
            Image(systemName: "house.fill").font(.system(size: 34)).foregroundStyle(Theme.good)
            VStack(alignment: .leading, spacing: 8) {
                EventBlock(title: "Days WFH", time: "6:30", color: Theme.shiftChip).frame(width: 150)
                Text("No drive · get ready 30 min").font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var vacation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textMuted).frame(maxWidth: .infinity)
                }
            }
            Text("Leave · all day")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.appointmentChip.text)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Theme.appointmentChip.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("No alarms Mon to Sun").font(.caption).foregroundStyle(Theme.textFaint)
        }
    }

    private var calendars: some View {
        VStack(spacing: 0) {
            ForEach(Array([("Work", true), ("Personal", true), ("Holidays", false)].enumerated()), id: \.offset) { index, item in
                HStack {
                    Circle().fill([Theme.accent, Theme.leaveBy, Theme.amber][index]).frame(width: 10, height: 10)
                    Text(item.0).foregroundStyle(Theme.text)
                    Spacer()
                    if item.1 { Image(systemName: "checkmark").foregroundStyle(Theme.accentIcon).fontWeight(.semibold) }
                }
                .padding(.vertical, 10)
                if index < 2 { Divider().overlay(Theme.divider) }
            }
        }
    }

    private var evening: some View {
        VStack(spacing: 10) {
            Text("Tomorrow 4:20 · not set yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSoft)
            HStack(spacing: 8) {
                Pill(title: "Set 3 · up 4:30", filled: true)
                Pill(title: "Preview plan", filled: false)
            }
            HStack(spacing: 8) {
                Pill(title: "Wake later…", filled: false)
                Pill(title: "No alarms Friday", filled: false)
            }
        }
    }

    private var morning: some View {
        VStack(spacing: 14) {
            HStack {
                Circle().fill(Theme.accent).frame(width: 44, height: 44)
                    .overlay(Image(systemName: "stop.fill").foregroundStyle(.white))
                Text("Slide to stop · hold for all").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .padding(5)
            .background(Theme.raised, in: Capsule())
            VStack(alignment: .leading, spacing: 0) {
                TimelineDot(title: "Wake up", value: "4:30", color: Theme.accent)
                TimelineDot(title: "Get ready", value: "78 min", color: Theme.accent, ring: true)
                TimelineDot(title: "Leave by", value: "5:48", color: Theme.leaveBy, last: true)
            }
        }
    }

    private var homeAssistant: some View {
        HStack(spacing: 18) {
            Image(systemName: "iphone").font(.system(size: 40)).foregroundStyle(Theme.accentIcon)
            Image(systemName: "arrow.left.arrow.right").font(.title3).foregroundStyle(Theme.textMuted)
            Image(systemName: "house.fill").font(.system(size: 40)).foregroundStyle(Theme.leaveBy)
        }
        .padding(.vertical, 10)
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(["Install from the Marketplace", "Add the integration", "Pair in the app"].enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent, in: Circle())
                    Text(step).foregroundStyle(Theme.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The last page: what's done and what's left, ticked from your settings.
private struct TutorialChecklist: View {
    @Environment(SettingsStore.self) private var store
    let open: (Tutorial.Link) -> Void

    var body: some View {
        let items = Tutorial.checklist(settings: store.settings,
                                       shiftFound: BedtimeCoordinator.shared.shiftThisWeek(settings: store.settings),
                                       paired: HomeAssistantLinks.current(store.settings) != nil)
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button { if !item.done { open(item.link) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.done ? Theme.good : Theme.textFaint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).foregroundStyle(Theme.text)
                            if item.optional { Text("Optional").font(.caption).foregroundStyle(Theme.textFaint) }
                        }
                        Spacer()
                        if !item.done { Image(systemName: "chevron.right").foregroundStyle(Theme.textFaint) }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title), \(item.done ? "done" : "not done")")
                if index < items.count - 1 { Divider().overlay(Theme.divider) }
            }
        }
    }
}

// MARK: Drawing pieces

private struct EventBlock: View {
    let title: String
    let time: String
    let color: (background: Color, text: Color)
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: compact ? 11 : 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(time).font(.system(size: compact ? 10 : 13).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(color.text)
        .padding(compact ? 5 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 3).padding(.vertical, 4)
        }
    }
}

private struct DetailCard: View {
    let rows: [(String, String)]
    var highlight: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0).font(.footnote).foregroundStyle(Theme.textMuted).frame(width: 74, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 14, weight: row.0 == highlight ? .bold : .regular))
                        .foregroundStyle(row.0 == highlight ? Theme.amber : Theme.text)
                    Spacer()
                }
                .padding(.vertical, 7)
                if index < rows.count - 1 { Divider().overlay(Theme.divider) }
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TitleCheck: View {
    let title: String
    let ok: Bool
    let note: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Theme.good : Theme.danger)
            Text("\u{201C}\(title)\u{201D}").foregroundStyle(Theme.text)
            Spacer()
            Text(note).font(.footnote).foregroundStyle(Theme.textMuted)
        }
    }
}

private struct MiniTimeline: View {
    let caption: String
    let marks: [(String, String, Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption).font(.caption.weight(.semibold)).foregroundStyle(Theme.textMuted)
            HStack(spacing: 0) {
                ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                    if index > 0 { Rectangle().fill(Theme.border).frame(height: 2) }
                    VStack(spacing: 4) {
                        Circle().fill(mark.2).frame(width: 12, height: 12)
                        Text(mark.1).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                        Text(mark.0).font(.caption2).foregroundStyle(Theme.textMuted)
                    }
                    .fixedSize()
                }
            }
        }
    }
}

private struct TimelineDot: View {
    let title: String
    let value: String
    let color: Color
    var ring = false
    var last = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Group {
                    if ring { Circle().strokeBorder(color, lineWidth: 2) } else { Circle().fill(color) }
                }
                .frame(width: 10, height: 10)
                .padding(.top, 4)
                if !last { Rectangle().fill(Theme.border).frame(width: 2).frame(maxHeight: .infinity) }
            }
            .frame(width: 12)
            HStack {
                Text(title).foregroundStyle(Theme.text)
                Spacer()
                Text(value).foregroundStyle(Theme.textMuted).monospacedDigit()
            }
            .font(.system(size: 14))
            .padding(.bottom, last ? 0 : 12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Pill: View {
    let title: String
    let filled: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(filled ? .white : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(filled ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(filled ? .clear : Theme.buttonOutline, lineWidth: 1.2))
    }
}
