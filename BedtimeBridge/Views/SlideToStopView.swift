import SwiftUI

/// Opened from Stop on the snooze countdown. Ending a snooze takes a full slide, so a
/// sleepy tap can't do it by accident; anything less springs back and it keeps snoozing.
/// Holding at the end of the slide for 5 seconds ends every alarm left in this wake-up.
struct SlideToStopView: View {
    /// Which alarm this is and what's left (item 1).
    let description: StopDescription
    /// Whether there are later alarms in the series for the hold to end (item 2).
    let canEndAll: Bool
    /// Settings for "Plans changed?" (item 3); nil hides it (temporary and test alarms).
    var settings: BridgeSettings? = nil
    /// `true` ends every alarm left in this wake-up; `false` only this one.
    let stop: (_ all: Bool) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var stopping = false

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
            if let settings {
                ChangeMorningEntry(
                    title: "Plans changed?",
                    detail: "Move this morning's alarms later, or turn them off.",
                    phase: .snoozing,
                    settings: settings,
                    done: { dismiss() }
                )
                .padding(.horizontal, 24)
            }
            // The easy, safe choice: big and obvious, unlike the deliberate slides above.
            Button { dismiss() } label: {
                Label("Keep snoozing", systemImage: "zzz")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.ground)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.accentText, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.ignoresSafeArea())
    }

    private var slider: some View {
        HoldSlider(
            label: stopping ? "Stopping…" : "Slide to stop",
            holdLabel: { "Ending all alarms in \($0)…" },
            holdSeconds: Self.holdSeconds,
            holdEnabled: canEndAll,
            onSlide: { finish(all: false) },
            onHold: { finish(all: true) },
            accessibilityHint: canEndAll ? "Stops this alarm. Hold at the end to end all of this morning's alarms." : "Stops the snoozed alarm"
        )
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
