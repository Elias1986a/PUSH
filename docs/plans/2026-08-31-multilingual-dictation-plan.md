# Multilingual Dictation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let the user dictate in a language they explicitly choose, without touching the English engines that are PUSH's core competency.

**Architecture:** Add one new engine — FluidAudio's `StreamingNemotronMultilingualAsrManager` — as a peer of the existing Parakeet engines, and give it plus Apple Speech an explicit language selector. Each engine publishes *its own* language list, sourced from the model itself (Nemotron's `promptDictionary`, Apple's `supportedLocales`), so no global union list exists and no hardcoded list can drift. Language is an explicit user choice; auto-detection is never consulted. English post-processing (`TextProcessing` number words, `capitalizeI`, `ContextGate` entity triggers) is gated off when the active language is not English.

**Tech Stack:** Swift 6, SwiftPM executable target, FluidAudio 0.15.5 (pinned at revision `19600a48`), CoreML/ANE, SwiftUI, XCTest.

---

## Critical Context for the Implementer

Read this before Task 1. These are non-obvious and each one has cost this project a release before.

### Do NOT create a git worktree

The writing-plans skill normally asks for one. **PUSH is an exception.** `git worktree` checkouts of this repo fail `swift build` with a bogus "couldn't be saved" error — an Xcode-beta SwiftPM manifest cache bug, not iCloud. Work in the main checkout at `/Users/kingpin/Documents/GitHub/PUSH` and commit directly to `main`. No feature branch, no PR. This is the established convention here.

### `.build` is a symlink — do not replace it

`.build` points at `~/Library/Developer/SwiftPackages/PUSH-build`. iCloud evicts files under `~/Documents` and hangs `read()` during `swift build`. If you break the symlink, builds hang.

### Never log transcript text

`PushLogger` events are operational only. Logging what the user dictated is a privacy violation. This applies doubly here — do not log the detected language alongside text.

### Only `ModelLoader` activates engines

Do not call `loadModel()` on an engine directly from app code. `AppState.activeModel` is what is actually serving; `selectedWhisperModel` is the persisted preference. Route everything through `ModelLoader`.

### Do not ask the user to read text aloud

The user finds reading difficult — it is why PUSH exists. Every test in this plan uses `/usr/bin/say` synthesis or a pre-recorded corpus. The only human-in-the-loop test is natural dictation in a language they already speak. See Task 12.

### The facts this plan is built on (verified in source, not assumed)

| Claim | Where |
|---|---|
| `parakeet-unified-en-0.6b` and `nemotron-speech-streaming-en-0.6b` are English-only | `ModelNames.swift:24-31` |
| TDT v3's `language:` param is a *script* filter (Latin/Cyrillic/Greek only), useless between es/fr/de | `TokenLanguageFilter.swift:39` |
| Nemotron Multilingual has real per-language conditioning via encoder `prompt_id` | `StreamingNemotronMultilingualAsrManager.swift:264` |
| ...plus optional Whisper-style forced-prefix decoder seeding | same file, `:283` |
| Its language list is `config.promptDictionary: [String: Int]`, read from the model's `metadata.json` | `NemotronMultilingualStreamingConfig.swift:43` |
| It ships two vocabs: `latin` (en/es/fr/it/pt/de) and `multilingual` (full 13k, incl. zh/ja) | `...+Shared.swift:324` |
| `EngineComparison.run(audio: Data, ...)` is not mic-coupled | `compare/Sources/compare/EngineComparison.swift:58` |

Paths above under `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/` unless noted.

### Scope note: TDT v3 is deliberately NOT shipped

v3 is a *benchmark contestant* only (Task 11). It is not given a language dropdown, because its `language:` parameter cannot distinguish Spanish from French — both are Latin script. Shipping a 22-entry dropdown where 22 entries behave identically would be a lie to the user.

---

## Task 0: Establish the baseline

**Files:** none (verification only)

**Step 1: Confirm a clean tree**

```bash
git -C /Users/kingpin/Documents/GitHub/PUSH status --short
```

Expected: no output. If there are changes, stop and ask.

**Step 2: Confirm the build is green before you touch anything**

```bash
swift build 2>&1 | tail -20
```

Expected: `Build complete!`. If it fails, stop — you are not debugging a pre-existing break as part of this feature.

**Step 3: Confirm tests pass**

```bash
swift test 2>&1 | tail -20
```

Expected: all tests pass. Record the count; you will compare against it later.

**Step 4: Confirm the `.build` symlink is intact**

```bash
ls -ld /Users/kingpin/Documents/GitHub/PUSH/.build
```

Expected: a symlink pointing into `~/Library/Developer/SwiftPackages/PUSH-build`.

No commit for this task.

---

## Task 1: The `DictationLanguage` value type

A language is a BCP-47-ish code plus a display name. It must be `Sendable` (crosses actor boundaries into engines) and sortable for the UI.

