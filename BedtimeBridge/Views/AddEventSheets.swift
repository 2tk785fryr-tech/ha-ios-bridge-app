import EventKit
import MapKit
import SwiftUI

/// "Add leave" (v0.4.3 item 12): first and last day → one all-day event in the Calendar for
/// new events. The confirm shows what's added.
struct AddLeaveSheet: View {
    let settings: BridgeSettings
    let added: () -> Void
    @State private var first = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
    @State private var last = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
    @State private var confirming = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var service: CalendarService { BedtimeCoordinator.shared.calendar }
    private var title: String { settings.leaveTitles.first ?? "Leave" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("First day", selection: $first, displayedComponents: .date)
                    DatePicker("Last day", selection: $last, in: first..., displayedComponents: .date)
                } footer: {
                    Text("One all-day event titled \"\(title)\", first day through last.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Add leave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { confirming = true } }
            }
            .confirmationDialog("Add this?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Add leave") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(LeaveDays.describe(title: title, first: first, last: last,
                                        calendarName: service.newEventsCalendar(settings: settings)?.title ?? "your calendar"))
            }
            .onChange(of: first) { _, day in if last < day { last = day } }
            .task { try? await service.ensureAccess() }
        }
    }

    private func save() {
        do {
            _ = try service.addLeave(first: first, last: last, settings: settings)
            added()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// "Add a wake-up event" (v0.4.3 item 13): always marked with the wake-up keyword, saved to the
/// Calendar for new events; afterwards the preview opens with the new plan.
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

/// Settings → Leave: the titles that make an all-day event leave, and Add leave.
struct LeaveSettings: View {
    @Binding var settings: BridgeSettings
    @State private var newTitle = ""
    @State private var adding = false

    var body: some View {
        SettingsPage(title: "Leave") {
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
                WithDefault(text: "Leave titles", defaultText: settings.leaveTitles == BridgeSettings().leaveTitles ? nil : "Leave")
            } footer: {
                Text("An all-day event with one of these titles (any case) is leave. Other events during leave work as usual. New leave uses the first. Home Assistant's current_shift.yaml has its own list until v0.6.")
            }
            Section {
                Button("Add leave", systemImage: "calendar.badge.plus") { adding = true }
            }
            ResetPageSection { settings.resetToDefaults(SettingsPages.leave) }
        }
        .sheet(isPresented: $adding) { AddLeaveSheet(settings: settings) {} }
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
