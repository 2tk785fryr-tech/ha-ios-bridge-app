import Foundation

/// The week from Home Assistant's own history (v0.4.3 item 15), for the summary screen.
struct WeeklySummary: Codable, Equatable {
    var from: Date?
    var to: Date?
    var text = ""
    var nightsTracked = 0
    var bedMinutesOffAverage: Int?
    var mornings = 0
    var snoozesPerMorning: Double?
    var backstopsFired = 0
    var morningsChanged = 0
    var changeReasons: [String] = []
    var naps = 0
    var napMinutes = 0

    init() {}

    init(_ reply: [String: Any]) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ key: String) -> Date? {
            guard let text = reply[key] as? String else { return nil }
            return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
        from = date("from")
        to = date("to")
        text = reply["text"] as? String ?? ""
        nightsTracked = reply["nights_tracked"] as? Int ?? 0
        bedMinutesOffAverage = reply["bed_minutes_off_average"] as? Int
        mornings = reply["mornings"] as? Int ?? 0
        snoozesPerMorning = (reply["snoozes_per_morning"] as? NSNumber)?.doubleValue
        backstopsFired = reply["backstops_fired"] as? Int ?? 0
        morningsChanged = reply["mornings_changed"] as? Int ?? 0
        changeReasons = reply["change_reasons"] as? [String] ?? []
        naps = reply["naps"] as? Int ?? 0
        napMinutes = reply["nap_minutes"] as? Int ?? 0
    }

    /// "12 min after target", "on target", "8 min before target"
    var bedLine: String? {
        guard let off = bedMinutesOffAverage else { return nil }
        if off == 0 { return "On target" }
        return "\(abs(off)) min \(off > 0 ? "after" : "before") target"
    }

    private static let key = "weeklySummary.v1"

    static var cached: WeeklySummary? {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(WeeklySummary.self, from: $0) } }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
}