**Files:**
- Create: `PUSHCore/DictationLanguage.swift`
- Test: `Tests/PUSHTests/DictationLanguageTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import PUSHCore

final class DictationLanguageTests: XCTestCase {

    /// The display name comes from the OS, not a table we maintain — a
    /// hardcoded list is the thing this type exists to avoid.
    func testDisplayNameIsLocalizedFromCode() {
        let pt = DictationLanguage(code: "pt-BR")
        XCTAssertTrue(pt.displayName.contains("Portuguese"), "got \(pt.displayName)")
    }

    /// Sorting is by display name so the picker reads alphabetically to a human,
    /// not by raw code (which would put "de" before "en" before "es" — fine by
    /// accident in that case, wrong as soon as codes and names diverge).
    func testSortsByDisplayName() {
        let sorted = [DictationLanguage(code: "fr-FR"),
                      DictationLanguage(code: "de-DE"),
                      DictationLanguage(code: "es-ES")].sorted()
        XCTAssertEqual(sorted.map(\.code), ["fr-FR", "de-DE", "es-ES"].sorted {
            Locale.current.localizedString(forIdentifier: $0)! <
            Locale.current.localizedString(forIdentifier: $1)!
        })
    }

    /// English is special-cased downstream (post-processing is English-only),
    /// so the test pins the predicate rather than leaving it implicit.
    func testIsEnglishRecognisesRegionalVariants() {
        XCTAssertTrue(DictationLanguage(code: "en-US").isEnglish)
        XCTAssertTrue(DictationLanguage(code: "en").isEnglish)
        XCTAssertFalse(DictationLanguage(code: "es-ES").isEnglish)
    }
}
```

**Step 2: Run it and watch it fail**

```bash
swift test --filter DictationLanguageTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'DictationLanguage' in scope`.

**Step 3: Write the minimal implementation**

```swift
import Foundation

/// A language a user can choose to dictate in.
///
/// Deliberately a thin wrapper over a code rather than an enum of languages:
/// the set of supported languages is a property of each *model*, discovered at
/// runtime (Nemotron reads its own `metadata.json`; Apple queries
/// `SpeechTranscriber.supportedLocales`). An enum here would be a second list
/// to maintain and a guaranteed source of drift.
public struct DictationLanguage: Sendable, Hashable, Identifiable, Comparable {
    /// BCP-47 code as the model reports it, e.g. "en-US", "pt-BR", "es".
    public let code: String

    public init(code: String) { self.code = code }

    public var id: String { code }

    /// Human-readable name in the user's own locale, from the OS.
    public var displayName: String {
        Locale.current.localizedString(forIdentifier: code)
            ?? Locale.current.localizedString(forLanguageCode: String(code.prefix(2)))
            ?? code
    }

    /// English gets post-processing (number words, "i" → "I", the entity gate)
    /// that is meaningless or harmful in other languages. See Task 8.
    public var isEnglish: Bool { code.lowercased().hasPrefix("en") }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}
```

**Step 4: Run the test and watch it pass**

```bash
swift test --filter DictationLanguageTests 2>&1 | tail -20
```

Expected: PASS, 3 tests.

**Step 5: Commit**

```bash
git add PUSHCore/DictationLanguage.swift Tests/PUSHTests/DictationLanguageTests.swift
git commit -m "Add DictationLanguage, a code + OS-supplied display name

Deliberately not an enum: the supported set is a property of each model,
read at runtime, so a compile-time list would only ever drift."
```

---

## Task 2: Add the `.nemotronMultilingual` case to `WhisperModel`

**Files:**
- Modify: `PUSHCore/WhisperModel.swift`
- Test: `Tests/PUSHTests/WhisperModelTests.swift` (create)

**Step 1: Write the failing test**

```swift
import XCTest
@testable import PUSHCore

final class WhisperModelTests: XCTestCase {

    /// The raw value is a persistence key in UserDefaults. Changing it silently
    /// resets every existing user's engine choice — `parakeetV2`'s comment says
    /// exactly this. Pin it.
    func testRawValueIsStableForPersistence() {
        XCTAssertEqual(WhisperModel.nemotronMultilingual.rawValue, "nemotron-multilingual")
    }

    /// Only the multilingual engines take a language; the English ones must not
    /// grow a picker.
    func testOnlyMultilingualEnginesAcceptALanguage() {
        XCTAssertTrue(WhisperModel.nemotronMultilingual.supportsLanguageSelection)
        XCTAssertTrue(WhisperModel.appleSpeech.supportsLanguageSelection)
        XCTAssertFalse(WhisperModel.parakeetUnified.supportsLanguageSelection)
        XCTAssertFalse(WhisperModel.parakeetStreaming.supportsLanguageSelection)
        XCTAssertFalse(WhisperModel.parakeetV2.supportsLanguageSelection)
    }

    /// Every case must be reachable from the settings list on a supported OS,
    /// or it can be chosen by a stale preference and never un-chosen.
    func testMultilingualEngineIsSelectable() {
        XCTAssertTrue(WhisperModel.selectable.contains(.nemotronMultilingual))
    }
}
```

**Step 2: Run it and watch it fail**

```bash
swift test --filter WhisperModelTests 2>&1 | tail -20
```

Expected: FAIL — `type 'WhisperModel' has no member 'nemotronMultilingual'`.

**Step 3: Implement**

In `PUSHCore/WhisperModel.swift`, add the case and fill in every `switch`. The compiler will list them — Swift's exhaustive switching is doing the checklist for you here. Add:

```swift
case nemotronMultilingual = "nemotron-multilingual"
```

Then, in order through the file:

- `selectable`: insert `.nemotronMultilingual` after `.parakeetStreaming` in the `order` array, and add it to the `.parakeet, .parakeetUnified, .parakeetStreaming` arm of the `engineType` switch (i.e. return `true`).
- `displayName`: `"Nemotron Multilingual — Other languages"`
- `shortName`: `"Nemotron Multilingual"`
- `badge`: `"Multilingual"`
- `downloadSizeLabel`: `"600 MB"`
- `modelDescription`: `"Streams like Parakeet Streaming, in the language you pick. Downloads one model per language group."`
- `engineType`: `.nemotronMultilingual` (add the case to the `EngineType` enum too)
- `hasNativePunctuation`: add to the existing `true` arm

