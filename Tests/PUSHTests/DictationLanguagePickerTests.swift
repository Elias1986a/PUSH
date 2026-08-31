import XCTest
@testable import PUSH
@testable import PUSHCore

/// The decisions behind the Models pane's language picker.
///
/// The picker itself is a SwiftUI view and this project has no view-hosting
/// test setup, so the three judgements it makes are deliberately *not* buried
/// in `body`: which rows get a picker at all, whether a chosen language will
/// pull another ~600 MB build, and whether the change has to reload a running
/// engine. Each is a plain function, and each is pinned here.
///
/// What is not covered, and cannot honestly be: the rendering itself — the
/// disabled state, the orange note's placement, and whether a click on the
/// popup reaches the picker rather than the row's own tap gesture. Those need
/// eyes on the window.
@MainActor
final class DictationLanguagePickerTests: XCTestCase {

    // MARK: - Which rows get a picker

    /// Both halves of the condition matter. A picker under an engine that
    /// cannot take a language is a control that silently does nothing; a picker
    /// under every row buries the model comparison the list exists for.
    func testOnlyTheSelectedLanguageTakingEngineShowsAPicker() {
        XCTAssertTrue(ModelsSettingsView.showsLanguagePicker(
            for: .nemotronMultilingual, selectedModel: .nemotronMultilingual))
        XCTAssertTrue(ModelsSettingsView.showsLanguagePicker(
            for: .appleSpeech, selectedModel: .appleSpeech))

        // Selected, but English-only by construction.
        XCTAssertFalse(ModelsSettingsView.showsLanguagePicker(
            for: .parakeetUnified, selectedModel: .parakeetUnified))
        XCTAssertFalse(ModelsSettingsView.showsLanguagePicker(
            for: .parakeetStreaming, selectedModel: .parakeetStreaming))
        XCTAssertFalse(ModelsSettingsView.showsLanguagePicker(
            for: .parakeetV2, selectedModel: .parakeetV2))

        // Takes a language, but is not the row the user has chosen.
        XCTAssertFalse(ModelsSettingsView.showsLanguagePicker(
            for: .nemotronMultilingual, selectedModel: .parakeetUnified))
        XCTAssertFalse(ModelsSettingsView.showsLanguagePicker(
            for: .appleSpeech, selectedModel: .nemotronMultilingual))
    }

    /// Holds the rule to `supportsLanguageSelection` rather than to today's list
    /// of engines, so adding one cannot quietly grow or lose a picker.
    func testEveryRowAgreesWithSupportsLanguageSelection() {
        for model in WhisperModel.allCases {
            XCTAssertEqual(
                ModelsSettingsView.showsLanguagePicker(for: model, selectedModel: model),
                model.supportsLanguageSelection,
                "\(model.rawValue) disagrees with its own supportsLanguageSelection")

            // Never under an unselected row, whatever the engine.
            let other: WhisperModel = model == .parakeetV2 ? .parakeetUnified : .parakeetV2
            XCTAssertFalse(ModelsSettingsView.showsLanguagePicker(for: model, selectedModel: other))
        }
    }

    // MARK: - The cross-group download warning

    /// A stand-in filesystem: exactly `present` vocab builds are on disk.
    ///
    /// Routes through the engine's real `vocabVariant(for:)` rather than a
    /// second copy of the language→build mapping — the mapping is the part that
    /// decides whether a switch costs 600 MB, so a test that reimplemented it
    /// would pass while the app downloaded the wrong build.
    private func builds(_ present: Set<String>) -> (() -> Bool, (String) -> Bool) {
        (
            { !present.isEmpty },
            { present.contains(NemotronMultilingualEngine.vocabVariant(for: $0)) }
        )
    }

    private func needsDownload(_ code: String, withBuildsOnDisk present: Set<String>,
                               model: WhisperModel = .nemotronMultilingual) -> Bool {
        let (engine, language) = builds(present)
        return DictationLanguagePicker.needsAdditionalDownload(
            for: model,
            language: DictationLanguage(code: code),
            isEngineDownloaded: engine,
            isLanguageDownloaded: language)
    }

