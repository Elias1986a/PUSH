import SwiftUI
import AppKit
import PUSHCore

// MARK: - Dictionary

struct DictionarySettingsView: View {
    @ObservedObject private var store = CorrectionsStore.shared

    /// A row being typed, held here rather than in the store: `addCorrection`
    /// refuses a half-empty entry, and it is right to — an entry with an empty
    /// "heard as" would match everything, and the dictionary syncs to iCloud.
    /// So the new row is a draft until it has both halves.
    @State private var draft: Draft?
    @FocusState private var draftFieldFocused: Bool
    /// Row order, held still while the list is on screen — see `displayed`.
    @State private var order: [UUID] = []

    private struct Draft {
        var wrong: String = ""
        var right: String = ""
        var contextual: Bool = false
        var entity: String = ""
        /// True once the mode control is changed by hand, so auto-defaulting
        /// (Context for common words) stops overriding that choice.
        var modeManuallySet: Bool = false

        var isComplete: Bool {
            !wrong.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !right.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        Form {
            Section("Your dictionary") {
                if let draft {
                    draftRow(draft)
                }

                ForEach(displayed) { correction in
                    // Look the binding back up by id: the display order is not
                    // the storage order, and rows must stay editable.
                    if let index = store.corrections.firstIndex(where: { $0.id == correction.id }) {
                        correctionRow($store.corrections[index])
                    }
                }

                if store.corrections.isEmpty && draft == nil {
                    Text("No corrections yet. Add one with +.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        draft = Draft()
                        draftFieldFocused = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 14)
                    }
                    .disabled(draft != nil)
                    .help("Add a correction")
                    Spacer()
                }

                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshOrder)
        // Ids only: the order settles when entries arrive or leave, never on a
        // keystroke. Editing a row re-stamps `modifiedAt`, and re-sorting on
        // that would slide the row out from under the cursor mid-word.
        .onChange(of: store.corrections.map(\.id)) { _, _ in refreshOrder() }
        .onDisappear(perform: commitDraft)
    }

    /// The rows as drawn: `order` while it holds, with anything it hasn't seen
    /// yet (a fresh add, entries arriving from another Mac) at the top.
    private var displayed: [CorrectionsStore.Correction] {
        let byID = Dictionary(store.corrections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = order.compactMap { byID[$0] }
        let knownIDs = Set(order)
        return newestFirst.filter { !knownIDs.contains($0.id) } + known
    }

    private func refreshOrder() {
        let live = Set(store.corrections.map(\.id))
        let kept = order.filter { live.contains($0) }
        let keptIDs = Set(kept)
        order = newestFirst.map(\.id).filter { !keptIDs.contains($0) } + kept
    }

    /// Newest first. Storage order is not display order: a merge re-sorts the
    /// whole list by `modifiedAt` ascending (`CloudSync.mergeCorrections`), so
    /// inserting locally at the top would survive only until the next sync.
    /// Sorting the view instead holds either way.
    private var newestFirst: [CorrectionsStore.Correction] {
        store.corrections.sorted {
            $0.modifiedAt == $1.modifiedAt
                ? $0.id.uuidString > $1.id.uuidString
                : $0.modifiedAt > $1.modifiedAt
        }
    }

    private var footnote: String {
        if draft != nil {
            return "Type what PUSH hears, then what it should insert. Choose “In context” for words that are also ordinary English, so they are replaced when you mean the name and left alone otherwise."
        }
        let count = store.corrections.count
        return count == 0
            ? "Corrections are applied to every transcription before it is inserted."
            : "\(count) correction\(count == 1 ? "" : "s") · applied to every transcription before it is inserted."
    }

    // MARK: Rows

    @ViewBuilder
    private func draftRow(_ current: Draft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // prompt:, not the first argument — inside a Form that
                // argument becomes a label beside the field, which both drew
                // the placeholder twice and squeezed the field to ~65pt.
                TextField("", text: Binding(
                    get: { draft?.wrong ?? "" },
                    set: { value in
                        draft?.wrong = value
                        // Default new common-word entries to Context (safer),
                        // unless the mode was already picked by hand.
                        if draft?.modeManuallySet == false {
                            draft?.contextual = WordChecker.isCommonWord(value)
                        }
                    }
                ), prompt: Text("Heard as"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
                .focused($draftFieldFocused)
                .onSubmit(commitDraft)
                // Focus has to wait for the field to exist; setting it in the
                // + action lands before this row is in the hierarchy.
                .onAppear { draftFieldFocused = true }

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("", text: Binding(
                    get: { draft?.right ?? "" },
                    set: { draft?.right = $0 }
                ), prompt: Text("Should be"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
                .onSubmit(commitDraft)

                modePicker(
                    isContextual: Binding(
                        get: { draft?.contextual ?? false },
                        set: { draft?.contextual = $0; draft?.modeManuallySet = true }
                    )
                )

                Button("Add", action: commitDraft)
                    .buttonStyle(.borderedProminent)
                    .disabled(!current.isComplete)
                    .help("Add this correction")

                Button {
                    draft = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Discard this row")
            }

            if current.contextual {
                entityField(text: Binding(
                    get: { draft?.entity ?? "" },
                    set: { draft?.entity = $0 }
                ))
            }

            if WordChecker.isCommonWord(current.wrong) && !current.contextual {
                Label("“\(current.wrong)” is also a common word — “In context” avoids over-correcting it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func correctionRow(_ correction: Binding<CorrectionsStore.Correction>) -> some View {
        let entityText = Binding<String>(
            get: { correction.wrappedValue.entity ?? "" },
            set: { correction.entity.wrappedValue = $0.isEmpty ? nil : $0 }
        )

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("", text: correction.wrong)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("", text: correction.right)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)

                modePicker(isContextual: Binding(
                    get: { correction.wrappedValue.kind == .contextual },
                    set: { correction.kind.wrappedValue = $0 ? .contextual : .always }
                ))

                Button {
                    store.remove(correction.wrappedValue)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Remove this correction")
            }

            if correction.wrappedValue.kind == .contextual {
                entityField(text: entityText)
            }
        }
        .padding(.vertical, 2)
    }

    private func modePicker(isContextual: Binding<Bool>) -> some View {
        Picker("", selection: isContextual) {
            Text("Always").tag(false)
            Text("In context").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Always replace, or only when the context fits")
    }

    private func entityField(text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", text: text, prompt: Text("what is it? (e.g. a person named Hamer)"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .font(.caption)
        }
    }

    // MARK: Draft

    /// Turns a complete draft into a real entry. An incomplete one is dropped —
    /// leaving a half-typed row behind would be worse than losing it, since it
    /// cannot be saved anyway.
    private func commitDraft() {
        guard let current = draft else { return }
        if current.isComplete {
            store.addCorrection(
                wrong: current.wrong,
                right: current.right,
                kind: current.contextual ? .contextual : .always,
                entity: current.contextual ? current.entity : nil
            )
        }
        draft = nil
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(AppState.shared)
}
#endif

/// Mirrors `AssetInventory.Status` so the view can hold it in `@State` without the
/// whole view needing `@available(macOS 26, *)`.
