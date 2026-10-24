import Foundation

struct ForecastHour: Equatable {
    var start: Date
    var condition: String
    var temperature: Double?
}

/// Extra time added to the morning because of the forecast.
struct WeatherAdjustment: Equatable {
    var minutes: Int
    /// e.g. "pouring at 6 AM"
    var reason: String
}

/// Pure rules for the Home Assistant inputs, kept apart from the network code so they
/// can be unit tested.
enum PlanAdjustments {
    /// Applies `input_select.select_shift_override`:
    /// "Auto" (or unknown) leaves the calendar alone, "Off" drops the work alarm, and a
    /// shift name ("Days", "Swings") swaps in that shift's rule for the calendar shift.
    static func applyShiftOverride(
        _ override: String?,
        to shift: ShiftCandidate?,
        rules: [ShiftRule]
    ) -> (shift: ShiftCandidate?, warning: String?) {
        guard let override = override?.trimmingCharacters(in: .whitespaces), !override.isEmpty else { return (shift, nil) }
        switch override.lowercased() {
        case "auto", "unknown", "unavailable":
            return (shift, nil)
        case "off":
            return (nil, shift.map { _ in "Shift override is Off, so no work alarm." })
        default:
            guard let rule = rules.first(where: { $0.keyword.caseInsensitiveCompare(override) == .orderedSame }) else {
                return (shift, "Shift override \"\(override)\" doesn't match a shift type in Settings; ignored.")
            }
            guard var shift else {
                return (nil, "Shift override is \(override), but there's no shift on the calendar.")
            }
            shift.cause = rule.keyword
            shift.wakeMinutesBefore = rule.wakeMinutesBefore
            return (shift, nil)
        }
    }

    /// Warns when Home Assistant's idea of the next shift disagrees with the calendar
    /// (for example leave that HA knows about but the calendar event wasn't removed for).
    static func shiftMismatchWarning(calendarShift: ShiftCandidate?, haNextShiftStart: Date?, lookAheadEnd: Date) -> String? {
        let haInWindow = haNextShiftStart.flatMap { $0 <= lookAheadEnd ? $0 : nil }
        switch (calendarShift, haInWindow) {
        case let (shift?, ha?) where abs(shift.start.timeIntervalSince(ha)) > 60:
            return "Home Assistant has the next shift at \(WakePlanner.format(ha)), the calendar says \(WakePlanner.format(shift.start))."
        case (_?, nil) where haNextShiftStart != nil:
            return "Home Assistant doesn't expect a shift this soon (leave?). Check before trusting this alarm."
        case (nil, let ha?):
            return "Home Assistant expects a shift at \(WakePlanner.format(ha)), but none was found on the calendar."
        default:
            return nil
        }
    }

    /// Looks at every forecast hour overlapping `window` (wake-up until you need to arrive).
    static func weather(
        forecast: [ForecastHour],
        window: ClosedRange<Date>,
        conditions: Set<String>,
        freezingAt: Double?,
        extraMinutes: Int
    ) -> WeatherAdjustment? {
        guard extraMinutes > 0 else { return nil }
        let precipitation: Set<String> = ["rainy", "pouring", "lightning-rainy", "snowy", "snowy-rainy", "hail"]
        for hour in forecast.sorted(by: { $0.start < $1.start }) {
            let end = hour.start.addingTimeInterval(3600)
            guard end > window.lowerBound, hour.start <= window.upperBound else { continue }
            let time = hour.start.formatted(date: .omitted, time: .shortened)
            if conditions.contains(hour.condition) {
                return WeatherAdjustment(minutes: extraMinutes, reason: "\(hour.condition) at \(time)")
            }
            if let freezingAt, let temperature = hour.temperature, temperature <= freezingAt, precipitation.contains(hour.condition) {
                return WeatherAdjustment(minutes: extraMinutes, reason: "freezing \(hour.condition) at \(time)")
            }
        }
        return nil
    }
}
