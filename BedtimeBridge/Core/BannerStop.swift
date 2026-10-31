import Foundation
import UserNotifications

/// v0.4.8 item 4: Stop on the alarm's banner or Lock Screen snoozes instead of ending the
/// alarms, and the app's Stop screen (slide-and-hold) asks you to end them. The system's Stop
/// always stops the alarm it's on, so the snooze is a new alarm at the snooze time.
enum BannerStop {
    static let category = "bannerStop"
    private static let pendingKey = "bannerStop.pending"
    private static let pendingAtKey = "bannerStop.pendingAt"

    /// The alarm the Stop screen should show when the app comes to the front, for a few
    /// minutes after a banner Stop.
    static var pending: UUID? {
        get {
            guard let at = UserDefaults.standard.object(forKey: pendingAtKey) as? Date, Date.now.timeIntervalSince(at) < 10 * 60 else { return nil }
            return UserDefaults.standard.string(forKey: pendingKey).flatMap(UUID.init)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: pendingKey)
            UserDefaults.standard.set(newValue.map { _ in Date.now }, forKey: pendingAtKey)
        }
    }

    static func takePending() -> UUID? {
        defer { pending = nil }
        return pending
    }

    static func stopURL(_ id: UUID) -> URL { URL(string: "bedtimebridge://stop?id=\(id.uuidString)")! }

    /// When the app can't come to the front by itself: "Snoozed · slide to end", which opens
    /// the Stop screen.
    static func notify(id: UUID, ringsAgain: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Snoozed · slide to end"
        content.body = "Rings again at \(WakePlanner.format(ringsAgain)). Open to end the alarms with the slide-and-hold."
        content.categoryIdentifier = category
        content.userInfo = ["url": stopURL(id).absoluteString]
        content.interruptionLevel = .timeSensitive
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "banner-stop", content: content, trigger: nil))
    }

    static func clearNotification() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["banner-stop"])
    }
}
