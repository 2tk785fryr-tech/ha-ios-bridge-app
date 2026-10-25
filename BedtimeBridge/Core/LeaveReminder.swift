import Foundation
import MapKit
import UserNotifications

/// The appointment tonight's alarm was set for, saved so the morning can recheck traffic.
struct PendingTrip: Codable, Equatable {
    var title: String
    var location: String
    var start: Date
    var arriveBy: Date
    var plannedTravelSeconds: TimeInterval
    var latitude: Double?
    var longitude: Double?

    var leaveBy: Date { arriveBy.addingTimeInterval(-plannedTravelSeconds) }
}

/// A "time to leave" notification for appointment mornings. It's set at bedtime, then
/// moved when you stop the alarm, using traffic as it looks that morning.
final class LeaveReminder {
    private static let requestID = "leave-reminder"
    private static let tripKey = "pendingTrip.v1"
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    var pendingTrip: PendingTrip? {
        get { defaults.data(forKey: Self.tripKey).flatMap { try? JSONDecoder().decode(PendingTrip.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.tripKey) }
    }

    func schedule(_ trip: PendingTrip, leadMinutes: Int, note: String? = nil) async {
        pendingTrip = trip
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        // Traffic rechecked in the morning can pull leave-by inside the lead time: say so now.
        guard trip.leaveBy > .now else { return }
        let fireAt = max(trip.leaveBy.addingTimeInterval(-Double(leadMinutes) * 60), Date.now.addingTimeInterval(5))

        let content = UNMutableNotificationContent()
        content.title = "Leave by \(WakePlanner.format(trip.leaveBy))"
        let minutes = Int((trip.plannedTravelSeconds / 60).rounded())
        content.body = [
            "\(trip.title) at \(WakePlanner.format(trip.start)), \(minutes) min drive.",
            note,
        ].compactMap { $0 }.joined(separator: " ")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireAt.timeIntervalSinceNow, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger))
    }

    func clear() {
        pendingTrip = nil
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
    }

    /// Re-asks the drive-time service now that it's morning and moves the reminder.
    func recheck(using provider: DriveTimeProvider, origin: MKMapItem, travel: TravelTimeService, leadMinutes: Int) async {
        guard var trip = pendingTrip, trip.arriveBy > .now else { return }
        let coordinates = trip.latitude.flatMap { lat in trip.longitude.map { CLLocation(latitude: lat, longitude: $0) } }
        guard let destination = try? await travel.destination(locationText: trip.location, coordinates: coordinates),
              let fresh = try? await provider.drivingTime(from: origin, to: destination, arrivingBy: trip.arriveBy) else { return }

        let change = Int(((fresh - trip.plannedTravelSeconds) / 60).rounded())
        let note: String? = switch change {
        case 3...: "Traffic is \(change) min worse than planned."
        case ...(-3): "Traffic is \(-change) min lighter than planned."
        default: nil
        }
        trip.plannedTravelSeconds = fresh
        await schedule(trip, leadMinutes: leadMinutes, note: note)
    }
}
