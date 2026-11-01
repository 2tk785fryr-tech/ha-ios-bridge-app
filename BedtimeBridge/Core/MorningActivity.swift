import CoreLocation
import Foundation

/// The morning Live Activity's lines (v0.4.3 item 14): "Leave in 25 min · 5:45", "Drive 32
/// min · worst case 41 min", weather for the drive and for the day, and the next backstop.
enum MorningActivity {
    /// Google's pessimistic estimate with a Google key, else the longest of the services asked,
    /// else nothing (one service has no worse case to show).
    static func worstCaseMinutes(_ estimates: [DriveEstimate]) -> Int? {
        if let google = estimates.first(where: { $0.service == .googleWorst }) { return Int((google.seconds / 60).rounded()) }
        guard estimates.count > 1, let longest = estimates.map(\.seconds).max() else { return nil }
        return Int((longest / 60).rounded())
    }

    /// Home Assistant / Open-Meteo condition words, in plain English.
    static func conditionName(_ condition: String) -> String {
        switch condition {
        case "clear-night", "sunny": "Clear"
        case "partlycloudy": "Partly cloudy"
        case "cloudy": "Cloudy"
        case "fog": "Fog"
        case "rainy": "Rain"
        case "pouring": "Heavy rain"
        case "lightning", "lightning-rainy": "Storms"
        case "snowy": "Snow"
        case "snowy-rainy": "Sleet"
        case "hail": "Hail"
        case "windy", "windy-variant": "Windy"
        default: condition.capitalized
        }
    }

    static func isWet(_ condition: String) -> Bool {
        ["rainy", "pouring", "lightning-rainy", "snowy", "snowy-rainy", "hail"].contains(condition)
    }

    /// ("Rain · 58°", "Cloudy · 71°/55° · rain after 3 PM") from the hourly forecast.
    static func weatherLines(hours: [ForecastHour], leaveBy: Date, now: Date = .now, calendar: Calendar = .current) -> (drive: String?, day: String?) {
        let sorted = hours.sorted { $0.start < $1.start }
        let atLeave = sorted.last { $0.start <= leaveBy } ?? sorted.first
        let drive = atLeave.map { hour in
            conditionName(hour.condition) + (hour.temperature.map { " · \(Int($0.rounded()))°" } ?? "")
        }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let today = sorted.filter { $0.start >= calendar.startOfDay(for: now) && $0.start < end }
        guard !today.isEmpty else { return (drive, nil) }
        // The most common condition through the day.
        let counts = Dictionary(grouping: today.filter { calendar.component(.hour, from: $0.start) >= 7 }.map(\.condition), by: { $0 }).mapValues(\.count)
        let main = counts.max { $0.value < $1.value }?.key ?? today[0].condition
        var day = conditionName(main)
        let temps = today.compactMap(\.temperature)
        if let high = temps.max(), let low = temps.min() { day += " · \(Int(high.rounded()))°/\(Int(low.rounded()))°" }
        // Rain still to come once it's dry: "rain after 3 PM" (a shower now is the drive's line).
        let ahead = today.filter { $0.start > now }
        let dryAt = ahead.firstIndex { !isWet($0.condition) }
        if !isWet(main), let dryAt, let wet = ahead[dryAt...].first(where: { isWet($0.condition) }) {
            let word = conditionName(wet.condition).lowercased()
            day += " · \(word) after \(wet.start.formatted(.dateTime.hour().locale(ClockStyle.locale)))"
        }
        return (drive, day)
    }

    /// The next backstop still to come: ("Deadline", 5:10).
    static func nextBackstop(_ backstops: [String: Date], now: Date = .now) -> (name: String, at: Date)? {
        backstops.filter { $0.value > now }.min { $0.value < $1.value }.map { ($0.key.capitalized, $0.value) }
    }

    /// It ends 15 min after leave-by.
    static func endsAt(leaveBy: Date) -> Date { leaveBy.addingTimeInterval(15 * 60) }
}

extension BedtimeCoordinator {
    /// Shows or refreshes the morning Live Activity after the alarms (or once the first is
    /// stopped) on a morning with a leave-by, and ends it 15 min after leave-by, once you've
    /// left home, or when the morning changed to no alarms. Runs whenever the app does
    /// (RUN_MORNING_UPDATE, leave checks, opening it).
    func updateMorningActivity(settings phoneSettings: BridgeSettings) async {
        let settings = phoneSettings.applying(HomeAssistantLinks.cachedSettings)
        let snapshot = NextAlarmSnapshot.load()
        let now = Date.now
        let firstDone = snapshot.alarmTimes.min().map { $0 <= now } ?? false
        guard let trip = leaveReminder.pendingTrip, let leaveBy = snapshot.leaveBy ?? Optional(trip.leaveBy),
              now < MorningActivity.endsAt(leaveBy: leaveBy), firstDone || stoppedThisWakeUp else {
            await BedtimeActivities.end(.morning)
            return
        }
        let link = HomeAssistantLinks.current(settings)
        let context = await morningContext(firstAlarm: nil, settings: settings)
        if let atHome = try? await link?.context(settings: settings).atHome, atHome == false {
            // Left home: the drive has started.
            await BedtimeActivities.end(.morning)
            return
        }
        var state = BedtimeActivityAttributes.ContentState(kind: .morning, firstAlarm: snapshot.alarmTimes.min(), leaveBy: leaveBy)
        state.driveMinutes = Int((trip.plannedTravelSeconds / 60).rounded())
        if let provider = try? travel.provider(for: settings), let origin = try? await travel.origin(homeAddress: settings.homeAddress) {
            let coordinates = trip.latitude.flatMap { lat in trip.longitude.map { CLLocation(latitude: lat, longitude: $0) } }
            if let destination = try? await travel.destination(locationText: trip.location, coordinates: coordinates),
               let compared = try? await provider.compare(from: origin, to: destination, arrivingBy: trip.arriveBy) {
                state.driveMinutes = Int((compared.seconds / 60).rounded())
                state.worstCaseMinutes = MorningActivity.worstCaseMinutes(compared.estimates)
            }
        }
        if let source = weatherForecast(settings: settings, link: link), let forecast = try? await source() {
            let lines = MorningActivity.weatherLines(hours: forecast.hours, leaveBy: leaveBy, now: now)
            state.driveWeather = lines.drive
            state.dayWeather = lines.day
        }
        // Only the ladder for this morning, not the next shift's (v0.4.9 item 6).
        if context?.ladderIsFor(morning: leaveBy) ?? false, let next = MorningActivity.nextBackstop(context?.backstops ?? [:], now: now) {
            state.nextBackstopName = next.name
            state.nextBackstop = next.at
        }
        await BedtimeActivities.show(state, title: trip.title, until: MorningActivity.endsAt(leaveBy: leaveBy))
        await BedtimeActivities.reportMorningContent(state)
    }
}
