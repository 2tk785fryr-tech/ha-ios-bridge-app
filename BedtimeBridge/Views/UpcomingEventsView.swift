import EventKit
import MapKit
import SwiftUI

/// The next week of appointments, flagging the ones with no location or no "wake up" in
/// the notes, so both can be filled in (or ignored) ahead of time instead of at bedtime.
struct UpcomingEventsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var events: [UpcomingEvent] = []
    @State private var filter = Filter.needsALook
    @State private var errorMessage: String?

    static let days = 7

    private var keyword: String { store.settings.appointmentKeyword }
    private var shown: [UpcomingEvent] {
        switch filter {
        case .needsALook: events.filter(\.needsALook)
        case .ignored: events.filter(\.hasIgnores)
        case .all: events
        }
    }

    private enum Filter { case needsALook, ignored, all }

    var body: some View {
        Form {
            Group {
                Section {
                    Picker("Show", selection: $filter) {
                        Text("Needs a look").tag(Filter.needsALook)
                        Text("Ignored").tag(Filter.ignored)
                        Text("All").tag(Filter.all)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("The next week from your appointment calendars, not counting shifts. Add a location for a real drive time, and \"\(keyword)\" to the notes to plan your alarms around it. Swipe left to ignore what an event doesn't need. Ignored ones move to the Ignored tab; swipe right there to undo.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                } else if shown.isEmpty {
                    Section {
                        Text(emptyText)
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                ForEach(days, id: \.self) { day in
                    Section(Self.dayTitle(day)) {
                        ForEach(shown.filter { Calendar.current.isDate($0.event.startDate, inSameDayAs: day) }) { item in
                            NavigationLink {
                                EventEditor(item: item, keyword: keyword)
                            } label: {
                                UpcomingEventRow(item: item, keyword: keyword)
                            }
                            .swipeActions(edge: .trailing) {
                                if item.missingWakeUp {
                                    Button("No wake-up", systemImage: "bell.slash") {
                                        BedtimeCoordinator.shared.setNoWakeUpNeeded(true, occurrence: item.id)
                                        Task { await reload() }
                                    }
                                    .tint(Theme.raised)
                                }
                                if item.missingLocation, let eventID = item.event.eventIdentifier {
                                    Button("No location", systemImage: "mappin.slash") {
                                        BedtimeCoordinator.shared.setNoLocationNeeded(true, eventID: eventID)
                                        Task { await reload() }
                                    }
                                    .tint(Theme.accent)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if item.noWakeUpNeeded {
                                    Button("Undo wake-up", systemImage: "arrow.uturn.backward") {
                                        BedtimeCoordinator.shared.setNoWakeUpNeeded(false, occurrence: item.id)
                                        Task { await reload() }
                                    }
                                    .tint(Theme.raised)
                                }
                                if item.noLocationNeeded, let eventID = item.event.eventIdentifier {
                                    Button("Undo location", systemImage: "arrow.uturn.backward") {
                                        BedtimeCoordinator.shared.setNoLocationNeeded(false, eventID: eventID)
                                        Task { await reload() }
                                    }
                                    .tint(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.divider)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .navigationTitle("Upcoming events")
        // Also runs when coming back from an event, so ignores made there show up.
        .onAppear { Task { await reload() } }
        // Edits here, in Calendar, or synced from another device.
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await reload() }
        }
    }

    private var emptyText: String {
        switch filter {
        case .needsALook: "Nothing missing in the next week."
        case .ignored: "Nothing ignored in the next week."
        case .all: "No events in the next week."
        }
    }

    private var days: [Date] {
        Array(Set(shown.map { Calendar.current.startOfDay(for: $0.event.startDate) })).sorted()
    }

    private func reload() async {
        let calendar = BedtimeCoordinator.shared.calendar
        do {
            try await calendar.ensureAccess()
            events = UpcomingEvent.load(from: calendar, settings: store.settings)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "Today", "Tomorrow", "Thursday, Oct 29"
    private static func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// An upcoming appointment, what it's missing, and what you've said it doesn't need.
struct UpcomingEvent: Identifiable {
    let event: EKEvent
    let hasLocation: Bool
    let wakesUp: Bool
    /// "No location needed": shared with the bedtime plan, which then skips the fallback drive.
    let noLocationNeeded: Bool
    let noWakeUpNeeded: Bool

    /// Repeating events share an identifier, so the start time tells occurrences apart.
    var id: String { "\(event.eventIdentifier ?? "")@\(Int(event.startDate.timeIntervalSince1970))" }
    var missingLocation: Bool { !hasLocation && !noLocationNeeded }
    var missingWakeUp: Bool { !wakesUp && !noWakeUpNeeded }
    var needsALook: Bool { missingLocation || missingWakeUp }
    /// Something you said it doesn't need, and it still doesn't have.
    var hasIgnores: Bool { (noLocationNeeded && !hasLocation) || (noWakeUpNeeded && !wakesUp) }

    @MainActor
    static func load(from calendar: CalendarService, settings: BridgeSettings) -> [UpcomingEvent] {
        let now = Date.now
        let end = Calendar.current.date(byAdding: .day, value: UpcomingEventsView.days, to: now) ?? now
        let coordinator = BedtimeCoordinator.shared
        return calendar.events(from: now, to: end, calendarIDs: settings.appointmentCalendarIDs)
            .filter { WakePlanner.matchingRule(forTitle: $0.title ?? "", rules: settings.shiftRules) == nil }
            .map { event in
                let occurrence = "\(event.eventIdentifier ?? "")@\(Int(event.startDate.timeIntervalSince1970))"
                return UpcomingEvent(
                    event: event,
                    hasLocation: !(event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    wakesUp: WakePlanner.notesRequestWakeUp(event.notes, keyword: settings.appointmentKeyword),
                    noLocationNeeded: coordinator.isNoLocationNeeded(eventID: event.eventIdentifier ?? ""),
                    noWakeUpNeeded: coordinator.isNoWakeUpNeeded(occurrence: occurrence)
                )
            }
    }
}

private struct UpcomingEventRow: View {
    let item: UpcomingEvent
    let keyword: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.event.title ?? "Untitled").foregroundStyle(Theme.text)
                Spacer()
                Text(WakePlanner.format(item.event.startDate))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textMuted)
            }
            if item.hasLocation {
                Text(item.event.location ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if item.missingLocation {
                    Chip(text: "No location", systemImage: "mappin.slash", colors: Theme.warning.background, Theme.warning.text)
                } else if item.noLocationNeeded, !item.hasLocation {
                    Chip(text: "Location ignored", systemImage: "mappin.slash", colors: Theme.raised, Theme.textFaint)
                }
                if item.wakesUp {
                    Chip(text: "Wake up", systemImage: "alarm", colors: Theme.appointmentChip.background, Theme.appointmentChip.text)
                } else if item.noWakeUpNeeded {
                    Chip(text: "Wake-up ignored", systemImage: "alarm", colors: Theme.raised, Theme.textFaint)
                } else {
                    Chip(text: "No \"\(keyword)\"", systemImage: "alarm", colors: Theme.warning.background, Theme.warning.text)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct Chip: View {
    let text: String
    let systemImage: String
    let background: Color
    let foreground: Color

    init(text: String, systemImage: String, colors background: Color, _ foreground: Color) {
        self.text = text
        self.systemImage = systemImage
        self.background = background
        self.foreground = foreground
    }

    var body: some View {
        // Not a Label: inside a List row it collapses to just the icon.
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(background, in: Capsule())
        .fixedSize()
    }
}

/// Location and "wake up" for one occurrence of an event, or ignoring either.
private struct EventEditor: View {
    let item: UpcomingEvent
    let keyword: String
    @State private var noLocationNeeded: Bool
    @State private var noWakeUpNeeded: Bool
    @State private var location: String
    @State private var pickedItem: MKMapItem?
    @State private var wakeUp: Bool
    @State private var completer = AddressCompleter(resultTypes: [.address, .pointOfInterest])
    @State private var errorMessage: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var event: EKEvent { item.event }

    init(item: UpcomingEvent, keyword: String) {
        self.item = item
        self.keyword = keyword
        _noLocationNeeded = State(initialValue: item.noLocationNeeded)
        _noWakeUpNeeded = State(initialValue: item.noWakeUpNeeded)
        _location = State(initialValue: item.event.location ?? "")
        _wakeUp = State(initialValue: item.wakesUp)
    }

    private var editable: Bool { event.calendar?.allowsContentModifications ?? false }
    private var trimmedLocation: String { location.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var locationChanged: Bool { trimmedLocation != (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var wakeUpChanged: Bool { wakeUp != item.wakesUp }
    private var ignoresChanged: Bool { noLocationNeeded != item.noLocationNeeded || noWakeUpNeeded != item.noWakeUpNeeded }
    private var hasChanges: Bool { (editable && (locationChanged || wakeUpChanged)) || ignoresChanged }

    var body: some View {
        Form {
            Group {
                Section {
                    LabeledContent("When", value: event.startDate.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                    LabeledContent("Calendar", value: event.calendar?.title ?? "")
                } header: {
                    Text(event.title ?? "Untitled")
                } footer: {
                    if !editable {
                        Text("This calendar is read-only, so only the ignore switches can be changed.")
                    } else if event.hasRecurrenceRules {
                        Text("Repeating event: changes apply to this one only.")
                    }
                }

                Section {
                    Group {
                        TextField("Address or place", text: $location, axis: .vertical)
                            .textContentType(.fullStreetAddress)
                            .focused($focused)
                            .onChange(of: location) { _, text in
                                if focused {
                                    pickedItem = nil
                                    completer.query = text
                                }
                            }
                            .onChange(of: focused) { _, isFocused in
                                completer.query = isFocused ? location : ""
                            }
                        ForEach(completer.suggestions, id: \.self) { suggestion in
                            SuggestionRow(suggestion: suggestion) {
                                Task { await choose(suggestion) }
                            }
                        }
                    }
                    .disabled(!editable)
                    if trimmedLocation.isEmpty, !item.hasLocation {
                        Toggle("No location needed", isOn: $noLocationNeeded)
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Search for a place or address. \"No location needed\" stops the flag, and a \"\(keyword)\" event then gets no drive time.\(event.hasRecurrenceRules ? " It applies to every time this event repeats." : "")")
                }

                Section {
                    Toggle("Wake me up for this", isOn: $wakeUp)
                        .disabled(!editable)
                    if !wakeUp {
                        Toggle("No wake-up needed", isOn: $noWakeUpNeeded)
                    }
                } footer: {
                    Text("Waking up adds \"\(keyword)\" to the event's notes, so Bedtime Bridge plans your alarms around it; turning it off takes it back out. \"No wake-up needed\" just stops the flag for this one.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!hasChanges)
            }
        }
    }

    private func choose(_ suggestion: MKLocalSearchCompletion) async {
        focused = false
        let item = await suggestion.mapItem()
        location = item?.placeAndAddress ?? suggestion.singleLine
        pickedItem = item
        completer.query = ""
    }

    private func save() {
        let coordinator = BedtimeCoordinator.shared
        do {
            if editable, locationChanged {
                try coordinator.calendar.setLocation(trimmedLocation, mapItem: pickedItem, on: event)
                if let id = event.eventIdentifier { LocationQuestions.clear(eventID: id) }
            }
            if editable, wakeUpChanged {
                try coordinator.calendar.setWakeUp(wakeUp, keyword: keyword, on: event)
            }
            if noLocationNeeded != item.noLocationNeeded, let id = event.eventIdentifier {
                coordinator.setNoLocationNeeded(noLocationNeeded, eventID: id)
            }
            // Turning the wake-up on makes the ignore moot, so it's cleared with it.
            let ignoreWakeUp = noWakeUpNeeded && !wakeUp
            if ignoreWakeUp != item.noWakeUpNeeded {
                coordinator.setNoWakeUpNeeded(ignoreWakeUp, occurrence: item.id)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
