import SwiftUI
import AppKit

/// Settings → Personal: what Type knows about the user — a name and a note
/// they write themselves, and (only if they turn it on) their own writing.
struct PersonalSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var history = TypingHistoryStore.shared
    @State private var confirmingDelete = false

    var body: some View {
        @Bindable var appState = appState
        @Bindable var history = history

        Form {
            Section {
                TextField("Name", text: $appState.typingName,
                          prompt: Text(TypingPreferences.signOffName(saved: "") ?? "Your name"))
                VStack(alignment: .leading, spacing: 6) {
                    Text("About you")
                    TextEditor(text: $appState.typingAbout)
                        .font(.body)
                        .frame(height: 64)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
                    HStack {
                        Text("For example: “I run a small design studio. I write short, friendly emails.”")
                        Spacer()
                        Text("\(appState.typingAbout.count)/\(TypingPreferences.aboutLimit)").monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("You")
            } footer: {
                Text("Suggestions lean toward how you describe yourself. Your name is only offered after a sign-off, such as “Thanks,” at the end of an email. With iCloud sync on, these follow you to your other Macs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle(isOn: $history.isOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Learn from my writing and voice")
                        Text("Keeps what you type and what you dictate where suggestions are on, so they sound like you. Only the finished text is kept, never audio. The writing stays encrypted on this Mac and is never synced or sent anywhere; only this switch follows you to your other Macs, if iCloud sync is on. Passwords, sign-in fields and terminals are never kept.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if history.unreadable {
                    Text("Your saved writing could not be opened (its key is missing). Delete it to start again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if history.isOn || !history.records.isEmpty {
                    LabeledContent("Kept") {
                        Text(history.records.isEmpty ? "Nothing yet"
                             : "\(history.records.count) pieces of writing")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(history.excludedApps, id: \.self) { id in
                        HStack {
                            Text("Never kept from").foregroundStyle(.secondary)
                            AppLabel(bundleID: id)
                            Spacer()
                            Button {
                                history.excludedApps.removeAll { $0 == id }
                            } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Menu("Never Keep from an App…") {
                            ForEach(TypingSettingsView.runningApps(excluding: history.excludedApps), id: \.bundleID) { app in
                                Button(app.name) { history.excludedApps.append(app.bundleID) }
                            }
                        }
                        .fixedSize()
                        Spacer()
                        Button("Delete All…", role: .destructive) { confirmingDelete = true }
                            .disabled(history.records.isEmpty && !history.unreadable)
                    }
                }
            } header: {
                Text("Your writing and voice")
            }

        }
        .formStyle(.grouped)
        .confirmationDialog("Delete everything PUSHTYPE has kept of your writing?", isPresented: $confirmingDelete) {
            Button("Delete All", role: .destructive) { history.deleteAll() }
        } message: {
            Text("This removes the saved writing and its encryption key from this Mac. It can’t be undone.")
        }
    }
}
