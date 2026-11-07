import SwiftUI

/// Settings → Notifications: Normal, Time-sensitive or Critical for each notification.
struct NotificationSettings: View {
    @Binding var settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "Notifications") {
            Section {
                ForEach(NotificationKind.allCases.filter(\.fromHomeAssistant)) { row($0) }
            } header: {
                Text("From Home Assistant")
            } footer: {
                Text("Critical sounds even on silent and through Focus; allow Critical Alerts for the Home Assistant app (Settings → Notifications → Home Assistant). Time-sensitive comes through Focus.")
            }
            Section {
                ForEach(NotificationKind.allCases.filter { !$0.fromHomeAssistant }) { row($0) }
            } header: {
                Text("From this app")
            } footer: {
                Text("Critical isn't offered here: Apple only allows it for this app after a separate request.")
            }
            // v0.4.11 item 63: moved from Alarms.
            Section {
                DefaultToggle(title: "Plug in your phone", isOn: $settings.chargeWarningEnabled, defaultValue: BridgeSettings().chargeWarningEnabled)
                if settings.chargeWarningEnabled {
                    DefaultStepper(value: $settings.chargeWarningThreshold, in: 5...80, step: 5, defaultValue: BridgeSettings().chargeWarningThreshold, note: { "\($0)%" }) { "Under \($0)% and not charging" }
                }
            } header: {
                Text("Plug in your phone")
            } footer: {
                Text("At bedtime (and at go to bed with wind-down on), a reminder to plug in, and once more after 10 minutes if it's still not charging.")
            }
            ResetPageSection { settings.resetToDefaults(SettingsPages.notifications) }
        }
    }

    private func row(_ kind: NotificationKind) -> some View {
        Picker(selection: Binding(
            get: { kind.level(settings) },
            set: { settings.notificationLevels[kind.rawValue] = $0 == kind.defaultLevel ? nil : $0.rawValue }
        )) {
            ForEach(kind.levels) { Text($0.title).tag($0) }
        } label: {
            WithDefault(text: kind.title, defaultText: kind.level(settings) == kind.defaultLevel ? nil : kind.defaultLevel.title.lowercased())
        }
        .info(kind.detail)
    }
}
