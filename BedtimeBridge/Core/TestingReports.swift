import Foundation

/// What the app did in the last 12 hours, for testing reports (v0.4.8 item 9): each message to
/// Home Assistant and the actions that matter, nothing else.
enum ActivityLog {
    private static let key = "activityLog.v1"
    static let keep: TimeInterval = 12 * 3600

    struct Entry: Codable, Equatable {
        var time: Date
        var text: String
    }

    static var entries: [Entry] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static func add(_ text: String, now: Date = .now) {
        entries = trimmed(entries + [Entry(time: now, text: text)], now: now)
    }

    /// The last 12 hours, at most 400 lines.
    static func trimmed(_ entries: [Entry], now: Date = .now) -> [Entry] {
        Array(entries.filter { now.timeIntervalSince($0.time) < keep }.suffix(400))
    }
}

/// Report something (v0.4.8 item 9) and the reports the app files by itself (item 11). Each one
/// goes to the Bedtime Bridge integration, which saves it for Claude to read; a copy stays here
/// until it's sent.
enum TestingReports {
    private static let enabledKey = "testingReports.enabled"
    private static let storeKey = "testingReports.v1"
    private static let autoKey = "testingReports.automatic"

    /// Settings → About → Testing reports; on by default for the testing phase.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    struct Saved: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var time: Date
        var note: String
        var automatic: Bool
        var kind: String?
        /// The report as sent, JSON.
        var body: Data
        var sent: Bool
    }

    /// Kept on the phone (the last 50), sent or not.
    static var saved: [Saved] {
        get { UserDefaults.standard.data(forKey: storeKey).flatMap { try? JSONDecoder().decode([Saved].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.suffix(50))), forKey: storeKey) }
    }

    /// A night runs noon to noon, so 1 AM and 11 PM are the same night.
    static func night(_ date: Date, calendar: Calendar = .current) -> String {
        let shifted = date.addingTimeInterval(-12 * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whether an automatic report of this kind may go tonight (once per kind per night), and
    /// marks it as gone.
    static func claimAutomatic(_ kind: String, now: Date = .now) -> Bool {
        var sent = UserDefaults.standard.dictionary(forKey: autoKey) as? [String: String] ?? [:]
        let tonight = night(now)
        guard sent[kind] != tonight else { return false }
        sent[kind] = tonight
        UserDefaults.standard.set(sent, forKey: autoKey)
        return true
    }

    /// The report's body: your words, the app's snapshot, the last 12 hours and the checklist.
    static func body(note: String, automatic: Bool, kind: String?, app: [String: Any], screenshot: Data?, id: UUID? = nil, now: Date = .now) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        var body: [String: Any] = [
            "time": iso.string(from: now),
            "note": note,
            "automatic": automatic,
            "app": app,
            "activity": ActivityLog.trimmed(ActivityLog.entries, now: now).map { "\(iso.string(from: $0.time)) \($0.text)" },
            "checklist": TestingChecklist.report(),
        ]
        if let kind { body["kind"] = kind }
        // So it can be edited or deleted later (v0.4.10 item 13).
        if let id { body["report_id"] = id.uuidString }
        if let screenshot { body["screenshot"] = screenshot.base64EncodedString() }
        return body
    }

    /// Saves it here, then sends it and anything not sent yet. Returns whether this one reached
    /// Home Assistant.
    @MainActor @discardableResult
    static func send(note: String, automatic: Bool = false, kind: String? = nil, app: [String: Any],
                     screenshot: Data? = nil, settings: BridgeSettings) async -> Bool {
        let id = UUID()
        let body = body(note: note, automatic: automatic, kind: kind, app: app, screenshot: screenshot, id: id)
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        let report = Saved(id: id, time: .now, note: note, automatic: automatic, kind: kind, body: data, sent: false)
        saved.append(report)
        ActivityLog.add(automatic ? "Automatic report: \(kind ?? "")" : "Report: \(note.prefix(40))")
        await sendUnsent(settings: settings)
        return saved.first { $0.id == report.id }?.sent ?? false
    }

    /// Sends what's waiting (Home Assistant was out of reach before).
    @MainActor
    static func sendUnsent(settings: BridgeSettings) async {
        guard let link = HomeAssistantLinks.current(settings.applying(HomeAssistantLinks.cachedSettings)) as? IntegrationLink else { return }
        var all = saved
        for index in all.indices where !all[index].sent {
            guard let body = try? JSONSerialization.jsonObject(with: all[index].body) as? [String: Any],
                  let reply = try? await link.reply(.report, data: body) else { continue }
            if reply["saved"] as? Bool == true {
                all[index].sent = true
                TestingChecklist.tick(.reportSent)
            }
        }
        saved = all
    }

    /// v0.4.10 item 13: what Testing → Reports sent lists: your last 20, newest first.
    static func listed(_ all: [Saved]) -> [Saved] {
        Array(all.filter { !$0.automatic }.reversed().prefix(20))
    }

    /// The request that edits (`note` given) or deletes a report you sent: by its id, and the
    /// time it was made for reports Home Assistant saved before 0.4.10.
    static func changeRequest(for report: Saved, note: String?) -> [String: Any] {
        let time = (try? JSONSerialization.jsonObject(with: report.body) as? [String: Any])?["time"]
        var request: [String: Any] = note == nil ? ["deletes": report.id.uuidString] : ["edits": report.id.uuidString, "note": note!]
        if let time { request["time"] = time }
        return request
    }

    /// The report with a new note, in its saved body too.
    static func withNote(_ report: Saved, _ note: String) -> Saved {
        var changed = report
        changed.note = note
        if var body = try? JSONSerialization.jsonObject(with: report.body) as? [String: Any] {
            body["note"] = note
            changed.body = (try? JSONSerialization.data(withJSONObject: body)) ?? report.body
        }
        return changed
    }

    /// Edits a report you sent (v0.4.10 item 13). Not sent yet: only the copy here changes.
    /// Returns whether it's done.
    @MainActor
    static func edit(_ id: UUID, note: String, settings: BridgeSettings) async -> Bool {
        guard let report = saved.first(where: { $0.id == id }), !report.automatic else { return false }
        if report.sent {
            guard let link = HomeAssistantLinks.current(settings.applying(HomeAssistantLinks.cachedSettings)) as? IntegrationLink,
                  let reply = try? await link.reply(.report, data: changeRequest(for: report, note: note)),
                  reply["saved"] as? Bool == true else { return false }
        }
        saved = saved.map { $0.id == id ? withNote($0, note) : $0 }
        return true
    }

    /// Deletes a report you sent, here and in Home Assistant (v0.4.10 item 13).
    @MainActor
    static func delete(_ id: UUID, settings: BridgeSettings) async -> Bool {
        guard let report = saved.first(where: { $0.id == id }), !report.automatic else { return false }
        if report.sent {
            guard let link = HomeAssistantLinks.current(settings.applying(HomeAssistantLinks.cachedSettings)) as? IntegrationLink,
                  (try? await link.reply(.report, data: changeRequest(for: report, note: nil))) != nil else { return false }
        }
        saved = saved.filter { $0.id != id }
        return true
    }

    /// An automatic report (item 11), with what the app can see.
    @MainActor
    static func automatic(_ kind: String, saw: String, settings: BridgeSettings) async {
        guard enabled, claimAutomatic(kind) else { return }
        await send(note: saw, automatic: true, kind: kind, app: BedtimeCoordinator.shared.reportSnapshot(settings: settings), settings: settings)
    }
}

