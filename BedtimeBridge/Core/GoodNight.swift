import Foundation

/// Good night (v0.4.8 item 5): once alarms are set, the bar's slide-and-hold (and Siri) asks Home
/// Assistant to send RUN_BEDTIME, the push the bedtime nudge sends, so the bedtime shortcut runs.
enum GoodNight {
    private static let setAtKey = "goodNight.alarmsSetAt"

    /// When alarms were last set outside bedtime (a plan, your own time, Undo).
    static var alarmsSetAt: Date? {
        get { UserDefaults.standard.object(forKey: setAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: setAtKey) }
    }

    /// Alarms set this soon after bedtime started are the bedtime shortcut's own plan.
    static let planGrace: TimeInterval = 30 * 60

    /// Whether setting alarms now counts as setting them before bedtime.
    static func countsAsBeforeBedtime(bedtimeRanAt: Date?, now: Date = .now) -> Bool {
        guard let ran = bedtimeRanAt else { return true }
        return now.timeIntervalSince(ran) >= planGrace
    }

    /// The bar offers Good night: alarms set, and bedtime hasn't run since they were set.
    static func offered(alarmsSet: Bool, alarmsSetAt: Date?, bedtimeRanAt: Date?) -> Bool {
        guard alarmsSet, let set = alarmsSetAt else { return false }
        return (bedtimeRanAt ?? .distantPast) < set
    }

    enum Outcome: Equatable {
        case sent
        case already
        /// Home Assistant couldn't be reached, or isn't the integration.
        case noHomeAssistant
        case notSent
    }

    /// What Siri and the app say.
    static func dialog(_ outcome: Outcome) -> String {
        switch outcome {
        case .sent: "Good night. Bedtime is starting."
        case .already: "Bedtime already ran tonight."
        case .noHomeAssistant: "Couldn't reach Home Assistant, so bedtime didn't start. Run I'm Ready For Bed yourself."
        case .notSent: "Home Assistant couldn't send bedtime to the phone. Check that phone commands are on."
        }
    }
}

extension BedtimeCoordinator {
    var goodNightOffered: Bool {
        GoodNight.offered(alarmsSet: !setAlarmTimes().filter { $0 > .now }.isEmpty,
                          alarmsSetAt: GoodNight.alarmsSetAt, bedtimeRanAt: bedtimeRanAt)
    }

    func goodNight(settings phoneSettings: BridgeSettings) async -> GoodNight.Outcome {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        guard let link = HomeAssistantLinks.current(settings) as? IntegrationLink,
              let reply = try? await link.reply(.goodNight, data: [:]) else { return .noHomeAssistant }
        if reply["already"] as? Bool == true { return .already }
        return reply["good_night"] as? Bool == true ? .sent : .notSent
    }
}
