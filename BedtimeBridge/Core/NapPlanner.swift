import Foundation

/// Something later today (within 12 hours) a nap has to end before (v0.4.2 item 3).
struct NapConflict: Equatable {
    var title: String
    var start: Date
    /// Shifts and events with an address need a drive and get-ready time.
    var hasAddress: Bool
    var driveMinutes: Int = 0
    var arriveEarlyMinutes: Int = 0
    /// The nap's get-ready buffer (with an address) or the no-address buffer.
    var readyMinutes: Int

    var leaveBy: Date { start.addingTimeInterval(-Double(arriveEarlyMinutes + driveMinutes) * 60) }

    /// Shifts and events with an address: start − arrive early − drive now − get ready.
    /// No address: start − the no-address buffer.
    var latestWake: Date {
        hasAddress ? leaveBy.addingTimeInterval(-Double(readyMinutes) * 60) : start.addingTimeInterval(-Double(readyMinutes) * 60)
    }
}

/// The latest the LAST nap alarm can be, and why.
struct NapLimit: Equatable {
    enum Reason: Equatable {
        case event(NapConflict)
        case nextAlarm(Date)
    }

    var latest: Date
    var reason: Reason

    /// "Dentist at 3:00 PM, 25 min drive. Leave by 2:25, ready 30 min before, so your last nap
    /// alarm can be 1:55 at the latest"
    var text: String {
        let latestText = WakePlanner.format(latest)
        switch reason {
        case .event(let event):
            let start = event.start.formatted(.dateTime.hour().minute())
            if event.hasAddress {
                return "\(event.title) at \(start), \(event.driveMinutes) min drive. Leave by \(WakePlanner.format(event.leaveBy)), ready \(event.readyMinutes) min before, so your last nap alarm can be \(latestText) at the latest"
            }
            let before = event.readyMinutes > 0 ? ", up \(event.readyMinutes) min before" : ""
            return "\(event.title) at \(start)\(before), so your last nap alarm can be \(latestText) at the latest"
        case .nextAlarm(let alarm):
            return "Your next alarm is at \(WakePlanner.format(alarm)), so your last nap alarm can be \(latestText) at the latest"
        }
    }
}

enum NapPlanner {
    /// First alarm = now + length; the rest at the set spacing.
    static func times(now: Date, minutes: Int, count: Int, spacing: Int) -> [Date] {
        (0..<max(count, 1)).map { now.addingTimeInterval(Double(minutes + $0 * spacing) * 60) }
    }

    /// The earliest of every conflict's latest wake and the next regular alarm.
    static func limit(conflicts: [NapConflict], nextAlarm: Date?) -> NapLimit? {
        var limits = conflicts.map { NapLimit(latest: $0.latestWake, reason: .event($0)) }
        if let nextAlarm { limits.append(NapLimit(latest: nextAlarm, reason: .nextAlarm(nextAlarm))) }
        return limits.min { $0.latest < $1.latest }
    }

    static func fits(minutes: Int, now: Date, count: Int, spacing: Int, limit: NapLimit?) -> Bool {
        guard let limit, let last = times(now: now, minutes: minutes, count: count, spacing: spacing).last else { return true }
        return last <= limit.latest
    }

    /// The longest nap (whole minutes) whose last alarm is at or before the limit; nil if not
    /// even a minute fits.
    static func longest(now: Date, count: Int, spacing: Int, limit: NapLimit) -> Int? {
        let minutes = Int((limit.latest.timeIntervalSince(now) / 60).rounded(.down)) - (max(count, 1) - 1) * spacing
        return minutes >= 1 ? minutes : nil
    }

    /// "20 min", "1 hr", "1.5 hr"
    static func lengthName(_ minutes: Int) -> String {
        guard minutes >= 60, minutes % 30 == 0 else { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) hr" : String(format: "%.1f hr", hours)
    }

    /// "1:22 & 1:32", "1:22, 1:32 & 1:42"
    static func timesText(_ times: [Date]) -> String {
        let names = times.map(WakePlanner.format)
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " & " + names.last!
    }
}

/// A nap alarm set on this iPhone.
struct NapAlarm: Codable, Equatable, Identifiable {
    let id: UUID
    let time: Date
}
