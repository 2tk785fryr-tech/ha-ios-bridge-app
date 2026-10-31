import Foundation

/// v0.4.8 item 2: Plan Wake-Up Alarms keeps your own alarms instead of planning over them, and
/// asks once when you ran the bedtime shortcut yourself.
enum OwnAlarmsKept {
    /// "Keep your alarms at 9:40, 9:50 and 10:00?", or with a shift or event that needs you up
    /// earlier: "Your Days shift needs you up at 5:30. Keep your alarms at 10:00?"
    static func question(kept: [Date], found: WakePlan?) -> String {
        let times = kept.sorted()
        let keep = "Keep your alarms at \(list(times))?"
        guard let found, found.hasAlarm, let up = found.wakeTime ?? found.alarmTimes.last,
              let first = times.first, (found.firstAlarm ?? up) < first else { return keep }
        let what: String
        switch found.source {
        case .shift: what = "Your \(found.cause) shift"
        case .appointment: what = found.appointment?.title ?? "A wake-up event"
        default: what = "Your calendar"
        }
        return "\(what) needs you up at \(WakePlanner.format(up)). Keep your alarms at \(WakePlanner.format(times.last ?? first))?"
    }

    /// "9:40", "9:40 and 10:00", "9:40, 9:50 and 10:00"
    static func list(_ times: [Date]) -> String {
        let text = times.map(WakePlanner.format)
        guard text.count > 1 else { return text.first ?? "" }
        return text.dropLast().joined(separator: ", ") + " and " + text.last!
    }
}

extension BedtimeCoordinator {
    /// Home Assistant sent RUN_BEDTIME in the last 15 minutes, so this run of the bedtime
    /// shortcut came from the push and nobody is there to answer. Unknown counts as by hand.
    func bedtimeByPush(settings: BridgeSettings) async -> Bool {
        guard let link = HomeAssistantLinks.current(settings.applying(HomeAssistantLinks.cachedSettings)) as? IntegrationLink,
              let reply = try? await link.reply(.health, data: [:]) else { return false }
        return reply["bedtime_by_push"] as? Bool == true
    }
}
