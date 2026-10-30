import SwiftUI

/// Settings → Reset (v0.4.3 item 7): four separate resets, each with a confirm screen saying
/// what it does and what it leaves alone.
struct ResetSettings: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "Reset") {
            Section {
                ForEach(ResetKind.allCases) { kind in
                    NavigationLink(kind.title) { ResetConfirm(kind: kind, settings: $settings) }
                }
            } footer: {
                Text("Each opens a confirm screen first.")
            }
        }
    }
}

enum ResetKind: String, CaseIterable, Identifiable {
    case alarms, settings, apiKeys, homeAssistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alarms: "Reset alarms and backstops to nothing set"
        case .settings: "Reset settings to defaults"
        case .apiKeys: "Clear API keys"
        case .homeAssistant: "Clear Home Assistant link"
        }
    }

    var does: [String] {
        switch self {
        case .alarms: [
            "Cancels every alarm the app set: regular, temporary, nap and test.",
            "Clears tonight's plan, a skip or your own time, a morning change, Sleep later, a nap, leave-by reminders and their notifications.",
            "Resets the widget and the alarm card.",
            "Home Assistant clears the alarm state (next alarm, times, cause, snoozing, snooze count, last morning change), the ladder's delay and weather moves, pending leave checks and phone commands, and turns the napping and winding-down helpers off.",
            "Then Home Assistant works the backstops out from the calendar alone: armed again if a covered shift is on it.",
        ]
        case .settings: [
            "Every setting you can change in the app goes back to its default: shifts, alarms, nap, wind-down, appointments, drive time, weather, calendars and the rest.",
        ]
        case .apiKeys: [
            "Removes the TomTom and Google keys from the Keychain. Drive times fall back to Apple Maps.",
        ]
        case .homeAssistant: [
            "Removes the webhook addresses and any token from the Keychain.",
        ]
        }
    }

    var leaves: [String] {
        switch self {
        case .alarms: ["Settings, API keys and the Home Assistant link.", "The shift override, Sleep In and Awake For Day.", "The calendar's backstops: a reset never turns them off."]
        case .settings: ["API keys and the Home Assistant link.", "Alarms already set.", "Nothing is sent to Home Assistant."]
        case .apiKeys: ["Settings, alarms and the Home Assistant link."]
        case .homeAssistant: ["Settings, alarms and API keys."]
        }
    }

    var warning: String? {
        switch self {
        case .homeAssistant: "Wake routines, Good Morning and the backstops stop getting events from this phone until you pair again."
        case .alarms: "Nothing will ring until you set alarms again."
        default: nil
        }
    }

    var button: String {
        switch self {
        case .alarms: "Reset alarms and backstops"
        case .settings: "Reset settings"
        case .apiKeys: "Clear API keys"
        case .homeAssistant: "Clear Home Assistant link"
        }
    }
}

private struct ResetConfirm: View {
    let kind: ResetKind
    @Binding var settings: BridgeSettings
    @State private var done: String?
    @State private var working = false

    var body: some View {
        SettingsPage(title: "Reset") {
            Section {
                ForEach(kind.does, id: \.self) { Label($0, systemImage: "arrow.counterclockwise").font(.subheadline) }
            } header: {
                Text("What it does")
            }
            Section {
                ForEach(kind.leaves, id: \.self) { Label($0, systemImage: "checkmark.shield").font(.subheadline) }
            } header: {
                Text("What it leaves alone")
            }
            if let warning = kind.warning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning.text).font(.subheadline)
                }
            }
            Section {
                if let done {
                    Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                } else if kind == .alarms {
                    // Also slide-and-hold: it turns every alarm off.
                    HoldSlider(label: "Slide and hold to reset", holdLabel: { "Resetting in \($0)…" },
                               knobSymbol: "stop.fill", tint: Theme.danger, onHold: run,
                               accessibilityHint: kind.button)
                        .frame(height: 72)
                        .disabled(working)
                        .listRowBackground(Color.clear)
                } else {
                    Button(role: .destructive, action: run) {
                        Text(kind.button)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.danger, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    private func run() {
        working = true
        Task { @MainActor in
            defer { working = false }
            switch kind {
            case .alarms:
                await BedtimeCoordinator.shared.resetAlarmsAndBackstops(settings: settings)
                done = "Alarms and backstops reset."
            case .settings:
                settings = ResetActions.defaultSettings(keeping: settings)
                done = "Settings are back to their defaults."
            case .apiKeys:
                ResetActions.clearAPIKeys()
                done = "API keys cleared. Drive times use Apple Maps."
            case .homeAssistant:
                ResetActions.clearHomeAssistantLink()
                done = "Home Assistant link cleared. Pair again from the integration."
            }
        }
    }
}

enum ResetActions {
    /// Every changeable setting at its default; the token connection's address is part of the
    /// Home Assistant link, so it stays.
    static func defaultSettings(keeping current: BridgeSettings) -> BridgeSettings {
        var reset = BridgeSettings()
        reset.homeAssistantURL = current.homeAssistantURL
        return reset
    }

    static func clearAPIKeys() {
        KeychainStore.setAPIKey("", for: .tomTom)
        KeychainStore.setAPIKey("", for: .google)
    }

    static func clearHomeAssistantLink() {
        for account in [HomeAssistantLinks.webhookAccount, HomeAssistantLinks.localWebhookAccount, KeychainStore.homeAssistantAccount] {
            KeychainStore.setSecret("", account: account)
        }
    }
}
