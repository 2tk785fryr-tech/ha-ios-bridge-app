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
    /// The drive time at bedtime, so a re-check can say how much worse or lighter it got.
    var bedtimeTravelSeconds: TimeInterval?
    /// When the drive was last re-checked; nil means only the bedtime figure.
    var checkedAt: Date?

    var leaveBy: Date { arriveBy.addingTimeInterval(-plannedTravelSeconds) }
}

/// "Time to leave" notifications for shift and appointment mornings (v0.4.1 item 17: one per
/// chosen reminder). Set at bedtime as a fallback; each is rescheduled with a fresh drive time
/// when you stop an alarm, open the app, or Home Assistant's RUN_LEAVE_CHECK runs Check drive
/// and remind.
final class LeaveReminder {
    private static let requestPrefix = "leave-reminder"
    private static let tripKey = "pendingTrip.v1"
    /// Scheduled notifications fire this long after each reminder time, so Home Assistant's
    /// RUN_LEAVE_CHECK (on time, with a fresh drive) gets there first and replaces them.
    static let fallbackDelay: TimeInterval = 120
    /// No reminders or re-checks this long after leave-by.
    static let tail: TimeInterval = 15 * 60
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    var pendingTrip: PendingTrip? {
        get { defaults.data(forKey: Self.tripKey).flatMap { try? JSONDecoder().decode(PendingTrip.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.tripKey) }
    }

    /// Each reminder still ahead: minutes before leave-by, and when it's due.
    static func dueTimes(leaveBy: Date, offsets: [Int], now: Date = .now) -> [(minutes: Int, due: Date)] {
        Set(offsets).sorted(by: >).compactMap { minutes in
            let due = leaveBy.addingTimeInterval(-Double(minutes) * 60)
            return due > now ? (minutes, due) : nil
        }
    }

    /// "Leave by 5:48 · 32 min drive (5 min worse than planned)", or "Leave now · …" once leave-by
    /// is within a minute.
    static func message(leaveBy: Date, travelSeconds: TimeInterval, bedtimeSeconds: TimeInterval?, now: Date = .now) -> String {
        let minutes = Int((travelSeconds / 60).rounded())
        let head = leaveBy <= now.addingTimeInterval(60) ? "Leave now" : "Leave by \(WakePlanner.format(leaveBy))"
        var text = "\(head) · \(minutes) min drive"
        if let bedtimeSeconds {
            let change = Int(((travelSeconds - bedtimeSeconds) / 60).rounded())
            if change >= 3 { text += " (\(change) min worse than planned)" }
            if change <= -3 { text += " (\(-change) min lighter than planned)" }
        }
        return text
    }

    /// The fallback notifications, one per reminder still ahead, with the trip's current figures.
    func schedule(_ trip: PendingTrip, offsets: [Int]) async {
        var trip = trip
        if trip.bedtimeTravelSeconds == nil { trip.bedtimeTravelSeconds = trip.plannedTravelSeconds }
        pendingTrip = trip
        await removePending()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let checked = trip.checkedAt.map { "Drive checked at \(WakePlanner.format($0)); not re-checked since." } ?? "Not re-checked."
        for (minutes, due) in Self.dueTimes(leaveBy: trip.leaveBy, offsets: offsets) {
            let content = UNMutableNotificationContent()
            content.title = Self.message(leaveBy: trip.leaveBy, travelSeconds: trip.plannedTravelSeconds, bedtimeSeconds: trip.bedtimeTravelSeconds, now: due)
            content.body = "\(trip.title) at \(WakePlanner.format(trip.start)). \(checked)"
            content.sound = .default
            // Through Focus (paid team, since 29 Oct 2026): leaving late is what this prevents.
            content.interruptionLevel = NotificationKind.leaveReminder.interruptionLevel
            let fireAt = max(due.addingTimeInterval(Self.fallbackDelay), Date.now.addingTimeInterval(5))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireAt.timeIntervalSinceNow, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(Self.requestPrefix)-\(minutes)", content: content, trigger: trigger))
        }
    }

    func clear() {
        pendingTrip = nil
        Task { await removePending() }
    }

    private func removePending() async {
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.requestPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Re-asks the drive-time service and moves the reminders still ahead. With `notify` (Check
    /// drive and remind), also notifies now and drops the fallback for the reminder that's due.
    /// Returns the updated trip, or nil when there's nothing to check.
    @discardableResult
    func recheck(using provider: DriveTimeProvider, origin: MKMapItem, travel: TravelTimeService, offsets: [Int], notify: Bool = false) async -> PendingTrip? {
        guard var trip = pendingTrip, Date.now < trip.leaveBy.addingTimeInterval(Self.tail) else { return nil }
        let coordinates = trip.latitude.flatMap { lat in trip.longitude.map { CLLocation(latitude: lat, longitude: $0) } }
        if let destination = try? await travel.destination(locationText: trip.location, coordinates: coordinates),
           let fresh = try? await provider.drivingTime(from: origin, to: destination, arrivingBy: trip.arriveBy) {
            if trip.bedtimeTravelSeconds == nil { trip.bedtimeTravelSeconds = trip.plannedTravelSeconds }
            trip.plannedTravelSeconds = fresh
            trip.checkedAt = .now
        } else if !notify {
            return nil
        }
        // A reminder due within the fallback delay is the one this check stands in for.
        let ahead = Self.dueTimes(leaveBy: trip.leaveBy, offsets: offsets, now: Date.now.addingTimeInterval(Self.fallbackDelay)).map(\.minutes)
        await schedule(trip, offsets: ahead)
        if notify {
            let content = UNMutableNotificationContent()
            content.title = Self.message(leaveBy: trip.leaveBy, travelSeconds: trip.plannedTravelSeconds, bedtimeSeconds: trip.bedtimeTravelSeconds)
            content.body = "\(trip.title) at \(WakePlanner.format(trip.start))." + (trip.checkedAt == nil ? " Couldn't re-check the drive." : "")
            content.sound = .default
            content.interruptionLevel = NotificationKind.leaveReminder.interruptionLevel
            try? await center.add(UNNotificationRequest(identifier: "leave-check-now", content: content, trigger: nil))
        }
        return trip
    }
}