And add the new property:

```swift
/// Whether this engine takes an explicit language, and so earns a picker in
/// Settings. The English engines never do — they are English-only by
/// construction (the HuggingFace repos are literally `-en-`), and Parakeet
/// TDT v3 is excluded on purpose: its `language:` parameter is a *script*
/// filter (Latin/Cyrillic/Greek), so it cannot tell Spanish from French and
/// a per-language picker for it would be decorative.
public var supportsLanguageSelection: Bool {
    switch self {
    case .nemotronMultilingual, .appleSpeech: return true
    case .parakeetV2, .parakeetUnified, .parakeetStreaming: return false
    }
}
```

**Step 4: Run the tests**

```bash
swift test --filter WhisperModelTests 2>&1 | tail -20
```

Expected: PASS, 3 tests.

**Step 5: Confirm nothing else broke**

```bash
swift build 2>&1 | tail -20
```

Expected: `Build complete!` — but if `ModelLoader` or `EngineComparison` now fail exhaustiveness, that is Task 4 and Task 9 respectively. Add a `fatalError("unimplemented — Task 4")` placeholder ONLY if needed to keep the build green, and remove it in that task.

**Step 6: Commit**

```bash
git add PUSHCore/WhisperModel.swift Tests/PUSHTests/WhisperModelTests.swift
git commit -m "Add the Nemotron Multilingual engine case

TDT v3 is deliberately not added: its language: parameter filters by
script, not language, so it cannot separate es from fr and a picker for
it would be decorative."
```

---

## Task 3: `NemotronMultilingualEngine` wrapper

Mirror `ParakeetUnifiedEngine` exactly — same actor shape, same lifecycle, same logging discipline. The one new thing is that `loadModel` takes a language, because the language decides *which model files get downloaded* (`latin/` vs `multilingual/`), not just a runtime flag.

**Files:**
- Create: `PUSHCore/ML/NemotronMultilingualEngine.swift`
- Test: `Tests/PUSHTests/NemotronMultilingualEngineTests.swift`

**Step 1: Write the failing test**

Model-dependent behavior can't run in CI without a 600 MB download, so follow `AppleSpeechSmokeTest`'s pattern: test the pure logic eagerly, and skip the model-dependent test when the model isn't present.

```swift
import XCTest
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

    /// "auto" must never reach the engine — this app always picks a language.
    /// If it somehow does, fall back to English rather than enabling detection.
    func testAutoIsRejectedInFavourOfExplicitEnglish() {
        XCTAssertEqual(NemotronMultilingualEngine.vocabVariant(for: "auto"), "latin")
    }

    /// The language list must come from the loaded model, never a constant.
    func testSupportedLanguagesIsEmptyUntilTheModelIsLoaded() async {
        let languages = await NemotronMultilingualEngine.shared.supportedLanguages()
        if !NemotronMultilingualEngine.isModelDownloaded() {
            XCTAssertTrue(languages.isEmpty,
                          "no model on disk means no list — never a hardcoded fallback")
        }
    }
}
```

**Step 2: Run it and watch it fail**

```bash
swift test --filter NemotronMultilingualEngineTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'NemotronMultilingualEngine' in scope`.

**Step 3: Implement**

