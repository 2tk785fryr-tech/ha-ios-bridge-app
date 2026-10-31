import SwiftUI

/// Settings → Shortcuts, controls and Siri (v0.4.3 item 16, renamed in v0.4.8 item 8): Siri
/// phrases, quick actions per moment, placing the controls, each control's options and the
/// widget's tap.
struct ShortcutsSettings: View {
    @Binding var settings: BridgeSettings
    private let d = BridgeSettings()

    var body: some View {
        SettingsPage(title: "Shortcuts, controls and Siri") {
            Section {
                NavigationLink {
                    SiriPhrasesPage()
                } label: {
                    Label("Siri phrases", systemImage: "waveform")
                }
            } footer: {
                Text("Everything you can say to Siri, and how to add your own phrase.")
            }
            ForEach(QuickActionMoment.allCases) { moment in
                Section {
                    let chosen = QuickActions.items(for: moment, settings: settings)
                    ForEach(chosen) { action in Label(action.title, systemImage: action.symbol) }
                        .onMove { from, to in update(moment) { $0.move(fromOffsets: from, toOffset: to) } }
                        .onDelete { offsets in update(moment) { $0.remove(atOffsets: offsets) } }
                    if chosen.count < 4 {
                        Menu("Add an action") {
                            ForEach(QuickAction.allCases.filter { !chosen.contains($0) }) { action in
                                Button(action.title) { update(moment) { $0.append(action) } }
                            }
                        }
                    }
                    if chosen != QuickActionMoment.defaults[moment] ?? [] {
                        Button("Reset to \((QuickActionMoment.defaults[moment] ?? []).map(\.title).joined(separator: " · "))") {
                            settings.quickActions[moment.rawValue] = nil
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("Quick actions · \(moment.title)")
                } footer: {
                    if moment == .morning { Text("Long-press the app icon. Up to 4 per moment; swipe to remove, Edit to reorder. Protected actions still need the slide-and-hold in the app.") }
                }
            }
            Section {
                Label("Lock Screen: long-press it → Customize → Lock Screen → tap a bottom button → choose Bedtime Bridge.", systemImage: "lock")
                Label("Control Center: swipe down → + → Add a Control → Bedtime Bridge.", systemImage: "switch.2")
                Label("Action button: Settings → Action Button → Controls → Bedtime Bridge.", systemImage: "button.vertical.right.press")
            } header: {
                Text("Placing the controls")
            } footer: {
                Text("Nap, Wind-down and Tonight.")
            }
            Section {
                Picker(selection: $settings.windDownControlOpensApp) {
                    Text("Act directly").tag(false)
                    Text("Open the app first").tag(true)
                } label: {
                    WithDefault(text: "Wind-down", defaultText: settings.windDownControlOpensApp == d.windDownControlOpensApp ? nil : "act directly")
                }
                Picker(selection: $settings.napControlNapsNow) {
                    Text("Open the nap screen").tag(false)
                    Text("Nap with \(NapPlanner.lengthName(settings.napLengths.first ?? 20)) now").tag(true)
                } label: {
                    WithDefault(text: "Nap", defaultText: settings.napControlNapsNow == d.napControlNapsNow ? nil : "open the nap screen")
                }
                Picker(selection: $settings.widgetTapAlwaysTonight) {
                    Text("Open what matters now").tag(false)
                    Text("Always open Tonight").tag(true)
                } label: {
                    WithDefault(text: "Next alarm widget", defaultText: settings.widgetTapAlwaysTonight == d.widgetTapAlwaysTonight ? nil : "what matters now")
                }
            } header: {
                Text("Options")
            } footer: {
                Text("Wind-down starts now within its window, or cancels if it's running. Napping straight away is still checked against what's later today; if it won't fit, a notification says why. What matters now: the stop screen while snoozing, otherwise Tonight.")
            }
            ResetPageSection { settings.resetToDefaults(SettingsPages.shortcuts) }
        }
        .toolbar { EditButton() }
    }

    private func update(_ moment: QuickActionMoment, _ change: (inout [QuickAction]) -> Void) {
        var list = QuickActions.items(for: moment, settings: settings)
        change(&list)
        settings.quickActions[moment.rawValue] = Array(list.prefix(4)).map(\.rawValue)
    }
}


/// Every phrase the app answers to (v0.4.8 item 8), and how to add your own.
struct SiriPhrasesPage: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPage(title: "Siri phrases") {
            ForEach(SiriPhrases.groups) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(entry.phrases, id: \.self) { phrase in
                                Text("\u{201C}\(phrase)\u{201D}").font(.body.weight(.semibold))
                            }
                            Text(entry.does).font(.footnote).foregroundStyle(Theme.textMuted)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section {
                ForEach(Array(SiriPhrases.ownPhraseSteps.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: "\(index + 1).circle")
                }
                Button {
                    if let url = URL(string: "shortcuts://create-shortcut") { openURL(url) }
                } label: {
                    Label("Add your own phrase", systemImage: "plus.circle")
                }
            } header: {
                Text("Your own phrase")
            } footer: {
                Text("Apple doesn't let an app's own phrases be changed; they always include \u{201C}Bedtime Bridge\u{201D}. A shortcut named what you want to say works instead. " + SiriPhrases.ownPhraseNote)
            }
        }
    }
}
