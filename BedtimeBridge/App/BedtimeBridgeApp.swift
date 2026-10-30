import SwiftUI
import UIKit

@main
struct BedtimeBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // The controls' actions run here (v0.4.3 item 16).
        ControlActions.windDown = { on in
            try await BedtimeCoordinator.shared.windDownAction(on ? "start" : "cancel", settings: SettingsStore.shared.settings)
        }
        ControlActions.napNow = {
            await BedtimeCoordinator.shared.napNowFromControl(settings: SettingsStore.shared.settings)
        }
        ControlActions.imAwake = {
            NoAlarmMorning.dialog(await BedtimeCoordinator.shared.imAwake(settings: SettingsStore.shared.settings))
        }
        // Live Activity push tokens go to Home Assistant from launch.
        Task { @MainActor in BedtimeActivities.watchPushTokens() }
        ControlActions.open = { url in
            await MainActor.run { UIApplication.shared.open(url) }
        }
        // Navigation titles (e.g. Settings) in Sora to match the Tonight screen.
        let appearance = UINavigationBar.appearance()
        if let large = UIFont(name: "Sora-SemiBold", size: 34), let inline = UIFont(name: "Sora-SemiBold", size: 17) {
            appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
            appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(SettingsStore.shared)
                // Nightfall is a dark-only theme: a bedside app shouldn't flash white.
                .preferredColorScheme(.dark)
                .tint(Theme.accentIcon)
        }
    }
}
