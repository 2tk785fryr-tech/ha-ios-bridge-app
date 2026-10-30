import UIKit

/// Home Screen quick actions (long press on the icon), up to 4, changing with the moment
/// (v0.4.3 item 16). Each opens the app on that screen; protected actions still need the
/// slide-and-hold there.
enum QuickAction: String, CaseIterable, Codable, Identifiable {
    case nap, previewTomorrow, addWakeUpEvent, addLeave
    case sleepLater, noAlarmsTomorrow, startWindDown
    case wakeLater, upEarlyOrEnd, backToBed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nap: "Nap"
        case .previewTomorrow: "Preview tomorrow"
        case .addWakeUpEvent: "Add a wake-up event"
        case .addLeave: "Add vacation"
        case .sleepLater: "Sleep later"
        case .noAlarmsTomorrow: "No alarms tomorrow"
        case .startWindDown: "Start wind-down"
        case .wakeLater: "Wake later…"
        case .upEarlyOrEnd: "I'm up early / End alarms"
        case .backToBed: "Back to bed"
        }
    }

    var symbol: String {
        switch self {
        case .nap: "powersleep"
        case .previewTomorrow: "eye"
        case .addWakeUpEvent: "calendar.badge.plus"
        case .addLeave: "beach.umbrella"
        case .sleepLater: "clock.arrow.circlepath"
        case .noAlarmsTomorrow: "alarm.slash"
        case .startWindDown: "moon.zzz"
        case .wakeLater: "clock"
        case .upEarlyOrEnd: "sun.max"
        case .backToBed: "bed.double"
        }
    }

    /// bedtimebridge://action/<id>
    var url: URL { URL(string: "bedtimebridge://action/\(rawValue)")! }
}

enum QuickActionMoment: String, CaseIterable, Codable, Identifiable {
    case daytime, evening, morning
    var id: String { rawValue }

    var title: String {
        switch self {
        case .daytime: "Daytime"
        case .evening: "Evening with alarms set"
        case .morning: "Morning"
        }
    }

    static let defaults: [QuickActionMoment: [QuickAction]] = [
        .daytime: [.nap, .previewTomorrow, .addWakeUpEvent, .addLeave],
        .evening: [.sleepLater, .noAlarmsTomorrow, .startWindDown, .previewTomorrow],
        .morning: [.wakeLater, .upEarlyOrEnd, .backToBed],
    ]

    /// Which moment it is: the morning's windows first, then an evening with alarms set.
    static func now(_ i: BottomBar.Inputs) -> QuickActionMoment {
        if i.snoozing || i.upEarlyWindow || i.backToBedWindow { return .morning }
        if i.evening && i.alarmsSet > 0 { return .evening }
        return .daytime
    }
}

enum QuickActions {
    /// The moment's actions from Settings, at most 4.
    static func items(for moment: QuickActionMoment, settings: BridgeSettings) -> [QuickAction] {
        let chosen = settings.quickActions[moment.rawValue]?.compactMap(QuickAction.init(rawValue:)) ?? QuickActionMoment.defaults[moment] ?? []
        return Array(chosen.prefix(4))
    }

    @MainActor
    static func update(_ inputs: BottomBar.Inputs, settings: BridgeSettings) {
        let moment = QuickActionMoment.now(inputs)
        UIApplication.shared.shortcutItems = items(for: moment, settings: settings).map { action in
            UIApplicationShortcutItem(type: action.rawValue, localizedTitle: action.title, localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: action.symbol))
        }
    }
}

/// Turns a quick action into the app's own URL, which the Tonight screen handles.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem { open(item) }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        open(shortcutItem)
        completionHandler(true)
    }

    private func open(_ item: UIApplicationShortcutItem) {
        guard let action = QuickAction(rawValue: item.type) else { return }
        // A moment later, so the Tonight screen is up to receive it on a cold start.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { UIApplication.shared.open(action.url) }
    }
}
