import SwiftUI
import UIKit

/// A slide all the way across, optionally followed by holding at the end for a few seconds while
/// a ring fills and the phone ticks once a second. Deliberate on purpose: a sleepy swipe or a
/// short hold never completes the hold.
struct HoldSlider: View {
    let label: String
    /// Shown while holding, with the seconds left.
    let holdLabel: (Int) -> String
    var knobSymbol = "stop.fill"
    var tint = Theme.danger
    var holdSeconds = 5
    /// Whether holding at the end does anything (otherwise only `onSlide` can complete).
    var holdEnabled = true
    /// Letting go at the end, before the hold completes. nil: it springs back instead.
    var onSlide: (() -> Void)?
    let onHold: () -> Void
    var accessibilityHint = ""

    @State private var offset: CGFloat = 0
    @State private var holdProgress: Double = 0
    @State private var hold: Task<Void, Never>?
    @State private var done = false
    /// True only while a finger is on the knob. Unlike onEnded, this also resets when the
    /// system cancels the drag, so a cancelled drag can never let the hold finish on its own.
    @GestureState private var pressing = false

    private let knob: CGFloat = 64

    private var text: String {
        if holdProgress > 0 {
            return holdLabel(max(holdSeconds - Int(holdProgress * Double(holdSeconds)), 1))
        }
        return label
    }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knob - 8, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface)
                Capsule().stroke(Theme.border, lineWidth: 1)
                Text(text)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(holdProgress > 0 ? Theme.text : Theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, knob + 8)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity)
                    .opacity(holdProgress > 0 || done ? 1 : 1 - Double(offset / travel))
                Circle()
                    .fill(tint)
                    .frame(width: knob, height: knob)
                    .overlay(Image(systemName: knobSymbol).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ground))
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
                            .updating($pressing) { _, state, _ in state = true }
                            .onChanged { value in
                                guard !done else { return }
                                offset = min(max(value.translation.width, 0), travel)
                                if offset >= travel * 0.98 { startHold() } else { cancelHold() }
                            }
                            .onEnded { _ in
                                guard !done else { return }
                                cancelHold()
                                if let onSlide, offset >= travel * 0.9 {
                                    offset = travel
                                    done = true
                                    onSlide()
                                } else {
                                    withAnimation(.spring(duration: 0.3)) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: knob + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(accessibilityHint)
        .accessibilityAction(named: Text(label)) {
            guard !done else { return }
            done = true
            if let onSlide { onSlide() } else { onHold() }
        }
        .onDisappear { hold?.cancel() }
        .onChange(of: pressing) { _, isPressing in
            // The drag ended or was cancelled. onEnded handles a normal end; a cancelled drag
            // (no onEnded) must stop the hold and spring back.
            guard !isPressing, !done else { return }
            cancelHold()
            withAnimation(.spring(duration: 0.3)) { offset = 0 }
        }
    }

    private func startHold() {
        guard holdEnabled, hold == nil else { return }
        hold = Task { @MainActor in
            let ticks = UIImpactFeedbackGenerator(style: .rigid)
            ticks.prepare()
            let steps = holdSeconds * 20
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                holdProgress = Double(step) / Double(steps)
                if step % 20 == 0, step < steps { ticks.impactOccurred() }
            }
            // Only a finger still holding the knob completes it.
            guard pressing else {
                hold = nil
                withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            hold = nil
            done = true
            onHold()
        }
    }

    private func cancelHold() {
        guard let running = hold else { return }
        running.cancel()
        hold = nil
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
    }
}
