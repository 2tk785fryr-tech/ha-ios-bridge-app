import Foundation

/// Days as the calendar has them, not 24 hours: the day the clocks go forward has 23 and the
/// day they go back 25 (v0.4.9 item 7).
extension Calendar {
    /// The same clock time the next day (11:30 PM Saturday → 11:30 PM Sunday, whatever the clocks do).
    func nextDay(after date: Date) -> Date {
        self.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
    }

    /// From the start of `day` to the start of the next.
    func dayRange(of day: Date) -> (start: Date, end: Date) {
        let start = startOfDay(for: day)
        return (start, nextDay(after: start))
    }
}
