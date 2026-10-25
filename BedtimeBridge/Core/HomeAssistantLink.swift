import Foundation

/// What the app reads from Home Assistant before planning.
struct HomeAssistantContext {
    var shiftOverride: String?
    var nextShiftStart: Date?
    /// "Days", "Swings": used for the fallback alarm when the calendar can't be read.
    var nextShiftType: String? = nil
    /// nil when Home Assistant didn't say (no presence entity set up).
    var atHome: Bool?
    /// Settings adjusted in HA (Bedtime Bridge integration only); see `BridgeSettings.applying`.
    var settings: [String: Any] = [:]
}

/// Alarm events reported to Home Assistant.
enum BridgeEvent: String {
    case planned, snoozed, stopped, cancelled, skipped, unskipped
    case leaveBy = "leave_by"
    case planFailed = "plan_failed"
    case temporarySnoozed = "temporary_snoozed"
    case temporaryStopped = "temporary_stopped"
    case bedtimeUndone = "bedtime_undone"
    case commandRan = "command_ran"
}

/// The two ways the app can talk to Home Assistant: the Bedtime Bridge integration
/// (preferred: a private webhook, entities that survive restarts, settings in HA) or a
/// long-lived token against the REST API.
protocol HomeAssistantLink {
    func context(settings: BridgeSettings) async throws -> HomeAssistantContext
    func forecast(settings: BridgeSettings) async throws -> (hours: [ForecastHour], temperatureUnit: String?)
    func report(_ event: BridgeEvent, data: [String: Any], settings: BridgeSettings) async throws
    /// Turns on the bedtime routine helper, only when you're home (if that's set).
    func startBedtime(settings: BridgeSettings) async throws -> (started: Bool, atHome: Bool)
    /// Are you really up (door opened, or bed empty a while)? nil when HA can't tell.
    func isUp(settings: BridgeSettings) async -> Bool?
    /// Anything at home needing a look (door open, lock unlocked), for bedtime away from
    /// home. nil when it can't be checked.
    func homeIssues(settings: BridgeSettings) async -> [String]?
}

/// Presence states that count as home; unknown/unavailable also count, so a glitching
/// tracker never skips your routine while you're actually in bed.
func presenceCountsAsHome(_ state: String?) -> Bool {
    guard let state else { return true }
    return ["home", "on", "unknown", "unavailable"].contains(state)
}

enum HomeAssistantLinks {
    /// Works from anywhere: the Nabu Casa cloudhook (or your external URL).
    static let webhookAccount = "homeAssistantWebhook"
    /// Home network only: the fallback when the internet is down at home.
    static let localWebhookAccount = "homeAssistantWebhookLocal"

    /// The integration if paired, otherwise the token connection, otherwise nil.
    static func current(_ settings: BridgeSettings) -> HomeAssistantLink? {
        let urls = [webhookAccount, localWebhookAccount]
            .map { KeychainStore.secret($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(URL.init(string:))
        if !urls.isEmpty {
            return IntegrationLink(webhookURLs: urls)
        }
        return HomeAssistantClient.configured(settings).map(TokenLink.init)
    }

    /// Saves the addresses from the integration's pairing link
    /// (bedtimebridge://pair?remote=…&local=…). Returns false if it isn't one.
    @discardableResult
    static func pair(with link: URL) -> Bool {
        guard let addresses = addresses(in: link) else { return false }
        KeychainStore.setSecret(addresses.remote, account: webhookAccount)
        KeychainStore.setSecret(addresses.local, account: localWebhookAccount)
        return true
    }

    /// The two addresses in a pairing link; nil if it isn't one or has neither.
    static func addresses(in link: URL) -> (remote: String, local: String)? {
        guard link.scheme == "bedtimebridge", link.host == "pair",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let remote = items.first { $0.name == "remote" }?.value ?? ""
        let local = items.first { $0.name == "local" }?.value ?? ""
        return remote.isEmpty && local.isEmpty ? nil : (remote, local)
    }

    private static let cachedSettingsKey = "homeAssistantSettings.v1"

    /// Last settings Home Assistant sent back, so snooze/stop in the morning use them
    /// without another round trip.
    static var cachedSettings: [String: Any] {
        get {
            guard let data = UserDefaults.standard.data(forKey: cachedSettingsKey) else { return [:] }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        set {
            UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: newValue), forKey: cachedSettingsKey)
        }
    }
}

// MARK: Bedtime Bridge integration

struct IntegrationLink: HomeAssistantLink {
    /// Tried in order: the anywhere address first, then the home-network one.
    let webhookURLs: [URL]
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func context(settings: BridgeSettings) async throws -> HomeAssistantContext {
        let reply = try await send("context")
        return HomeAssistantContext(
            shiftOverride: reply["shift_override"] as? String,
            nextShiftStart: (reply["next_shift_start"] as? String).flatMap(Self.parseDate),
            nextShiftType: reply["next_shift_type"] as? String,
            atHome: reply["at_home"] as? Bool,
            settings: reply["settings"] as? [String: Any] ?? [:]
        )
    }

