import SwiftUI
import UIKit

/// The three Nightfall icons. Crescent is the app's own icon; the others are alternates
/// (registered with ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES in project.yml).
enum AppIconChoice: String, CaseIterable, Identifiable {
    case crescent
    case bridge
    case dial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crescent: "Crescent"
        case .bridge: "Bridge"
        case .dial: "Night dial"
        }
    }

    /// nil = the primary icon.
    var alternateName: String? {
        switch self {
        case .crescent: nil
        case .bridge: "AppIcon-Bridge"
        case .dial: "AppIcon-Dial"
        }
    }

    var preview: String {
        switch self {
        case .crescent: "IconPreview-Crescent"
        case .bridge: "IconPreview-Bridge"
        case .dial: "IconPreview-Dial"
        }
    }

    @MainActor
    static var current: AppIconChoice {
        allCases.first { $0.alternateName == UIApplication.shared.alternateIconName } ?? .crescent
    }
}

struct AppIconSection: View {
    @State private var selected = AppIconChoice.current
    @State private var error: String?

    var body: some View {
        Section {
            HStack(spacing: 12) {
                ForEach(AppIconChoice.allCases) { choice in
                    Button {
                        Task { await pick(choice) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(choice.preview)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(selected == choice ? Theme.accentIcon : .clear, lineWidth: 3)
                                        .padding(-4)
                                )
                            Text(choice.title)
                                .font(.footnote)
                                .foregroundStyle(selected == choice ? Theme.text : Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(choice.title) icon")
                    .accessibilityAddTraits(selected == choice ? .isSelected : [])
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("App icon")
        }
    }

    @MainActor
    private func pick(_ choice: AppIconChoice) async {
        guard choice != selected, UIApplication.shared.supportsAlternateIcons else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(choice.alternateName)
            selected = choice
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
