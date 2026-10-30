import UserNotifications

/// How loud a notification is (Settings → Notifications). Critical only for the ones Home
/// Assistant sends: its app has Critical Alerts permission; this app would need Apple's approval.
enum NotificationLevel: String, Codable, CaseIterable, Identifiable {
    case normal
    case timeSensitive = "time_sensitive"
    case critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .timeSensitive: "Time-sensitive"
        case .critical: "Critical"
        }
    }

    var interruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .normal: .active
        case .timeSensitive: .timeSensitive
        case .critical: .critical
        }
    }
}

/// Every notification you get, who sends it, and its level by default. Home Assistant's keys are
/// the notification tags the integration uses.
enum NotificationKind: String, CaseIterable, Identifiable {
    // From the app
    case leaveReminder, planChanged, napControl, missingLocation
    // From Home Assistant
    case windDownWarning = "wind_down_warning"
    case tomorrow = "wind_down_tomorrow"
    case goToBed = "wind_down_bed"
    case stillUp = "wind_down_reminder"
    case bedtimeMoved = "wind_down_moved"
    case plugIn = "charge"
    case appExpiry = "app_expiry"
    case weekly
    /// A leave check worked out in Home Assistant (drive times there, 0.4.4).
    case leaveCheck = "leave_check"

    var id: String { rawValue }

    var fromHomeAssistant: Bool {
        switch self {
        case .leaveReminder, .planChanged, .napControl, .missingLocation: false
        default: true
        }
    }

    var title: String {
        switch self {
        case .leaveReminder: "Leave-by reminders"
        case .planChanged: "Tomorrow changed"
        case .napControl: "Nap won't fit (Nap control)"
        case .missingLocation: "Appointment has no location"
        case .windDownWarning: "Wind-down soon"
        case .tomorrow: "Tomorrow's first alarm (event or moved)"
        case .goToBed: "Time for bed"
        case .stillUp: "Still up"
        case .bedtimeMoved: "New bedtime"
        case .plugIn: "Plug in your phone"
        case .appExpiry: "Reinstall the app"
        case .weekly: "Your week"
        case .leaveCheck: "Leave by (checked by Home Assistant)"
        }
    }

    var defaultLevel: NotificationLevel {
        switch self {
        case .goToBed: .critical
        case .leaveReminder, .planChanged, .napControl, .stillUp, .plugIn, .leaveCheck: .timeSensitive
        default: .normal
        }
    }

    /// The levels it can have: Critical only from Home Assistant.
    var levels: [NotificationLevel] { fromHomeAssistant ? NotificationLevel.allCases : [.normal, .timeSensitive] }

    func level(_ settings: BridgeSettings) -> NotificationLevel {
        let chosen = settings.notificationLevels[rawValue].flatMap(NotificationLevel.init(rawValue:)) ?? defaultLevel
        return levels.contains(chosen) ? chosen : defaultLevel
    }

    /// For the app's own notifications, read where SettingsStore isn't at hand.
    var interruptionLevel: UNNotificationInterruptionLevel {
        let saved = (UserDefaults.standard.dictionary(forKey: Self.savedKey) as? [String: String])?[rawValue]
        let chosen = saved.flatMap(NotificationLevel.init(rawValue:)) ?? defaultLevel
        return (levels.contains(chosen) ? chosen : defaultLevel).interruptionLevel
    }

    static let savedKey = "notificationLevels.v1"

    /// Sent to Home Assistant with every message: the level of each one it sends.
    static func forHomeAssistant(_ settings: BridgeSettings) -> [String: String] {
        Dictionary(uniqueKeysWithValues: allCases.filter(\.fromHomeAssistant).map { ($0.rawValue, $0.level(settings).rawValue) })
    }
}
