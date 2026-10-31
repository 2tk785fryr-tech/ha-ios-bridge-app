import Foundation

/// Settings → Shortcuts, controls and Siri → Siri phrases (v0.4.8 item 8): every phrase the app
/// answers to, grouped by what it does. Kept in step with BedtimeBridgeShortcuts (a test checks
/// there's one entry per Siri shortcut).
enum SiriPhrases {
    struct Entry: Identifiable, Equatable {
        let phrases: [String]
        let does: String
        var id: String { phrases[0] }
    }

    struct Group: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Alarms", entries: [
            Entry(phrases: ["Plan my wake up with Bedtime Bridge", "Set my Bedtime Bridge alarms"],
                  does: "Plans from your calendar and sets the alarms; keeps your own alarms if they're set."),
            Entry(phrases: ["Cancel my Bedtime Bridge alarms"], does: "Turns the alarms off."),
            Entry(phrases: ["No alarms tomorrow in Bedtime Bridge", "No Bedtime Bridge alarms tomorrow"],
                  does: "Turns the next morning's alarms off and asks about Sleep In."),
            Entry(phrases: ["Sleep later 30 minutes with Bedtime Bridge", "Sleep later with Bedtime Bridge"],
                  does: "Moves tonight's alarms later."),
        ]),
        Group(title: "Bedtime", entries: [
            Entry(phrases: ["Good night in Bedtime Bridge", "Bedtime Bridge good night"],
                  does: "Starts bedtime, after you confirm: the lights go off."),
        ]),
        Group(title: "Morning", entries: [
            Entry(phrases: ["I'm awake in Bedtime Bridge", "Good morning with Bedtime Bridge", "Bedtime Bridge I'm awake"],
                  does: "On a morning with no alarms: Sleep In off and Good Morning runs."),
        ]),
        Group(title: "Nap", entries: [
            Entry(phrases: ["Nap 20 minutes with Bedtime Bridge", "Start a Bedtime Bridge nap", "Nap with Bedtime Bridge"],
                  does: "Sets a nap's alarms."),
        ]),
        Group(title: "Wind-down", entries: [
            Entry(phrases: ["Start wind-down in Bedtime Bridge", "Cancel wind-down in Bedtime Bridge",
                            "Start winding down with Bedtime Bridge"],
                  does: "Starts tonight's wind-down now, or cancels it (after you confirm)."),
        ]),
        Group(title: "Calendar", entries: [
            Entry(phrases: ["Add a vacation in Bedtime Bridge", "Add leave in Bedtime Bridge"],
                  does: "Adds a vacation to your calendar."),
            Entry(phrases: ["Add a wake-up event in Bedtime Bridge"], does: "Adds an event that sets a wake-up."),
        ]),
    ]

    static var entries: [Entry] { groups.flatMap(\.entries) }

    /// Your own phrase: a shortcut named what you want to say, running one Bedtime Bridge action.
    static let ownPhraseSteps = [
        "Open the Shortcuts app and tap +.",
        "Add the Bedtime Bridge action you want, e.g. Good Night.",
        "Name the shortcut what you want to say, e.g. \"Let's go sleepy bye\".",
        "Say \"Hey Siri, let's go sleepy bye\".",
    ]

    static let ownPhraseNote = "Pick a name that isn't close to another shortcut's (\"I'm ready for bed\" is too close to \"I'm Ready For Bed - App\"), or Siri may ask which one you meant."
}