    func isUp(settings: BridgeSettings) async -> Bool? {
        guard let reply = try? await send("up_check") else { return nil }
        return reply["up"] as? Bool
    }

    func homeIssues(settings: BridgeSettings) async -> [String]? {
        guard let reply = try? await send("home_check") else { return nil }
        return reply["issues"] as? [String]
    }

    /// The integration checks presence and turns on its bedtime helper.
    func startBedtime(settings: BridgeSettings) async throws -> (started: Bool, atHome: Bool) {
        let reply = try await send("bedtime")
        return (reply["started"] as? Bool ?? false, reply["at_home"] as? Bool ?? true)
    }

    func forecast(settings: BridgeSettings) async throws -> (hours: [ForecastHour], temperatureUnit: String?) {
        let reply = try await send("forecast")
        let hours = (reply["forecast"] as? [[String: Any]] ?? []).compactMap { entry -> ForecastHour? in
            guard let text = entry["datetime"] as? String, let start = Self.parseDate(text) else { return nil }
            return ForecastHour(start: start, condition: entry["condition"] as? String ?? "", temperature: (entry["temperature"] as? NSNumber)?.doubleValue)
        }
        return (hours, reply["temperature_unit"] as? String)
    }

    /// The integration turns on helpers and/or fires events for snooze and stop, as chosen
    /// in its options. Snooze/stop retry: a missed one means the morning routine doesn't run.
    func report(_ event: BridgeEvent, data: [String: Any], settings: BridgeSettings) async throws {
        let attempts: Int = [.snoozed, .stopped, .temporaryStopped, .skipped, .bedtimeUndone].contains(event) ? 3 : 1
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                _ = try await send(event.rawValue, data: data)
                return
            } catch {
                lastError = error
                if attempt < attempts - 1 { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// Tries each address in turn. A connection or HTTP failure moves on to the next one (off
    /// home Wi-Fi the local address can't work; with the internet down at home the Nabu Casa
    /// one can't). An error Home Assistant itself reports is final.
    private func send(_ type: String, data: [String: Any] = [:]) async throws -> [String: Any] {
        var lastError: Error = URLError(.badURL)
        for url in webhookURLs {
            do {
                return try await send(type, data: data, to: url)
            } catch let error as HomeAssistantReplyError {
                throw BridgeError.homeAssistant(200, error.message)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private struct HomeAssistantReplyError: Error { let message: String }

    private func send(_ type: String, data: [String: Any], to url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["type": type, "data": data])
        let (body, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BridgeError.homeAssistant(http.statusCode, String(decoding: body.prefix(200), as: UTF8.self))
        }
        let reply = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if let error = reply["error"] as? String {
            throw HomeAssistantReplyError(message: error)
        }
        if let settings = reply["settings"] as? [String: Any] {
            HomeAssistantLinks.cachedSettings = settings
        }
        return reply
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}

// MARK: Long-lived token (fallback)

struct TokenLink: HomeAssistantLink {
    let client: HomeAssistantClient

    func context(settings: BridgeSettings) async throws -> HomeAssistantContext {
        let override = try await client.state(of: settings.shiftOverrideEntity).state
        let sensor = try? await client.state(of: settings.shiftSensorEntity)
        let start = (sensor?.attributes["next_shift_start"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return HomeAssistantContext(
            shiftOverride: override,
            nextShiftStart: start,
            nextShiftType: sensor?.attributes["next_shift_type"] as? String,
            atHome: await isHome(settings)
        )
    }

    func startBedtime(settings: BridgeSettings) async throws -> (started: Bool, atHome: Bool) {
        let atHome = await isHome(settings)
        guard !settings.bedtimeHelper.isEmpty, atHome || !settings.homeOnly else { return (false, atHome) }
        try await client.turnOn(settings.bedtimeHelper)
        return (true, atHome)
    }

    func isUp(settings: BridgeSettings) async -> Bool? {
        let latch = settings.exitLatch.isEmpty ? nil : try? await client.state(of: settings.exitLatch)
        let bed = settings.bedSensor.isEmpty ? nil : try? await client.state(of: settings.bedSensor)
        return PlanAdjustments.isUp(
            latchState: latch?.state,
            bedState: bed?.state,
            bedUnchangedFor: bed?.lastChanged.map { Date.now.timeIntervalSince($0) }
        )
    }

    /// Token mode has no list of things to check.
    func homeIssues(settings: BridgeSettings) async -> [String]? { nil }

    private func isHome(_ settings: BridgeSettings) async -> Bool {
        guard !settings.presenceEntity.isEmpty else { return true }
        return presenceCountsAsHome(try? await client.state(of: settings.presenceEntity).state)
    }

    func forecast(settings: BridgeSettings) async throws -> (hours: [ForecastHour], temperatureUnit: String?) {
        async let hours = client.hourlyForecast(for: settings.weatherEntity)
        async let state = client.state(of: settings.weatherEntity)
        return (try await hours, try await state.attributes["temperature_unit"] as? String)
    }

    /// Without the integration the app does the work itself: turns on the helpers and
    /// writes a state-only sensor.
    func report(_ event: BridgeEvent, data: [String: Any], settings: BridgeSettings) async throws {
        let wakeHelper = event == .snoozed ? settings.snoozeHelper : event == .stopped ? settings.stopHelper : ""
        if !wakeHelper.isEmpty, await isHome(settings) || !settings.homeOnly {
            try? await client.turnOn(wakeHelper)
        }
        // Token mode has no integration to disarm, re-arm or turn the failsafe off.
        guard [.planned, .snoozed, .stopped, .cancelled].contains(event), !settings.nextAlarmSensor.isEmpty else { return }
        var attributes = data
        attributes["friendly_name"] = "Bedtime Bridge Next Alarm"
        attributes["device_class"] = "timestamp"
        attributes["icon"] = "mdi:alarm"
        attributes["last_event"] = event.rawValue
        try await client.setState(settings.nextAlarmSensor, state: data["alarm_time"] as? String ?? "unknown", attributes: attributes)
    }
}

// MARK: Payloads and settings

extension WakePlan {
    /// Short label: "Days shift", "Dentist", "Day off".
    var label: String {
        switch source {
        case .shift: "\(cause) shift"
        case .appointment: appointment?.title ?? "Appointment"
        case .manual: "Day off"
        case .none: ""
        }
    }

    /// Sent to Home Assistant: flat keys the integration stores, plus nested details.
    func homeAssistantPayload(settings: BridgeSettings) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        var body: [String: Any] = [
            "has_alarm": hasAlarm,
            "alarm_cause": cause,
            "label": label,
            "reason": reason,
            "alarm_times": alarmTimes.map { iso.string(from: $0) },
            "warnings": warnings + [getReadyShortfall(settings: settings).map {
                "Only \($0.minutes) min to get ready before leaving at \(WakePlanner.format($0.leaveBy)); you've set \(settings.getReadyMinutes)."
            }].compactMap { $0 },
            "weather_extra_minutes": weather?.minutes ?? 0,
            "alarm_style": settings.alarmStyle.rawValue,
        ]
        if let first = firstAlarm { body["alarm_time"] = iso.string(from: first) }
        if let wakeTime { body["wake_time"] = iso.string(from: wakeTime) }
        if let appointment, source == .appointment, appointment.hasLocation {
            let leaveBy = iso.string(from: appointment.leaveBy(bufferMinutes: settings.arrivalBufferMinutes))
            body["leave_by"] = leaveBy
            body["drive_minutes"] = Int((appointment.travelSeconds / 60).rounded())
            body["appointment"] = [
                "title": appointment.title,
                "start": iso.string(from: appointment.start),
                "location": appointment.location,
                "leave_by": leaveBy,
                "drive_minutes": Int((appointment.travelSeconds / 60).rounded()),
                "drive_time_estimated": appointment.usedFallbackTravel,
            ]
        }
        if let weather {
            body["weather_extra"] = ["minutes": weather.minutes, "reason": weather.reason]
        }
        if let shift {
            var shiftBody: [String: Any] = ["title": shift.title, "start": iso.string(from: shift.start)]
            if source == .shift, let commute, let leaveBy = leaveBy(settings: settings) {
                let minutes = Int((commute.travelSeconds / 60).rounded())
                body["leave_by"] = iso.string(from: leaveBy)
                body["drive_minutes"] = minutes
                shiftBody["location"] = shift.location
                shiftBody["leave_by"] = iso.string(from: leaveBy)
                shiftBody["drive_minutes"] = minutes
                shiftBody["drive_time_estimated"] = commute.fallbackReason != nil
            }
            body["shift"] = shiftBody
        }
        return body
    }
}

extension BridgeSettings {
    /// The phone's own values, sent with each plan so the integration's settings start out
    /// matching the app.
    var homeAssistantSettings: [String: Any] {
        [
            "get_ready_minutes": getReadyMinutes,
            "arrival_buffer_minutes": arrivalBufferMinutes,
            "snooze_minutes": snoozeMinutes,
            "weather_extra_minutes": weatherExtraMinutes,
            "leave_reminder_minutes": leaveReminderLeadMinutes,
            "shift_lead_minutes": Dictionary(
                shiftRules.map { ($0.keyword.trimmingCharacters(in: .whitespaces), $0.wakeMinutesBefore) },
                uniquingKeysWith: { first, _ in first }
            ),
        ]
    }

    /// Settings adjusted in Home Assistant win over the phone's for this run.
    func applying(_ remote: [String: Any]) -> BridgeSettings {
        var settings = self
        func int(_ key: String) -> Int? { (remote[key] as? NSNumber)?.intValue }
        if let value = int("get_ready_minutes") { settings.getReadyMinutes = value }
        if let value = int("arrival_buffer_minutes") { settings.arrivalBufferMinutes = value }
        if let value = int("snooze_minutes") { settings.snoozeMinutes = value }
        if let value = int("weather_extra_minutes") { settings.weatherExtraMinutes = value }
        if let value = int("leave_reminder_minutes") { settings.leaveReminderLeadMinutes = value }
        if let leads = remote["shift_lead_minutes"] as? [String: Any] {
            for index in settings.shiftRules.indices {
                let keyword = settings.shiftRules[index].keyword.trimmingCharacters(in: .whitespaces)
                if let match = leads.first(where: { $0.key.caseInsensitiveCompare(keyword) == .orderedSame }),
                   let minutes = (match.value as? NSNumber)?.intValue {
                    settings.shiftRules[index].wakeMinutesBefore = minutes
                }
            }
        }
        return settings
    }
}
