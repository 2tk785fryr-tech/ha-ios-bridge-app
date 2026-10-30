import Foundation

/// Settings → Clock (v0.4.7 item 10): times as the phone shows them, or always 12- or 24-hour.
/// Kept in the App Group so the widgets and Live Activities follow it too.
enum ClockStyle: String, Codable, CaseIterable, Identifiable {
    case phone, twelveHour, twentyFourHour

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .phone: "Phone setting"
        case .twelveHour: "12-hour"
        case .twentyFourHour: "24-hour"
        }
    }

    private static let key = "clockStyle.v1"

    static var current: ClockStyle {
        get { UserDefaults(suiteName: NextAlarmSnapshot.appGroup)?.string(forKey: key).flatMap(ClockStyle.init(rawValue:)) ?? .phone }
        set { UserDefaults(suiteName: NextAlarmSnapshot.appGroup)?.set(newValue.rawValue, forKey: key) }
    }

    /// Whether times are 24-hour with this style, on a phone set to `phone24Hour`.
    func uses24Hour(phone24Hour: Bool = ClockStyle.phoneUses24Hour) -> Bool {
        switch self {
        case .phone: phone24Hour
        case .twelveHour: false
        case .twentyFourHour: true
        }
    }

    /// The phone's own choice (Settings → General → Date & Time → 24-Hour Time).
    static var phoneUses24Hour: Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    /// The phone's locale with the hour cycle this style wants.
    static func locale(for style: ClockStyle = .current, base: Locale = .current) -> Locale {
        guard style != .phone else { return base }
        var components = Locale.Components(locale: base)
        components.hourCycle = style == .twentyFourHour ? .zeroToTwentyThree : .oneToTwelve
        return Locale(components: components)
    }

    static var locale: Locale { locale() }
}

extension Date {
    /// "5:30 AM" or "05:30", as Settings → Clock says.
    func clockTime(style: ClockStyle = .current) -> String {
        formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(ClockStyle.locale(for: style)))
    }
}
