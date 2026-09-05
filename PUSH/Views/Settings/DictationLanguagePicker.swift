import SwiftUI
import AppKit
import PUSHCore

// MARK: - Dictation language

/// The language control that sits inside the selected engine's row in Models.
///
/// Its own view rather than a `@ViewBuilder` on `ModelsSettingsView` for one
/// concrete reason: the language list is resolved asynchronously and has to be
/// held in `@State`, and there is exactly one picker on screen at a time (the
/// selected engine's). A dictionary of per-model lists on the parent would
/// carry four dead entries and would still need re-resolving by hand when the
/// selection moved; here SwiftUI's own view identity does that work.
struct DictationLanguagePicker: View {
    let model: AppState.WhisperModel

    /// Called once a language change has finished loading. Choosing a language
    /// can pull a ~600 MB build without anyone pressing Download, and the row's
    /// "on this Mac" line and the Storage total would otherwise both go stale.
    var onModelsChanged: () -> Void = {}

    /// Performs the reload. `willDownload` says whether it is about to pull
    /// another ~600 MB build.
    ///
    /// Supplied by the parent rather than run here because the progress bar and
    /// the error line belong to the model row, not to this control — and
    /// because the flag matters: a same-build language change is a prompt swap
    /// that finishes in about 0.15s, and putting a progress bar on that would
    /// only flicker.
    var reload: @MainActor (_ willDownload: Bool) async -> Void = { _ in }

    @EnvironmentObject private var appState: AppState

    /// `nil` means "not asked yet", which is a genuinely different state from
    /// "this engine offers nothing" and must not draw the same UI. Collapsing
    /// them made Apple Speech flash "no languages" on every appearance while
    /// the OS query was in flight.
    @State private var languages: [DictationLanguage]?

    /// Whether the language now selected still needs its model build fetched.
    @State private var needsAnotherDownload = false

