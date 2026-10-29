import SwiftUI
import UIKit

/// Wake at a different time (v0.4.1 item 18), used for skipping with your own time, the day-off
/// prompt and Tonight. Step 1: the time (6 hours from now, rounded up) and the series; step 2:
/// "Your morning" as it will be set, where single alarms and backstops can be changed first.
struct OwnAlarmSheet: View {
    let title: String
    let note: String
    let settings: BridgeSettings
    /// Default for the backstops switch (a day off, or leave).
    var backstopsDefault = false
    let done: (SkipReplacement) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var wakeIs: WakeTimeAlarm
    @State private var count: Int
    @State private var spacing: Int
    @State private var backstopsOn: Bool
    @State private var cutoverPending = true
    /// Set on Next: the preview starts from exactly what step 1 shows at that moment.
    @State private var preview: OwnAlarmDraft?

    init(title: String, note: String, settings: BridgeSettings, backstopsDefault: Bool = false, done: @escaping (SkipReplacement) -> Void) {
        self.title = title
        self.note = note
        self.settings = settings
        self.backstopsDefault = backstopsDefault
        self.done = done
        _time = State(initialValue: OwnAlarmDraft.defaultTime(hoursAhead: settings.newAlarmHoursAhead, roundingMinutes: settings.ownAlarmRoundingMinutes))
        _wakeIs = State(initialValue: settings.ownAlarmWakeIs)
        _count = State(initialValue: settings.ownAlarmCount)
        _spacing = State(initialValue: settings.ownAlarmSpacingMinutes)
        _backstopsOn = State(initialValue: backstopsDefault)
    }

    private var draft: OwnAlarmDraft {
        OwnAlarmDraft.make(wake: BedtimeCoordinator.nextOccurrence(ofTimeIn: time), count: count, spacingMinutes: spacing,
                           wakeIs: wakeIs, backstopsOn: backstopsOn, settings: settings)
    }

    var body: some View {
        NavigationStack {
            SettingsPage(title: title) {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("This time is the", selection: $wakeIs) {
                        ForEach(WakeTimeAlarm.allCases) { Text($0.displayName).tag($0) }
                    }
                    Stepper("\(count) \(count == 1 ? "alarm" : "alarms")", value: $count, in: 1...10)
                    if count > 1 {
                        Stepper("\(spacing) min apart", value: $spacing, in: 1...60)
                    }
                } footer: {
                    Text(note)
                }
                Section {
                    Toggle("Backstops", isOn: $backstopsOn)
                } footer: {
                    Text(cutoverPending
                         ? "Early, deadline and late after your last alarm. Takes effect after the backstop cutover; until then the house backstop fires on shifts only."
                         : "Early, deadline and late after your last alarm.")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { preview = draft }
                }
            }
            .navigationDestination(item: $preview) { start in
                OwnAlarmPreview(draft: start, spacing: spacing, settings: settings) { replacement in
                    done(replacement)
                    dismiss()
                }
            }
            .task {
                cutoverPending = await BedtimeCoordinator.shared.morningContext(firstAlarm: nil, settings: settings)?.houseUsesOldTimes ?? true
            }
            .onAppear {
                // Only the chosen interval in the time picker, when set to (SwiftUI has no option for it).
                if settings.ownAlarmPickerSnaps, settings.ownAlarmRoundingMinutes > 0 {
                    UIDatePicker.appearance().minuteInterval = settings.ownAlarmRoundingMinutes
                }
            }
            .onDisappear { UIDatePicker.appearance().minuteInterval = 1 }
        }
    }
}

/// Step 2: exactly what will be set. Tap an alarm to change or remove it, add one before, after
/// or between; change or remove a backstop.
private struct OwnAlarmPreview: View {
    @State var draft: OwnAlarmDraft
    let spacing: Int
    let settings: BridgeSettings
    let set: (SkipReplacement) -> Void
    @State private var editingAlarm: Int?
    @State private var editingBackstop: String?
    @State private var editTime = Date.now
    @State private var undoneNote = false

