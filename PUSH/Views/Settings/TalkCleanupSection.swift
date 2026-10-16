import SwiftUI
import PUSHCore

/// Settings → Talk: the cleanup models on trial, each with its own switch and
/// download, so they can be tried alone or together.
struct TalkCleanupSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Section {
            Picker("Punctuation", selection: $appState.talkPunctuation) {
                Text("Off (speech model's own)").tag(TalkPunctuation.off)
                Text("Small model").tag(TalkPunctuation.smallModel)
                Text("Fast model").tag(TalkPunctuation.fastModel)
            }
            if appState.talkPunctuation == .smallModel {
                TalkCleanupRow(pass: .punctuation, isOn: nil)
            } else if appState.talkPunctuation == .fastModel {
                FastPunctuationRow()
            }
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

/// The fast punctuation model normally arrives with Streaming or Ultra; this
/// row fetches it on its own when it isn't here (an older download, or that
/// part of one failed).
private struct FastPunctuationRow: View {
    @State private var onDisk = FastPunctuationLoader.isOnDisk
    @State private var downloading = false
    @State private var progress = 0.0
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(onDisk ? "Fast model: about 10 ms, \(size)." : "Fast model isn't on this Mac yet (\(size)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !onDisk, !downloading {
                    Button("Download") { download() }
                }
            }
            if downloading {
                ProgressView(value: progress, total: 1).progressViewStyle(.linear)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var size: String {
        ByteCountFormatter.string(fromByteCount: FastPunctuation.totalBytes, countStyle: .file)
    }

    private func download() {
        downloading = true
        progress = 0
        error = nil
        Task {
            do {
                try await FastPunctuationLoader.download { bytes in
                    progress = Double(bytes) / Double(FastPunctuation.totalBytes)
                }
            } catch {
                self.error = error.localizedDescription
            }
            downloading = false
            onDisk = FastPunctuationLoader.isOnDisk
        }
    }
}

private struct TalkCleanupRow: View {
    let pass: TalkCleanupPass
    /// Nil for the small punctuation model, chosen in the Punctuation menu instead.
    var isOn: Binding<Bool>?
    @State private var confirmingDelete = false

    private var store: TalkCleanupStore { .shared }
    private var isOnDisk: Bool { store.onDisk.contains(pass) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if let isOn {
                    Toggle(pass.title, isOn: isOn)
                        .disabled(!isOnDisk)
                } else {
                    Text(pass.title)
                }
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
                if isOn?.wrappedValue ?? true {
                    Text(store.ready.contains(pass) ? "In use" : "Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Delete…") { confirmingDelete = true }
                    .foregroundStyle(.red)
                    .confirmationDialog("Delete the \(pass.title.lowercased())?", isPresented: $confirmingDelete) {
                        Button("Delete", role: .destructive) {
                            isOn?.wrappedValue = false
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
        case .punctuation: return "Small punctuation model"
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
