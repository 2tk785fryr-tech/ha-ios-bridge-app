import Foundation

/// Your morning's steps for a morning with an event (a shift, or an appointment): wind-down and
/// bed, the wake-up (or each alarm once the morning is under way), get ready, the backstops,
/// Leave by and its worst case, Arrive, and the event, in time order. Pure, so it can be tested;
/// the view only draws it.
enum MorningSteps {
    enum Kind: Equatable { case windDown, goToBed, wake, alarm, getReady, backstop, leaveBy, leaveByWorst, arrive, beReady, event }

    struct Step: Equatable {
        var kind: Kind
        var title: String
        var value: String
        var detail: String? = nil
        var time: Date
        /// Already past on a morning under way (v0.4.11 item 3), or an alarm stopped or ended.
        var dimmed = false
        /// The next step still to come on a morning under way.
        var next = false
        /// Get ready flagged short of the goal.
        var short = false
    }

    /// One alarm of the morning and what happened to it (v0.4.11 item 3).
    struct AlarmMark: Equatable {
        enum State: Equatable {
            case set
            case snoozing(until: Date?)
            /// Stopped, and when if the app saw it.
            case stopped(at: Date?)
            /// Turned off without ringing (ended with the rest).
            case ended
            case notSet
        }
        var time: Date
        var isWake: Bool
        var state: State
    }

    struct Drive: Equatable {
        var travelSeconds: TimeInterval
        var estimates: [DriveEstimate] = []
        var fallbackReason: String? = nil
        var weather: WeatherAdjustment? = nil
    }

    struct Input {
        /// "Days starts", or the appointment's title.
        var eventTitle: String
        var start: Date
        var location: String
        /// Under the event's name: the location, or *Remote* (v0.4.11 item 5).
        var eventDetail: String? = nil
        /// The trip; nil for no drive (no location, or a remote day).
        var drive: Drive?
        /// Be ready's note with no drive.
        var noDriveDetail = "No location, so no drive"
        var wake: Date
        var bufferMinutes: Int
        var getReadyGoal = 0
        var rungs: [BackstopInfo.Rung] = []
        var rungsEstimate = false
        var windDown: Date? = nil
        var goToBed: Date? = nil
        /// Each alarm, once one has rung or been stopped; empty shows the one Wake up step.
        var alarms: [AlarmMark] = []
        var worstCase: WorstCase? = nil
        var now: Date = .now
    }

    /// The morning's bubbles as Your morning's alarms (v0.4.11 item 3), once one has rung or been
    /// stopped; empty before, so the timeline shows the one Wake up step. An alarm off after
    /// ringing is Stopped (at its own stop, or the stop that ended it with the rest); off before
    /// its time without ringing is Ended.
    static func marks(_ bubbles: [AlarmBubble], stops: [Date: Date], lastStop: Date?, now: Date = .now) -> [AlarmMark] {
        guard bubbles.contains(where: { $0.time <= now || $0.ring == .off }) || lastStop != nil else { return [] }
        return bubbles.map { bubble in
            let state: AlarmMark.State
            switch bubble.ring {
            case .none, .set: state = .set
            case .snoozing(let until): state = .snoozing(until: until)
            case .notSet: state = .notSet
            case .off:
                if let at = stops.first(where: { abs($0.key.timeIntervalSince(bubble.time)) < 1 })?.value {
                    state = .stopped(at: at)
                } else if let lastStop, bubble.time <= lastStop {
                    state = .stopped(at: lastStop)
                } else if bubble.time <= now && lastStop == nil {
                    state = .stopped(at: nil)
                } else {
                    state = .ended
                }
            }
            return AlarmMark(time: bubble.time, isWake: bubble.isWake, state: state)
        }
    }

    // MARK: Leave by, worst case (v0.4.11 item 1)

    struct WorstCase: Equatable {
        var time: Date
        var note: String
        var drive: String
    }

