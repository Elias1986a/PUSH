import XCTest
@testable import PUSHCore

/// The evidence behind `Candidate.languagesTheVocabularyCannotWrite`, read back
/// off the model itself.
///
/// Eleven of the eighty-four prompts in the dictionary name a script the
/// `multilingual` build's tokenizer has no glyphs for. That is not an opinion
/// about the model's accuracy — it is arithmetic: a transcript it cannot spell
/// is a transcript it cannot emit, and the decoder's only remaining move is
/// `<unk>`. This file re-derives the count from the shipped `tokenizer.json` so
/// the suppression list cannot outlive its reason. The day FluidAudio ships a
/// vocabulary with Tamil in it, this fails and the list gets revisited.
///
/// Needs the ~640 MB `multilingual` build and skips cleanly without it.
final class NemotronVocabularyTests: XCTestCase {

    /// Every distinct character the model can spell a transcript with.
    private func vocabularyCharacters() throws -> Set<Character> {
        let tokenizer = NemotronMultilingualEngine.modelDirectory(for: "ja-JP")
            .appendingPathComponent("tokenizer.json")
        guard let data = try? Data(contentsOf: tokenizer) else {
            throw XCTSkip("Nemotron multilingual build not on disk")
        }
        guard let table = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            XCTFail("tokenizer.json is not the id → token map it used to be")
            return []
        }
        return Set(table.values.flatMap { $0 })
    }

    /// Unicode ranges, one entry per script a prompt in the dictionary names.
    private static let scripts: [String: [ClosedRange<UInt32>]] = [
        "Latin": [0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF],
        "Greek": [0x370...0x3FF, 0x1F00...0x1FFF],
        "Cyrillic": [0x400...0x52F],
        "Armenian": [0x530...0x58F],
        "Hebrew": [0x590...0x5FF],
        "Arabic": [0x600...0x6FF, 0x750...0x77F, 0x8A0...0x8FF],
        "Devanagari": [0x900...0x97F],
        "Bengali": [0x980...0x9FF],
        "Gujarati": [0xA80...0xAFF],
        "Odia": [0xB00...0xB7F],
        "Tamil": [0xB80...0xBFF],
        "Telugu": [0xC00...0xC7F],
        "Kannada": [0xC80...0xCFF],
        "Malayalam": [0xD00...0xD7F],
        "Sinhala": [0xD80...0xDFF],
        "Thai": [0xE00...0xE7F],
        "Georgian": [0x10A0...0x10FF, 0x1C90...0x1CBF],
        "Ethiopic": [0x1200...0x137F],
        "Khmer": [0x1780...0x17FF],
        "Kana": [0x3040...0x30FF],
        "Han": [0x3400...0x4DBF, 0x4E00...0x9FFF],
        "Hangul": [0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF],
    ]

    private func glyphCount(_ script: String, in characters: Set<Character>) -> Int {
        let ranges = Self.scripts[script]!
        return characters.filter { character in
            character.unicodeScalars.contains { scalar in
                ranges.contains { $0.contains(scalar.value) }
            }
        }.count
    }

    /// The eleven. Georgian is the only one that is not a flat zero, and three
    /// vowels ("ე", "ი", "ა") do not spell Georgian either.
    func testTheSuppressedScriptsHaveNoGlyphsInTheVocabulary() throws {
        let characters = try vocabularyCharacters()
        for script in ["Armenian", "Bengali", "Gujarati", "Kannada", "Malayalam",
                       "Sinhala", "Tamil", "Telugu", "Khmer", "Ethiopic"] {
            XCTAssertEqual(glyphCount(script, in: characters), 0,
                           "\(script) is now spellable — revisit the suppression list")
        }
        XCTAssertLessThanOrEqual(glyphCount("Georgian", in: characters), 3,
                                 "Georgian grew glyphs — revisit the suppression list")
    }

    /// The other half, and the one that keeps the rule honest: every script
    /// behind a language still on the menu *is* spellable. If this ever fails,
    /// a language is being offered that the model cannot write.
    func testEveryOfferedScriptIsSpellable() throws {
        let characters = try vocabularyCharacters()
        for script in ["Latin", "Greek", "Cyrillic", "Hebrew", "Arabic",
                       "Devanagari", "Thai", "Kana", "Han", "Hangul"] {
            XCTAssertGreaterThan(glyphCount(script, in: characters), 20,
                                 "\(script) is offered but barely spellable")
        }
    }

    /// `or-KE` is the one row whose script nobody can name. The model wrote
    /// `or` — Odia — with Kenya's region, which is almost certainly Oromo
    /// (`om`), a Latin-script language of Kenya and Ethiopia, misspelled. This
    /// pins the fact that decides it either way: the vocabulary has no Odia at
    /// all, so under the literal reading the prompt is unservable, and under
    /// the Oromo reading it is fine.
    ///
    /// Nothing here remaps it. Rewriting a model's own key on a hunch invents
    /// data, and macOS ships no Oromo voice to settle it with. The row stays,
    /// labelled the way the model spelled it, and this test is the note.
    func testOrKeIsUnresolvedAndSaysSo() throws {
        let characters = try vocabularyCharacters()
        XCTAssertEqual(glyphCount("Odia", in: characters), 0,
                       "Odia became spellable — or-KE is worth re-testing")
        XCTAssertGreaterThan(glyphCount("Latin", in: characters), 20)
    }
}
