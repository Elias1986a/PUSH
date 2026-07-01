# PUSH iOS Voice Keyboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an iOS custom keyboard that lets the user tap a key in any app, speak, and have on-device Parakeet transcription inserted inline — reusing PUSH's existing macOS transcription core.

**Architecture:** Extract PUSH's platform-agnostic transcription + text-formatting code into a local Swift package (`PushKit`) with two products: a tiny `PushShared` (formatting + IPC, linked by *both* the app and the keyboard extension) and a heavy `PushTranscription` (FluidAudio/Parakeet, linked by the **app only**). Build the iOS side as an Xcode project with an **app target** (owns the microphone + Parakeet, because a keyboard extension is hard-blocked from the mic and capped at ~48 MB) and a **keyboard-extension target** (UI + trigger + text insertion only). The two communicate through an **App Group** shared container (shared `UserDefaults` + Darwin notifications): the extension triggers dictation and foregrounds the app; the app records, transcribes on-device, and hands back the finished *text*; the extension inserts it via `UITextDocumentProxy`.

**Tech Stack:** Swift 6, SwiftPM (shared core), Xcode project (iOS app + `UIInputViewController` keyboard extension), FluidAudio (Parakeet TDT v2, CoreML/ANE), AVFoundation (`AVAudioSession`/`AVAudioEngine`), App Groups, Darwin notifications, XCTest.

**Why this order:** Milestone 0 delivers value immediately and independently — it de-duplicates the macOS app against a tested shared package with **zero behavior change**, verifiable with `swift test` before any iOS work exists. Each later milestone produces something runnable on a device.

---

## Feasibility basis (verified 2026-07-01, 3-0 adversarial confirmation)

These facts are load-bearing for the design. Do not "optimize" them away.

