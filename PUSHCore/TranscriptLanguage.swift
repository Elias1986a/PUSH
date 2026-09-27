import Foundation
import NaturalLanguage

/// Works out which language a finished transcript is in, for engines that
/// detect the language themselves and don't say what they detected.
///
/// Parakeet Ultra is the one such engine today: it is v3-derived, auto-detects
/// per utterance across the Latin-script European languages, and FluidAudio's
/// `ASRResult` carries no language field. Without this, every Ultra transcript
/// would be treated as English and run through the English post-processing
/// chain — which is measured to corrupt other languages (see
/// `TextProcessing.postProcess`: Spanish "ten cuidado" → "10 cuidado").
///
/// Uses Apple's on-device `NLLanguageRecognizer`, so nothing is downloaded and
/// no text leaves the Mac.
public enum TranscriptLanguage {

    /// The languages Ultra can produce under PUSH's Latin-script filter.
    /// Constraining the recognizer to these keeps a short phrase from being
    /// "detected" as a language the engine could never have written.
    static let candidates: [NLLanguage] = [
        .english, .spanish, .french, .german, .italian, .portuguese, .dutch,
        .swedish, .danish, .norwegian, .finnish, .polish, .czech, .slovak,
        .hungarian, .romanian, .croatian,
    ]

    /// Below this, a non-English guess is not trusted.
    static let minimumConfidence = 0.5

    /// The transcript's language, defaulting to English whenever the evidence
    /// is thin.
    ///
    /// English is the safe default rather than a guess: it is what every
    /// Parakeet transcript was treated as before this existed, and the English
    /// chain on a short foreign phrase does little harm, while skipping it on
    /// English loses number and "I" formatting the user relies on. So a single
    /// word, or a guess below `minimumConfidence`, stays English.
    public static func detect(_ text: String) -> DictationLanguage {
        let english = DictationLanguage(code: "en-US")
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 2 else { return english }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates
        recognizer.processString(text)
        guard let (best, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              best != .english,
              confidence >= minimumConfidence
        else { return english }
        return DictationLanguage(code: best.rawValue)
    }
}
