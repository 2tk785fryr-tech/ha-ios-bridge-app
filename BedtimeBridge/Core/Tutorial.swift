import Foundation

/// v0.4.11 item 31: How to use Bedtime Bridge. The pages' words, order and links, and what the
/// last page's checklist ticks. Pure, so it can be tested; TutorialView draws it.
enum Tutorial {
    /// A Settings page a tutorial page can open ("Take me there").
    enum Link: String, Identifiable, Hashable {
        case shifts, alarms, appointments, remoteDays, vacations, calendars, home, driveTime, homeAssistant
        var id: String { rawValue }

        var title: String {
            switch self {
            case .shifts: "Shifts"
            case .alarms: "Alarms"
            case .appointments: "Appointments"
            case .remoteDays: "Remote days"
            case .vacations: "Vacations"
            case .calendars: "Calendars"
            case .home: "Home address"
            case .driveTime: "Drive time"
            case .homeAssistant: "Home Assistant"
            }
        }
    }

    /// The drawing on a page.
    enum Graphic: Equatable {
        case welcome, calendarWeek, shiftTitles, shiftTiming, alarmSeries, appointment, remote, vacation,
             calendars, evening, morning, homeAssistant, pairing, checklist
    }

    struct Page: Identifiable, Equatable {
        let id: Int
        let title: String
        let text: String
        var bullets: [String] = []
        let graphic: Graphic
        var links: [Link] = []
        /// The first Home Assistant page: Skip Home Assistant jumps to the last page.
        var startsHomeAssistant = false
    }

    static let pages: [Page] = [
        Page(id: 0, title: "Welcome to Bedtime Bridge",
             text: "Bedtime Bridge reads your calendar and sets your alarms each night, so you never sleep through a shift or an appointment. You set it up once, in Apple Calendar and here, and then it runs on its own.",
             graphic: .welcome),
        Page(id: 1, title: "Put your work schedule in Apple Calendar",
             text: "Everything starts in the Calendar app.",
             bullets: [
                "Add one event per shift, on the day you work, with the real start and end times.",
                "Put your workplace's address in Location, so the app can work out the drive.",
                "Repeating events are fine, and so is a work calendar you subscribe to or share.",
             ],
             graphic: .calendarWeek),
        Page(id: 2, title: "Name your shifts",
             text: "The event's title decides which shift it is. If the title contains a shift's word, it counts.",
             bullets: [
                "Capitals don't matter, and extra words are fine: \"Days\", \"days OT\" and \"Days – cover for Sam\" are all Days.",
                "\"Day\" on its own isn't \"Days\": the whole word has to be there.",
                "Each word is a shift type in Settings. Days and Swings are there to start; add your own, like Nights.",
             ],
             graphic: .shiftTitles, links: [.shifts]),
        Page(id: 3, title: "Set each shift's wake-up",
             text: "Each shift type wakes you one of two ways.",
             bullets: [
                "Before the shift starts: Days wakes you 2 hours before its start, so a 6:30 shift wakes you at 4:30.",
                "The same time every day: Swings always wakes you at 8:00, whatever time it starts.",
             ],
             graphic: .shiftTiming, links: [.shifts]),
        Page(id: 4, title: "The alarm series",
             text: "You get several alarms a few minutes apart, not just one.",
             bullets: [
                "Choose how many alarms and how far apart.",
                "Choose whether the wake-up is the last alarm (the others ring before it: 4:20, 4:25, 4:30) or the first (the others ring after it).",
                "A shift type can have its own series, or use the general one.",
             ],
             graphic: .alarmSeries, links: [.alarms]),
        Page(id: 5, title: "Appointments that need an early wake-up",
             text: "Most appointments shouldn't wake you, so an appointment only counts when its notes say so.",
             bullets: [
                "Write \"wake up\" in the event's notes, not its title. (The words are in Settings → Appointments.)",
                "Give it a location. The app works back from the start: arrive a little early, the drive with expected traffic, then your get ready time.",
                "If a shift and an appointment are on the same morning, the earlier wake-up wins.",
                "Or use Add a wake-up event in the app, which writes the notes for you.",
             ],
             graphic: .appointment, links: [.appointments]),
        Page(id: 6, title: "Working from home",
             text: "A shift worked from home gets no drive and a shorter get ready time.",
             bullets: [
                "Put Home, or your home address, in the shift's location.",
                "Or add WFH or Remote to its title: \"Days WFH\".",
             ],
             graphic: .remote, links: [.remoteDays]),
        Page(id: 7, title: "Days off and vacations",
             text: "No event means no alarm, so a normal day off needs nothing.",
             bullets: [
                "For time off, add an all-day event titled Leave (or one of your own titles) from the first day to the last.",
                "No alarms on those mornings, and the app reminds you before you're back.",
             ],
             graphic: .vacation, links: [.vacations]),
        Page(id: 8, title: "Calendars, home and drive time",
             text: "A few settings make the plan right.",
             bullets: [
                "Calendars: which calendars hold your shifts and appointments. All of them, unless you choose.",
                "Home: your address, so drives start from home and not wherever the phone is.",
                "Drive time: Apple Maps, or Google for a second opinion on traffic.",
             ],
             graphic: .calendars, links: [.calendars, .driveTime]),
        Page(id: 9, title: "Each evening",
             text: "Tonight shows what tomorrow will be.",
             bullets: [
                "Preview plan shows tomorrow's alarms without setting anything. Set alarms sets them.",
                "The bar at the bottom changes through the evening: wake up later, no alarms tomorrow, a temporary alarm, a nap.",
                "Watch for the banner about an event with no location or no wake-up, and fix it there.",
             ],
             graphic: .evening),
        Page(id: 10, title: "In the morning",
             text: "When an alarm rings:",
             bullets: [
                "Slide to stop that alarm, or slide and hold to end them all.",
                "Snooze, or I'm up early if you beat the alarms.",
                "Your morning shows the steps: wake up, get ready, leave by, and the weather.",
             ],
             graphic: .morning),
        Page(id: 11, title: "Home Assistant (optional)",
             text: "The app works on its own. With Home Assistant it does more:",
             bullets: [
                "Alarms set by themselves when you get into bed.",
                "Wind-down in the evening, and a go to bed time from your sleep goal.",
                "Backstops that escalate if you don't get up: lights, sounds, the house.",
                "A weekly summary of your nights and mornings.",
             ],
             graphic: .homeAssistant, startsHomeAssistant: true),
        Page(id: 12, title: "Pairing Home Assistant",
             text: "Three steps:",
             bullets: [
                "In Home Assistant, install Bedtime Bridge from the Marketplace (HACS before Home Assistant 2026.11).",
                "Add it under Settings → Devices & services.",
                "Pair it here, in Settings → Home Assistant.",
             ],
             graphic: .pairing, links: [.homeAssistant]),
        Page(id: 13, title: "You're set",
             text: "What's done, and what's left. Tap a line to finish it.",
             graphic: .checklist),
    ]

