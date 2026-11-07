import SwiftUI

/// v0.4.11 item 49: the circled i on a settings row. Tapped, a short pop-up with what that one
/// setting does; the grey text under a section only describes the group.
struct InfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(Theme.accentText)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("More about this setting")
        .accessibilityHint(text)
        .popover(isPresented: $shown) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 300, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }
}

extension View {
    /// The row with its ⓘ at the end.
    func info(_ text: String) -> some View {
        HStack(spacing: 10) {
            self
            InfoButton(text: text)
        }
    }
}
