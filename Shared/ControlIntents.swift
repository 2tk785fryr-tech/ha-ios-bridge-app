import AppIntents
import Foundation

/// The Lock Screen / Control Center / Action button controls' actions (v0.4.3 item 16). They're
/// built into the widget too (controls need them there), but run in the app's process (a Live
/// Activity intent does), where the app has set these handlers.
enum ControlActions {
    /// Wind-down on (start now, within its window) or off (cancel).
    nonisolated(unsafe) static var windDown: ((Bool) async throws -> Void)?
    /// Nap with the first quick length, checked as on the nap screen.
    nonisolated(unsafe) static var napNow: (() async throws -> Void)?
    /// Opens the app at one of its own URLs (once it's in the foreground).
    nonisolated(unsafe) static var open: ((URL) async -> Void)?
}

struct WindDownControlIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Wind-Down"
    static var description = IntentDescription("Starts tonight's wind-down now (within its window), or cancels it if it's running.")
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Winding down")
    var value: Bool

    func perform() async throws -> some IntentResult {
        if NextAlarmSnapshot.load().windDownControlOpensApp == true {
            // Settings: open the app first, at the bottom bar.
            try await continueInForeground()
            await ControlActions.open?(URL(string: "bedtimebridge://action/startWindDown")!)
        } else {
            try await ControlActions.windDown?(value)
        }
        return .result()
    }
}

/// The Nap control: opens the nap screen (default), or naps straight away.
struct NapControlIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Nap"
    static var description = IntentDescription("Opens the nap screen, or naps with your first quick length if it fits before what's later today.")
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    func perform() async throws -> some IntentResult {
        if NextAlarmSnapshot.load().napControlNapsNow == true {
            try await ControlActions.napNow?()
        } else {
            try await continueInForeground()
            await ControlActions.open?(URL(string: "bedtimebridge://action/nap")!)
        }
        return .result()
    }
}

/// What the controls show, from the shared snapshot.
struct ControlState {
    static func snapshot() -> NextAlarmSnapshot { NextAlarmSnapshot.load() }
}