```swift
import Foundation
import FluidAudio

/// Wrapper for FluidAudio's Nemotron 3.5 ASR Streaming Multilingual 0.6B.
///
/// This is the only engine PUSH ships that transcribes a language other than
/// English. It is cache-aware streaming, like `ParakeetStreamingEngine` — the
/// multilingual option does *not* cost the user the streaming behaviour.
///
/// The language is always explicit. `setLanguage(_:)` sets the encoder's
/// `prompt_id` and `setForcedPrefix(true)` additionally seeds the decoder with
/// the language-tag token, which is as close to "transcribe this as Portuguese"
/// as the model offers. `detectedLanguage()` exists and is deliberately never
/// called: auto-detection is not a feature of this app.
public actor NemotronMultilingualEngine {
    public static let shared = NemotronMultilingualEngine()

    private var manager: StreamingNemotronMultilingualAsrManager?
    private var loadedLanguage: String?
    private var isLoaded = false

    private init() {}

    // MARK: - Vocab routing

    /// Which of the repo's two model builds serves a language.
    ///
    /// Mirrors `StreamingNemotronMultilingualAsrManager.languageDirectory(for:)`.
    /// Duplicated rather than called because that helper takes "auto" to mean
    /// the full vocab, and this app never wants "auto" — an unrecognised code
    /// here means a bug upstream of us, and English is the safe landing.
    public nonisolated static func vocabVariant(for languageCode: String) -> String {
        let c = languageCode.lowercased()
        if c == "auto" { return "latin" }
        let latinPrefixes = ["en", "es", "fr", "it", "pt", "de"]
        return latinPrefixes.contains(where: { c.hasPrefix($0) }) ? "latin" : "multilingual"
    }

    /// Chunk tier. 2240ms is FluidAudio's default and the highest-throughput
    /// tier; revisit only if the bake-off says a lower tier feels better.
    private static let chunkMs = 2240

    // MARK: - Model storage

    public nonisolated static func modelDirectory(for languageCode: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
            .appendingPathComponent(Repo.nemotronMultilingual.folderName, isDirectory: true)
            .appendingPathComponent(vocabVariant(for: languageCode), isDirectory: true)
            .appendingPathComponent("\(chunkMs)ms", isDirectory: true)
    }

    /// True when *any* variant is on disk. The settings row needs one answer,
    /// and "downloaded" for this engine means "at least one language is ready".
    public nonisolated static func isModelDownloaded() -> Bool {
        ["latin", "multilingual"].contains { variant in
            let dir = modelDirectory(for: variant == "latin" ? "en" : "zh")
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return contents.contains { $0.hasSuffix(".mlmodelc") }
        }
    }

    public nonisolated static func deleteModel() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let root = appSupport
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
            .appendingPathComponent(Repo.nemotronMultilingual.folderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
            PushLogger.log("NemotronMultilingualEngine: Models deleted")
        }
    }

    // MARK: - Languages

    /// The languages this model actually supports, read from the model's own
    /// `metadata.json` prompt dictionary. Empty until a model is loaded — there
    /// is deliberately no hardcoded fallback, because a fallback list that
    /// disagrees with the model is worse than no list.
    public func supportedLanguages() -> [DictationLanguage] {
        guard let manager else { return [] }
        return manager.configuration.promptDictionary.keys
            .filter { $0.lowercased() != "auto" }
            .map(DictationLanguage.init(code:))
            .sorted()
    }

    // MARK: - Lifecycle

    /// Load the variant serving `languageCode`, downloading it if needed.
    ///
    /// Switching to a language in the other vocab group is a genuine model
    /// swap, so an already-loaded engine is torn down first.
    public func loadModel(languageCode: String) async throws {
        if isLoaded, let loadedLanguage,
           Self.vocabVariant(for: loadedLanguage) == Self.vocabVariant(for: languageCode) {
            await manager?.setLanguage(languageCode)
            self.loadedLanguage = languageCode
            return
        }
        if isLoaded { unloadModel() }

        PushLogger.log("NemotronMultilingualEngine: Loading \(Self.vocabVariant(for: languageCode)) variant...")

        do {
            let shared = try await StreamingNemotronMultilingualAsrManager
                .downloadAndPreloadShared(languageCode: languageCode, chunkMs: Self.chunkMs)
            let manager = StreamingNemotronMultilingualAsrManager()
            try await manager.loadModels(fromShared: shared)
            await manager.setLanguage(languageCode)
            await manager.setForcedPrefix(true)

            self.manager = manager
            self.loadedLanguage = languageCode
            isLoaded = true
            PushLogger.log("NemotronMultilingualEngine: ✅ Loaded")
        } catch {
            PushLogger.log("NemotronMultilingualEngine: ❌ Load failed: \(error)")
            throw ParakeetEngineError.loadFailed(error.localizedDescription)
        }
    }

    public func unloadModel() {
        manager = nil
        loadedLanguage = nil
        isLoaded = false
        PushLogger.log("NemotronMultilingualEngine: Model unloaded")
    }

    public func warmup(languageCode: String) async {
        let startTime = Date()
        do {
            try await loadModel(languageCode: languageCode)
            _ = try await transcribeFloats([Float](repeating: 0.0, count: 16000))
            let elapsed = Date().timeIntervalSince(startTime)
            PushLogger.log(String(format: "NemotronMultilingualEngine: ✅ Warmup in %.2fs", elapsed))
        } catch {
            PushLogger.log("NemotronMultilingualEngine: Warmup failed: \(error)")
        }
    }

    // MARK: - Transcription

    public func transcribeFloats(_ samples: [Float]) async throws -> String {
        guard let manager else { throw ParakeetEngineError.loadFailed("not loaded") }
        let start = Date()
        try await manager.reset()
        let text = try await manager.process(samples: samples)
        _ = text
        let final = try await manager.finish()
        PushLogger.log(String(format: "NemotronMultilingualEngine: Transcribed %.2fs audio in %.3fs",
                              Double(samples.count) / 16000.0, Date().timeIntervalSince(start)))
        return final
    }
}
```

> **Implementer note:** the exact `loadModels(fromShared:)` spelling and
> `manager.configuration` accessor are the two things to verify against the
> checkout before writing — read
> `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager+Shared.swift`
> for the real preload signature and adjust. Everything else above is settled.
> Do NOT invent an API; read it.

**Step 4: Run the tests**

```bash
swift test --filter NemotronMultilingualEngineTests 2>&1 | tail -20
```

Expected: PASS, 4 tests.

**Step 5: Commit**

```bash
git add PUSHCore/ML/NemotronMultilingualEngine.swift Tests/PUSHTests/NemotronMultilingualEngineTests.swift
git commit -m "Add NemotronMultilingualEngine

Explicit language only: setLanguage sets the encoder prompt_id and
forced-prefix seeds the decoder with the lang tag. detectedLanguage()
is never called."
```

---

## Task 4: Route the new engine through `ModelLoader`

**Files:**
- Modify: `PUSH/Core/ModelLoader.swift` (the `load`, `unload`, `warmup` switches at `:90`, `:112`, `:122`)

**Step 1: Add the cases**

The engine needs a language, and `ModelLoader` takes only a model. Read the current language off `AppState` at the call site — it is `@MainActor`, so hop deliberately:

