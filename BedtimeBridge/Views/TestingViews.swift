import SwiftUI
import UIKit

/// The app as it looks now, small enough to send with a report (v0.4.8 item 9).
enum AppScreenshot {
    @MainActor
    static func capture(width: CGFloat = 600) -> Data? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        let scale = width / max(window.bounds.width, 1)
        let size = CGSize(width: width, height: window.bounds.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false)
        }
        return image.pngData()
    }
}

/// Report something (v0.4.8 item 9): what you type or dictate, with the app's snapshot and,
/// if you like, a picture of the screen as it was.
struct ReportSheet: View {
    let screen: [String: Any]
    let screenshot: Data?
    let settings: BridgeSettings

    @State private var note = ""
    @State private var includeScreenshot = true
    @State private var sending = false
    @State private var result: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 140)
                        .focused($focused)
                } header: {
                    Text("What happened?")
                } footer: {
                    Text("Can be empty. The time, the bar and alarms as they are, what the app did in the last 12 hours and the testing checklist go with it.")
                }
                if screenshot != nil {
                    Section {
                        Toggle("Include a picture of the screen", isOn: $includeScreenshot)
                    }
                }
                if let result {
                    Section { Text(result).font(.footnote).foregroundStyle(Theme.textMuted) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Report something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }.disabled(sending)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func send() {
        sending = true
        Task {
            var app = BedtimeCoordinator.shared.reportSnapshot(settings: settings)
            app["screen"] = screen
            let sent = await TestingReports.send(note: note, app: app, screenshot: includeScreenshot ? screenshot : nil, settings: settings)
            sending = false
            if sent {
                dismiss()
            } else {
                result = "Saved on the phone. It goes to Home Assistant once it can be reached."
                try? await Task.sleep(for: .seconds(1.5))
                dismiss()
            }
        }
    }
}

/// Settings → About → Testing reports (v0.4.8 item 9): on or off, and the ones kept here.
struct TestingReportsPage: View {
    @State private var enabled = TestingReports.enabled
    @State private var saved = TestingReports.saved
    @State private var editing: TestingReports.Saved?
    @State private var deleting: TestingReports.Saved?
    @State private var problem: String?
    let settings: BridgeSettings

    var body: some View {
        SettingsPage(title: "Testing reports") {
            Section {
                Toggle("Report something in ⋯", isOn: $enabled)
                    .onChange(of: enabled) { _, on in TestingReports.enabled = on }
            } footer: {
                Text("Reports (yours, and the ones the app files when it sees something wrong) go to the Bedtime Bridge integration, which saves them in bedtime_bridge_reports in Home Assistant's config folder.")
            }
            Section {
                if listed.isEmpty {
                    Text("None yet").foregroundStyle(Theme.textMuted)
                }
                ForEach(listed) { report in
                    Button { editing = report } label: { row(report) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleting = report }
                        }
                }
                if saved.contains(where: { !$0.sent }) {
                    Button("Send the rest now") {
                        Task {
                            await TestingReports.sendUnsent(settings: settings)
                            saved = TestingReports.saved
                        }
                    }
                }
                if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.danger) }
            } header: {
                Text("Reports sent")
            } footer: {
                Text("Your last 20. Tap one to edit its note, or swipe to delete it, here and in Home Assistant.")
            }
        }
        .sheet(item: $editing) { report in
            EditReportSheet(report: report) { note in
                let done = await TestingReports.edit(report.id, note: note, settings: settings)
                saved = TestingReports.saved
                problem = done ? nil : "Couldn't reach Home Assistant, so the report wasn't changed."
                return done
            }
        }
        .confirmationDialog("Delete this report?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete report", role: .destructive) {
                guard let report = deleting else { return }
                Task {
                    let done = await TestingReports.delete(report.id, settings: settings)
                    saved = TestingReports.saved
                    problem = done ? nil : "Couldn't reach Home Assistant, so the report wasn't deleted."
                }
            }
        } message: {
            Text("It's removed from this phone and from Home Assistant, with its screenshot.")
        }
    }

    /// v0.4.10 item 13.
    private var listed: [TestingReports.Saved] { TestingReports.listed(saved) }

    private func row(_ report: TestingReports.Saved) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(report.time.formatted(date: .abbreviated, time: .shortened)).font(.footnote.weight(.semibold))
                Spacer()
                Text(report.sent ? "Sent" : "Not sent yet").font(.caption).foregroundStyle(report.sent ? Theme.good : Theme.textMuted)
            }
            Text(report.note.isEmpty ? "(no note)" : report.note).font(.footnote).lineLimit(3)
            ShareLink(item: String(data: report.body, encoding: .utf8) ?? "") { Label("Share", systemImage: "square.and.arrow.up") }
                .font(.caption)
        }
        .contentShape(Rectangle())
    }
}

/// Edits a report's note (v0.4.10 item 13).
private struct EditReportSheet: View {
    let report: TestingReports.Saved
    let save: (String) async -> Bool
    @State private var note = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $note).frame(minHeight: 160)
            }
            .navigationTitle("Edit report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        saving = true
                        Task {
                            _ = await save(note)
                            dismiss()
                        }
                    }
                    .disabled(saving || note == report.note)
                }
            }
            .onAppear { note = report.note }
        }
    }
}

/// Settings → About → Testing checklist (v0.4.8 item 12).
struct TestingChecklistPage: View {
    @State private var ticked = TestingChecklist.ticked

    var body: some View {
        SettingsPage(title: "Testing checklist") {
            Section {
                ForEach(TestingChecklist.Item.allCases) { item in
                    let done = ticked[item.rawValue]
                    Button {
                        TestingChecklist.set(item, done: done == nil)
                        ticked = TestingChecklist.ticked
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: done == nil ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(done == nil ? Theme.textMuted : Theme.good)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(Theme.text)
                                if let done {
                                    Text("Seen \(done.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Theme.textMuted)
                                } else if item.ticksItself {
                                    Text("Ticks itself when it happens").font(.caption).foregroundStyle(Theme.textMuted)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Not yet seen working for real. Tap to tick or untick. Sent with every testing report.")
            }
        }
    }
}
