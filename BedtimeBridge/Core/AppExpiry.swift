import Foundation

/// Free-team installs stop opening 7 days after they're signed (v0.4.3 item 9). The expiry is in
/// the embedded provisioning profile; the main screen warns from 3 days before and Home
/// Assistant gets it with every message.
enum AppExpiry {
    /// From embedded.mobileprovision (a signed plist); nil in the simulator or from the App Store.
    static let date: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expiration(inProfile: data)
    }()

    static func expiration(inProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = data[start.lowerBound..<end.upperBound]
        let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        return object?["ExpirationDate"] as? Date
    }

    struct Banner: Equatable {
        var text: String
        /// Red on the last day.
        var urgent: Bool
    }

    /// "Reinstall from Xcode in 2 days (expires Sat 9:14 PM)", from 3 days before; nil otherwise.
    static func banner(expires: Date?, now: Date = .now, calendar: Calendar = .current) -> Banner? {
        guard let expires, expires > now, expires.timeIntervalSince(now) <= 3 * 86400 else {
            if let expires, expires <= now { return Banner(text: "This install has expired. Reinstall from Xcode.", urgent: true) }
            return nil
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expires)).day ?? 0
        let when = expires.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let lead: String
        switch days {
        case 0: lead = "Reinstall from Xcode today"
        case 1: lead = "Reinstall from Xcode by tomorrow"
        default: lead = "Reinstall from Xcode in \(days) days"
        }
        return Banner(text: "\(lead) (expires \(when))", urgent: days == 0)
    }

    static var iso: String? { date.map { ISO8601DateFormatter().string(from: $0) } }
}
