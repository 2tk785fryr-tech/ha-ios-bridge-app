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
    /// A plan whose alarms fall on a morning you turned off becomes one with no alarms,
    /// keeping what it found so the Tonight screen can still say why.
    /// `noAlarms`: "No alarms tomorrow" (v0.4.3 item 3) rather than a skip.
    static func skipping(_ plan: WakePlan, morning skipped: Date?, noAlarms: Bool = false, calendar: Calendar = .current) -> WakePlan {
        guard let skipped, let first = plan.firstAlarm, calendar.isDate(first, inSameDayAs: skipped) else { return plan }
        let day = skipped.formatted(.dateTime.weekday(.wide))
        var off = WakePlan(source: .none, alarmTimes: [], reason: noAlarms ? "No alarms \(day) morning" : "Alarms off for \(day) morning")
        off.shift = plan.shift
        off.appointment = plan.appointment
        off.atHome = plan.atHome
        off.warnings = [noAlarms
            ? "You chose no alarms for \(day) morning (\(plan.reason), first alarm \(WakePlanner.format(first))). Plan and set alarms to set them again."
            : "You turned off alarms for \(day) morning (\(plan.reason), first alarm \(WakePlanner.format(first))). Undo on the Tonight screen."] + plan.warnings
        return off
    }

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
            guard let shift else {
                return (nil, "Shift override is \(override), but there's no shift on the calendar.")
            }
            // Rebuild from the override's rule: its timing and alarm series, not just the name.
            var (rebuilt, warning) = ShiftCandidate.make(title: shift.title, start: shift.start, rule: rule)
            rebuilt.location = shift.location
            rebuilt.latitude = shift.latitude
            rebuilt.longitude = shift.longitude
            return (rebuilt, warning)
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

    /// Are you really up? True: the bedroom door was opened (exit latch on), or the bed has been
    /// empty for over a minute (it drops out for up to ~19 s while you're in it). False: still
    /// in bed, or the bed reads unavailable. nil: neither sensor is available.
    static func isUp(latchState: String?, bedState: String?, bedUnchangedFor: TimeInterval?) -> Bool? {
        if latchState == nil && bedState == nil { return nil }
        if latchState == "on" { return true }
        if bedState == "off" { return (bedUnchangedFor ?? 0) >= 60 }
        return false
    }

    /// Looks at every forecast hour overlapping `window` (wake-up until you need to arrive).
    /// The extra time for the worst weather between waking and arriving. Each ticked
    /// condition adds its own minutes, or `extraMinutes` when it has none; when several turn
    /// up, the largest wins (snow at 30 beats wind at 10, it doesn't add to 40).
    /// `minutes["freezing"]` is the amount for rain or snow at or below `freezingAt`.
    static func weather(
        forecast: [ForecastHour],
        window: ClosedRange<Date>,
        conditions: Set<String>,
        freezingAt: Double?,
        extraMinutes: Int,
        minutes: [String: Int] = [:]
    ) -> WeatherAdjustment? {
        let precipitation: Set<String> = ["rainy", "pouring", "lightning-rainy", "snowy", "snowy-rainy", "hail"]
        var worst: WeatherAdjustment?
        for hour in forecast.sorted(by: { $0.start < $1.start }) {
            let end = hour.start.addingTimeInterval(3600)
            guard end > window.lowerBound, hour.start <= window.upperBound else { continue }
            let time = hour.start.clockTime()
            var found: [WeatherAdjustment] = []
            if conditions.contains(hour.condition) {
                found.append(WeatherAdjustment(minutes: minutes[hour.condition] ?? extraMinutes, reason: "\(hour.condition) at \(time)"))
            }
            if let freezingAt, let temperature = hour.temperature, temperature <= freezingAt, precipitation.contains(hour.condition) {
                found.append(WeatherAdjustment(minutes: minutes[Self.freezing] ?? extraMinutes, reason: "freezing \(hour.condition) at \(time)"))
            }
            for candidate in found where candidate.minutes > (worst?.minutes ?? 0) {
                worst = candidate
            }
        }
        return worst
    }

    /// The key for "rain or snow at freezing" in the per-condition minutes.
    static let freezing = "freezing"
}