/// Settings → About → Testing checklist (v0.4.8 item 12): what hasn't been seen working for real
/// yet. Some tick themselves when the app sees them happen; the rest you tick.
enum TestingChecklist {
    enum Item: String, CaseIterable, Identifiable {
        case liveActivityPush, appleWeather, driveChecksInHA, widgetSizes, windDownEvening
        case leaveBedroomRearm, imAwake, weeklyWeeks
        case backupLeaveWithdrawn, backToWork, sleepInVacation, clock24InHA, twoRowBar
        case goodNightSent, bannerStopSnoozed, ownAlarmsKept, bedtimePending, reportSent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .liveActivityPush: "A Live Activity updated by Home Assistant's push"
            case .appleWeather: "Apple Weather in the morning forecast"
            case .driveChecksInHA: "A drive check done in Home Assistant"
            case .widgetSizes: "The widget in each size"
            case .windDownEvening: "Wind-down on a real evening"
            case .leaveBedroomRearm: "Leaving the bedroom, re-arm, Up for the day? (no-alarm morning)"
            case .imAwake: "I'm awake from the bar, Siri or the control"
            case .weeklyWeeks: "The weekly summary's earlier weeks"
            case .backupLeaveWithdrawn: "The backup leave reminder withdrawn by Home Assistant"
            case .backToWork: "The back-to-work reminder after a vacation"
            case .sleepInVacation: "Sleep In on a vacation morning"
            case .clock24InHA: "24-hour times in Home Assistant's notifications"
            case .twoRowBar: "The two-row bar on opening in the evening"
            case .goodNightSent: "Good night starting bedtime"
            case .bannerStopSnoozed: "Stop on the banner snoozing, then the Stop screen"
            case .ownAlarmsKept: "The bedtime shortcut keeping your own alarms"
            case .bedtimePending: "Bedtime starting after midnight (bedtime pending)"
            case .reportSent: "A testing report reaching Home Assistant"
            }
        }

        /// Ticked by the app when it sees it happen.
        var ticksItself: Bool {
            [.backupLeaveWithdrawn, .imAwake, .goodNightSent, .bannerStopSnoozed, .ownAlarmsKept, .reportSent].contains(self)
        }
    }

    private static let key = "testingChecklist.v1"

    /// When each item was seen working.
    static var ticked: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func tick(_ item: Item, now: Date = .now) {
        guard ticked[item.rawValue] == nil else { return }
        ticked[item.rawValue] = now
    }

    static func set(_ item: Item, done: Bool) {
        ticked[item.rawValue] = done ? (ticked[item.rawValue] ?? .now) : nil
    }

    /// For the reports: each item and when it was seen ("not yet" otherwise).
    static func report() -> [String: String] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        let done = ticked
        return Dictionary(uniqueKeysWithValues: Item.allCases.map { ($0.rawValue, done[$0.rawValue].map(iso.string(from:)) ?? "not yet") })
    }
}
