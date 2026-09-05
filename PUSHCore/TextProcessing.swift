import Foundation
import NaturalLanguage

/// Turns a raw transcript into the text PUSH pastes.
///
/// Split out of the app target so the engines, the pipeline and the comparison tool
/// share one implementation — a second copy of these rules would drift, and the whole
/// point of comparing engines is that only the engine differs.
///
/// Every pass here is a pure function of its input. The orchestration that has opinions
/// about `AppState`, injection and logging lives in `TranscriptionPipeline+App.swift`
/// in the app target.
public actor TranscriptionPipeline {
    public static let shared = TranscriptionPipeline()

    init() {}

    // MARK: - Engine routing

    /// Route audio to the engine backing `model`. Shared by the main pipeline
    /// and the wake word listener so both always use the loaded engine.
    public static func transcribe(audioData: Data, using model: WhisperModel) async throws -> String {
        switch model.engineType {
        case .parakeet:
            return try await ParakeetEngine.shared.transcribe(audioData: audioData)
        case .parakeetUnified:
            return try await ParakeetUnifiedEngine.shared.transcribe(audioData: audioData)
        case .parakeetStreaming:
            return try await ParakeetStreamingEngine.shared.transcribe(audioData: audioData)
        case .nemotronMultilingual:
            return try await NemotronMultilingualEngine.shared.transcribe(audioData: audioData)
        case .appleSpeech:
            guard #available(macOS 26, *) else { throw PipelineError.requiresNewerSystem }
            return try await AppleSpeechEngine.shared.transcribe(audioData: audioData)
        }
    }

    // MARK: - Post-processing chain

    /// The whole post-processing chain, in order. Extracted from the transcription
    /// path so the passes can be tested *in composition* — the number bugs users
    /// actually hit have been interactions between passes (comma-grouping running
    /// before the dollar rule, decimal dictation running before magnitude words),
    /// not faults in any single pass. Testing them one at a time hides that.
    ///
    /// `hasNativePunctuation` (Parakeet) skips the punctuation/capitalisation
    /// passes so we don't override the model's own, better, formatting.
    ///
    /// `language` gates the whole chain, and defaults to English so every call
    /// site that predates multilingual dictation behaves exactly as it did.
    public static func postProcess(_ text: String,
                                   hasNativePunctuation: Bool,
                                   language: DictationLanguage = DictationLanguage(code: "en-US")) -> String {
        // Everything below encodes English: English number grammar ("twenty
        // five" → 25), English orthography ("i" → "I"), English lexis
        // ("dollars" → "$") and an English filler-word list. Run over another
        // language it cannot improve a transcript, only corrupt one — measured,
        // not assumed: Spanish "ten cuidado" came out "10 cuidado", the German
        // preposition in "um die zwanzig" was eaten as a filler, and the Italian
        // article in "Ho visto i gatti" was capitalised into the English
        // pronoun. So a non-English transcript is returned exactly as the engine
        // wrote it.
        //
        // Returned untouched rather than routed through a shortened chain
        // because there is nothing language-neutral left to run: every pass in
        // the chain below is English-specific, and the whitespace the engines
        // emit is already well-formed. The user's dictionary replacements do
        // still apply to non-English — they are literal strings the user typed,
        // carrying no language assumption — but those run in
        // `TranscriptionPipeline+App`, before this function, so nothing here has
        // to make an exception for them.
        //
        // Rejected: gating each pass individually, so that e.g.
        // `ensureEndingPunctuation` could still run for other Latin-script
        // languages. It would mean auditing ~15 passes against every language a
        // user can pick, with a wrong answer showing up as a silently mangled
        // transcript. Doing nothing is always safe; doing nearly-the-right-thing
        // is not.
        guard language.isEnglish else { return text }

        var out = normalizeCause(text)
        out = removeFillerWords(out)
        out = removeStutteredWords(out)
        out = stripConnectingAnd(out)
        out = normalizeOrdinals(out)
        out = normalizeDecimalDictation(out)
        out = normalizeNumberWords(out)
        out = groupThousands(out)
        if !hasNativePunctuation {
            out = fixTrailingComma(out)
            out = ensureEndingPunctuation(out)
            out = fixQuestionMarks(out)
        }
        out = smartSymbols(out)
        if !hasNativePunctuation {
            out = fixCapitalization(out)
            out = capitalizeI(out)
        }
        return out
    }
}