    static var lastIndex: Int { pages.count - 1 }

    /// Where Skip Home Assistant goes: the last page.
    static func afterSkippingHomeAssistant() -> Int { lastIndex }

    // MARK: Opening by itself

    static let seenKey = "tutorialSeen.v1"

    /// Opens once on a fresh install, never by itself on an install that already had settings.
    static func showsOnLaunch(freshInstall: Bool, seen: Bool) -> Bool { freshInstall && !seen }

    static var seen: Bool {
        get { UserDefaults.standard.bool(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    // MARK: The checklist

    struct CheckItem: Identifiable, Equatable {
        let title: String
        let done: Bool
        var optional = false
        let link: Link
        var id: String { title }
    }

    /// - Parameters:
    ///   - shiftFound: a shift in your calendars in the next week; nil without calendar access.
    ///   - paired: Home Assistant is set up.
    static func checklist(settings: BridgeSettings, shiftFound: Bool?, paired: Bool) -> [CheckItem] {
        let rules = settings.shiftRules.filter { !$0.keyword.trimmingCharacters(in: .whitespaces).isEmpty }
        return [
            CheckItem(title: shiftFound == nil ? "Allow calendar access" : "A shift in your calendar this week",
                      done: shiftFound == true, link: .calendars),
            CheckItem(title: "Shift types and their wake-ups", done: !rules.isEmpty, link: .shifts),
            CheckItem(title: "The wake-up words for appointments",
                      done: !settings.appointmentKeyword.trimmingCharacters(in: .whitespaces).isEmpty, link: .appointments),
            CheckItem(title: "Your home address", done: !settings.homeAddress.trimmingCharacters(in: .whitespaces).isEmpty, link: .home),
            CheckItem(title: "Home Assistant paired", done: paired, optional: true, link: .homeAssistant),
        ]
    }
}
