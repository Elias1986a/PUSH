import SwiftUI
import PUSHCore

/// Settings → Talk: the cleanup models on trial, each with its own switch and
/// download, so they can be tried alone or together.
struct TalkCleanupSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Section {
            TalkCleanupRow(pass: .punctuation, isOn: $appState.talkPunctuationModel)
            TalkCleanupRow(pass: .autocorrect, isOn: $appState.talkAutocorrectModel)
        } header: {
            Text("Cleanup models (experimental)")
        } footer: {
            Text("English only. Each runs on your Mac after you release the key. When a model takes too long or changes more than it should, PUSHTYPE pastes your words as they were.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TalkCleanupRow: View {
    let pass: TalkCleanupPass
    @Binding var isOn: Bool
    @State private var confirmingDelete = false

    private var store: TalkCleanupStore { .shared }
    private var isOnDisk: Bool { store.onDisk.contains(pass) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Toggle(pass.title, isOn: $isOn)
                    .disabled(!isOnDisk)
                Spacer(minLength: 8)
                trailing
            }
            Text(pass.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.downloading == pass {
                ProgressView(value: store.progress, total: 1)
                    .progressViewStyle(.linear)
                Text("Downloading… \(Int(store.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = store.lastError[pass] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var trailing: some View {
        if store.downloading == pass {
            Button("Cancel") { store.cancelDownload() }
        } else if isOnDisk {
            HStack(spacing: 10) {
                if isOn {
                    Text(store.ready.contains(pass) ? "In use" : "Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Delete…") { confirmingDelete = true }
                    .foregroundStyle(.red)
                    .confirmationDialog("Delete the \(pass.title.lowercased())?", isPresented: $confirmingDelete) {
                        Button("Delete", role: .destructive) {
                            isOn = false
                            Task { await store.delete(pass) }
                        }
                    }
            }
        } else {
            Button("Download (about \(ByteCountFormatter.string(fromByteCount: pass.approximateBytes, countStyle: .file)))") {
                store.download(pass)
            }
            .disabled(store.downloading != nil)
        }
    }
}

extension TalkCleanupPass {
    var title: String {
        switch self {
        case .punctuation: return "Punctuation model"
        case .autocorrect: return "Autocorrect model"
        }
    }

    var blurb: String {
        switch self {
        case .punctuation: return "Fixes commas, periods, question marks, and capitals. Never changes a word you said."
        case .autocorrect: return "Also fixes misheard words and grammar, like “no” for “know”. Changes a few words at most."
        }
    }
}
