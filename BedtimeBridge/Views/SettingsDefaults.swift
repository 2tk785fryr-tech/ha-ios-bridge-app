import SwiftUI

/// v0.4.3 item 8: each setting shows its default when it differs ("5 alarms · default 3"), and
/// each page ends with "Reset this page to defaults".
struct DefaultNote: View {
    let text: String

    var body: some View {
        Text("default \(text)")
            .font(.caption)
            .foregroundStyle(Theme.textFaint)
    }
}

/// A stepper whose label shows the value, plus the default in grey when it differs.
struct DefaultStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let defaultValue: Int
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(title): \(format(value))")
                if value != defaultValue { DefaultNote(text: format(defaultValue)) }
            }
        }
    }
}

/// A switch with its default in grey when it differs.
struct DefaultToggle: View {
    let title: String
    @Binding var isOn: Bool
    let defaultValue: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if isOn != defaultValue { DefaultNote(text: defaultValue ? "on" : "off") }
            }
        }
    }
}

/// "Reset this page to defaults" at the bottom of a settings page, with a confirm.
struct ResetPageSection: View {
    var detail = "Only this page's settings go back to their defaults."
    let reset: () -> Void
    @State private var confirming = false

    var body: some View {
        Section {
            Button("Reset this page to defaults", role: .destructive) { confirming = true }
                .confirmationDialog("Reset this page to defaults?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Reset", role: .destructive, action: reset)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(detail)
                }
        }
    }
}

enum DurationText {
    /// 390 → "6.5 h", 60 → "60 min"
    static func hours(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%.2g h", Double(minutes) / 60).replacingOccurrences(of: ".0 ", with: " ")
    }

    static func minutes(_ minutes: Int) -> String { "\(minutes) min" }
}
