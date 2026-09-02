import XCTest
import FluidAudio
@testable import PUSHCore

final class NemotronMultilingualEngineTests: XCTestCase {

    /// The latin vocab is smaller and has a faster joint network. Routing must
    /// match FluidAudio's own mapping or we download the wrong 600 MB.
    func testLatinLanguagesRouteToTheLatinVocab() {
        for code in ["en-US", "es-ES", "fr-FR", "it-IT", "pt-BR", "de-DE"] {
            XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: code), "latin",
                           "\(code) should use the pruned latin vocab")
        }
    }

    func testNonLatinLanguagesRouteToTheFullVocab() {
        for code in ["zh-CN", "ja-JP", "ru-RU"] {
            XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: code), "multilingual")
        }
    }

    /// The drift guard the duplication exists to need. `vocabVariant(for:)`
    /// copies FluidAudio's split rather than calling it, so nothing but this
    /// test notices when a FluidAudio bump moves a language between the two
    /// builds — and the symptom of not noticing is a wrong 600 MB download.
    ///
    /// "auto" is excluded on purpose; it is the one deliberate divergence, and
    /// `testAutoNormalizesToACodeBothMappingsAgreeOn` covers it instead.
    func testVocabVariantMatchesFluidAudioExceptForAuto() {
        for code in ["en-US", "es-ES", "fr-FR", "it-IT", "pt-BR", "de-DE",
                     "zh-CN", "ja-JP", "ru-RU", "ko-KR", "ar-SA"] {
            XCTAssertEqual(
                NemotronMultilingualEngine.vocabVariant(for: code),
                StreamingNemotronMultilingualAsrManager.languageDirectory(for: code),
                "\(code) drifted from FluidAudio's mapping")
        }
    }

    /// "auto" must never reach the engine — this app always picks a language.
    /// If it somehow does, fall back to English rather than enabling detection.
    func testAutoIsRejectedInFavourOfExplicitEnglish() {
        XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: "auto"), "latin")
    }

    /// The bookkeeping-vs-download agreement, which is the whole reason `"auto"`
    /// is normalized before anything downstream sees it.
    ///
    /// Forwarding a raw `"auto"` to FluidAudio loads the `multilingual` build
    /// while we record `latin`; every later latin language then takes the
    /// cheap-switch path onto the wrong build, permanently. This asserts that
    /// what we forward is a code both mappings resolve the same way.
    func testAutoNormalizesToACodeBothMappingsAgreeOn() {
        let forwarded = NemotronMultilingualEngine.effectiveLanguageCode("auto")

        XCTAssertNotEqual(forwarded.lowercased(), "auto",
                          "a raw \"auto\" must never be forwarded to FluidAudio")
        XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: forwarded), "latin")
        XCTAssertEqual(
            StreamingNemotronMultilingualAsrManager.languageDirectory(for: forwarded), "latin",
            "our variant bookkeeping and FluidAudio's download path must name the same build")
    }

    /// Any code that isn't "auto" passes through untouched — normalization is
    /// one special case, not a rewrite of what the user picked.
    func testEffectiveLanguageCodeLeavesRealLanguagesAlone() {
        for code in ["en-US", "pt-BR", "ja-JP"] {
            XCTAssertEqual(NemotronMultilingualEngine.effectiveLanguageCode(code), code)
        }
    }

    /// The language list must come from the loaded model, never a constant.
    ///
    /// Uses a fresh instance rather than `shared` so this asserts on a developer
    /// machine that already has the model downloaded — guarding on
    /// `isModelDownloaded()` made it vacuously green exactly where a hardcoded
    /// fallback list would show up.
    func testSupportedLanguagesIsEmptyUntilTheModelIsLoaded() async {
        let engine = NemotronMultilingualEngine()
        let languages = await engine.supportedLanguages()
        XCTAssertTrue(languages.isEmpty,
                      "no model loaded means no list — never a hardcoded fallback")
    }

    /// A per-language answer is what warns before a surprise second download;
    /// it has to agree with the variant mapping it is built on.
    func testPerLanguageDownloadCheckFollowsTheVariantMapping() {
        let latinReady = NemotronMultilingualEngine.isModelDownloaded(for: "es-ES")
        XCTAssertEqual(latinReady, NemotronMultilingualEngine.isModelDownloaded(for: "de-DE"),
                       "languages sharing a build must share an answer")
        XCTAssertEqual(
            NemotronMultilingualEngine.isModelDownloaded(for: "ja-JP"),
            NemotronMultilingualEngine.isModelDownloaded(for: "ru-RU"),
            "languages sharing a build must share an answer")

        // The either-variant row can only ever be the more optimistic of the two.
        if latinReady {
            XCTAssertTrue(NemotronMultilingualEngine.isModelDownloaded())
        }
    }

    // MARK: - Build completeness

    /// The seven files the repo ships for one build.
    private static let fullBuild = [
        "metadata.json", "tokenizer.json", "encoder.mlmodelc",
        "decoder.mlmodelc", "joint.mlmodelc", "decoder_joint.mlmodelc",
        "preprocessor.mlmodelc",
    ]

    /// Builds a variant directory holding exactly `names`, faithful to the real
    /// layout: `.mlmodelc` are directories on disk, the rest are files.
    private func makeBuild(_ names: [String]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nemotron-build-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        for name in names {
            let url = dir.appendingPathComponent(name)
            if name.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Data().write(to: url)
            }
        }
        return dir
    }

    func testAFullyDownloadedBuildIsComplete() throws {
        XCTAssertTrue(NemotronMultilingualEngine.isBuildComplete(at: try makeBuild(Self.fullBuild)))
    }

    /// The v7.5.0 bug, pinned. The files arrive one at a time over minutes, and
    /// the old check ("contains any .mlmodelc") was satisfied by the first of
    /// the seven — so Settings reported "600 MB · on this Mac" while a load
    /// against that directory was still certain to fail.
    func testABuildWithOnlyTheFirstFileIsNotComplete() throws {
        XCTAssertFalse(
            NemotronMultilingualEngine.isBuildComplete(at: try makeBuild(["decoder.mlmodelc"])),
            "one .mlmodelc out of seven is a download in progress, not a usable build")
    }

    func testAnEmptyOrAbsentDirectoryIsNotComplete() throws {
        let dir = try makeBuild([])
        XCTAssertFalse(NemotronMultilingualEngine.isBuildComplete(at: dir))
        XCTAssertFalse(NemotronMultilingualEngine.isBuildComplete(
            at: dir.appendingPathComponent("never-downloaded")))
    }

    /// Each file the loader opens unconditionally, removed one at a time.
    func testEveryRequiredFileIsActuallyRequired() throws {
        for missing in ["metadata.json", "tokenizer.json", "encoder.mlmodelc"] {
            let dir = try makeBuild(Self.fullBuild.filter { $0 != missing })
            XCTAssertFalse(NemotronMultilingualEngine.isBuildComplete(at: dir),
                           "a build missing \(missing) cannot load")
        }
    }

    /// The decode path is an either/or, mirroring the guard in `preloadShared`.
    /// A lean ship carries only the fused bundle; an older export only the bare
    /// pair. Both load, so both must count as complete.
    func testEitherDecodePathAloneIsEnough() throws {
        let fused = try makeBuild(
            ["metadata.json", "tokenizer.json", "encoder.mlmodelc", "decoder_joint.mlmodelc"])
        XCTAssertTrue(NemotronMultilingualEngine.isBuildComplete(at: fused))

        let bare = try makeBuild(
            ["metadata.json", "tokenizer.json", "encoder.mlmodelc",
             "decoder.mlmodelc", "joint.mlmodelc"])
        XCTAssertTrue(NemotronMultilingualEngine.isBuildComplete(at: bare))
    }

    /// Half of the bare pair is no decode path — the exact on-disk shape that
    /// produced the shipped "No decode path" error.
    func testHalfOfTheBareDecodePairIsNotEnough() throws {
        let dir = try makeBuild(
            ["metadata.json", "tokenizer.json", "encoder.mlmodelc", "decoder.mlmodelc"])
        XCTAssertFalse(NemotronMultilingualEngine.isBuildComplete(at: dir))
    }

    /// `preprocessor.mlmodelc` is downloaded but never opened — the manager
    /// computes log-mel natively in Swift. Requiring it would call a perfectly
    /// loadable build broken.
    func testTheCoreMLPreprocessorIsNotRequired() throws {
        let dir = try makeBuild(Self.fullBuild.filter { $0 != "preprocessor.mlmodelc" })
        XCTAssertTrue(NemotronMultilingualEngine.isBuildComplete(at: dir))
    }
}
