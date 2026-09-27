import XCTest
@testable import PUSH
@testable import PUSHCore

/// Parakeet Ultra auto-detects its language and doesn't report which, so PUSH
/// reads it back from the text. These pin that the English chain still runs on
/// English and stays off everything else.
final class TranscriptLanguageTests: XCTestCase {

    private func detected(_ text: String) -> String {
        TranscriptLanguage.detect(text).code
    }

    func testEnglishIsEnglish() {
        XCTAssertTrue(TranscriptLanguage.detect(
            "Can you send me the quarterly numbers by Friday before the meeting?").isEnglish)
    }

    func testLatinScriptEuropeanLanguagesAreRecognised() {
        XCTAssertEqual(detected("¿Cómo estás? Ten cuidado con el perro cuando salgas de casa."), "es")
        XCTAssertEqual(detected("Bonjour, ça va ? Je voudrais un café avant la réunion."), "fr")
        XCTAssertEqual(detected("Guten Morgen, wir treffen uns um die zwanzig Minuten nach acht."), "de")
        XCTAssertEqual(detected("Ho visto i gatti nel giardino questa mattina presto."), "it")
        XCTAssertEqual(detected("Bom dia, você pode me mandar o relatório até sexta-feira?"), "pt")
    }

    /// A lone word is too little to go on; English is what every Parakeet
    /// transcript was treated as before detection existed.
    func testSingleWordsStayEnglish() {
        XCTAssertTrue(TranscriptLanguage.detect("Hola").isEnglish)
        XCTAssertTrue(TranscriptLanguage.detect("Bonjour.").isEnglish)
        XCTAssertTrue(TranscriptLanguage.detect("").isEnglish)
    }

    /// Only Ultra reads the language from the text. Every other engine keeps
    /// the configured language, whatever the words look like.
    func testOnlyPerUtteranceEnginesReadTheText() {
        let spanishText = "¿Cómo estás? Ten cuidado con el perro cuando salgas de casa."
        let english = DictationLanguage(code: "en-US")
        XCTAssertEqual(TranscriptionPipeline.transcriptLanguage(
            of: spanishText, from: .parakeetUltra, configured: english).code, "es")
        for model in [WhisperModel.parakeetUnified, .parakeetStreaming, .parakeetV2] {
            XCTAssertTrue(TranscriptionPipeline.transcriptLanguage(
                of: spanishText, from: model, configured: english).isEnglish,
                "\(model.rawValue) should not second-guess its configured language")
        }
    }

    /// End to end through the real chain: the measured corruption ("ten
    /// cuidado" → "10 cuidado") no longer happens on an Ultra transcript, and
    /// English still gets its formatting.
    func testUltraTranscriptsGetTheRightPostProcessing() {
        let spanish = "Ten cuidado con el perro cuando salgas de casa."
        let spanishOut = TranscriptionPipeline.postProcess(
            spanish, hasNativePunctuation: true,
            language: TranscriptionPipeline.transcriptLanguage(
                of: spanish, from: .parakeetUltra, configured: DictationLanguage(code: "en-US")))
        XCTAssertEqual(spanishOut, spanish)

        let english = "I think we're about twenty five percent over budget."
        let englishOut = TranscriptionPipeline.postProcess(
            english, hasNativePunctuation: true,
            language: TranscriptionPipeline.transcriptLanguage(
                of: english, from: .parakeetUltra, configured: DictationLanguage(code: "en-US")))
        XCTAssertTrue(englishOut.contains("25"), "English lost its number formatting: \(englishOut)")
    }

    func testOnlyUltraDetectsPerUtterance() {
        XCTAssertEqual(WhisperModel.allCases.filter(\.detectsLanguagePerUtterance), [.parakeetUltra])
    }
}
