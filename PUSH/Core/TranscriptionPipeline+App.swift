import Foundation
import PUSHCore

/// The parts of the pipeline that belong to the running app: routing to the loaded
/// engine, filtering hallucinations, and injecting the result. The text rules themselves
/// live in `PUSHCore`.
extension TranscriptionPipeline {

    // MARK: - Hallucination Filters

    /// Exact-match hallucination phrases (Whisper outputs these on silence/ambient noise)
    private static let hallucinationPhrases: Set<String> = [
        "subscribe", "like and subscribe",
        "see you next time", "bye", "goodbye",
        "you", "the end", "the end."
    ]

    /// Prefix-match hallucinations (catch "thank you", "thank you so much", "thanks for watching", etc.)
    private static let hallucinationPrefixes = [
        "thank you", "thanks for"
    ]

    // MARK: - Active language

    /// The language the *active* engine is actually transcribing in.
    ///
    /// Deliberately not just `AppState.language(for:)`. The English-only
    /// engines (`.parakeetUnified`, `.parakeetStreaming`, `.parakeetV2`) are
    /// English by construction — their FluidAudio repos are literally named
    /// `-en-` — and `supportsLanguageSelection` is false for them, so no picker
    /// can ever write their `language.*` defaults key. A key left there by an
    /// earlier build, a hand-edited plist or a synced defaults domain would
    /// otherwise turn off English post-processing for the *default* engine, and
    /// the user would have no setting anywhere to point at as the cause.
    ///
    /// One function rather than the same two lines at each call site: the two
    /// consumers (the post-processing chain and the contextual dictionary gate)
    /// must never disagree about what language is being spoken.
    @MainActor
    static func activeLanguage(for model: WhisperModel) -> DictationLanguage {
        guard model.supportsLanguageSelection else { return DictationLanguage(code: "en-US") }
        return AppState.shared.language(for: model)
    }

    // MARK: - Pipeline

