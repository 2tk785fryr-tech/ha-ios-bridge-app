import EventKit
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var calendars: [EKCalendar] = []

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                ForEach($store.settings.shiftRules) { $rule in
                    HStack {
                        TextField("Title contains", text: $rule.keyword)
                        Stepper("\(rule.wakeMinutesBefore) min", value: $rule.wakeMinutesBefore, in: 0...240, step: 5)
                            .fixedSize()
                    }
                }
                .onDelete { store.settings.shiftRules.remove(atOffsets: $0) }
                Button("Add shift type", systemImage: "plus") {
                    store.settings.shiftRules.append(ShiftRule(keyword: "", wakeMinutesBefore: 60))
                }
            } header: {
                Text("Shifts")
            } footer: {
                Text("A calendar event whose title contains the word counts as a shift. The first alarm goes off this long before it starts.")
            }

            Section {
                TextField("Notes contain", text: $store.settings.appointmentKeyword)
                Stepper("Get ready: \(store.settings.getReadyMinutes) min", value: $store.settings.getReadyMinutes, in: 0...240, step: 5)
                Stepper("If no drive time: \(store.settings.fallbackTravelMinutes) min", value: $store.settings.fallbackTravelMinutes, in: 0...180, step: 5)
                TextField("Home address (blank = current location)", text: $store.settings.homeAddress, axis: .vertical)
            } header: {
                Text("Appointments")
            } footer: {
                Text("Wake time = start − drive time (with traffic expected at that hour) − get-ready time. Only used when it's earlier than your shift alarm.")
            }

            Section("Alarms") {
                Stepper("\(store.settings.alarmCount) alarms", value: $store.settings.alarmCount, in: 1...10)
                Stepper("\(store.settings.alarmSpacingMinutes) min apart", value: $store.settings.alarmSpacingMinutes, in: 1...60)
                Stepper("Look ahead \(store.settings.lookAheadHours) h", value: $store.settings.lookAheadHours, in: 6...72)
            }

            Section("Shift calendars") {
                CalendarPicker(calendars: calendars, selection: $store.settings.shiftCalendarIDs)
            }
            Section("Appointment calendars") {
                CalendarPicker(calendars: calendars, selection: $store.settings.appointmentCalendarIDs)
            }
        }
        .navigationTitle("Settings")
        .task {
            let service = BedtimeCoordinator.shared.calendar
            try? await service.ensureAccess()
            calendars = service.eventCalendars()
        }
    }
}

/// Nothing ticked means every calendar is searched.
private struct CalendarPicker: View {
    let calendars: [EKCalendar]
    @Binding var selection: Set<String>

    var body: some View {
        if calendars.isEmpty {
            Text("Allow calendar access to choose calendars.").foregroundStyle(.secondary)
        }
        ForEach(calendars, id: \.calendarIdentifier) { calendar in
            Button {
                if selection.contains(calendar.calendarIdentifier) {
                    selection.remove(calendar.calendarIdentifier)
                } else {
                    selection.insert(calendar.calendarIdentifier)
                }
            } label: {
                HStack {
                    Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 10, height: 10)
                    Text(calendar.title).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(calendar.calendarIdentifier) {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        if !calendars.isEmpty {
            Text(selection.isEmpty ? "Searching all calendars" : "Searching \(selection.count) selected")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
