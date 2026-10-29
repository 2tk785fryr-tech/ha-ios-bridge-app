import SwiftUI

/// Nap (v0.4.2 item 3): "How long?" Tap a length and the alarms are set straight away. Lengths
/// whose last alarm would land after the next thing today are greyed out, with the reason and
/// the longest nap that fits.
struct NapSheet: View {
    let settings: BridgeSettings
    /// Change nap (v0.4.2 item 6): the new length needs a slide-and-hold before it's set.
    var protected = false
    /// Set the nap's alarms for this many minutes.
    let start: (Int) async -> Void
    @State private var pending: Int?
    @State private var limit: NapLimit?
    @State private var loaded = false
    @State private var other = false
    @State private var otherMinutes = 25
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    private var count: Int { settings.napAlarmCount }
    private var spacing: Int { settings.napSpacingMinutes }

    private func times(_ minutes: Int) -> [Date] {
        NapPlanner.times(now: .now, minutes: minutes, count: count, spacing: spacing)
    }

    private func fits(_ minutes: Int) -> Bool {
        NapPlanner.fits(minutes: minutes, now: .now, count: count, spacing: spacing, limit: limit)
    }

    private var anyTooLate: Bool { settings.napLengths.contains { !fits($0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How long?")
                            .font(.sora(28, .semibold, relativeTo: .title))
                            .foregroundStyle(Theme.text)
                        Text("\(count) alarm\(count == 1 ? "" : "s"), \(spacing) min apart · tap to set")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                    }
                    if !loaded {
                        ProgressView("Checking what's later today…")
                            .tint(Theme.accentText)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(settings.napLengths, id: \.self) { minutes in
                                lengthButton(minutes)
                            }
                        }
                        if anyTooLate, let limit {
                            Label(limit.text, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(Theme.warning.text)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.warning.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.warning.border))
                            if let longest = NapPlanner.longest(now: .now, count: count, spacing: spacing, limit: limit) {
                                Button { set(longest) } label: {
                                    Text("Nap \(NapPlanner.lengthName(longest)) · \(NapPlanner.timesText(times(longest)))")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                        Button { other = true } label: {
                            Text("Other…")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accentText)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border))
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.ground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let pending {
                    VStack(spacing: 8) {
                        Text("Nap \(NapPlanner.lengthName(pending)) · \(NapPlanner.timesText(times(pending)))")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textSoft)
                        HoldSlider(label: "Slide and hold to change the nap", holdLabel: { "Changing in \($0)…" },
                                   knobSymbol: "clock.fill", tint: Theme.accent, onHold: { commit(pending) },
                                   accessibilityHint: "Replaces the nap's alarms.")
                            .frame(height: 72)
                            .id(pending)
                    }
                    .padding(20)
                    .background(Theme.ground)
                }
            }
            .disabled(working)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $other) { otherSheet }
            .task {
                limit = await BedtimeCoordinator.shared.napLimit(settings: settings)
                loaded = true
            }
        }
    }

    private func lengthButton(_ minutes: Int) -> some View {
        let ok = fits(minutes)
        return Button { set(minutes) } label: {
            VStack(spacing: 4) {
                Text(NapPlanner.lengthName(minutes))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ok ? Theme.text : Theme.textFaint)
                Text(ok ? NapPlanner.timesText(times(minutes)) : "too late")
                    .font(.caption)
                    .foregroundStyle(ok ? Theme.textMuted : Theme.textFaint)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(ok ? Theme.raised : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(ok ? 1 : 0.6)
        }
        .disabled(!ok)
    }

    private var otherSheet: some View {
        NavigationStack {
            SettingsPage(title: "Nap length") {
                Section {
                    Stepper(NapPlanner.lengthName(otherMinutes), value: $otherMinutes, in: 5...600, step: 5)
                    Text(fits(otherMinutes) ? NapPlanner.timesText(times(otherMinutes)) : "too late")
                        .foregroundStyle(fits(otherMinutes) ? Theme.textMuted : Theme.warning.text)
                } footer: {
                    if let limit, !fits(otherMinutes) { Text(limit.text) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { other = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        other = false
                        set(otherMinutes)
                    }
                    .disabled(!fits(otherMinutes))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func set(_ minutes: Int) {
        guard fits(minutes) else { return }
        if protected { pending = minutes } else { commit(minutes) }
    }

    private func commit(_ minutes: Int) {
        guard fits(minutes) else { return }
        working = true
        Task {
            await start(minutes)
            working = false
            dismiss()
        }
    }
}

/// During a nap, at the top of the main screen: when you're up, the nap's alarms with their
/// rings, what Home Assistant turned on, and End nap / Change….
struct NappingCard: View {
    let alarms: [NapAlarm]
    let status: String?
    let ring: (NapAlarm) -> AlarmBubble.Ring
    let end: () -> Void
    let change: () -> Void
    @State private var confirmingEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Napping", systemImage: "powersleep")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.accentText)
            if let first = alarms.first {
                Text("Up at \(WakePlanner.format(first.time))")
                    .font(.sora(26, .semibold, relativeTo: .title2))
                    .foregroundStyle(Theme.text)
            }
            Text("\(alarms.count) alarm\(alarms.count == 1 ? "" : "s") set · " + alarms.map { WakePlanner.format($0.time) }.joined(separator: " "))
                .font(.subheadline)
                .foregroundStyle(Theme.textSoft)
            AlarmBubbleRow(bubbles: alarms.map { AlarmBubble(time: $0.time, ring: ring($0), isWake: $0 == alarms.first) })
            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: 10) {
                Button { confirmingEnd = true } label: {
                    Label("End nap", systemImage: "stop.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button(action: change) {
                    Label("Change…", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .confirmationDialog("End your nap?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End nap", role: .destructive, action: end)
            } message: {
                Text("Turns the nap's alarms off. Home Assistant turns the napping helper and nap Focus off.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightfallCard()
    }
}
