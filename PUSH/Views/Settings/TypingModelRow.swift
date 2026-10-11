import SwiftUI
import PUSHCore

/// One typing model: pick it, download it, delete it. Shared by Settings →
/// Typing and the onboarding step, so both offer exactly the same choice.
struct TypingModelRow: View {
    @Environment(AppState.self) private var appState
    let model: TypingModel
    var allowsDelete = true

    private var store: TypingModelStore { .shared }
    private var isSelected: Bool { appState.selectedTypingModel == model }
    private var isOnDisk: Bool { store.onDisk.contains(model) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(model.tier).fontWeight(.medium)
                    Text(model.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundStyle(.secondary)
                }
                Text(model.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)
                     + " · up to \(model.maxLength.words.upperBound) words at a time")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.downloading == model {
                    ProgressView(value: store.progress, total: 1)
                        .progressViewStyle(.linear)
                    Text("Downloading… \(Int(store.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isSelected, let error = store.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)
            trailing.padding(.top, 2)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { if isOnDisk { appState.selectedTypingModel = model } }
    }

    @ViewBuilder
    private var trailing: some View {
        if store.downloading == model {
            Button("Cancel") { store.cancelDownload() }
        } else if isOnDisk {
            if isSelected {
                HStack(spacing: 5) {
                    Image(systemName: appState.typingModelReady ? "checkmark.circle.fill" : "hourglass")
                        .foregroundStyle(appState.typingModelReady ? .green : .secondary)
                    Text(appState.typingModelReady ? "In use" : (appState.typeEnabled ? "Loading…" : "Selected"))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } else if allowsDelete {
                Button("Delete") { Task { await store.delete(model) } }
                    .foregroundStyle(.red)
            }
        } else {
            Button("Download") {
                appState.selectedTypingModel = model
                store.download(model)
            }
            .disabled(store.downloading != nil)
        }
    }
}

extension TypingModel {
    /// The name the user chooses by; the model's own name is the badge.
    var tier: String {
        switch self {
        case .lite: return "Lite"
        case .recommended: return "Recommended"
        case .best: return "Best"
        }
    }

    var blurb: String {
        switch self {
        case .lite: return "Smallest and quickest. Short suggestions, for older or 8 GB Macs."
        case .recommended: return "Good suggestions at a modest size."
        case .best: return "The strongest suggestions and the longest. Needs the most memory."
        }
    }
}
