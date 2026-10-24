import SwiftUI

@main
struct BedtimeBridgeApp: App {
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
