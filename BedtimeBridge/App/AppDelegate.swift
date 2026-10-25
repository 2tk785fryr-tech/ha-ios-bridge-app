import UIKit
import UserNotifications

/// Handles answers to the missing-location notification, in the background when possible.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        LocationQuestions.registerCategory()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
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

    /// Show it even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
