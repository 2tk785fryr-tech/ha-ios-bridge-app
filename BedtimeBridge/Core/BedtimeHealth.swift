import Foundation

/// The bedtime health check (v0.4.8 item 14): what should be true once bedtime has run.
enum BedtimeHealth {
    private static let issueKey = "bedtimeHealth.issue"
    private static let checkedKey = "bedtimeHealth.checkedAt"

    /// The first thing that's off, from the last check.
    static var issue: String? {
        get { UserDefaults.standard.string(forKey: issueKey) }
        set { UserDefaults.standard.set(newValue, forKey: issueKey) }
    }

    static var checkedAt: Date? {
        get { UserDefaults.standard.object(forKey: checkedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: checkedKey) }
    }

    /// The issue still applies to tonight (checked in the last 12 hours).
    static func current(now: Date = .now) -> String? {
        guard let issue, let at = checkedAt, now.timeIntervalSince(at) < 12 * 3600 else { return nil }
        return issue
    }

    /// Home Assistant's health reply against the alarms set here. nil reply: not reachable.
    static func issues(reply: [String: Any]?, localAlarms: [Date], expectsBackstops: Bool) -> [String] {
        guard let reply else { return ["Home Assistant not reachable"] }
        var issues: [String] = []
        let theirs = (reply["alarm_times"] as? [String] ?? []).compactMap { ISO8601DateFormatter().date(from: $0) }
        if !localAlarms.isEmpty, !UndoRecord.same(localAlarms, theirs.filter { $0 > (localAlarms.min() ?? .now).addingTimeInterval(-60) }) {
            issues.append("Alarms differ from Home Assistant")
        }
        if expectsBackstops, reply["ladder"] as? String != "armed" { issues.append("Backstops not armed") }
        if reply["phone_commands"] as? Bool != true { issues.append("Phone commands off") }
        if reply["push_token"] as? Bool != true { issues.append("Push token not sent") }
        return issues
    }
}