```swift
// in load(_:)
case .nemotronMultilingual:
    let code = await MainActor.run { AppState.shared.language(for: .nemotronMultilingual).code }
    try await NemotronMultilingualEngine.shared.loadModel(languageCode: code)
```

```swift
// in unload(_:)
case .nemotronMultilingual: await NemotronMultilingualEngine.shared.unloadModel()
```

```swift
// in warmup(_:)
case .nemotronMultilingual:
    let code = await MainActor.run { AppState.shared.language(for: .nemotronMultilingual).code }
    await NemotronMultilingualEngine.shared.warmup(languageCode: code)
```

`AppState.language(for:)` lands in Task 6 — if you are doing this task first, stub it returning `DictationLanguage(code: "en-US")` and finish it there.

**Step 2: Verify the build**

```bash
swift build 2>&1 | tail -20
```

Expected: `Build complete!`, and no remaining `fatalError("unimplemented")` from Task 2.

**Step 3: Confirm the main thread is not blocked**

Blocking the main thread makes macOS silently disable the CGEvent tap and drop hotkey presses — this has been the root cause of several unrelated-looking bugs here. `MainActor.run` reading one property is fine; anything longer is not.

Re-read your diff and confirm no `await MainActor.run` block does I/O or model work.

**Step 4: Commit**

```bash
git add PUSH/Core/ModelLoader.swift
git commit -m "Route the multilingual engine through ModelLoader"
```

---

## Task 5: Give Apple Speech an explicit language

Today `AppleSpeechEngine.resolveLocale()` guesses: user's locale, else en-US. That guess becomes the fallback, and an explicit preference wins.

**Files:**
- Modify: `PUSHCore/ML/AppleSpeechEngine.swift:42-51`
- Test: `Tests/PUSHTests/AppleSpeechLanguageTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import PUSHCore

final class AppleSpeechLanguageTests: XCTestCase {

    /// The list must come from the OS, and must not be empty on a supported
    /// system — an empty list would silently present an empty picker.
    func testSupportedLanguagesComeFromTheSystem() async throws {
        guard #available(macOS 26, *), AppleSpeechEngine.isSupported else {
            throw XCTSkip("Apple Speech needs macOS 26")
        }
        let languages = await AppleSpeechEngine.supportedLanguages()
        XCTAssertFalse(languages.isEmpty)
        XCTAssertTrue(languages.contains { $0.isEnglish }, "en must always be offered")
    }

    /// Every offered language must actually resolve, or the picker can seat a
    /// choice that then fails to load.
    func testEveryOfferedLanguageResolves() async throws {
        guard #available(macOS 26, *), AppleSpeechEngine.isSupported else {
            throw XCTSkip("Apple Speech needs macOS 26")
        }
        for language in await AppleSpeechEngine.supportedLanguages().prefix(5) {
            let resolved = await AppleSpeechEngine.resolveLocale(preferred: language.code)
            XCTAssertNotNil(resolved, "\(language.code) was offered but does not resolve")
        }
    }
}
```

**Step 2: Run it and watch it fail**

```bash
swift test --filter AppleSpeechLanguageTests 2>&1 | tail -20
```

Expected: FAIL — no `supportedLanguages`.

**Step 3: Implement**

```swift
/// Languages this system's transcriber actually supports. Queried from the OS
/// rather than listed here, so it tracks whatever Apple ships.
@available(macOS 26, *)
public static func supportedLanguages() async -> [DictationLanguage] {
    await SpeechTranscriber.supportedLocales
        .map { DictationLanguage(code: $0.identifier(.bcp47)) }
        .sorted()
}

/// The locale to transcribe in: the user's explicit choice when it is
/// supported, then their system locale, then en-US. Returns nil only when the
/// transcriber supports none of the three — the one case the caller surfaces.
@available(macOS 26, *)
static func resolveLocale(preferred: String?) async -> Locale? {
    if let preferred,
       let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: preferred)) {
        return match
    }
    if let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
        return match
    }
    return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
}
```

Update the two existing `resolveLocale()` call sites (in `assetStatus` and `loadModel`) to pass the stored preference. Keep the no-argument form as `resolveLocale(preferred: nil)` if that reads better at a call site.

**Step 4: Run the tests**

```bash
swift test --filter AppleSpeechLanguageTests 2>&1 | tail -20
```

Expected: PASS or SKIP (skip is correct below macOS 26).

**Step 5: Commit**

```bash
git add PUSHCore/ML/AppleSpeechEngine.swift Tests/PUSHTests/AppleSpeechLanguageTests.swift
git commit -m "Let Apple Speech take an explicit language

The old locale guess becomes the fallback behind an explicit choice."
```

---

## Task 6: Persist the language per engine

Two engines, two different language lists — so two independent preferences. One shared key would seat an unsupported language whenever the user switches engines.