- A keyboard extension **cannot** access the microphone — OS/sandbox block, not a toggle; even with Full Access it fails at runtime (`CMSUtility_IsAllowedToStartRecording ... is an extension`). [Apple Custom Keyboard guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html), [Forum 742601](https://developer.apple.com/forums/thread/742601).
- The **containing app** may record and hand text to the keyboard. This is how Wispr Flow & Gboard ship voice typing. [TechCrunch](https://techcrunch.com/2017/02/23/googles-ios-keyboard-gets-the-one-feature-it-really-lacked-voice-typing/).
- Keyboard-extension memory ceiling ≈ **48 MB** ([RN #31910](https://github.com/facebook/react-native/issues/31910)); the Parakeet-v3 CoreML encoder alone is ~445 MB ([HF](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/main)). ⇒ Parakeet runs in the app, never the extension.
- FluidAudio supports iOS (`Package.swift` `.iOS(.v17)`, ANE). ⇒ On-device stays intact; PUSH can be the *private* alternative to cloud-only Wispr.
- App Store permits this pattern; `NSMicrophoneUsageDescription` is mandatory in the app; always-on mic invites Guideline 2.5.4 / 2.5.14 scrutiny + the permanent orange dot.

---

## File Structure

**New local package (repo root):**
```
PushKit/
  Package.swift                         # PushShared (no deps) + PushTranscription (FluidAudio)
  Sources/PushShared/
    TextFormatter.swift                 # pure text formatting (moved from TranscriptionPipeline)
    TranscriptCleaner.swift             # hallucination/beep/wake-word stripping (parameterized)
    DictationBridge.swift               # App Group IPC (UserDefaults + Darwin notifications)
    FlowSessionTimeout.swift            # session-persistence setting enum
    AppGroup.swift                      # single source of truth for the group id
  Sources/PushTranscription/
    ParakeetTranscriber.swift           # FluidAudio/Parakeet wrapper (moved from ParakeetEngine)
  Tests/PushSharedTests/
    TextFormatterTests.swift
    TranscriptCleanerTests.swift
    DictationBridgeTests.swift
```

**Existing macOS app (refactored to consume `PushShared`, no behavior change):**
```
Package.swift                           # add .package(path: "PushKit"); link PushShared + PushTranscription
PUSH/Core/TranscriptionPipeline.swift   # delete moved funcs; call TextFormatter/TranscriptCleaner
PUSH/ML/ParakeetEngine.swift            # thin shim over PushTranscription.ParakeetTranscriber (or delete)
```

**New iOS Xcode project:**
```
PushiOS/
  PushiOS.xcodeproj
  PushApp/                              # iOS app target (owns mic + Parakeet)
    PushAppApp.swift                    # @main App
    DictationController.swift           # AVAudioSession record → ParakeetTranscriber → DictationBridge
    FlowSessionManager.swift            # background-audio session lifetime per FlowSessionTimeout
    OnboardingView.swift                # enable keyboard, Full Access, mic permission walkthrough
    SettingsView.swift                  # timeout picker, model download/status
    Info.plist                          # NSMicrophoneUsageDescription, UIBackgroundModes (opt), URL scheme
    PushApp.entitlements                # App Group
  PushKeyboard/                         # keyboard extension target (NO FluidAudio)
    KeyboardViewController.swift        # UIInputViewController: mic button, trigger, insert text
    Info.plist                          # RequestsOpenAccess = YES
    PushKeyboard.entitlements           # App Group
```

**Dependency rule (enforced, load-bearing):** `PushKeyboard` links **only** `PushShared`. `PushApp` links `PushShared` **and** `PushTranscription`. If the extension ever imports `PushTranscription`/`FluidAudio`, it will jetsam at launch.

---

## Milestone 0 — Extract & test the shared core (no iOS yet)

*Outcome: `PushKit` package exists, `swift test` passes, macOS PUSH builds and behaves identically. Independently valuable even if iOS is never built.*

### Task 0.1: Create the PushKit package skeleton

**Files:**
- Create: `PushKit/Package.swift`
- Create: `PushKit/Sources/PushShared/AppGroup.swift`
- Create: `PushKit/Sources/PushTranscription/ParakeetTranscriber.swift` (placeholder compile stub, filled in 0.5)

- [ ] **Step 1: Write `PushKit/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PushKit",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "PushShared", targets: ["PushShared"]),
        .library(name: "PushTranscription", targets: ["PushTranscription"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.13.6"),
    ],
    targets: [
        .target(name: "PushShared"),
        .target(
            name: "PushTranscription",
            dependencies: [
                "PushShared",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(name: "PushSharedTests", dependencies: ["PushShared"]),
    ]
)
```

- [ ] **Step 2: Write `AppGroup.swift`** (single source of truth; the real id is chosen when the Apple Developer App Group is registered in Milestone 3)

```swift
import Foundation

public enum AppGroup {
    /// Must match the App Group capability on BOTH the iOS app and keyboard extension.
    public static let identifier = "group.com.push.shared"

    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
```

- [ ] **Step 3: Write a temporary compile stub** so `PushTranscription` builds before 0.5

`PushKit/Sources/PushTranscription/ParakeetTranscriber.swift`:
```swift
import Foundation
// Filled in Task 0.5. Placeholder keeps the target compiling.
public enum ParakeetTranscriberPlaceholder {}
```

- [ ] **Step 4: Verify the package resolves and builds**

Run: `cd PushKit && swift build`
Expected: `Build complete!` (FluidAudio resolves; no errors)

- [ ] **Step 5: Commit**

```bash
git add PushKit/Package.swift PushKit/Sources
git commit -m "feat(pushkit): scaffold shared PushKit package (PushShared + PushTranscription)"
```

### Task 0.2: Move pure text formatting into `TextFormatter` (characterization tests first)

**Files:**
- Create: `PushKit/Sources/PushShared/TextFormatter.swift`
- Create: `PushKit/Tests/PushSharedTests/TextFormatterTests.swift`
- Source of truth to move: `PUSH/Core/TranscriptionPipeline.swift:188-631` (all `private static` formatting funcs)

- [ ] **Step 1: Write failing characterization tests**

`TextFormatterTests.swift`:
```swift
import XCTest
@testable import PushShared

final class TextFormatterTests: XCTestCase {
    func testNormalizeCauseDropsLeadingApostrophe() {
        XCTAssertEqual(TextFormatter.normalizeCause("I left 'cause it rained"),
                       "I left cause it rained")
    }
    func testNumberWordsApStyle() {
        XCTAssertEqual(TextFormatter.normalizeNumberWords("twenty-five years"), "25 years")
        XCTAssertEqual(TextFormatter.normalizeNumberWords("five apples"), "five apples")
    }
    func testOrdinals() {
        XCTAssertEqual(TextFormatter.normalizeOrdinals("the twenty fifth"), "the 25th")
    }
    func testSmartSymbols() {
        XCTAssertEqual(TextFormatter.smartSymbols("50 percent"), "50%")
    }
    func testParakeetPipelineComposition() {
        // hasNativePunctuation = true path
        let out = TextFormatter.format("i saved 'cause it was fifty percent off",
                                       hasNativePunctuation: true)
        XCTAssertTrue(out.contains("cause"))
        XCTAssertTrue(out.contains("50%"))
        XCTAssertFalse(out.contains("'cause"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd PushKit && swift test --filter TextFormatterTests`
Expected: FAIL — `cannot find 'TextFormatter' in scope`

- [ ] **Step 3: Create `TextFormatter.swift` by moving the functions verbatim**

Create `PushKit/Sources/PushShared/TextFormatter.swift` with `public enum TextFormatter {`. Move — **verbatim, no logic changes** — every `static` formatting function and its supporting `static let` tables from `PUSH/Core/TranscriptionPipeline.swift:188-631`:
`fixCapitalization`, `capitalizeI`, `doubleSpaceAfterPeriods`, `removeFillerWords`, `removeStutteredWords`, `fixQuestionMarks`, `fixTrailingComma`, `ensureEndingPunctuation`, `smartSymbols`, `normalizeCause`, `baseNumberWords`, `numberWordPattern`, `decimalWordPattern`, `ordinalWords`, `ordinalWordPattern`, `parseNumberRun`, `normalizeDecimalDictation`, `normalizeNumberWords`, `ordinalSuffix`, `parseOrdinalRun`, `normalizeOrdinals`, `stripConnectingAnd`.

Change each `private static` → `public static` (the tests reach them; keep the `parse*`/pattern helpers `static` internal if you prefer — the tests only need the named transforms above). Then add the two composition entry points (new code, transcribed exactly from `TranscriptionPipeline.swift:118-166`):

```swift
extension TextFormatter {
    /// Compose the post-processing pipeline. Mirrors TranscriptionPipeline exactly.
    public static func format(_ text: String, hasNativePunctuation: Bool) -> String {
        if hasNativePunctuation {
            return doubleSpaceAfterPeriods(smartSymbols(normalizeNumberWords(
                normalizeDecimalDictation(normalizeOrdinals(stripConnectingAnd(
                    removeStutteredWords(removeFillerWords(normalizeCause(text)))))))))
        } else {
            return doubleSpaceAfterPeriods(capitalizeI(fixCapitalization(smartSymbols(
                fixQuestionMarks(ensureEndingPunctuation(fixTrailingComma(normalizeNumberWords(
                    normalizeDecimalDictation(normalizeOrdinals(stripConnectingAnd(
                        removeStutteredWords(removeFillerWords(normalizeCause(text)))))))))))))
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd PushKit && swift test --filter TextFormatterTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add PushKit/Sources/PushShared/TextFormatter.swift PushKit/Tests
git commit -m "feat(pushshared): extract TextFormatter with characterization tests"
```

### Task 0.3: Extract `TranscriptCleaner` (hallucination / beep / wake-word stripping)

**Files:**
- Create: `PushKit/Sources/PushShared/TranscriptCleaner.swift`
- Create: `PushKit/Tests/PushSharedTests/TranscriptCleanerTests.swift`
- Source of truth: `PUSH/Core/TranscriptionPipeline.swift:11-107` (hallucination sets + beep + wake-word logic)

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import PushShared

final class TranscriptCleanerTests: XCTestCase {
    func testDropsHallucinationOnly() {
        XCTAssertNil(TranscriptCleaner.clean("thank you so much", wakeWord: "", wakeWordEnabled: false))
        XCTAssertNil(TranscriptCleaner.clean("[BLANK_AUDIO]", wakeWord: "", wakeWordEnabled: false))
    }
    func testStripsBeepPrefix() {
        XCTAssertEqual(TranscriptCleaner.clean("beep, hello world", wakeWord: "", wakeWordEnabled: false),
                       "hello world")
    }
    func testStripsWakeWord() {
        XCTAssertEqual(TranscriptCleaner.clean("push send this note", wakeWord: "push", wakeWordEnabled: true),
                       "send this note")
    }
    func testKeepsNormalText() {
        XCTAssertEqual(TranscriptCleaner.clean("hello there", wakeWord: "", wakeWordEnabled: false),
                       "hello there")
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `cd PushKit && swift test --filter TranscriptCleanerTests`
Expected: FAIL — `cannot find 'TranscriptCleaner' in scope`

- [ ] **Step 3: Implement `TranscriptCleaner`**

Create `TranscriptCleaner.swift` with `public enum TranscriptCleaner`. Move the `hallucinationPhrases`/`hallucinationPrefixes` sets and the filtering + beep-strip + wake-word-strip logic from `TranscriptionPipeline.swift:44-107` into one pure function that returns `nil` when the result is "no speech":

```swift
import Foundation

public enum TranscriptCleaner {
    private static let hallucinationPhrases: Set<String> = [
        "subscribe", "like and subscribe", "see you next time", "bye",
        "goodbye", "you", "the end", "the end."
    ]
    private static let hallucinationPrefixes = ["thank you", "thanks for"]

    /// Returns cleaned speech, or nil if the input is silence/hallucination/only-wake-word.
    public static func clean(_ raw: String, wakeWord: String, wakeWordEnabled: Bool) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var lower = text.lowercased()
        if text.isEmpty || lower.contains("blank_audio") || lower.contains("blank audio")
            || lower.contains("silence") || hallucinationPhrases.contains(lower)
            || hallucinationPrefixes.contains(where: { lower.hasPrefix($0) })
            || (text.hasPrefix("(") && text.hasSuffix(")"))
            || (text.hasPrefix("[") && text.hasSuffix("]")) {
            return nil
        }
        // Beep strip (port the three regex patterns from TranscriptionPipeline.swift:64-76)
        let beepPatterns = [#/^\(beep(ing)?\)[,.\s]*/#, #/^\[beep(ing)?\][,.\s]*/#, #/^beep(ing)?[,.\s]*/#]
        for p in beepPatterns {
            if let m = try? p.ignoresCase().prefixMatch(in: text) {
                text = String(text[m.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                lower = text.lowercased(); break
            }
        }
        if text.isEmpty || lower == "beep" || lower == "beeping" { return nil }
        // Wake-word strip (port from TranscriptionPipeline.swift:88-106)
        if wakeWordEnabled && !wakeWord.isEmpty {
            let esc = NSRegularExpression.escapedPattern(for: wakeWord)
            if let re = try? NSRegularExpression(pattern: "^" + esc + "[,.:!?\\s]*", options: .caseInsensitive) {
                let r = NSRange(text.startIndex..., in: text)
                if let match = re.firstMatch(in: text, options: [], range: r),
                   let mr = Range(match.range, in: text) {
                    text = String(text[mr.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    lower = text.lowercased()
                }
            }
            if text.isEmpty || lower == wakeWord.lowercased() { return nil }
        }
        return text
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd PushKit && swift test --filter TranscriptCleanerTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add PushKit/Sources/PushShared/TranscriptCleaner.swift PushKit/Tests/PushSharedTests/TranscriptCleanerTests.swift
git commit -m "feat(pushshared): extract TranscriptCleaner with tests"
```

### Task 0.4: Point the macOS app at `PushShared` (prove no regression)

**Files:**
- Modify: `Package.swift` (root) — add local package dep
- Modify: `PUSH/Core/TranscriptionPipeline.swift:11-166` and delete `:188-631`

- [ ] **Step 1: Add the local package to the root `Package.swift`**

In `dependencies:` add `.package(path: "PushKit"),`. In the `PUSH` target `dependencies:` add:
```swift
.product(name: "PushShared", package: "PushKit"),
```

- [ ] **Step 2: Replace the pipeline body to call the shared code**

In `TranscriptionPipeline.swift`, `import PushShared` at top. Replace the cleaning block (`:44-107`) and formatting block (`:118-166`) with:
```swift
guard let cleaned = TranscriptCleaner.clean(
    rawText, wakeWord: wakeWord, wakeWordEnabled: wakeWordEnabled
) else {
    PushLogger.log("TranscriptionPipeline: No speech detected")
    return
}
// KEEP the context-aware dictionary step (v5.0.0 feature) between clean and format —
// it currently lives at :115-116 and must NOT be deleted with the surrounding blocks.
let corrections = await MainActor.run { CorrectionsStore.shared.corrections }
let corrected = await CorrectionsStore.applyContextAware(corrections, to: cleaned)
let formattedText = TextFormatter.format(corrected, hasNativePunctuation: selectedModel.hasNativePunctuation)
```
(Fetch `wakeWord`/`wakeWordEnabled` from `AppState` before the guard, as the current code does at `:85-87`.) Then **delete** the now-duplicated `private static` funcs and tables at `TranscriptionPipeline.swift:188-631`, and the hallucination sets at `:11-21`.

> ⚠️ **Regression trap:** the current code runs `CorrectionsStore.applyContextAware` *between* cleaning and formatting. A naive "replace both blocks" edit deletes it silently — the pipeline still compiles and dictates fine, but user dictionary corrections stop applying. The snippet above preserves it; the smoke test in Step 4 exercises it.

- [ ] **Step 3: Build the macOS app**

Run: `swift build`
Expected: `Build complete!` — no "duplicate"/"cannot find" errors.

- [ ] **Step 4: Manual smoke test (behavior unchanged)**

Run: `swift run`. First add a dictionary entry (e.g. Always-correct "clod" → "Claude") in Settings, then dictate: "push I saved twenty five percent 'cause clod was on sale".
Expected inserted text: `I saved 25% cause Claude was on sale.` (wake word stripped; number/percent/`'cause` normalized; **dictionary correction applied** — this last one catches the regression trap above) — identical to pre-refactor.

- [ ] **Step 5: Commit**

```bash
git add Package.swift PUSH/Core/TranscriptionPipeline.swift
git commit -m "refactor(macos): consume PushShared TextFormatter/TranscriptCleaner (no behavior change)"
```

### Task 0.5: Move the Parakeet engine into `PushTranscription`

**Files:**
- Modify: `PushKit/Sources/PushTranscription/ParakeetTranscriber.swift` (replace stub)
- Modify: `PUSH/ML/ParakeetEngine.swift` → thin shim, or delete and update `TranscriptionPipeline.swift:38`

- [ ] **Step 1: Implement `ParakeetTranscriber` by moving `ParakeetEngine`**

Replace the stub with the full body of `PUSH/ML/ParakeetEngine.swift:1-155`, renamed `public actor ParakeetTranscriber`, `public` on `shared`, `loadModel`, `warmup`, `transcribe(audioData:)`, `unloadModel`, and the static model-dir helpers. Replace `PushLogger.log(...)` calls with a `public` logging closure parameter or `print` (PushKit must not depend on the app):
```swift
public static var log: (String) -> Void = { _ in }
```
and swap each `PushLogger.log(x)` → `Self.log(x)`.

- [ ] **Step 2: Add a build check test**

`PushKit/Tests/PushSharedTests/` can't import FluidAudio; instead verify compilation via build:
Run: `cd PushKit && swift build --target PushTranscription`
Expected: `Build complete!`

- [ ] **Step 3: Repoint the macOS app**

In root `Package.swift`, add `.product(name: "PushTranscription", package: "PushKit")` to the `PUSH` target. In `TranscriptionPipeline.swift`, `import PushTranscription`; change `ParakeetEngine.shared.transcribe(...)` (`:38`) → `ParakeetTranscriber.shared.transcribe(...)`. Set `ParakeetTranscriber.log = { PushLogger.log($0) }` once at app startup (`AppDelegate`). Delete `PUSH/ML/ParakeetEngine.swift` and its other references (`AppState.swift`, `SettingsView.swift`, `SileroVAD.swift`) — repoint them to `ParakeetTranscriber`.

- [ ] **Step 4: Build + smoke test**

Run: `swift build && swift run`
Expected: build passes; Parakeet dictation works exactly as before.

- [ ] **Step 5: Commit**

```bash
git add Package.swift PushKit/Sources/PushTranscription PUSH
git commit -m "refactor: move Parakeet engine into PushTranscription; macOS app consumes it"
```

---

## Milestone 1 — iOS app shell (Xcode project against PushKit)

*Outcome: an iOS app that builds/runs on a device, downloads the Parakeet model, and transcribes a hardcoded audio buffer — proving PushKit runs on iOS.*

### Task 1.1: Create the Xcode project + app target wired to PushKit

**Files:** `PushiOS/PushiOS.xcodeproj`, `PushiOS/PushApp/PushAppApp.swift`

- [ ] **Step 1 (Xcode GUI):** File ▸ New ▸ Project ▸ iOS App. Product Name `PushApp`, Interface SwiftUI, Language Swift, save under `PushiOS/`. Set deployment target **iOS 17.0**.
- [ ] **Step 2 (Xcode GUI):** File ▸ Add Package Dependencies ▸ Add Local ▸ select repo-root `PushKit`. Add **both** `PushShared` and `PushTranscription` to the `PushApp` target.
- [ ] **Step 3:** Replace `PushAppApp.swift`:
```swift
import SwiftUI
import PushTranscription

@main
struct PushAppApp: App {
    init() { ParakeetTranscriber.log = { print("[Parakeet] \($0)") } }
    var body: some Scene { WindowGroup { ContentView() } }
}
```
- [ ] **Step 4:** Build to a simulator.
Run: `xcodebuild -project PushiOS/PushiOS.xcodeproj -scheme PushApp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`
- [ ] **Step 5: Commit**
```bash
git add PushiOS
git commit -m "feat(ios): create PushApp Xcode project linked to PushKit"
```

### Task 1.2: Prove Parakeet transcribes on-device

**Files:** `PushiOS/PushApp/ContentView.swift`

- [ ] **Step 1:** Add a button that loads the model and transcribes 1s of silence (smoke path):
```swift
import SwiftUI
import PushTranscription

struct ContentView: View {
    @State private var status = "idle"
    var body: some View {
        VStack(spacing: 16) {
            Text(status).font(.headline)
            Button("Test Parakeet") {
                Task {
                    status = "loading…"
                    do {
                        try await ParakeetTranscriber.shared.loadModel()
                        let silence = Data(count: 16000 * MemoryLayout<Float>.size)
                        let text = try await ParakeetTranscriber.shared.transcribe(audioData: silence)
                        status = "ok: '\(text)'"
                    } catch { status = "error: \(error.localizedDescription)" }
                }
            }
        }.padding()
    }
}
```
- [ ] **Step 2:** Run on a **real device** (model download + ANE need device; the sim is slow but works).
Expected: status becomes `ok: ''` (silence → empty), proving the model loaded and ran on iOS.
- [ ] **Step 3: Commit**
```bash
git add PushiOS/PushApp/ContentView.swift
git commit -m "test(ios): verify Parakeet loads and transcribes on-device"
```

---

## Milestone 2 — Microphone capture + full transcription in the app

*Outcome: in-app "hold to talk" records the mic, runs Parakeet + TextFormatter, shows the finished text.*

### Task 2.1: Add mic permission + Info.plist

- [ ] **Step 1:** In `PushApp/Info.plist` add:
  - `NSMicrophoneUsageDescription` = `PUSH transcribes your voice on-device to type for you.`
- [ ] **Step 2 (Xcode GUI):** Signing & Capabilities ▸ ensure a valid team; no extra capability needed yet.
- [ ] **Step 3: Commit** `git commit -am "feat(ios): declare microphone usage"`.

### Task 2.2: `DictationController` — record → transcribe → format

**Files:** `PushiOS/PushApp/DictationController.swift`

- [ ] **Step 1: Write the recorder/transcriber** (16 kHz mono Float32 to match `ParakeetTranscriber`'s `audioDataToFloatArray`):
```swift
import AVFoundation
import PushShared
import PushTranscription

@MainActor
final class DictationController: ObservableObject {
    @Published var transcript = ""
    private let engine = AVAudioEngine()
    private var buffer = Data()

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    func start() throws {
        buffer.removeAll()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: hwFormat, to: target)!
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] pcm, _ in
            let ratio = target.sampleRate / hwFormat.sampleRate
            let cap = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
            var err: NSError?
            converter.convert(to: out, error: &err) { _, s in s.pointee = .haveData; return pcm }
            if let ch = out.floatChannelData {
                self?.buffer.append(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
                    // append raw Float bytes:
            }
        }
        try engine.start()
    }

    func stopAndTranscribe(wakeWord: String, wakeWordEnabled: Bool,
                           hasNativePunctuation: Bool) async -> String? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let raw = try? await ParakeetTranscriber.shared.transcribe(audioData: buffer) else { return nil }
        guard let cleaned = TranscriptCleaner.clean(raw, wakeWord: wakeWord,
                                                    wakeWordEnabled: wakeWordEnabled) else { return nil }
        return TextFormatter.format(cleaned, hasNativePunctuation: hasNativePunctuation)
    }
}
```
> Note for the implementer: the tap closure must append the Float32 bytes correctly. Replace the `buffer.append(UnsafeBufferPointer…)` line with:
```swift
if let ch = out.floatChannelData {
    ch[0].withMemoryRebound(to: UInt8.self, capacity: Int(out.frameLength) * 4) { p in
        self?.buffer.append(p, count: Int(out.frameLength) * 4)
    }
}
```

- [ ] **Step 2:** Wire a press-and-hold button in `ContentView` to `start()` / `stopAndTranscribe(...)` and display `transcript`.
- [ ] **Step 3:** Run on device; hold, say "hello world, twenty five percent"; release.
Expected: `Hello world, 25%.` shown (Parakeet has native punctuation ⇒ pass `hasNativePunctuation: true`).
- [ ] **Step 4: Commit** `git commit -am "feat(ios): in-app mic capture → Parakeet → formatted transcript"`.

---

## Milestone 3 — App Group IPC bridge

*Outcome: app and (soon) extension share state through `group.com.push.shared`; round-trip is unit-tested.*

### Task 3.1: Register the App Group + entitlements

- [ ] **Step 1 (Apple Developer portal / Xcode GUI):** Signing & Capabilities ▸ `PushApp` ▸ + App Groups ▸ create `group.com.push.shared`. This generates `PushApp.entitlements`.
- [ ] **Step 2:** Confirm `AppGroup.identifier` in `PushShared/AppGroup.swift` matches exactly. If Apple forces a different suffix (team-prefixed), update the constant.
- [ ] **Step 3: Commit** `git commit -am "feat(ios): add App Group capability to PushApp"`.

### Task 3.2: `DictationBridge` — request/result over UserDefaults + Darwin notifications

**Files:** `PushKit/Sources/PushShared/DictationBridge.swift`, `PushKit/Tests/PushSharedTests/DictationBridgeTests.swift`, `PushKit/Sources/PushShared/FlowSessionTimeout.swift`

- [ ] **Step 1: Write failing tests for the UserDefaults round-trip**
```swift
import XCTest
@testable import PushShared

final class DictationBridgeTests: XCTestCase {
    func testResultRoundTrip() {
        let d = UserDefaults(suiteName: "test.push.bridge")!
        d.removePersistentDomain(forName: "test.push.bridge")
        let bridge = DictationBridge(defaults: d)
        XCTAssertNil(bridge.consumePendingResult())
        bridge.postResult("hello world")
        XCTAssertEqual(bridge.consumePendingResult(), "hello world")
        XCTAssertNil(bridge.consumePendingResult()) // consumed once
    }
    func testTimeoutPersistence() {
        let d = UserDefaults(suiteName: "test.push.bridge2")!
        let bridge = DictationBridge(defaults: d)
        bridge.timeout = .never
        XCTAssertEqual(bridge.timeout, .never)
    }
}
```
- [ ] **Step 2: Run to verify fail** — `cd PushKit && swift test --filter DictationBridgeTests` → FAIL (`DictationBridge`/`FlowSessionTimeout` not found).
- [ ] **Step 3: Implement `FlowSessionTimeout`**
```swift
import Foundation
public enum FlowSessionTimeout: String, CaseIterable, Sendable {
    case immediately, fiveMinutes, oneHour, never
    public var seconds: TimeInterval? {
        switch self {
        case .immediately: return 0
        case .fiveMinutes: return 300
        case .oneHour: return 3600
        case .never: return nil // keep session warm
        }
    }
    public var label: String {
        switch self {
        case .immediately: return "Immediately"
        case .fiveMinutes: return "After 5 minutes"
        case .oneHour: return "After 1 hour"
        case .never: return "Never (always ready)"
        }
    }
}
```
- [ ] **Step 4: Implement `DictationBridge`**
```swift
import Foundation

public final class DictationBridge {
    public static let requestName = "com.push.dictation.request"
    public static let resultName  = "com.push.dictation.result"
    private let defaults: UserDefaults
    private let resultKey = "pendingTranscript"
    private let timeoutKey = "flowSessionTimeout"

    public init(defaults: UserDefaults? = AppGroup.defaults) {
        self.defaults = defaults ?? .standard
    }

    deinit {
        // The keyboard creates a bridge per UIInputViewController, and iOS recreates
        // controllers frequently — without cleanup every observe() leaks a Handler
        // and leaves a dangling Darwin observer.
        for box in observerBoxes {
            CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), box)
            Unmanaged<Handler>.fromOpaque(box).release()
        }
    }

    public var timeout: FlowSessionTimeout {
        get { FlowSessionTimeout(rawValue: defaults.string(forKey: timeoutKey) ?? "") ?? .immediately }
        set { defaults.set(newValue.rawValue, forKey: timeoutKey) }
    }

    // Extension → App: ask the app to start dictation.
    public func requestDictation() { postDarwin(Self.requestName) }
    public func onDictationRequested(_ handler: @escaping () -> Void) { observeDarwin(Self.requestName, handler) }

    // App → Extension: publish finished text.
    public func postResult(_ text: String) {
        defaults.set(text, forKey: resultKey)
        postDarwin(Self.resultName)
    }
    public func onResult(_ handler: @escaping () -> Void) { observeDarwin(Self.resultName, handler) }
    public func consumePendingResult() -> String? {
        guard let t = defaults.string(forKey: resultKey) else { return nil }
        defaults.removeObject(forKey: resultKey)
        return t
    }

    private func postDarwin(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }
    private var observerBoxes: [UnsafeMutableRawPointer] = []
    private func observeDarwin(_ name: String, _ handler: @escaping () -> Void) {
        let box = Unmanaged.passRetained(Handler(handler)).toOpaque()
        observerBoxes.append(box)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), box,
            { _, obs, _, _, _ in obs.map { Unmanaged<Handler>.fromOpaque($0).takeUnretainedValue().run() } },
            name as CFString, nil, .deliverImmediately)
    }
    private final class Handler { let run: () -> Void; init(_ r: @escaping () -> Void) { run = r } }
}
```
- [ ] **Step 5: Run to verify pass** — `cd PushKit && swift test --filter DictationBridgeTests` → PASS (2 tests).
- [ ] **Step 6: Commit** `git commit -am "feat(pushshared): DictationBridge IPC + FlowSessionTimeout with tests"`.

---

## Milestone 4 — Keyboard extension (trigger + insert)

*Outcome: a working custom keyboard that, on tap, foregrounds the app to dictate and inserts the returned text at the cursor.*

### Task 4.1: Create the keyboard-extension target (PushShared only)

- [ ] **Step 1 (Xcode GUI):** File ▸ New ▸ Target ▸ **Custom Keyboard Extension**, name `PushKeyboard`.
- [ ] **Step 2 (Xcode GUI):** Add **only** `PushShared` to `PushKeyboard`'s "Frameworks and Libraries". Do **not** add `PushTranscription`/FluidAudio (memory-limit rule).
- [ ] **Step 3:** In `PushKeyboard/Info.plist`, under `NSExtension ▸ NSExtensionAttributes`, set `RequestsOpenAccess` = `YES` (needed to write the App Group container + read the transcript).
- [ ] **Step 4 (Xcode GUI):** Signing & Capabilities ▸ `PushKeyboard` ▸ + App Groups ▸ check `group.com.push.shared` (same group as the app).
- [ ] **Step 5:** Build both targets. Run: `xcodebuild -project PushiOS/PushiOS.xcodeproj -scheme PushApp -destination 'generic/platform=iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Commit** `git commit -am "feat(ios): add PushKeyboard extension (PushShared only, Full Access, App Group)"`.

### Task 4.2: `KeyboardViewController` — mic button, trigger, insertion

**Files:** `PushiOS/PushKeyboard/KeyboardViewController.swift`

- [ ] **Step 1: Implement the controller**
```swift
import UIKit
import PushShared

class KeyboardViewController: UIInputViewController {
    private let bridge = DictationBridge()
    private let micButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        micButton.setTitle("🎤 Speak", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .semibold)
        micButton.addTarget(self, action: #selector(startDictation), for: .touchUpInside)
        nextButton.setTitle("🌐", for: .normal)
        nextButton.addTarget(self, action: #selector(nextKeyboard), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [nextButton, micButton])
        stack.distribution = .fill; stack.spacing = 12; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 216),
        ])
        // When the app publishes a transcript, insert it.
        bridge.onResult { [weak self] in
            DispatchQueue.main.async { self?.insertPending() }
        }
    }

    @objc private func nextKeyboard() { advanceToNextInputMode() }

    @objc private func startDictation() {
        guard hasFullAccess else { micButton.setTitle("Enable Full Access", for: .normal); return }
        bridge.requestDictation()
        // Foreground the containing app so it can access the mic.
        openContainingApp()
        micButton.setTitle("Listening… (return here)", for: .normal)
    }

    private func insertPending() {
        if let text = bridge.consumePendingResult() {
            textDocumentProxy.insertText(text)
            micButton.setTitle("🎤 Speak", for: .normal)
        }
    }

    // Also check on appearance, in case the result landed while we were backgrounded.
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); insertPending() }

    private func openContainingApp() {
        let url = URL(string: "push://dictate")!
        var responder: UIResponder? = self
        let sel = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: sel) { _ = r.perform(sel, with: url); break }
            responder = r.next
        }
    }
}
```
> Note: `extensionContext?.open(_:)` is unavailable to keyboard extensions; the responder-chain `openURL:` walk above is the established workaround.

- [ ] **Step 2: Build.** Expected `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Commit** `git commit -am "feat(ios): keyboard mic button, dictation trigger, text insertion"`.

### Task 4.3: App handles the `push://dictate` URL and completes the loop

**Files:** `PushiOS/PushApp/Info.plist`, `PushiOS/PushApp/PushAppApp.swift`, `PushiOS/PushApp/DictationController.swift`

- [ ] **Step 1:** Register the URL scheme in `PushApp/Info.plist` → `CFBundleURLTypes` with `CFBundleURLSchemes` = `["push"]`.
- [ ] **Step 2:** In `PushAppApp.swift`, handle the URL by starting dictation and showing a Stop button; posting the result happens on Stop:
```swift
// In the App/ContentView scope:
@StateObject private var dictation = DictationController()
@State private var isDictating = false

// On the root view:
.onOpenURL { url in
    guard url.host == "dictate" else { return }
    Task {
        guard await dictation.requestPermission(), (try? dictation.start()) != nil else { return }
        isDictating = true
    }
}

// Shown while isDictating — the explicit end-point:
Button("Stop & Insert") {
    Task {
        isDictating = false
        if let text = await dictation.stopAndTranscribe(wakeWord: "", wakeWordEnabled: false,
                                                        hasNativePunctuation: true) {
            DictationBridge().postResult(text)
        }
    }
}
```
> The explicit Stop button is deliberate: a fixed time window truncates or pads speech unpredictably. VAD end-pointing (PUSH already has `SileroVAD`) replaces the button later — that's Task 6.4.

- [ ] **Step 3: End-to-end test on device:** enable PushKeyboard in Settings ▸ General ▸ Keyboard ▸ Keyboards ▸ Add ▸ PushKeyboard ▸ Allow Full Access. In Notes, switch to PushKeyboard, tap 🎤, speak in the app, return.
Expected: transcribed text appears at the cursor in Notes.
- [ ] **Step 4: Commit** `git commit -am "feat(ios): app completes dictation on push://dictate and returns text to keyboard"`.

---

## Milestone 5 — Flow-session persistence (the "immediate vs never" setting)

*Outcome: a user setting controlling how long the app keeps the mic session warm; "never" enables background-audio so the keyboard feels native.*

### Task 5.1: Settings UI bound to `DictationBridge.timeout`

**Files:** `PushiOS/PushApp/SettingsView.swift`

- [ ] **Step 1:** Picker over `FlowSessionTimeout.allCases` writing `DictationBridge().timeout`. Include copy explaining the tradeoff (battery + orange dot vs. seamlessness). The default stays `.immediately` (already encoded in the `timeout` getter's fallback) — "never" is opt-in only, since it's the battery-hungry, App-Store-scrutinized mode.
- [ ] **Step 2:** Build + verify the value persists across launches (read back in `onAppear`).
- [ ] **Step 3: Commit** `git commit -am "feat(ios): Flow-session timeout setting"`.

### Task 5.2: `FlowSessionManager` — keep the session warm per setting

**Files:** `PushiOS/PushApp/FlowSessionManager.swift`, `PushApp/Info.plist`

- [ ] **Step 1:** Add `UIBackgroundModes` = `["audio"]` to `PushApp/Info.plist` **only if** shipping "never"/long timeouts. Document the user-facing feature that justifies it (Guideline 2.5.4).
- [ ] **Step 2:** Implement a manager that, on `timeout == .never`, keeps `AVAudioSession` active and the engine running (muted) so a subsequent `push://dictate` resumes instantly; on finite timeouts, tears down after N seconds; always handle `AVAudioSession.interruptionNotification` and re-arm, and treat force-quit as "cold" (fall back to app-hop).
- [ ] **Step 3:** Device test: set "never", dictate from keyboard twice in a row without the app visibly re-launching between; set "immediately", confirm the app-hop each time.
- [ ] **Step 4: Commit** `git commit -am "feat(ios): FlowSessionManager warm-session lifetime + interruption handling"`.

---

## Milestone 6 — Onboarding, model management, polish

- [ ] **Task 6.1:** `OnboardingView` walking the user through: add keyboard → Allow Full Access → grant mic. Detect `hasFullAccess` from the keyboard and mic permission from the app; show checkmarks. Commit.
- [ ] **Task 6.2:** Model download UX in the app (reuse `ParakeetTranscriber.isModelDownloaded()`/`modelDirectory`): progress + "Download voice model (~600 MB, on-device)". Commit.
- [ ] **Task 6.3:** Keyboard states: no-Full-Access prompt, offline/again states, error toast when the app couldn't record. Commit.
- [ ] **Task 6.4:** Port `SileroVAD` end-pointing from `PUSH/Core/SileroVAD.swift` into the app to auto-stop recording (replaces the fixed window). Commit.

---

## Milestone 7 — App Store readiness

- [ ] **Task 7.1:** App Privacy nutrition label: declare microphone/audio; since transcription is **on-device**, mark "not collected / not linked" — a genuine differentiator vs. cloud keyboards. Commit any config.
- [ ] **Task 7.2:** Review-guideline pass: honest `NSMicrophoneUsageDescription`; if `UIBackgroundModes: audio` is present, ensure a real persistent-audio feature exists (2.5.4) and the orange indicator is expected (2.5.14). Write `docs/appstore-review-notes.md` explaining the keyboard→app mic handoff for the reviewer.
- [ ] **Task 7.3:** TestFlight build; verify on ≥2 device classes; confirm no jetsam of the keyboard extension (watch for the 48 MB ceiling — the extension must stay tiny).

---

## Known failure modes (call these out during execution)

- **Extension jetsam:** if `PushKeyboard` ever links FluidAudio/Parakeet, it dies at ~48 MB. Keep it on `PushShared` only.
- **Darwin notifications don't wake a suspended extension:** while the user is in the app dictating, the keyboard extension is backgrounded/suspended, so `onResult` will usually NOT fire in real time. The `viewWillAppear` → `insertPending()` check is the path that actually inserts in practice — treat the Darwin observer as a nice-to-have for the rare still-alive case, and never rely on it in tests.
- **Dictionary-corrections regression (Task 0.4):** `CorrectionsStore.applyContextAware` runs between clean and format; deleting it compiles fine but silently kills the v5.0.0 dictionary feature. The Task 0.4 smoke test includes a correction specifically to catch this.
- **Session fragility:** background mic session is best-effort — killed by phone calls/Siri/alarms, memory pressure (silent SIGKILL), and force-quit. Always fall back to the app-hop.
- **iOS 26.4+ swipe-back:** the app→keyboard return may require a manual swipe; don't design as if auto-return is guaranteed.
- **Audio format mismatch:** `ParakeetTranscriber` expects 16 kHz mono Float32; the `AVAudioConverter` step in `DictationController` is mandatory (device hardware is usually 44.1/48 kHz).
- **App Group id drift:** the portal may team-prefix the group; keep `AppGroup.identifier` authoritative and update once.

---

## Self-Review (performed against the feasibility spec)

**Spec coverage:** Prove-it's-possible → Feasibility basis + Milestones 1–4 (working loop). On-device Parakeet tradeoff → Milestones 0.5/1.2/2 (app-side) + extension memory rule. Build plan (targets/App Group/pipeline/entitlements/reuse) → Milestones 1–4 + File Structure. Wispr "immediate vs never" → Milestone 5. App Store → Milestone 7. ✅ No gaps.

**Placeholder scan:** Concrete code is provided for the load-bearing pieces (TextFormatter/TranscriptCleaner/DictationBridge/KeyboardViewController/DictationController). Genuinely GUI-only steps (creating Xcode targets, App Group capability) are written as exact manual instructions with the values to enter — these are not code and correctly aren't code blocks. Milestones 5–7 are intentionally task-level (they depend on decisions like the exact background-audio UX) and are flagged as such rather than faking code.

**Type consistency:** `ParakeetTranscriber` (not the old `ParakeetEngine`), `DictationBridge`, `FlowSessionTimeout`, `TextFormatter.format(_:hasNativePunctuation:)`, `TranscriptCleaner.clean(_:wakeWord:wakeWordEnabled:)`, `AppGroup.identifier` are used consistently across tasks. Darwin notification names (`com.push.dictation.request/result`) and the `push://dictate` scheme match on both sides.

**Honesty note:** Milestone 0 is fully TDD and independently shippable. Milestones 1–4 are concrete but assume an implementer comfortable with Xcode target creation. Milestones 5–7 are milestone-level scaffolding to be expanded into bite-sized steps when you actually start them (or split into their own plans).
