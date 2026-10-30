import ActivityKit
import Foundation

/// Starts, updates and ends the app's own Live Activities (v0.4.3 items 5 and 14). The free
/// team can't receive Live Activity pushes, so these change only when the app runs.
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
            _ = try? Activity.request(attributes: BedtimeActivityAttributes(title: title), content: content)
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
}
