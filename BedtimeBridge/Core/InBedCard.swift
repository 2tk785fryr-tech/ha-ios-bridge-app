import Foundation

/// v0.4.11 item 34: when Morning weather's no-alarm forecast is fetched again.
enum NoAlarmWeather {
    /// Kept for 30 min, while it's for the same Good morning from time and still ahead.
    static func fresh(fetched: Date, time: String, settingTime: String, forecastAt: Date, now: Date) -> Bool {
        time == settingTime && now.timeIntervalSince(fetched) < 1800 && forecastAt > now
    }

    /// The row's text: the forecast with no extra time (there's no leave-by).
    static func text(_ forecast: MorningForecast?) -> String? { forecast?.text() }
}

/// v0.4.11 item 33: Tonight's card after a bedtime that set no alarms. Pure, so it can be tested.
enum InBedCard {
    struct Content: Equatable {
        var title: String
        var lines: [String]
    }

    /// - Parameters:
    ///   - plan: the plan bedtime set (no alarms), for why.
    ///   - skipped: you turned that morning's alarms off.
    ///   - sleepIn: Home Assistant's Sleep In; nil when it couldn't be reached.
    ///   - ladderStatus: the backstops, shown only when they matter.
    static func content(bedtimeRan: Date, day: String, plan: WakePlan?, skipped: Bool, sleepIn: Bool?,
                        ladderStatus: String?, ladderReason: String?) -> Content {
        var lines = ["Bedtime ran at \(WakePlanner.format(bedtimeRan))."]
        if skipped {
            lines.append("No alarms \(day): you turned them off.")
        } else if plan?.vacationMorning == true {
            lines.append("Vacation, so no alarms \(day).")
        } else {
            lines.append("Nothing on your calendar for \(day).")
        }
        if let sleepIn { lines.append(sleepIn ? "Sleep In is on." : "Sleep In is off.") }
        switch ladderStatus {
        case "armed": lines.append("Backstops are armed.")
        case "fault": lines.append("Backstop fault: \(ladderReason ?? "unknown").")
        case "idle_uncovered": lines.append("No backstops: nothing to cover.")
        default: break
        }
        lines.append("Added something for the morning? Tap Preview plan.")
        return Content(title: "In bed · no alarms \(day)", lines: lines)
    }
}
