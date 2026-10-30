import ActivityKit
import Foundation

/// Starts, updates and ends the app's own Live Activities (v0.4.3 items 5 and 14). With an Apple
/// push key in the integration, Home Assistant also updates, ends and starts them by push (each
/// activity's token, and the push-to-start token, are reported to it); without one they change
/// when the app runs.
enum BedtimeActivities {
    private static func current(_ kind: BedtimeActivityAttributes.Kind) -> Activity<BedtimeActivityAttributes>? {
        Activity<BedtimeActivityAttributes>.activities.first { $0.content.state.kind == kind }
    }

    /// Shows (or updates) one activity of this kind, gone by `staleAfter` at the latest.
    static func show(_ state: BedtimeActivityAttributes.ContentState, title: String, until end: Date) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, end > .now else { return }
        let content = ActivityContent(state: state, staleDate: end)
        if let activity = current(state.kind) {
            await activity.update(content)
        } else {
            _ = try? Activity.request(attributes: BedtimeActivityAttributes(title: title), content: content, pushType: .token)
        }
    }

    static func end(_ kind: BedtimeActivityAttributes.Kind) async {
        for activity in Activity<BedtimeActivityAttributes>.activities where activity.content.state.kind == kind {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Wind-down: "Bed in 42 min · first alarm 4:20", until go to bed.
    static func syncWindDown(_ state: WindDownState) async {
        guard state.status == .windingDown, let bed = state.goToBed, bed > .now else {
            await end(.windDown)
            return
        }
        await show(.init(kind: .windDown, goToBed: bed, firstAlarm: state.firstAlarm), title: "Wind-down", until: bed)
    }

    // MARK: Push tokens for Home Assistant

    private static var watching = false

    /// From launch: the push-to-start token, and each activity's token (including ones Home
    /// Assistant started by push), sent to the integration as they arrive or change.
    @MainActor
    static func watchPushTokens() {
        guard !watching else { return }
        watching = true
        Task {
            for await data in Activity<BedtimeActivityAttributes>.pushToStartTokenUpdates {
                await report(["kind": "start", "token": hex(data)])
            }
        }
        Task {
            for activity in Activity<BedtimeActivityAttributes>.activities { watch(activity) }
            for await activity in Activity<BedtimeActivityAttributes>.activityUpdates { watch(activity) }
        }
    }

    private static func watch(_ activity: Activity<BedtimeActivityAttributes>) {
        let kind = activity.content.state.kind.rawValue
        Task {
            for await data in activity.pushTokenUpdates {
                await report(["kind": kind, "token": hex(data), "activity_id": activity.id])
            }
        }
        Task {
            for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
                await report(["kind": kind, "ended": true, "activity_id": activity.id])
            }
        }
    }

    /// The morning activity's lines Home Assistant can't work out itself (worst case drive,
    /// weather), so its pushes keep them.
    static func reportMorningContent(_ state: BedtimeActivityAttributes.ContentState) async {
        var content: [String: Any] = [:]
        if let worst = state.worstCaseMinutes { content["worst_case_minutes"] = worst }
        if let drive = state.driveMinutes { content["drive_minutes"] = drive }
        if let weather = state.driveWeather { content["drive_weather"] = weather }
        if let day = state.dayWeather { content["day_weather"] = day }
        await report(["kind": "morning", "content": content])
    }

    private static func report(_ data: [String: Any]) async {
        var data = data
        #if DEBUG
        data["environment"] = "development"
        #else
        data["environment"] = "production"
        #endif
        data["bundle_id"] = Bundle.main.bundleIdentifier
        if let team = AppExpiry.teamID { data["team_id"] = team }
        guard let link = HomeAssistantLinks.current(SettingsStore.shared.settings) as? IntegrationLink else { return }
        _ = try? await link.reply(.liveActivity, data: data)
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
