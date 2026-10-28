import SwiftUI
import UIKit

/// Opened from Stop on the snooze countdown. Ending a snooze takes a full slide, so a
/// sleepy tap can't do it by accident; anything less springs back and it keeps snoozing.
/// Holding at the end of the slide for 5 seconds ends every alarm left in this wake-up.
struct SlideToStopView: View {
    /// Which alarm this is and what's left (item 1).
    let description: StopDescription
    /// Whether there are later alarms in the series for the hold to end (item 2).
    let canEndAll: Bool
    /// `true` ends every alarm left in this wake-up; `false` only this one.
    let stop: (_ all: Bool) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var stopping = false
    @State private var holdProgress: Double = 0
    @State private var hold: Task<Void, Never>?

    private let knob: CGFloat = 64
    static let holdSeconds = 5

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "zzz")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Theme.accentIcon)
            Text("Snoozing")
                .font(.sora(34, .semibold, relativeTo: .largeTitle))
                .foregroundStyle(Theme.text)
            VStack(spacing: 6) {
                Text(description.title)
                    .font(.sora(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Theme.accentText)
                Text(description.detail)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            Text(canEndAll
                 ? "Slide all the way to stop this alarm. Hold at the end for \(Self.holdSeconds) seconds to end all of this morning's alarms. Let go early and it keeps snoozing."
                 : "Slide all the way to stop this alarm. Let go early and it keeps snoozing.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            slider
                .padding(.horizontal, 24)
            Button("Keep snoozing") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.ignoresSafeArea())
        .onDisappear { hold?.cancel() }
    }

    private var sliderText: String {
        if stopping { return "Stopping…" }
        if holdProgress > 0 {
            let left = max(Self.holdSeconds - Int(holdProgress * Double(Self.holdSeconds)), 1)
            return "Ending all alarms in \(left)…"
        }
        return "Slide to stop"
    }

    private var slider: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knob - 8, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface)
                Capsule().stroke(Theme.border, lineWidth: 1)
                Text(sliderText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(holdProgress > 0 ? Theme.text : Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .opacity(holdProgress > 0 || stopping ? 1 : 1 - Double(offset / travel))
                Circle()
                    .fill(Theme.danger)
                    .frame(width: knob, height: knob)
                    .overlay(Image(systemName: "stop.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ground))
                    // The ring that fills while you hold at the end.
                    .overlay(
                        Circle()
                            .trim(from: 0, to: holdProgress)
                            .stroke(Theme.text, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(-3)
                    )
                    .padding(4)
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !stopping else { return }
                                offset = min(max(value.translation.width, 0), travel)
                                if offset >= travel * 0.98 {
                                    startHold()
                                } else {
                                    cancelHold()
                                }
                            }
                            .onEnded { _ in
                                guard !stopping else { return }
                                cancelHold()
                                if offset >= travel * 0.9 {
                                    offset = travel
                                    finish(all: false)
                                } else {
                                    withAnimation(.spring(duration: 0.3)) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: knob + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slide to stop")
        .accessibilityHint(canEndAll ? "Stops this alarm. Hold at the end to end all of this morning's alarms." : "Stops the snoozed alarm")
        .accessibilityAction(named: "Stop alarm") { finish(all: false) }
    }

    /// Five seconds at the end of the slide, with a tick each second; letting go first leaves
    /// it as a normal stop of this alarm.
    private func startHold() {
        guard canEndAll, hold == nil else { return }
        hold = Task { @MainActor in
            let ticks = UIImpactFeedbackGenerator(style: .rigid)
            ticks.prepare()
            let steps = Self.holdSeconds * 20
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                holdProgress = Double(step) / Double(steps)
                if step % 20 == 0, step < steps { ticks.impactOccurred() }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            hold = nil
            finish(all: true)
        }
    }

    private func cancelHold() {
        guard let running = hold else { return }
        running.cancel()
        hold = nil
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
    }

    private func finish(all: Bool) {
        guard !stopping else { return }
        stopping = true
        Task {
            await stop(all)
            dismiss()
        }
    }
}
