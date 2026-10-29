import SwiftUI

/// The Nightfall palette: midnight blue ground, violet accents. Shared by the app and the
/// widgets so the Lock Screen matches. Text colors are chosen to stay readable (4.5:1 or
/// better) on `ground` and `surface`.
enum Theme {
    static let ground = Color(hex: 0x0B1026)
    static let surface = Color(hex: 0x141B3A)
    static let raised = Color(hex: 0x1C2550)
    static let border = Color(hex: 0x2A3366)
    static let divider = Color(hex: 0x222B58)

    static let text = Color(hex: 0xEEF0FF)
    static let textSoft = Color(hex: 0xC9CEEA)
    static let textMuted = Color(hex: 0xA9B1D6)
    static let textFaint = Color(hex: 0x8F98C4)

    /// Buttons and the highlighted alarm. White text on it.
    static let accent = Color(hex: 0x6D4AFF)
    /// Violet for text, icons and the big alarm time.
    static let accentText = Color(hex: 0xDDD6FE)
    static let accentIcon = Color(hex: 0xC4B5FD)

    static let shiftChip = (background: Color(hex: 0x2B1F5C), text: Color(hex: 0xDDD6FE))
    static let appointmentChip = (background: Color(hex: 0x13305A), text: Color(hex: 0xBFDBFE))
    static let leaveBy = Color(hex: 0x60A5FA)

    static let good = Color(hex: 0x7DE3C8)
    static let warning = (background: Color(hex: 0x2A1E12), border: Color(hex: 0x5B3B1A), text: Color(hex: 0xFCD9B0))
    static let danger = Color(hex: 0xFCA5A5)
    /// A snoozing alarm's ring (v0.4.2 item 5).
    static let snoozing = Color(hex: 0xFDE047)
}

/// Sora (SIL Open Font License, Shared/Fonts/OFL.txt) for times and titles; body text stays
/// SF Pro. Five static weights are bundled and listed under UIAppFonts in both targets.
enum SoraWeight: String {
    case light = "Light"
    case regular = "Regular"
    case medium = "Medium"
    case semibold = "SemiBold"
    case bold = "Bold"
}

extension Font {
    /// Scales with Dynamic Type relative to `style`.
    static func sora(_ size: CGFloat, _ weight: SoraWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Sora-\(weight.rawValue)", size: size, relativeTo: style)
    }

    /// Fixed size, for the big alarm digits that already fill their space.
    static func sora(fixed size: CGFloat, _ weight: SoraWeight = .regular) -> Font {
        .custom("Sora-\(weight.rawValue)", fixedSize: size)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// A Nightfall card: surface fill, hairline border, rounded corners.
    func nightfallCard(radius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