**Files:**
- Modify: `PUSH/App/AppState.swift` (`UserDefaultsKeys` at `:12`, plus new accessors)
- Test: `Tests/PUSHTests/LanguagePreferenceTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import PUSH
@testable import PUSHCore

final class LanguagePreferenceTests: XCTestCase {

    /// Independent keys: choosing Portuguese on Nemotron must not silently
    /// change what Apple Speech will use, since the two lists differ.
    func testEachEngineStoresItsOwnLanguage() {
        let state = AppState.shared
        state.setLanguage(DictationLanguage(code: "pt-BR"), for: .nemotronMultilingual)
        state.setLanguage(DictationLanguage(code: "fr-FR"), for: .appleSpeech)

        XCTAssertEqual(state.language(for: .nemotronMultilingual).code, "pt-BR")
        XCTAssertEqual(state.language(for: .appleSpeech).code, "fr-FR")
    }

    /// An engine with no stored choice yet must default to English, not to the
    /// system locale — the English engines are the product's core and a fresh
    /// install should behave identically to today.
    func testDefaultsToEnglish() {
        UserDefaults.standard.removeObject(forKey: "language.nemotron-multilingual")
        XCTAssertTrue(AppState.shared.language(for: .nemotronMultilingual).isEnglish)
    }
}
```

**Step 2: Run and watch it fail**

```bash
swift test --filter LanguagePreferenceTests 2>&1 | tail -20
```

**Step 3: Implement**

```swift
/// Language is stored per engine because each engine supports a different set.
/// A single shared key would seat an unsupported language the moment the user
/// switched engines.
func language(for model: WhisperModel) -> DictationLanguage {
    let stored = UserDefaults.standard.string(forKey: "language.\(model.rawValue)")
    return DictationLanguage(code: stored ?? "en-US")
}

func setLanguage(_ language: DictationLanguage, for model: WhisperModel) {
    UserDefaults.standard.set(language.code, forKey: "language.\(model.rawValue)")
    objectWillChange.send()
}
```

**Step 4: Run the tests**

```bash
swift test --filter LanguagePreferenceTests 2>&1 | tail -20
```

Expected: PASS, 2 tests.

**Step 5: Commit**

```bash
git add PUSH/App/AppState.swift Tests/PUSHTests/LanguagePreferenceTests.swift
git commit -m "Store the dictation language per engine

One shared key would seat an unsupported language on engine switch."
```

---

## Task 7: The language picker in Settings

**Files:**
- Modify: `PUSH/Views/SettingsView.swift` (the model list `ForEach` at `:489`, description row at `:553`)

**Step 1: Add the picker**

Show it only under the *selected* engine, and only when that engine takes a language. A picker under every row is noise; a picker for the English engines is a lie.

```swift
if model.supportsLanguageSelection && appState.selectedWhisperModel == model {
    Picker("Language", selection: Binding(
        get: { appState.language(for: model) },
        set: { appState.setLanguage($0, for: model) }
    )) {
        ForEach(availableLanguages(for: model)) { language in
            Text(language.displayName).tag(language)
        }
    }
    .pickerStyle(.menu)
    .disabled(availableLanguages(for: model).isEmpty)
}
```

**Step 2: Source each list from its own engine**

```swift
/// Each engine's own list — never a union. Nemotron reads its model's
/// prompt dictionary; Apple queries the system. An engine whose model is not
/// downloaded yet reports nothing, and the picker disables rather than
/// offering languages that cannot load.
@State private var languageLists: [WhisperModel: [DictationLanguage]] = [:]

private func availableLanguages(for model: WhisperModel) -> [DictationLanguage] {
    languageLists[model] ?? []
}

private func refreshLanguages(for model: WhisperModel) async {
    switch model {
    case .nemotronMultilingual:
        languageLists[model] = await NemotronMultilingualEngine.shared.supportedLanguages()
    case .appleSpeech:
        if #available(macOS 26, *) {
            languageLists[model] = await AppleSpeechEngine.supportedLanguages()
        }
    default:
        break
    }
}
```

Call `refreshLanguages(for:)` from a `.task` on the row, and again after a model download completes.

**Step 3: Handle the empty case honestly**

When Nemotron has no model on disk, its list is empty and the picker is disabled. Add a caption under it:

```swift
if availableLanguages(for: model).isEmpty && model == .nemotronMultilingual {
    Text("Download the model to see its languages.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**Step 4: Build**

```bash
swift build 2>&1 | tail -20
```

**Step 5: Verify visually — ASK FIRST**

Launching PUSH takes over the screen. **Ask the user before launching**, batch every capture into one run, and quit the app afterwards. Check the picker appears only under the selected multilingual engine, and not at all under Unified/Streaming/v2.

**Step 6: Commit**

```bash
git add PUSH/Views/SettingsView.swift
git commit -m "Add a per-engine language picker

Shown only under the selected engine, and only for engines that take a
language. Each list comes from that engine, never a union."
```

---

## Task 8: Gate English-only post-processing

This is the open design question, and here is its answer.

`TextProcessing` does several things that are English-specific: `capitalizeI` ("i" → "I"), spoken-number conversion ("twenty five" → 25), English connector handling ("two hundred **and** five"), and `NLTagger(.lexicalClass)` tagging tuned for English. `ContextGate.entityTriggers` is a hardcoded set of English words ("to", "from", "dear", "thanks"…).

**The decision:** when the active language is not English, skip all of it. Apply only language-neutral processing (whitespace normalisation, the user's literal `always` dictionary replacements). The `ContextGate` heuristic simply never fires — and because its contract is already "on any uncertainty return `.keep`", that is a no-op path, not a new risk.

**Files:**
- Modify: `PUSHCore/TextProcessing.swift`
- Modify: `PUSH/Core/ContextGate.swift`
- Modify: `PUSH/Core/TranscriptionPipeline+App.swift` (pass the language in)
- Test: `Tests/PUSHTests/TextProcessingTests.swift` (extend)

**Step 1: Write the failing tests**

```swift
/// Spoken-number conversion is English arithmetic. "vinte e cinco" is not
/// "twenty five", and running the English path over Portuguese can only damage
/// a correct transcript.
func testNumberConversionIsSkippedForNonEnglish() {
    let pt = TextProcessing.process("vinte e cinco", language: DictationLanguage(code: "pt-BR"))
    XCTAssertEqual(pt, "vinte e cinco")
}