    /// Process audio data through the full pipeline
    func process(audioData: Data) async {
        do {
            PushLogger.log("TranscriptionPipeline: Starting transcription, audio size: \(audioData.count) bytes")
            // Step 1: Transcribe with the active (loaded) engine — the selected
            // preference may still be downloading; ModelLoader swaps activeModel
            // only once the new model is ready.
            // Both read in the one hop that was already here. The language is a
            // property of the *active* model, not the selected preference, so it
            // has to be resolved from the same value transcription uses.
            let (activeModel, language) = await MainActor.run { () -> (WhisperModel, DictationLanguage) in
                let model = AppState.shared.activeModel
                return (model, Self.activeLanguage(for: model))
            }
            PushLogger.log("TranscriptionPipeline: Using \(activeModel.engineType) engine...")
            let rawText = try await Self.transcribe(audioData: audioData, using: activeModel)

            // Filter out empty results and Whisper's blank audio markers
            var filteredText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for empty, [BLANK_AUDIO], bracketed text, silence markers,
            // and common Whisper hallucinations on silence/ambient noise
            var lowerText = filteredText.lowercased()
            if filteredText.isEmpty ||
               lowerText.contains("blank_audio") ||
               lowerText.contains("blank audio") ||
               lowerText.contains("silence") ||
               Self.hallucinationPhrases.contains(lowerText) ||
               Self.hallucinationPrefixes.contains(where: { lowerText.hasPrefix($0) }) ||
               filteredText.hasPrefix("(") && filteredText.hasSuffix(")") ||
               filteredText.hasPrefix("[") && filteredText.hasSuffix("]") {
                PushLogger.log("TranscriptionPipeline: No speech detected (empty, blank, or hallucination)")
                return
            }

            // Strip "beep" from the start of transcription (microphone picks up the chirp sound effect)
            // Handle variations: "Beep", "beep,", "Beep.", "beep ", "(beeping)", "[beeping]", etc.
            let beepPatterns = [
                #/^\(beep(ing)?\)[,.\s]*/#,      // (beep) or (beeping)
                #/^\[beep(ing)?\][,.\s]*/#,      // [beep] or [beeping]
                #/^beep(ing)?[,.\s]*/#           // beep or beeping
            ]
            for pattern in beepPatterns {
                if let match = try? pattern.ignoresCase().prefixMatch(in: filteredText) {
                    filteredText = String(filteredText[match.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    lowerText = filteredText.lowercased()
                    PushLogger.log("TranscriptionPipeline: Stripped beep prefix from transcription")
                    break
                }
            }

            // If only "beep" was transcribed (nothing left after stripping), treat as no speech
            if filteredText.isEmpty || lowerText == "beep" || lowerText == "beeping" {
                PushLogger.log("TranscriptionPipeline: No speech detected (only beep sound)")
                return
            }

            // Strip wake word from the start of transcription if enabled
            let (wakeWordEnabled, wakeWord) = await MainActor.run {
                (AppState.shared.wakeWordEnabled, AppState.shared.wakeWord)
            }
            if wakeWordEnabled && !wakeWord.isEmpty {
                // Create pattern to match wake word at start (case insensitive)
                // Handle variations: "push", "Push,", "push.", "push " etc.
                let escapedWakeWord = NSRegularExpression.escapedPattern(for: wakeWord)
                if let regex = try? NSRegularExpression(pattern: "^" + escapedWakeWord + "[,.:!?\\s]*", options: .caseInsensitive) {
                    let range = NSRange(filteredText.startIndex..., in: filteredText)
                    if let match = regex.firstMatch(in: filteredText, options: [], range: range) {
                        let matchRange = Range(match.range, in: filteredText)!
                        filteredText = String(filteredText[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        lowerText = filteredText.lowercased()
                        PushLogger.log("TranscriptionPipeline: Stripped wake word from transcription")
                    }
                }

                // If only wake word was transcribed (nothing left after stripping), treat as no speech
                if filteredText.isEmpty || lowerText == wakeWord.lowercased() {
                    PushLogger.log("TranscriptionPipeline: No speech detected (only wake word)")
                    return
                }
            }

            // Avoid logging raw transcription text to protect user privacy.
            PushLogger.log("TranscriptionPipeline: Whisper transcription received (\(filteredText.count) chars)")

            // Apply user-defined dictionary corrections (e.g. names Whisper consistently mishears).
            // `.always` entries replace unconditionally; `.contextual` entries are gated so
            // homophones (the tool "hammer" vs. the person "Hamer") aren't corrupted.
            //
            // The `.always` lane is language-neutral by construction — literal
            // strings the user typed — and runs in every language. The
            // `.contextual` gate is not: its cues are an English word list and a
            // mid-sentence capital, and German capitalises every noun. Off
            // English it is handed a gate that knows the language and so never
            // fires, which is the verdict (`.keep`) the lane already falls back
            // to whenever it is unsure. English keeps the store's *configured*
            // source untouched, so a future Phase 2 judge still lands here
            // without this line having to learn about it.
            let corrections = await MainActor.run { CorrectionsStore.shared.corrections }
            let verdictSource: VerdictSource = language.isEnglish
                ? CorrectionsStore.defaultVerdictSource
                : HeuristicVerdictSource(language: language)
            filteredText = await CorrectionsStore.applyContextAware(
                corrections, to: filteredText, using: verdictSource)

            // Act on spoken self-corrections before formatting, while the
            // markers are still intact — the formatting pipeline rewrites
            // punctuation around exactly the commas these depend on.
            if await MainActor.run(body: { AppState.shared.resolveSelfCorrections }) {
                let beforeCount = filteredText.count
                filteredText = Self.resolveSelfCorrections(filteredText)
                if filteredText.count != beforeCount {
                    // Lengths only — the transcript itself is never logged.
                    PushLogger.log("TranscriptionPipeline: resolved self-correction (\(beforeCount) → \(filteredText.count) chars)")
                }
            }

            // Post-processing pipeline varies by model capability:
            // Models with native punctuation (Parakeet) get a reduced pipeline
            // to avoid overriding their higher-quality formatting.
            // ...and by language: the whole chain is English (number grammar,
            // "i" → "I", an English filler list), so anything else takes the
            // neutral path and is pasted as the engine wrote it.
            var formattedText = Self.postProcess(
                filteredText,
                hasNativePunctuation: activeModel.hasNativePunctuation,
                language: language)

            // Typographic preference — off by request via Settings → General.
            if await MainActor.run(body: { AppState.shared.doubleSpaceAfterSentence }) {
                formattedText = Self.doubleSpaceAfterPeriods(formattedText)
            }

            // Step 2: Inject into active text field
            PushLogger.log("TranscriptionPipeline: Injecting text...")
            let textToInject = formattedText
            await MainActor.run {
                TextInjector.shared.insertText(textToInject)
            }

            PushLogger.log("TranscriptionPipeline: ✅ Text injected successfully")

        } catch {
            PushLogger.log("TranscriptionPipeline: ❌ ERROR - \(error)")
            await MainActor.run {
                AppState.shared.statusMessage = "Error: \(error.localizedDescription)"
                NotificationManager.shared.showTranscriptionError()
            }
        }
    }
}
