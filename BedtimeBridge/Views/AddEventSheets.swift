import EventKit
import MapKit
import SwiftUI

/// "Add <title>" (v0.4.7 item 6; "Add leave" in v0.4.3 item 12): first and last day → one all-day
/// event with that vacation title in the Calendar for new events, optionally travelling. The
/// confirm shows what's added.
struct AddLeaveSheet: View {
    let settings: BridgeSettings
    /// The vacation title; nil asks when there's more than one.
    var title: String? = nil
    let added: () -> Void
    @State private var chosenTitle: String = ""
    @State private var first = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
    @State private var last = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
    @State private var travelling = false
    @State private var confirming = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var service: CalendarService { BedtimeCoordinator.shared.calendar }
    private var titles: [String] { settings.leaveTitles.isEmpty ? ["Leave"] : settings.leaveTitles }

    var body: some View {
        NavigationStack {
            Form {
                if title == nil, titles.count > 1 {
                    Section {
                        Picker("Kind", selection: $chosenTitle) {
                            ForEach(titles, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                Section {
                    DatePicker("First day", selection: $first, displayedComponents: .date)
                    DatePicker("Last day", selection: $last, in: first..., displayedComponents: .date)
                } footer: {
                    Text("One all-day event titled \"\(chosenTitle)\", first day through last.")
                }
                Section {
                    Toggle("I'm travelling", isOn: $travelling)
                } footer: {
                    Text("Drives start from where you are and the weather is where you are, on these days.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Add \(title ?? (titles.count == 1 ? titles[0] : "vacation"))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { confirming = true } }
            }
            .confirmationDialog("Add this?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Add \(chosenTitle)") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(LeaveDays.describe(title: chosenTitle, first: first, last: last,
                                        calendarName: service.newEventsCalendar(settings: settings)?.title ?? "your calendar")
                     + (travelling ? ", travelling" : ""))
            }
            .onChange(of: first) { _, day in if last < day { last = day } }
            .onAppear { if chosenTitle.isEmpty { chosenTitle = title ?? titles[0] } }
            .task { try? await service.ensureAccess() }
        }
    }

    private func save() {
        do {
            _ = try service.addVacation(title: chosenTitle, first: first, last: last, travelling: travelling, settings: settings)
            added()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Edit or delete a vacation from Settings → Vacations (v0.4.7 item 6e).
struct EditVacationSheet: View {
    let vacation: Vacation
    let changed: () -> Void
    @State private var first: Date
    @State private var last: Date
    @State private var travelling: Bool
    @State private var confirmingDelete = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(vacation: Vacation, changed: @escaping () -> Void) {
        self.vacation = vacation
        self.changed = changed
        _first = State(initialValue: vacation.first)
        _last = State(initialValue: vacation.last)
        _travelling = State(initialValue: vacation.travelling)
    }

    private var service: CalendarService { BedtimeCoordinator.shared.calendar }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("First day", selection: $first, displayedComponents: .date)
                    DatePicker("Last day", selection: $last, in: first..., displayedComponents: .date)
                    Toggle("I'm travelling", isOn: $travelling)
                } footer: {
                    Text("Back early? Move the last day.")
                }
                Section {
                    Button("Delete \(vacation.title)", role: .destructive) { confirmingDelete = true }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle(vacation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { run { try service.updateVacation(id: vacation.id, first: first, last: last, travelling: travelling) } } }
            }
            .confirmationDialog("Delete \(vacation.title) \(vacation.rangeText)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { run { try service.deleteVacation(id: vacation.id) } }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: first) { _, day in if last < day { last = day } }
        }
    }

    private func run(_ change: () throws -> Void) {
        do {
            try change()
            changed()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AddWakeUpEventSheet: View {
    let settings: BridgeSettings
    let added: () -> Void
    @State private var event = NewWakeUpEvent(
        day: Calendar.current.date(byAdding: .day, value: 1, to: .now)!,
        start: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
    )
    @State private var completer = AddressCompleter()
    @State private var mapItem: MKMapItem?
    @State private var error: String?
    @FocusState private var locationFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var service: CalendarService { BedtimeCoordinator.shared.calendar }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $event.title)
                    DatePicker("Date", selection: $event.day, displayedComponents: .date)
                    DatePicker("Starts", selection: $event.start, displayedComponents: .hourAndMinute)
                    Stepper("Length: \(NapPlanner.lengthName(event.lengthMinutes))", value: $event.lengthMinutes, in: 15...600, step: 15)
                }
                Section {
                    TextField("Location (optional)", text: $event.location, axis: .vertical)
                        .focused($locationFocused)
                        .onChange(of: event.location) { _, text in
                            mapItem = nil
                            if locationFocused { completer.query = text }
                        }
                    ForEach(completer.suggestions, id: \.self) { suggestion in
                        SuggestionRow(suggestion: suggestion) {
                            Task {
                                locationFocused = false
                                let item = await suggestion.mapItem()
                                event.location = item?.singleLineAddress ?? suggestion.singleLine
                                mapItem = item
                                completer.query = ""
                            }
                        }
                    }
                } footer: {
                    Text("Saved with \"\(settings.appointmentKeyword)\" in its notes, so it always decides the wake-up. In \(service.newEventsCalendar(settings: settings)?.title ?? "your calendar").")
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Add a wake-up event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save).disabled(event.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { try? await service.ensureAccess() }
        }
    }

    private func save() {
        do {
            _ = try service.addWakeUpEvent(event, mapItem: mapItem, settings: settings)
            dismiss()
            added()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Settings → Vacations (v0.4.7 item 6; "Leave" before): the titles that make an all-day event a
/// vacation, an Add for each title, and the vacations coming up.
struct LeaveSettings: View {
    @Binding var settings: BridgeSettings
    @State private var newTitle = ""
    @State private var adding: String?
    @State private var editing: Vacation?
    @State private var coming: [Vacation] = []

    private var service: CalendarService { BedtimeCoordinator.shared.calendar }

    var body: some View {
        SettingsPage(title: "Vacations") {
            Section {
                ForEach(settings.leaveTitles, id: \.self) { Text($0) }
                    .onDelete { settings.leaveTitles.remove(atOffsets: $0) }
                HStack {
                    TextField("Add a title", text: $newTitle)
                    Button("Add") {
                        let title = newTitle.trimmingCharacters(in: .whitespaces)
                        if !title.isEmpty, !LeaveDays.isLeave(title: title, titles: settings.leaveTitles) { settings.leaveTitles.append(title) }
                        newTitle = ""
                    }
                }
            } header: {
                WithDefault(text: "Vacation titles", defaultText: settings.leaveTitles == BridgeSettings().leaveTitles ? nil : "Leave")
            } footer: {
                Text("An all-day event with one of these titles (any case) is a vacation: no shift alarms, the backstops off, Sleep In on each morning, and a reminder the evening before you're back at work. Other events during a vacation work as usual. Home Assistant's current_shift.yaml has its own list until v0.6.")
            }
            Section {
                ForEach(settings.leaveTitles.isEmpty ? ["Leave"] : settings.leaveTitles, id: \.self) { title in
                    Button("Add \(title)", systemImage: "calendar.badge.plus") { adding = title }
                }
            }
            Section {
                if coming.isEmpty {
                    Text("None in the next year.").foregroundStyle(Theme.textMuted)
                }
                ForEach(coming) { vacation in
                    Button { editing = vacation } label: {
                        LabeledContent {
                            Text(vacation.rangeText)
                        } label: {
                            Label(vacation.title, systemImage: vacation.travelling ? "airplane" : "beach.umbrella")
                        }
                    }
                    .foregroundStyle(Theme.text)
                }
            } header: {
                Text("Coming up")
            } footer: {
                Text("Tap one to move it, shorten it (back early) or delete it.")
            }
            ResetPageSection { settings.resetToDefaults(SettingsPages.leave) }
        }
        .sheet(item: Binding(get: { adding.map { TitleItem(title: $0) } }, set: { adding = $0?.title })) { item in
            AddLeaveSheet(settings: settings, title: item.title) { reload() }
        }
        .sheet(item: $editing) { vacation in EditVacationSheet(vacation: vacation) { reload() } }
        .task { try? await service.ensureAccess(); reload() }
    }

    private func reload() {
        coming = service.vacations(from: Calendar.current.startOfDay(for: .now), to: .now.addingTimeInterval(365 * 86400), settings: settings)
        Task { await BedtimeCoordinator.shared.scheduleBackToWork(settings: settings) }
    }

    private struct TitleItem: Identifiable {
        let title: String
        var id: String { title }
    }
}

/// Apple's mark and its legal page, required wherever Apple Weather data is used.
struct AppleWeatherAttribution: View {
    @State private var attribution: (markURL: URL, legalURL: URL)?

    var body: some View {
        HStack {
            if let attribution {
                AsyncImage(url: attribution.markURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(" Weather").font(.footnote)
                }
                .frame(height: 14)
                Spacer()
                Link("Data sources", destination: attribution.legalURL).font(.footnote)
            } else {
                Text(" Weather").font(.footnote).foregroundStyle(Theme.textMuted)
            }
        }
        .task { attribution = await AppleWeatherForecast.attribution() }
    }
}