    /// Bumped after a reload. Crossing vocab groups swaps in a build with a
    /// different `prompt_dictionary`, so the list of offered languages is not
    /// the same list it was a moment ago.
    @State private var reloadToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Language")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Language", selection: selection) {
                    ForEach(options) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220, alignment: .leading)
                // Disabled rather than hidden when there is nothing to choose
                // from: a control that vanishes reads as a bug, and the note
                // below only makes sense next to the thing it is explaining.
                .disabled(hasNoChoice)
            }

            if let unavailableNote {
                note(unavailableNote)
            } else if needsAnotherDownload {
                note(extraDownloadNote)
            }
        }
        .task(id: listKey) { await resolveLanguages() }
    }

    /// Matches `TeleprompterSettingsView`'s "needs the Parakeet model" note
    /// exactly — same orange, same triangle, same caption size. Two panes
    /// describing the same situation (a model that isn't there yet) in two
    /// different visual languages would read as two different problems.
    private func note(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    // MARK: Contents

    private var current: DictationLanguage { appState.language(for: model) }

    private var hasNoChoice: Bool { (languages ?? []).isEmpty }

    /// What the popup lists.
    ///
    /// Never empty: a `Picker` whose selection is absent from its content draws
    /// a blank button, so the fallback while the list is unknown or empty is the
    /// saved choice on its own — disabled, but at least naming the language the
    /// engine will actually use.
    ///
    /// The same reasoning covers a saved language the engine no longer offers
    /// (a preference from another build, or a dependency bump that changed the
    /// list): it is appended rather than dropped, because silently showing blank
    /// leaves the user unable to see — or move off — what they are set to.
    private var options: [DictationLanguage] {
        guard let languages, !languages.isEmpty else { return [current] }
        guard !languages.contains(current) else { return languages }
        return (languages + [current]).sorted()
    }

    private var selection: Binding<DictationLanguage> {
        // Hand-built rather than bound to a stored property: the preference is
        // keyed by engine, so there is no single property to bind to.
        // `AppState.setLanguage` publishes the change itself, which is what
        // makes this redraw.
        Binding(get: { current }, set: { choose($0) })
    }

    /// Shown in place of a usable picker when the engine can't name its
    /// languages yet.
    private var unavailableNote: String? {
        guard let languages, languages.isEmpty else { return nil }
        switch model {
        case .nemotronMultilingual:
            // `supportedLanguages()` reads the loaded model's own prompt
            // dictionary and deliberately has no hardcoded fallback, so an
            // undownloaded engine has genuinely nothing to offer.
            return "Download the model to see its languages."
        case .appleSpeech:
            return "macOS hasn't offered any dictation languages yet."
        case .parakeetV2, .parakeetUnified, .parakeetStreaming:
            // Unreachable — `showsLanguagePicker` keeps the English engines out
            // of this view. Listed rather than defaulted so adding an engine is
            // a compile error here instead of a wrong sentence at runtime.
            return nil
        }
    }

    private var extraDownloadNote: String {
        "\(current.displayName) needs a different model build. "
            + "That's another \(model.downloadSizeLabel) to download."
    }

    // MARK: Resolving the list

    /// Re-resolve whenever the running engine changes: downloading Nemotron
    /// from the row's own Download button is what turns its empty list into a
    /// real one, and that arrives as an `activeModel`/`isModelReady` change.
    private var listKey: String {
        "\(appState.activeModel.rawValue)|\(appState.isModelReady)|\(reloadToken)"
    }

    /// Each engine reports only its own languages. Never merged: Nemotron's six
    /// or so latin-build languages and Apple's forty-five are different sets,
    /// and a combined list would offer the user languages the engine they are
    /// running cannot transcribe.
    private func resolveLanguages() async {
        let resolved: [DictationLanguage]
        switch model.engineType {
        case .nemotronMultilingual:
            resolved = await NemotronMultilingualEngine.shared.supportedLanguages()
        case .appleSpeech:
            if #available(macOS 26, *) {
                resolved = await AppleSpeechEngine.supportedLanguages()
            } else {
                resolved = []
            }
        case .parakeet, .parakeetUnified, .parakeetStreaming:
            resolved = []
        }
        languages = resolved
        needsAnotherDownload = Self.currentNeedsAdditionalDownload(for: model, language: current)
    }

    // MARK: Choosing

    private func choose(_ language: DictationLanguage) {
        guard language != current else { return }
        appState.setLanguage(language, for: model)

        // Computed here and now, not inside the Task below, because the whole
        // value of this note is that it is on screen *before* the download
        // starts. It is two directory listings — nowhere near the sustained
        // main-thread block that makes macOS disable PUSH's event tap.
        needsAnotherDownload = Self.currentNeedsAdditionalDownload(for: model, language: language)

        guard ModelLoader.languageChangeNeedsReload(
            changed: model,
            activeModel: appState.activeModel,
            isModelReady: appState.isModelReady
        ) else { return }

        // Kicked off and left to run. A settings click must never wait on a
        // model load or an OS asset install: blocking the main thread is how
        // this app loses its CGEvent tap and starts silently dropping hotkey
        // presses. The status the reload writes into `AppState` is already read
        // by the menu bar and the pill, so there is nothing to wait for here.
        let willDownload = needsAnotherDownload

        Task {
            await reload(willDownload)
            // Re-ask rather than assume: the build is on disk now, unless the
            // load failed, in which case the warning is still true.
            needsAnotherDownload = Self.currentNeedsAdditionalDownload(for: model, language: language)
            reloadToken += 1
            onModelsChanged()
        }
    }

    // MARK: The cross-group download warning

    /// Whether choosing `language` will pull another model build.
    ///
    /// Nemotron ships two ~600 MB builds — `latin` (en/es/fr/it/pt/de) and
    /// `multilingual` (everything else) — and the Models row says "Downloaded"
    /// when *either* is present, which is the right answer for a row that asks
    /// one yes/no question about one engine. It is also, on its own, how a user
    /// who has Japanese down picks Spanish and gets several minutes of nothing
    /// happening while the UI insists the model is already there.
    ///
    /// The two on-disk checks are injected rather than called directly so this
    /// decision can be tested against known filesystem states instead of
    /// whatever this machine happens to have downloaded.
    static func needsAdditionalDownload(
        for model: AppState.WhisperModel,
        language: DictationLanguage,
        isEngineDownloaded: () -> Bool,
        isLanguageDownloaded: (String) -> Bool
    ) -> Bool {
        // The only engine with more than one build. Apple's assets are the OS's
        // business and the row already reports their state in its own words.
        guard model == .nemotronMultilingual else { return false }

        // Nothing on disk at all is not a surprise — the row says "not
        // downloaded" and offers a Download button. Warning here as well would
        // put two download notices on the same row and bury the one case that
        // actually catches people out.
        guard isEngineDownloaded() else { return false }

        return !isLanguageDownloaded(language.code)
    }

    /// The live-filesystem form of the above, for the view to call.
    private static func currentNeedsAdditionalDownload(
        for model: AppState.WhisperModel,
        language: DictationLanguage
    ) -> Bool {
        needsAdditionalDownload(
            for: model,
            language: language,
            isEngineDownloaded: { NemotronMultilingualEngine.isModelDownloaded() },
            isLanguageDownloaded: { NemotronMultilingualEngine.isModelDownloaded(for: $0) }
        )
    }
}