/// The standalone "i" → "I" rule is English orthography. In Italian "i" is a
/// definite article and capitalising it is a straightforward corruption.
func testCapitalizeIIsSkippedForNonEnglish() {
    let it = TextProcessing.process("i cani", language: DictationLanguage(code: "it-IT"))
    XCTAssertEqual(it, "I cani".replacingOccurrences(of: "I ", with: "i "),
                   "the article must stay lowercase")
}

/// English behaviour must be bit-identical to before this feature.
func testEnglishPathIsUnchanged() {
    let before = TextProcessing.process("i have twenty five apples")
    let after = TextProcessing.process("i have twenty five apples",
                                       language: DictationLanguage(code: "en-US"))
    XCTAssertEqual(before, after)
}
```

**Step 2: Run and watch them fail**

```bash
swift test --filter TextProcessingTests 2>&1 | tail -20
```

**Step 3: Implement**

Add a `language:` parameter defaulting to English so every existing call site compiles and behaves identically:

```swift
public static func process(_ text: String,
                           language: DictationLanguage = DictationLanguage(code: "en-US")) -> String {
    var out = normalizeWhitespace(text)
    guard language.isEnglish else {
        // Everything below this line encodes English orthography or English
        // number grammar. Running it over another language can only corrupt a
        // correct transcript, so non-English gets the neutral path only.
        return out
    }
    out = capitalizeI(out)
    // ...existing English chain unchanged...
    return out
}
```

In `ContextGate`, add the same guard at the top of `entityLikely`:

```swift
// The trigger words are English. In another language they either never match
// (harmless but pointless) or match a false friend (harmful). The gate's
// contract is fail-safe — not firing means .keep, which is the safe verdict.
guard language.isEnglish else { return false }
```

Thread the active language from `TranscriptionPipeline+App` into both.

**Step 4: Run the tests**

```bash
swift test --filter TextProcessingTests 2>&1 | tail -20
swift test 2>&1 | tail -20
```

Expected: all pass, and the total count is the Task 0 baseline plus everything added since.

**Step 5: Commit**

```bash
git add PUSHCore/TextProcessing.swift PUSH/Core/ContextGate.swift PUSH/Core/TranscriptionPipeline+App.swift Tests/PUSHTests/TextProcessingTests.swift
git commit -m "Skip English-only post-processing in other languages

Number words, capitalizeI and the entity gate all encode English. The
gate's fail-safe contract means not firing is already the safe verdict."
```

---

# Benchmarking

The user's bar is "as many languages as we can that feel stable." Only Brazilian Portuguese, basic Spanish and basic French are spoken in their house — so "feel" cannot be the judge for every language, and nobody is going to be handed a script to read.

Three tiers. A language ships only if it clears the tier that applies to it.

| Tier | Audio source | Judges | Covers |
|---|---|---|---|
| 1 · Smoke | `/usr/bin/say` synthesis | automated | every candidate language |
| 2 · WER | public corpus w/ reference transcripts | automated | every candidate language |
| 3 · Feel | the user dictating naturally | the user | pt-BR, es, fr only |

Tier 1 catches "this language is outright broken." Tier 2 ranks engines honestly. Tier 3 is the only tier that decides what ships in the three languages that can be judged properly — consistent with how every engine change in this project has been decided.

**On "faking it with a recording":** the instinct is right, but do NOT play audio through speakers into the microphone. That adds room acoustics that dictation (a close-talk scenario) never has, and it penalises engines unevenly. Feed the audio into `compare/` as a file instead — same idea, none of the contamination, and reproducible.

**On synthetic speech:** `say` output is unrealistically clean and flatters every ASR engine. It is sufficient to prove a language is *not broken*; it is not evidence about accuracy. Never rank engines on Tier 1 alone.

---

## Task 9: Teach `compare/` to read a WAV file

`EngineComparison.run(audio: Data, ...)` already takes raw sample data — it is not mic-coupled. Only the UI assumes a recording.

**Files:**
- Create: `compare/Sources/compare/AudioFileLoader.swift`
- Modify: `compare/Sources/compare/ComparisonView.swift`

**Step 1: Write the loader**

```swift
import AVFoundation

/// Loads a WAV/AIFF/M4A file as the same 16 kHz mono float `Data` the Recorder
/// produces, so a file and a live recording are interchangeable inputs to
/// `EngineComparison.run`.
enum AudioFileLoader {
    static func load(_ url: URL) throws -> Data {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let output = AVAudioPCMBuffer(pcmFormat: target,
                                            frameCapacity: AVAudioFrameCount(
                                                Double(file.length) * 16000 / file.processingFormat.sampleRate) + 1024)
        else { throw CocoaError(.fileReadCorruptFile) }

        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                     frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }

        return Data(bytes: output.floatChannelData![0],
                    count: Int(output.frameLength) * MemoryLayout<Float>.size)
    }
}
```

**Step 2: Add a file picker to the compare UI**

An "Open audio file…" button beside the record button, feeding the same `EngineComparison.run`.

**Step 3: Build and verify**

```bash
./compare/build_compare.sh 2>&1 | tail -20
```

**Step 4: Commit**

```bash
git add compare/Sources/compare/AudioFileLoader.swift compare/Sources/compare/ComparisonView.swift
git commit -m "compare: accept an audio file, not just the microphone

