import Foundation
import UserNotifications

/// "Dentist at 9:00 AM has no location. Should it have one?" as a notification you can answer
/// from the Lock Screen (type the place, or "No location needed"), or ignore. The bedtime
/// shortcut runs with nobody tapping, so the question must never block it; until you answer,
/// the appointment keeps its fallback drive time.
enum LocationQuestions {
    static let category = "MISSING_LOCATION"
    static let addAction = "ADD_LOCATION"
    static let noneAction = "NO_LOCATION_NEEDED"
    private static let prefix = "missing-location-"

    /// Registered at launch (with the app's other categories) so the notification shows its buttons.
    static var notificationCategory: UNNotificationCategory {
        let add = UNTextInputNotificationAction(
            identifier: addAction,
            title: "Add location",
            options: [],
            textInputButtonTitle: "Save",
            textInputPlaceholder: "Address or place name"
        )
        let none = UNNotificationAction(identifier: noneAction, title: "No location needed", options: [])
        return UNNotificationCategory(identifier: category, actions: [add, none], intentIdentifiers: [], options: [])
    }

    /// Every category the app's notifications use; setting them replaces any registered before.
    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories([notificationCategory, PlanChangeNotice.notificationCategory])
    }

    static func ask(about appointments: [AppointmentCandidate]) async {
        let center = UNUserNotificationCenter.current()
        guard !appointments.isEmpty, (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        for appointment in appointments {
            guard let eventID = appointment.eventID else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(appointment.title) has no location"
            content.body = "At \(WakePlanner.format(appointment.start)). Planned with a drive to be safe. Should it have a location?"
            content.categoryIdentifier = category
            content.userInfo = ["eventID": eventID]
            content.sound = nil  // you're probably dozing off; it waits on the Lock Screen
            content.interruptionLevel = NotificationKind.missingLocation.interruptionLevel
            // Same identifier per event, so re-planning replaces rather than stacks.
            try? await center.add(UNNotificationRequest(identifier: prefix + eventID, content: content, trigger: nil))
        }
    }

    static func clear(eventID: String) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [prefix + eventID])
        center.removePendingNotificationRequests(withIdentifiers: [prefix + eventID])
    }
}