    /// The latest you can leave on a bad-traffic day: the start minus the worst-case drive (and
    /// the weather minutes), and with *Early, like Leave by* the arrival buffer too. Nil with no
    /// drive or an assumed one, when Leave by is already planned on Google's worst case, when
    /// there's no worse case (one service, no Google key), or when another service says longer
    /// than Google's worst case.
    static func worstCase(start: Date, drive: Drive?, source: DriveTimeSource, googleWorstPlanned: Bool,
                          arrival: WorstCaseArrival, bufferMinutes: Int) -> WorstCase? {
        guard let drive, drive.fallbackReason == nil, !(source == .google && googleWorstPlanned),
              let worst = MorningActivity.worstCaseMinutes(drive.estimates) else { return nil }
        let google = drive.estimates.first { $0.service == .googleWorst }
        if let google, drive.estimates.contains(where: { $0.service != .googleWorst && $0.seconds > google.seconds }) { return nil }
        let weather = drive.weather?.minutes ?? 0
        let buffer = arrival == .early ? bufferMinutes : 0
        let time = start.addingTimeInterval(-Double(worst + weather + buffer) * 60)
        let note = buffer > 0 ? "Leaving now gets you there \(buffer) min early."
                              : "Leaving now gets you there right when it starts, not early."
        let name = google != nil ? DriveEstimate.Service.googleWorst.displayName
            : drive.estimates.max { $0.seconds < $1.seconds }?.service.displayName ?? "Longest"
        let weatherNote = drive.weather.map { " + \($0.minutes) min for \($0.reason)" } ?? ""
        return WorstCase(time: time, note: note, drive: "\(name) \(worst) min" + weatherNote)
    }

    // MARK: Steps

    static func steps(_ input: Input) -> [Step] {
        let arrive = input.start.addingTimeInterval(-Double(input.bufferMinutes) * 60)
        var steps: [Step] = []
        if let windDown = input.windDown, let bed = input.goToBed {
            steps.append(Step(kind: .windDown, title: "Wind-down", value: WakePlanner.format(windDown), time: windDown))
            steps.append(Step(kind: .goToBed, title: "Go to bed", value: WakePlanner.format(bed), time: bed))
        }
        if input.alarms.isEmpty {
            steps.append(Step(kind: .wake, title: "Wake up", value: WakePlanner.format(input.wake), time: input.wake))
        } else {
            let count = input.alarms.count
            for (index, alarm) in input.alarms.sorted(by: { $0.time < $1.time }).enumerated() {
                var step = Step(kind: alarm.isWake ? .wake : .alarm, title: alarm.isWake ? "Wake up" : "Alarm \(index + 1) of \(count)",
                                value: WakePlanner.format(alarm.time), time: alarm.time)
                switch alarm.state {
                case .set: break
                case .snoozing(let until): step.detail = "Snoozing" + (until.map { " · rings \(WakePlanner.format($0))" } ?? "")
                case .stopped(let at):
                    step.detail = at.map { "Stopped \(WakePlanner.format($0))" } ?? "Stopped"
                    step.dimmed = true
                case .ended:
                    step.detail = "Ended"
                    step.dimmed = true
                case .notSet: step.detail = "Not set"
                }
                steps.append(step)
            }
        }
        let readyBy: Date
        if let drive = input.drive {
            let leaveBy = arrive.addingTimeInterval(-drive.travelSeconds)
            readyBy = leaveBy
            let ready = Int(leaveBy.timeIntervalSince(input.wake) / 60)
            steps.append(Step(kind: .getReady, title: "Get ready", value: ready >= 0 ? "\(ready) min" : "\(-ready) min short",
                              time: input.wake, short: ready < input.getReadyGoal))
            steps.append(Step(kind: .leaveBy, title: "Leave by", value: WakePlanner.format(leaveBy),
                              detail: driveDetail(drive), time: leaveBy))
            if let worst = input.worstCase {
                steps.append(Step(kind: .leaveByWorst, title: "Leave by · worst case", value: WakePlanner.format(worst.time),
                                  detail: worst.note + "\n" + worst.drive, time: worst.time))
            }
            steps.append(Step(kind: .arrive, title: "Arrive", value: "\(input.bufferMinutes) min early · \(WakePlanner.format(arrive))", time: arrive))
        } else {
            readyBy = arrive
            steps.append(Step(kind: .getReady, title: "Get ready", value: "\(Int(arrive.timeIntervalSince(input.wake) / 60)) min", time: input.wake))
            steps.append(Step(kind: .beReady, title: "Be ready", value: WakePlanner.format(arrive), detail: input.noDriveDetail, time: arrive))
        }
        steps += input.rungs.map { Step(kind: .backstop, title: $0.name, value: WakePlanner.format($0.time),
                                        detail: input.rungsEstimate ? "estimate" : nil, time: $0.time) }
        steps.append(Step(kind: .event, title: input.eventTitle, value: WakePlanner.format(input.start),
                          detail: input.eventDetail ?? input.location, time: input.start))
        steps = steps.enumerated().sorted { a, b in
            a.element.time != b.element.time ? a.element.time < b.element.time : rank(a.element.kind) < rank(b.element.kind)
        }.map(\.element)
        return marked(steps, readyBy: readyBy, now: input.now, underWay: !input.alarms.isEmpty)
    }

