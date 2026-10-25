import SwiftUI

/// Opened from Stop on the snooze countdown. Ending a snooze takes a full slide, so a
/// sleepy tap can't do it by accident; anything less springs back and it keeps snoozing.
struct SlideToStopView: View {
    let stop: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var stopping = false

    private let knob: CGFloat = 64

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "zzz")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Theme.accentIcon)
            Text("Snoozing")
                .font(.sora(34, .semibold, relativeTo: .largeTitle))
                .foregroundStyle(Theme.text)
            Text("Slide all the way to stop the alarm. Let go early and it keeps snoozing.")
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
    }

    private var slider: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knob - 8, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface)
                Capsule().stroke(Theme.border, lineWidth: 1)
                Text(stopping ? "Stopping…" : "Slide to stop")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .opacity(1 - Double(offset / travel))
                Circle()
                    .fill(Theme.danger)
                    .frame(width: knob, height: knob)
                    .overlay(Image(systemName: "stop.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ground))
                    .padding(4)
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !stopping else { return }
                                offset = min(max(value.translation.width, 0), travel)
                            }
                            .onEnded { _ in
                                guard !stopping else { return }
                                if offset >= travel * 0.9 {
                                    offset = travel
                                    finish()
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
        .accessibilityHint("Stops the snoozed alarm")
        .accessibilityAction(named: "Stop alarm") { finish() }
    }

    private func finish() {
        stopping = true
        Task {
            await stop()
            dismiss()
        }
    }
}