Makes a benchmark run reproducible, and lets languages nobody here speaks
be tested from a corpus instead of read aloud."
```

---

## Task 10: Register the multilingual engines in `compare/`

**Files:**
- Modify: `compare/Sources/compare/EngineComparison.swift` (three switches at `:45`, `:131`, `:161`)

Add `.nemotronMultilingual` to the availability, warmup and load switches, mirroring the Parakeet cases. Add a language selector to the compare UI so a run is pinned to one language.

Keep the sequential execution — engines racing for the ANE contaminate each other's timings, and timings are half the point.

```bash
git add compare/Sources/compare/EngineComparison.swift
git commit -m "compare: register the multilingual engine and a language picker"
```

---

## Task 11: Tier 1 — synthesized smoke tests

**Files:**
- Create: `Tests/PUSHTests/MultilingualSmokeTests.swift`

Follow `AppleSpeechSmokeTest`'s existing pattern exactly — `/usr/bin/say -v <voice>` then `afconvert` to 16 kHz mono float WAV, skipping when synthesis is unavailable. `say` ships voices for German, Spanish, French, Italian, Portuguese, Japanese and Chinese, which covers the whole `latin` group plus CJK.

The assertion is deliberately weak, because synthetic audio cannot support a strong one:

```swift
/// Not an accuracy test — synthetic speech flatters every engine. This asserts
/// only that the language is not *broken*: the engine loads, returns non-empty
/// text, and returns it in the right script. A language that fails here never
/// reaches tier 2.
func testEachLanguageProducesPlausibleText() async throws { ... }
```

Assert: non-empty result, and the output's Unicode script matches the language's expected script (reuse the Latin/Cyrillic/Greek partition idea from `TokenLanguageFilter`). Do not assert on exact words.

```bash
git add Tests/PUSHTests/MultilingualSmokeTests.swift
git commit -m "Add synthesized per-language smoke tests

Asserts the language is not broken, not that it is accurate — synthetic
speech is too clean to support an accuracy claim."
```

---

## Task 12: Tier 2 and Tier 3 — the actual bake-off

**Files:**
- Create: `docs/plans/2026-08-31-multilingual-results.md` (results log)

**Tier 2 — corpus WER (automated, every candidate language):**

1. Fetch a small fixed set of clips per language from a public corpus that ships reference transcripts (FLEURS or Common Voice). Keep them out of git — note the exact clip IDs in the results doc so a run is reproducible.
2. Run each clip through `compare/` file input against: Nemotron Multilingual (correct language selected), Apple Speech (same), Parakeet TDT v3, SenseVoiceSmall, and for zh/ja the dedicated `paraformer-large-zh` / `parakeet-0.6b-ja`.
3. Record WER and wall-clock per engine per language.

**Tier 3 — feel (pt-BR, es, fr only):**

The user dictates naturally — their own words, their own phrasing, the way they actually use PUSH. No script. Ship the candidates as a togglable choice in the app first so the comparison happens in real use rather than in a test harness; that is how every engine decision in this project has been made.

**The shipping rule:**

- pt-BR / es / fr → ship if Tier 3 says it feels right. Tier 2 informs, it does not decide.
- Every other language → ship only if it clears Tier 1 *and* its Tier 2 WER is within a stated margin of the best engine for that language. Write the margin down in the results doc before running, not after.
- A language that clears nothing does not appear in the picker.

Record everything in the results doc, including languages that were rejected and why. A silent omission reads as "not tested."

```bash
git add docs/plans/2026-08-31-multilingual-results.md
git commit -m "Record the multilingual bake-off protocol and results"
```

---

## Task 13: Refresh `docs/MODELS.md`

It is a year stale and actively wrong: it never mentions Nemotron Multilingual, SenseVoice, `paraformer-zh` or `parakeet-ja`, and its review log claims a v2→v3 change that `git log -S"version: .v3"` proves never landed.

- Correct the false 2026-06-30 log entry.
- Add the models found in the pinned checkout.
- Record why TDT v3 was evaluated and not shipped a language picker.
- Update "Last reviewed".

```bash
git add docs/MODELS.md
git commit -m "Refresh MODELS.md: correct a review-log entry that never landed"
```

---

## Verification Before Calling This Done

Do not claim completion until every line below has been run and its output seen:

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -5
./compare/build_compare.sh 2>&1 | tail -5
```

Then, in the app (ask before launching — it takes over the screen):

- [ ] English default is unchanged: fresh install still lands on Parakeet Unified, English, no picker visible
- [ ] The language picker appears only under the selected multilingual engine
- [ ] Choosing pt-BR downloads/loads the `latin` variant, and dictation works
- [ ] Switching to a CJK language swaps to the `multilingual` variant cleanly
- [ ] Hotkey press/release still works after an engine switch (the CGEvent tap is sensitive to main-thread blocking)
- [ ] No transcript text appears anywhere in the logs

Open questions deliberately left for after the bake-off, not before:

- Whether the `latin`/`multilingual` split becomes user-visible or stays an automatic consequence of the language chosen
- Whether the 2240ms chunk tier is the right default, or a lower-latency tier feels better
- Whether Nemotron Multilingual should ever become the default for a user whose system locale is not English