    /// On a morning under way, past steps dim and the next still to come is marked. Get ready
    /// lasts until Leave by (or Be ready); a snoozing alarm isn't past.
    private static func marked(_ steps: [Step], readyBy: Date, now: Date, underWay: Bool) -> [Step] {
        guard underWay else { return steps }
        var steps = steps
        for index in steps.indices {
            let step = steps[index]
            let snoozing = step.detail?.hasPrefix("Snoozing") == true
            let ends = step.kind == .getReady ? readyBy : step.time
            if ends <= now && !snoozing { steps[index].dimmed = true }
        }
        if let next = steps.firstIndex(where: { $0.kind != .getReady && $0.kind != .windDown && $0.kind != .goToBed && !$0.dimmed && $0.time > now }) {
            steps[next].next = true
        }
        return steps
    }

    /// Ties keep the usual order: the wake-up before get ready, Leave by before its worst case.
    private static func rank(_ kind: Kind) -> Int {
        switch kind {
        case .windDown: 0
        case .goToBed: 1
        case .alarm: 2
        case .wake: 3
        case .getReady: 4
        case .backstop: 5
        case .leaveBy: 6
        case .leaveByWorst: 7
        case .beReady: 8
        case .arrive: 9
        case .event: 10
        }
    }

    /// "32 min drive with expected traffic + 30 min for snowy at 5:00 AM\nApple 28 · TomTom 30 · Google 29 · Google worst case 41 min"
    static func driveDetail(_ drive: Drive) -> String {
        let minutes = Int((drive.travelSeconds / 60).rounded())
        let weatherMinutes = drive.weather?.minutes ?? 0
        let weatherNote = drive.weather.map { " + \($0.minutes) min for \($0.reason)" } ?? ""
        if let fallbackReason = drive.fallbackReason {
            return "\(minutes - weatherMinutes) min assumed: no drive time (\(fallbackReason))" + weatherNote
        }
        let line = "\(minutes - weatherMinutes) min drive with expected traffic" + weatherNote
        guard drive.estimates.count > 1 else { return line }
        let parts = drive.estimates.map { "\($0.service.displayName) \(Int(($0.seconds / 60).rounded()))" }
        return line + "\n" + parts.joined(separator: " · ") + " min"
    }

    // MARK: The saved plan's footer (v0.4.11 items 3 and 4)

    /// "As of Sun 10:42 PM · tap Preview to update", the day only when it isn't today.
    static func asOf(_ when: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = calendar.isDate(when, inSameDayAs: now) ? "" : when.formatted(.dateTime.weekday(.abbreviated)) + " "
        return "As of \(day)\(WakePlanner.format(when)) · tap Preview to update"
    }
}

/// v0.4.11 item 1: what Leave by's worst case gets you there for.
enum WorstCaseArrival: String, Codable, CaseIterable, Identifiable {
    /// Right when it starts, not early.
    case whenItStarts
    /// Early by the same arrival buffer as Leave by.
    case early

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whenItStarts: "When it starts"
        case .early: "Early, like Leave by"
        }
    }
}
