import UIKit
import UserNotifications

/// Handles answers to the missing-location notification, in the background when possible.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        LocationQuestions.registerCategories()
        // A silent push from Home Assistant when its leave check went out (v0.4.7 item 2).
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await BedtimeActivities.sendDeviceToken(token) }
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard userInfo["bedtime_bridge"] as? String == LeaveReminder.checkedSignal else { return completionHandler(.noData) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [LeaveReminder.backupID])
        TestingChecklist.tick(.backupLeaveWithdrawn)
        completionHandler(.newData)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // "Snoozed · slide to end" (v0.4.8 item 4): the Stop screen.
        if response.notification.request.content.categoryIdentifier == BannerStop.category,
           let url = (response.notification.request.content.userInfo["url"] as? String).flatMap(URL.init(string:)) {
            await MainActor.run { UIApplication.shared.open(url) }
            return
        }
        // "Tomorrow changed … Re-plan?" (v0.4.3 item 4): opens the preview, which changes nothing
        // until you confirm.
        if response.notification.request.content.categoryIdentifier == PlanChangeNotice.category,
           response.actionIdentifier != UNNotificationDismissActionIdentifier {
            await MainActor.run { UIApplication.shared.open(PlanChangeNotice.replanURL) }
            return
        }
        guard response.notification.request.content.categoryIdentifier == LocationQuestions.category,
              let eventID = response.notification.request.content.userInfo["eventID"] as? String else { return }

        let answered = await MainActor.run { () -> Bool in
            let coordinator = BedtimeCoordinator.shared
            switch response.actionIdentifier {
            case LocationQuestions.addAction:
                let place = (response as? UNTextInputNotificationResponse)?.userText ?? ""
                return (try? coordinator.addLocation(place, eventID: eventID)) != nil
            case LocationQuestions.noneAction:
                coordinator.markNoLocationNeeded(eventID: eventID)
                return true
            default:
                return false  // tapped the notification itself: the Tonight screen asks the same question
            }
        }
        guard answered else { return }
        // Either answer changes the wake-up time (real drive, or none), so plan again.
        _ = try? await BedtimeCoordinator.shared.planAndSchedule(settings: SettingsStore.shared.settings)
    }

    /// Quick actions on the app icon (v0.4.3 item 16) arrive through this scene delegate.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }

    /// Show it even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
