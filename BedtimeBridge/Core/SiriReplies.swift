import Foundation

/// v0.4.11 items 29 and 30: what Siri hears and says. Pure, so it can be tested.
enum SiriReplies {
    // MARK: Nap lengths (item 29)

    /// How a nap length is said: the first is its name in Siri and Shortcuts, the rest are other
    /// ways to say it. "20 minutes", "20 minute", "20 min"; "an hour", "1 hour", "one hour"…
    static func napNames(_ minutes: Int) -> [String] {
        var names: [String]
        switch minutes {
        case 30: names = ["30 minutes", "half an hour", "30 minute", "thirty minutes"]
        case 60: names = ["an hour", "1 hour", "one hour", "60 minutes"]
        case 90: names = ["an hour and a half", "1.5 hours", "one and a half hours", "90 minutes", "hour and a half"]
        default:
            if minutes > 60, minutes % 60 == 0 {
                let hours = minutes / 60
                names = ["\(hours) hours"] + (word(hours).map { ["\($0) hours"] } ?? []) + ["\(minutes) minutes"]
            } else {
                names = ["\(minutes) minutes", "\(minutes) minute"] + (word(minutes).map { ["\($0) minutes", "\($0) minute"] } ?? [])
            }
        }
        let short = NapPlanner.lengthName(minutes)
        if !names.contains(short) { names.append(short) }
        return names
    }

    /// A spoken length back to minutes: "25 minutes", "twenty minute", "half an hour", "1.5
    /// hours", "an hour and a half", "2 hr". Nil when it isn't a length.
    static func napMinutes(spoken text: String) -> Int? {
        var s = text.lowercased().replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("for ") { s.removeFirst(4) }
        if s.contains("half an hour") || s == "half hour" { return 30 }
        if s.contains("hour and a half") || s.contains("one and a half hour") || s.contains("1 and a half hour") { return 90 }
        if s == "an hour" || s == "a hour" || s == "hour" { return 60 }
        for (index, number) in words.enumerated().reversed() where s.contains(number) {
            s = s.replacingOccurrences(of: number, with: String(numbers[index]))
        }
        let pattern = #"(\d+(?:\.\d+)?)\s*(minutes?|mins?|m|hours?|hrs?|h)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let numberRange = Range(match.range(at: 1), in: s), let unitRange = Range(match.range(at: 2), in: s),
              let value = Double(s[numberRange]) else { return nil }
        let minutes = s[unitRange].hasPrefix("h") ? value * 60 : value
        let rounded = Int(minutes.rounded())
        return rounded >= 1 && rounded <= 12 * 60 ? rounded : nil
    }

    private static let words = ["one", "two", "three", "four", "five", "ten", "fifteen", "twenty", "twenty five",
                                "thirty", "forty", "forty five", "fifty", "sixty", "ninety"]
    private static let numbers = [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 45, 50, 60, 90]

    private static func word(_ number: Int) -> String? {
        numbers.firstIndex(of: number).map { words[$0] }
    }

    // MARK: Cancel (item 30a)

    /// The question before Cancel turns the alarms off; nil with nothing set.
    static func cancelQuestion(_ times: [Date]) -> String? {
        guard let first = times.min() else { return nil }
        return times.count == 1 ? "Turn off your alarm at \(WakePlanner.format(first))?"
            : "Turn off your \(times.count) alarms? The first is at \(WakePlanner.format(first))."
    }

    static let nothingToCancel = "There are no alarms set."

    // MARK: Plan (item 30b)

    /// "3 alarms set, first at 4:20 for Days." or "Nothing on your calendar for Saturday, so no
    /// alarms set." Previewing: "Tomorrow would be 3 alarms, first at 4:20 for Days. Nothing set."
    static func planReply(alarms: [Date], cause: String, set: Bool, day: String) -> String {
        guard let first = alarms.min() else {
            return set ? "Nothing on your calendar for \(day), so no alarms set." : "Nothing on your calendar for \(day), so no alarms."
        }
        let count = alarms.count == 1 ? "1 alarm" : "\(alarms.count) alarms"
        let why: String
        switch cause {
        case AlarmCause.calendar: why = " for an appointment"
        case AlarmCause.manual, AlarmCause.none, "": why = ""
        default: why = " for \(cause)"
        }
        return set ? "\(count) set, first at \(WakePlanner.format(first))\(why)."
            : "\(day) would be \(count), first at \(WakePlanner.format(first))\(why). Nothing set."
    }

    // MARK: Add a wake-up event (item 30d)

    /// "none", "skip", "no", "nowhere": no location.
    static func isNoLocation(_ answer: String) -> Bool {
        let s = answer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return s.isEmpty || ["none", "skip", "no", "nowhere", "no location", "nothing"].contains(s)
    }

    // MARK: Wake up later (item 30c)

    static let nothingToMove = "There are no alarms to move tonight. To set one, use Set alarms for a time in the app."
}
