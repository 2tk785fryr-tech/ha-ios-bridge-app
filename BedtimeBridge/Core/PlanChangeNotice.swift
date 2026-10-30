import Foundation
import UserNotifications

/// "Tomorrow changed: Days shift deleted. Your 4:20 alarms are still set. Re-plan?" with a
/// Re-plan action that opens the preview (v0.4.3 item 4). Nothing changes until you confirm.
enum PlanChangeNotice {
    static let category = "PLAN_CHANGED"
    static let replanAction = "REPLAN"
    static let replanURL = URL(string: "bedtimebridge://replan")!
    private static let identifier = "plan-changed"

    static var notificationCategory: UNNotificationCategory {
        let replan = UNNotificationAction(identifier: replanAction, title: "Re-plan", options: [.foreground])
        return UNNotificationCategory(identifier: category, actions: [replan], intentIdentifiers: [], options: [])
    }

    static func post(_ text: String) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tomorrow changed"
        content.body = text.replacingOccurrences(of: "Tomorrow changed: ", with: "")
        content.categoryIdentifier = category
        content.sound = .default
        // Alarms that may be wrong for tomorrow: through Focus.
        content.interruptionLevel = .timeSensitive
        // One at a time: a newer change replaces the older notice.
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