    /// Spanish to Portuguese is a prompt swap inside the resident build. Warning
    /// here would train the user to ignore the warning that matters.
    func testLatinToLatinNeedsNoDownload() {
        XCTAssertFalse(needsDownload("es-ES", withBuildsOnDisk: ["latin"]))
        XCTAssertFalse(needsDownload("pt-BR", withBuildsOnDisk: ["latin"]))
        XCTAssertFalse(needsDownload("de-DE", withBuildsOnDisk: ["latin"]))
    }

    /// The case this whole warning exists for: the row says "Downloaded"
    /// truthfully, and picking Japanese then stalls for minutes.
    func testLatinToMultilingualNeedsAnotherDownload() {
        XCTAssertTrue(needsDownload("ja-JP", withBuildsOnDisk: ["latin"]))
        XCTAssertTrue(needsDownload("zh-CN", withBuildsOnDisk: ["latin"]))
    }

    /// And the same crossing in the other direction — a user who came for
    /// Japanese and now wants Spanish pays the same 600 MB.
    func testMultilingualToLatinNeedsAnotherDownload() {
        XCTAssertTrue(needsDownload("es-ES", withBuildsOnDisk: ["multilingual"]))
        XCTAssertTrue(needsDownload("en-US", withBuildsOnDisk: ["multilingual"]))
    }

    /// Someone who has crossed once has both builds and never sees this again.
    func testNothingToWarnAboutOnceBothBuildsAreOnDisk() {
        XCTAssertFalse(needsDownload("ja-JP", withBuildsOnDisk: ["latin", "multilingual"]))
        XCTAssertFalse(needsDownload("es-ES", withBuildsOnDisk: ["latin", "multilingual"]))
    }

    /// With nothing on disk the row already says "not downloaded" and offers a
    /// Download button. A second download notice beside it would bury the one
    /// case that actually catches people out.
    func testNoWarningWhenTheEngineIsNotDownloadedAtAll() {
        XCTAssertFalse(needsDownload("ja-JP", withBuildsOnDisk: []))
        XCTAssertFalse(needsDownload("en-US", withBuildsOnDisk: []))
    }

    /// Apple Speech has one asset set, managed by the OS, and the row reports
    /// its state in the system's own terms. Nothing here to warn about.
    func testAppleSpeechIsNeverWarnedAbout() {
        XCTAssertFalse(needsDownload("ja-JP", withBuildsOnDisk: ["latin"], model: .appleSpeech))
        XCTAssertFalse(needsDownload("ja-JP", withBuildsOnDisk: [], model: .appleSpeech))
    }

    // MARK: - Reloading the running engine

    /// `ModelLoader.activate` early-returns when the model is already active, so
    /// a language change on the running engine needs its own path — without it
    /// the user switches to Portuguese and keeps dictating in English until
    /// they quit.
    func testChangingTheActiveModelsLanguageReloads() {
        XCTAssertTrue(ModelLoader.languageChangeNeedsReload(
            changed: .nemotronMultilingual,
            activeModel: .nemotronMultilingual,
            isModelReady: true))
        XCTAssertTrue(ModelLoader.languageChangeNeedsReload(
            changed: .appleSpeech, activeModel: .appleSpeech, isModelReady: true))
    }

    /// Every other engine reads the preference on its way up. Reloading for one
    /// the user is not running would download and warm a model to serve nobody.
    func testChangingAnIdleModelsLanguageDoesNotReload() {
        XCTAssertFalse(ModelLoader.languageChangeNeedsReload(
            changed: .nemotronMultilingual,
            activeModel: .parakeetUnified,
            isModelReady: true))
        XCTAssertFalse(ModelLoader.languageChangeNeedsReload(
            changed: .appleSpeech,
            activeModel: .nemotronMultilingual,
            isModelReady: true))
    }

    /// Nothing is loaded during startup or after a delete, and there is nothing
    /// to reload — the pending activation will read the new preference itself.
    func testNoReloadWhileNoModelIsReady() {
        XCTAssertFalse(ModelLoader.languageChangeNeedsReload(
            changed: .nemotronMultilingual,
            activeModel: .nemotronMultilingual,
            isModelReady: false))
    }
}
