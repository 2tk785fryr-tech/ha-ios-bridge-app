import Foundation

/// Mornings with no alarms (v0.4.6 item 2): Home Assistant says when I'm awake applies (at home,
/// before Awake For Day, nothing left to ring); I'm awake runs good morning there.
enum NoAlarmMorning {
    private static let offeredKey = "noAlarmMorning.offered"

    /// From Home Assistant's latest reply.
    static var offered: Bool {
        get { UserDefaults.standard.bool(forKey: offeredKey) }
        set { UserDefaults.standard.set(newValue, forKey: offeredKey) }
    }

    /// The bar offers it on such a morning, from 4:00 AM until the evening, with no alarm or nap set.
    static func barOffers(offered: Bool, alarmsSet: Int, napping: Bool, evening: Bool) -> Bool {
        offered && alarmsSet == 0 && !napping && !evening
    }

    enum Outcome: Equatable {
        case done
        /// Home Assistant couldn't be reached, or isn't the integration.
        case noHomeAssistant
        case away
        case notSent
    }

    /// What Siri and the control say.
    static func dialog(_ outcome: Outcome) -> String {
        switch outcome {
        case .done: "Good morning. Sleep In is off and Good Morning is running."
        case .noHomeAssistant: "Couldn't reach Home Assistant, so nothing changed."
        case .away: "You're not home, so nothing changed."
        case .notSent: "Home Assistant couldn't send Good Morning to the phone. Check that phone commands are on."
        }
    }
}

extension BedtimeCoordinator {
    /// I'm awake: Sleep In off, Awake For Day on, the house disarmed and Good Morning run, in
    /// Home Assistant.
    func imAwake(settings phoneSettings: BridgeSettings) async -> NoAlarmMorning.Outcome {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        guard let link = HomeAssistantLinks.current(settings) as? IntegrationLink,
              let reply = try? await link.reply(.awake, data: [:]) else { return .noHomeAssistant }
        if reply["away"] as? Bool == true { return .away }
        guard reply["good_morning"] as? Bool == true else { return .notSent }
        NoAlarmMorning.offered = false
        return .done
    }
}