    var body: some View {
        SettingsPage(title: "Your morning") {
            Section("Alarms") {
                if let first = draft.times.first {
                    Button("Add one before \(WakePlanner.format(first))", systemImage: "plus") { change(draft.adding(.before, spacingMinutes: spacing)) }
                        .font(.footnote)
                }
                ForEach(Array(draft.times.enumerated()), id: \.offset) { index, time in
                    Button {
                        editTime = time
                        editingAlarm = index
                    } label: {
                        HStack {
                            Text(WakePlanner.format(time)).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(Theme.textMuted)
                        }
                    }
                    if index + 1 < draft.times.count {
                        Button("Add one between \(WakePlanner.format(time)) and \(WakePlanner.format(draft.times[index + 1]))", systemImage: "plus") {
                            change(draft.adding(.between(index), spacingMinutes: spacing))
                        }
                        .font(.footnote)
                    }
                }
                if let last = draft.times.last {
                    Button("Add one after \(WakePlanner.format(last))", systemImage: "plus") { change(draft.adding(.after, spacingMinutes: spacing)) }
                        .font(.footnote)
                } else {
                    Button("Add an alarm", systemImage: "plus") {
                        change([OwnAlarmDraft.defaultTime(hoursAhead: settings.newAlarmHoursAhead, roundingMinutes: settings.ownAlarmRoundingMinutes)])
                    }
                }
                if undoneNote {
                    Text("Changing the alarms updates the backstops and undoes changes you made to them.")
                        .font(.footnote).foregroundStyle(Theme.warning.text)
                }
            }
            if draft.backstopsOn {
                Section("Backstops") {
                    ForEach(["early", "deadline", "late"], id: \.self) { rung in
                        if let time = draft.backstops[rung] {
                            Button {
                                editTime = time
                                editingBackstop = rung
                            } label: {
                                HStack {
                                    Label("\(rung.capitalized) backstop", systemImage: "shield").foregroundStyle(Theme.textSoft)
                                    Spacer()
                                    Text(WakePlanner.format(time)).foregroundStyle(Theme.textMuted)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    if let replacement = draft.replacement { set(replacement) }
                } label: {
                    Text("Set alarms").font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity)
                }
                .disabled(draft.times.isEmpty || draft.times.contains { $0 <= .now })
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { editingAlarm != nil }, set: { if !$0 { editingAlarm = nil } })) {
            TimeEditSheet(title: "Alarm", time: $editTime, removeTitle: "Remove alarm") { remove in
                guard let index = editingAlarm, draft.times.indices.contains(index) else { return }
                var times = draft.times
                if remove { times.remove(at: index) } else { times[index] = BedtimeCoordinator.nextOccurrence(ofTimeIn: editTime) }
                change(times)
                editingAlarm = nil
            }
        }
        .sheet(isPresented: Binding(get: { editingBackstop != nil }, set: { if !$0 { editingBackstop = nil } })) {
            TimeEditSheet(title: "\(editingBackstop?.capitalized ?? "") backstop", time: $editTime, removeTitle: "Remove backstop") { remove in
                guard let rung = editingBackstop else { return }
                draft.backstops[rung] = remove ? nil : BedtimeCoordinator.nextOccurrence(ofTimeIn: editTime)
                draft.backstopsEdited = true
                editingBackstop = nil
            }
        }
    }

    private func change(_ times: [Date]) {
        if draft.setAlarms(times, settings: settings) { undoneNote = true }
    }
}

/// Change a time, or remove it.
private struct TimeEditSheet: View {
    let title: String
    @Binding var time: Date
    let removeTitle: String
    let done: (_ remove: Bool) -> Void

    var body: some View {
        NavigationStack {
            SettingsPage(title: title) {
                Section { DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute) }
                Section { Button(removeTitle, role: .destructive) { done(true) } }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { done(false) } } }
        }
        .presentationDetents([.medium])
    }
}
