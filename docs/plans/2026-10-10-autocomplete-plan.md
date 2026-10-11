# Autocomplete Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add on-device, context-aware inline autocomplete to PUSH as a third
feature beside Dictation and Teleprompter, each switchable, without being able
to regress dictation.

**Architecture:** Pure prompt/context logic in `PUSHCore/Autocomplete` (TDD,
no AppKit). llama.cpp in-process via a pinned xcframework `binaryTarget`.
App-side pieces in `PUSH/Autocomplete`: an Accessibility focus reader, its own
`CGEvent` tap, a click-through ghost-text panel and a coordinator. Feature
switches gate existing dictation start sites in `AppDelegate`; nothing inside
the dictation path changes. Design and rationale:
`docs/plans/2026-10-10-autocomplete-design.md`.

**Tech Stack:** Swift 6 toolchain (Swift 5 language mode), SwiftPM, XCTest,
llama.cpp xcframework, Accessibility (AXUIElement), CGEvent taps, AppKit
`NSPanel`, SwiftUI settings.

**Conventions (from CLAUDE.md):** `swift build`, `swift test`. Test focus,
permissions and first launch with a real `.app`, not `swift run`. Never log
typed text. Commit after every task. Branch: `feature/autocomplete`.

**Detail level:** Phases 0–2 are written out step by step. Phases 3–7 are
listed task by task with files and acceptance checks; each is expanded into
full steps (with code) at the start of that phase, because Phase 0's results
change them.

---

## Phase 0 — Spike and model eval (go/no-go)

Exit gate: (a) a chosen catalog of 3 models with measured latency and quality,
(b) llama.cpp loads and generates inside a **signed, notarized** PUSH build,
(c) Unicode key-event insertion works in the target apps. If (a) or (b) fails,
stop and re-plan (MLX is the fallback runtime).

### Task 0.1: Autocomplete eval scenarios

**Files:**
- Create: `eval/autocomplete_scenarios.jsonl`

**Step 1:** Write ~60 scenarios, one JSON object per line:

```json
{"id":"slack-01","surface":"Format: chat; App: Slack; Title: #design; Field: Message #design.","before":"Hey, can you send me the latest mock","after":"","expected":"ups for the onboarding flow"}
```

Mix: chat (Slack, Messages), email (Mail, Gmail in a browser), docs (Notes,
Google Docs), browser forms, and 10 with `"surface": ""` (no context) as a
control. Include 15 mid-word cases (`before` ends inside a word) and 5
sign-offs ("Thanks,\n"). Write them as the user would actually type; the user's
custom-prompt note (short, friendly sentences; PM in streaming TV) is a good
voice for a third of them.

**Step 2:** Commit.

```bash
git add eval/autocomplete_scenarios.jsonl
git commit -m "eval: autocomplete scenarios"
```

### Task 0.2: Eval runner

**Files:**
- Create: `eval/run_autocomplete_eval.py` (same structure as `eval/run_llm_eval.py`: `llama-server` per model, port 8090)

**Step 1:** Implement. For each model: start `llama-server -hf <repo>:<quant> --port 8090 -c 4096 -ngl 99`,
then for each scenario POST `/completion` with
`prompt = (surface + "\n\n" if surface else "") + before`,
`n_predict: 16`, `temperature: 0`, `stop: ["\n"]`, `cache_prompt: true`.
Record: time to first token (`timings.prompt_ms`), total time, the output cut
to 6 words.

Score per scenario:
- `first_word_hit`: first predicted word == first expected word (case-insensitive, punctuation stripped)
- `prefix_words`: number of leading words matching `expected`
- `leak`: output contains `Format:`, `App:`, `Title:` or a quote of the preface

Print one table per model: median/p90 first-token ms, mean prefix_words,
first_word_hit rate, leak count, and the same split by surface vs no-surface.

Models:

```python
MODELS = {
    "qwen3.5-0.8b-base": "mradermacher/Qwen3.5-0.8B-Base-i1-GGUF:Q6_K",
    "qwen3.5-2b-base":   "mradermacher/Qwen3.5-2B-Base-i1-GGUF:Q4_K_M",
    "gemma4-e2b-base":   "mradermacher/gemma-4-E2B-i1-GGUF:Q4_K_M",
    "granite4-1b-base":  "<GGUF repo for ibm-granite/granite-4.0-1b-base>:Q4_K_M",
    "smollm3-3b-base":   "<GGUF repo for HuggingFaceTB/SmolLM3-3B-Base>:Q4_K_M",
    # Control: the instruct model both earlier prototypes used.
    "qwen3-4b-instruct": "Qwen/Qwen3-4B-GGUF:Q4_K_M",
}
```

Look up the two `<…>` repos on Hugging Face before running; drop a model if no
trustworthy GGUF exists.

**Step 2:** Run: `python3 eval/run_autocomplete_eval.py`. Expected: a table per
model. Save output to `eval/results/2026-10-autocomplete.md`.

**Step 3:** Commit runner and results.

### Task 0.3: Choose the catalog

**Files:**
- Modify: `docs/plans/2026-10-10-autocomplete-design.md` (Model catalog section)
- Modify: `docs/MODELS.md` (add an "Autocomplete models" section + review-log entry)

**Step 1:** Pick Lite / Recommended / Best from the table. Gate: Recommended
p90 first-token ≤ 150 ms on this Mac with a 1,500-char prompt, and 0 leaks.
**Step 2:** Record the measured numbers and the reason for each pick. Commit.

### Task 0.4: llama.cpp in the package

**Files:**
- Modify: `Package.swift`
- Create: `PUSHCore/Autocomplete/LlamaSmoke.swift` (temporary)
- Create: `Tests/PUSHTests/LlamaSmokeTests.swift` (temporary)

**Step 1:** Pick the latest llama.cpp release tag ≥ 2 weeks old. Download
`llama-<tag>-xcframework.zip`, run `swift package compute-checksum` on it.

**Step 2:** Add to `Package.swift`:

```swift
.binaryTarget(
    name: "llama",
    url: "https://github.com/ggml-org/llama.cpp/releases/download/<tag>/llama-<tag>-xcframework.zip",
    checksum: "<checksum>"
),
```

and add `"llama"` to `PUSHCore`'s dependencies.

**Step 3:** `LlamaSmoke.generate(modelPath:prompt:maxTokens:)`: load model,
tokenize, decode greedily, return text. A test gated on env var
`PUSH_LLAMA_SMOKE_MODEL` (skip when unset) asserts non-empty output for
`"The capital of France is"`.

**Step 4:** Run:
`PUSH_LLAMA_SMOKE_MODEL=~/path/Qwen3.5-0.8B-Base.i1-Q6_K.gguf swift test --filter LlamaSmokeTests`
Expected: PASS, output contains "Paris".

**Step 5:** Commit.

### Task 0.5: Signed-build check

**Files:**
- Modify: `build_distribution.sh` (copy + sign `llama.framework` before the app; the script already adds the `@executable_path/../Frameworks` rpath)

**Step 1:** Add a hidden DEBUG-only menu item or launch flag
`PUSH_LLAMA_SMOKE_MODEL` that runs `LlamaSmoke` once at launch and logs only
`ok`/`failed` + timing (never the text).

**Step 2:** Build the signed, notarized app **without publishing**: run the
build script but do not commit `appcast.xml` or upload. Launch
`/Applications`-installed copy with the env var. Expected log: `llama smoke ok`.

**Step 3:** Commit the script change. Do not commit appcast or version changes.

### Task 0.6: Insertion spike

**Files:**
- Create: `PUSH/Autocomplete/KeystrokeTyper.swift`

**Step 1:** `KeystrokeTyper.type(_ text: String)`: for each chunk of ≤ 20 UTF-16
units, post a keyDown/keyUp pair with `CGEventKeyboardSetUnicodeString` to
`.cghidEventTap`.

**Step 2:** DEBUG hotkey (e.g. ⌃⌥⌘T) types `"hello wörld 👋"` into the focused
field. Try Mail, Notes, Slack, Chrome (Gmail + a plain textarea), Safari, VS Code.
Record per app: correct / wrong / nothing in the design doc.

**Step 3:** Commit.

**Phase 0 checkpoint:** report results to the user before Phase 1.

---

## Phase 1 — Feature switches and onboarding

### Task 1.1: Switches in AppState

**Files:**
- Modify: `PUSH/App/AppState.swift` (`UserDefaultsKeys`, two properties, init load)
- Test: `Tests/PUSHTests/FeatureSwitchTests.swift`

**Step 1: Failing test**

```swift
import XCTest
@testable import PUSH

@MainActor
final class FeatureSwitchTests: XCTestCase {
    func testDictationDefaultsOnWhenKeyAbsent() {
        let d = UserDefaults(suiteName: #function)!
        d.removePersistentDomain(forName: #function)
        XCTAssertTrue(FeatureSwitches.dictationEnabled(in: d))
    }

    func testAutocompleteDefaultsOff() {
        let d = UserDefaults(suiteName: #function)!
        d.removePersistentDomain(forName: #function)
        XCTAssertFalse(FeatureSwitches.autocompleteEnabled(in: d))
    }

    func testStoredValuesWin() {
        let d = UserDefaults(suiteName: #function)!
        d.set(false, forKey: FeatureSwitches.dictationKey)
        d.set(true, forKey: FeatureSwitches.autocompleteKey)
        XCTAssertFalse(FeatureSwitches.dictationEnabled(in: d))
        XCTAssertTrue(FeatureSwitches.autocompleteEnabled(in: d))
    }

    func testNeitherSwitchIsSynced() {
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains(FeatureSwitches.dictationKey))
        XCTAssertFalse(CloudSync.mirroredSettingKeys.contains(FeatureSwitches.autocompleteKey))
    }
}
```

**Step 2:** `swift test --filter FeatureSwitchTests` → FAIL (`FeatureSwitches` undefined).

**Step 3: Implement** `PUSH/App/FeatureSwitches.swift`:

```swift
import Foundation

/// Which of PUSH's features this Mac runs. Per-machine on purpose: each
/// feature needs a model on disk, and models are never synced.
enum FeatureSwitches {
    static let dictationKey = "feature.dictationEnabled"
    static let autocompleteKey = "feature.autocompleteEnabled"

    /// Absent means on, so every install from before this switch existed
    /// keeps dictating exactly as it did.
    static func dictationEnabled(in d: UserDefaults = .standard) -> Bool {
        d.object(forKey: dictationKey) as? Bool ?? true
    }

    static func autocompleteEnabled(in d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: autocompleteKey)
    }
}
```

Add to `AppState`:

```swift
var dictationEnabled: Bool = FeatureSwitches.dictationEnabled() {
    didSet { UserDefaults.standard.set(dictationEnabled, forKey: FeatureSwitches.dictationKey) }
}
var autocompleteEnabled: Bool = FeatureSwitches.autocompleteEnabled() {
    didSet { UserDefaults.standard.set(autocompleteEnabled, forKey: FeatureSwitches.autocompleteKey) }
}
```

**Step 4:** `swift test --filter FeatureSwitchTests` → PASS. Run full `swift test` → all pass.

**Step 5:** Commit: `feat: per-machine feature switches for dictation and autocomplete`.

### Task 1.2: Onboarding step list as a pure function

**Files:**
- Create: `PUSH/Views/Onboarding/OnboardingFlow.swift`
- Test: `Tests/PUSHTests/OnboardingFlowTests.swift`

**Step 1: Failing test**

```swift
import XCTest
@testable import PUSH

final class OnboardingFlowTests: XCTestCase {
    typealias S = OnboardingFlow.Step

    func testDictationOnlyMatchesTodaysWizardPlusFeatures() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, autocomplete: false),
                       [.welcome, .features, .permissions, .speechModel, .tryIt, .pill, .more, .finish])
    }

    func testAutocompleteOnlySkipsSpeechAndPill() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: false, autocomplete: true),
                       [.welcome, .features, .permissions, .typingModel, .tryIt, .more, .finish])
    }

    func testBoth() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: true, autocomplete: true),
                       [.welcome, .features, .permissions, .speechModel, .typingModel, .tryIt, .pill, .more, .finish])
    }

    func testNeitherStopsAtFeatures() {
        XCTAssertEqual(OnboardingFlow.steps(dictation: false, autocomplete: false),
                       [.welcome, .features])
    }

    func testMicrophoneRowOnlyWithDictation() {
        XCTAssertTrue(OnboardingFlow.needsMicrophone(dictation: true))
        XCTAssertFalse(OnboardingFlow.needsMicrophone(dictation: false))
    }
}
```

**Step 2:** Run → FAIL.

**Step 3: Implement**

```swift
/// The wizard's steps for a given choice of features. Pure, so the order is
/// pinned by tests rather than by reading a view.
enum OnboardingFlow {
    enum Step: Equatable {
        case welcome, features, permissions, speechModel, typingModel, tryIt, pill, more, finish
    }

    static func steps(dictation: Bool, autocomplete: Bool) -> [Step] {
        // Nothing chosen: the wizard cannot continue past the choice.
        guard dictation || autocomplete else { return [.welcome, .features] }
        var s: [Step] = [.welcome, .features, .permissions]
        if dictation { s.append(.speechModel) }
        if autocomplete { s.append(.typingModel) }
        s.append(.tryIt)
        if dictation { s.append(.pill) }
        s += [.more, .finish]
        return s
    }

    static func needsMicrophone(dictation: Bool) -> Bool { dictation }
}
```

**Step 4:** Run → PASS. **Step 5:** Commit.

### Task 1.3: Wire the wizard to the flow

**Files:**
- Modify: `PUSH/Views/Onboarding/OnboardingView.swift`

**Steps:**
1. Replace `enum Step: Int, CaseIterable` with an index into
   `OnboardingFlow.steps(dictation: appState.dictationEnabled, autocomplete: appState.autocompleteEnabled)`.
   `advance(to:)` moves the index; `stepDots` iterates the computed list.
2. Add `featuresStep`: two `featureCard`s with switches bound to
   `$appState.dictationEnabled` and `$appState.autocompleteEnabled`. Dictation's
   card mentions the teleprompter. Continue disabled when both are off, with one
   line: "Turn on at least one to continue."
3. `permissionsStep`: show the Microphone row only when
   `OnboardingFlow.needsMicrophone(dictation:)`; update the header copy for the
   one-permission case ("One permission").
4. Rename the case `.model` → `.speechModel` in the view; body unchanged.
5. `.typingModel`: placeholder text "Typing model — coming in Phase 5" behind a
   DEBUG flag; Phase 5 replaces it. Until Phase 5 ships, the features step
   shows Autocomplete as "Coming soon" and its switch disabled in release builds.
6. `.tryIt`: unchanged dictation sandbox when dictation is on; when only
   autocomplete is on, skip it (Phase 5 adds the typing sandbox).
7. Footer Skip: shown when every enabled feature has a model on disk.

**Verify:** build a real `.app` (see CLAUDE.md), reset with
`defaults delete com.push.voicetotext` on a test account or a fresh user, walk
the wizard with dictation only — must be identical to today apart from the new
features step. Screenshot every step. Commit.

### Task 1.4: Gate dictation start sites

**Files:**
- Modify: `PUSH/App/AppDelegate.swift` (microphone request, wake word start, `activateAtLaunch`, pill window)
- Modify: `PUSH/Core/HotkeyManager.swift` (one guard at the top of `handleKeyDown`)
- Modify: `PUSH/Views/MenuBarView.swift` (teleprompter item disabled with reason when dictation is off)

**Steps:**
1. Each start site checks `appState.dictationEnabled`. `HotkeyManager` keeps
   running (it also drives teleprompter arrows and the accessibility retry);
   only the start-recording path returns early.
2. Turning dictation on at runtime starts the same things; turning it off
   stops recording if active, stops wake word, unloads the speech model through
   `ModelLoader` (never directly).
3. Test: extend `LaunchModelTests` with "dictation off → activateAtLaunch not called" if
   the launch decision can be factored into a pure function; otherwise verify
   manually with logs.

**Verify:** with dictation on, a full dictation round-trip behaves exactly as
on `main` (hotkey, wake word, pill, paste). With it off, the hotkey does
nothing and no model loads (check `PushLogger`). Commit.

**Phase 1 checkpoint:** release-candidate quality on its own; could ship even
if autocomplete slips.

---

## Phase 2 — Pure core (`PUSHCore/Autocomplete`), TDD

All types `Sendable`, no AppKit. Tests in `Tests/PUSHTests/Autocomplete*Tests.swift`
with `@testable import PUSHCore`.

### Task 2.1: Surface classifier

**Files:** Create `PUSHCore/Autocomplete/SurfaceClass.swift`; test `AutocompleteSurfaceClassTests.swift`.

**Test:**

```swift
func testClassifiesKnownApps() {
    XCTAssertEqual(SurfaceClass.classify(bundleID: "com.tinyspeck.slackmacgap"), .chat)
    XCTAssertEqual(SurfaceClass.classify(bundleID: "com.apple.mail"), .email)
    XCTAssertEqual(SurfaceClass.classify(bundleID: "com.google.Chrome"), .browser)
    XCTAssertEqual(SurfaceClass.classify(bundleID: "com.microsoft.VSCode"), .code)
    XCTAssertEqual(SurfaceClass.classify(bundleID: "com.apple.Terminal"), .terminal)
    XCTAssertEqual(SurfaceClass.classify(bundleID: "com.apple.Notes"), .other)
    XCTAssertEqual(SurfaceClass.classify(bundleID: nil), .other)
}
```

**Implementation:** `enum SurfaceClass { case email, chat, browser, code, terminal, other }`
with lowercase bundle-id prefix tables (our own lists: Mail, Outlook, Spark,
Superhuman, Mimestream; Slack, Teams, Discord, Messages, WhatsApp, Telegram,
Signal; Safari, Chrome, Arc, Dia, Brave, Edge, Firefox, Zen, Orion; Xcode,
VS Code, Cursor, Zed, JetBrains, Sublime, Nova; Terminal, iTerm2, Ghostty,
Warp, WezTerm, kitty, Alacritty). Run → PASS → commit.

### Task 2.2: Surface line

**Files:** Create `PUSHCore/Autocomplete/SurfaceLine.swift`; test `AutocompleteSurfaceLineTests.swift`.

**Tests:**

```swift
func testChat() {
    let line = SurfaceLine.render(surface: .chat, appName: "Slack",
        windowTitle: "#design - Slack", url: nil, placeholder: "Message #design")
    XCTAssertEqual(line, "Format: chat; App: Slack; Title: #design; Field: Message #design.")
}
func testBrowserAddsHostOnly() {
    let line = SurfaceLine.render(surface: .browser, appName: "Google Chrome",
        windowTitle: "Inbox (3) - you@gmail.com - Gmail - Google Chrome",
        url: "https://www.mail.google.com/mail/u/0/#inbox?x=1", placeholder: nil)
    XCTAssertEqual(line, "Format: web text; App: Google Chrome; Domain: mail.google.com; Title: Inbox (3) - you@gmail.com - Gmail.")
}
func testCodeAndTerminalGetNothing() {
    XCTAssertNil(SurfaceLine.render(surface: .code, appName: "Xcode", windowTitle: "x", url: nil, placeholder: nil))
    XCTAssertNil(SurfaceLine.render(surface: .terminal, appName: "Terminal", windowTitle: "x", url: nil, placeholder: nil))
}
func testOtherWithNoFactsGetsNothing() {
    XCTAssertNil(SurfaceLine.render(surface: .other, appName: "Notes", windowTitle: nil, url: nil, placeholder: nil))
}
func testTitleCappedAt80AndQuotesRemoved() {
    let long = String(repeating: "a", count: 200) + "\""
    let line = SurfaceLine.render(surface: .other, appName: "Pages", windowTitle: long, url: nil, placeholder: nil)!
    XCTAssertEqual(line, "Format: text; App: Pages; Title: \(String(repeating: "a", count: 80)).")
}
```

**Implementation:** strip control chars and `"`, collapse whitespace, remove a
trailing ` - App` / ` — App` / ` – App` (case-insensitive), cap title 80 and
placeholder 60, host via `URL(string:)?.host` minus `www.`. Run → PASS → commit.

### Task 2.3: Section budget

**Files:** Create `PUSHCore/Autocomplete/PromptBudget.swift`; test `AutocompletePromptBudgetTests.swift`.

**Tests:**

```swift
func testHighestPriorityFilledFirstAndOrderPreserved() {
    let out = PromptBudget.fit([
        .init(name: "a", text: "AAAA", priority: 10, keep: .start),
        .init(name: "p", text: "PPPPPP", priority: 100, keep: .end),
    ], total: 8)
    XCTAssertEqual(out.map(\.name), ["a", "p"])
    XCTAssertEqual(out.last!.text, "PPPPPP")
    XCTAssertEqual(out.first!.text, "A")        // 8 - 6 - 1 separator = 1
}
func testKeepEndTrimsFromTheFront() {
    let out = PromptBudget.fit([.init(name: "p", text: "hello world", priority: 100, keep: .end)], total: 5)
    XCTAssertEqual(out.first!.text, "world")
}
func testAllOrNothingSectionIsDroppedWhole() {
    let out = PromptBudget.fit([
        .init(name: "p", text: "PPPP", priority: 100, keep: .end),
        .init(name: "q", text: "“quoted”", priority: 50, keep: .start, allOrNothing: true),
    ], total: 8)
    XCTAssertEqual(out.map(\.name), ["p"])
}
func testSectionCap() {
    let out = PromptBudget.fit([.init(name: "a", text: "abcdef", priority: 1, keep: .start, cap: 3)], total: 100)
    XCTAssertEqual(out.first!.text, "abc")
}
```

**Implementation:** visit sections by priority (desc, stable); allowance =
`min(cap ?? .max, remaining)`; all-or-nothing sections need the full length;
empty results are dropped; each kept section costs `count + 1` (newline);
return kept sections in input order. Run → PASS → commit.

### Task 2.4: Prompt renderer

**Files:** Create `PUSHCore/Autocomplete/AutocompletePrompt.swift`; test `AutocompletePromptTests.swift`.

**Input:** `AutocompleteContext { before, after, surfaceLine?, style?, language?, userName?, clipboard?, screen?, examples: [String] }`.

**Tests (behaviour, not exact prose):**
- caret text is the exact last bytes of the prompt
- no context → prompt == `before`
- surface line comes first; a blank line separates preface from `before`
- `after` rendered as `Later in the same passage:\n“…”` (≤ 200 chars), dropped whole under pressure
- name appears only when `before` ends at a sign-off (`Thanks,`, `Best,`, `Cheers,`, `Regards,` + optional newline)
- total length ≤ budget (default 6,000) and `before` never trimmed below its last 1,000 chars

Priorities: before 100, after 80, surface 70, name 60, style 55, language 50,
examples 38 (all-or-nothing), screen 45, clipboard 35. Run → PASS → commit.

### Task 2.5: Suggestion normaliser

**Files:** Create `PUSHCore/Autocomplete/SuggestionText.swift`; test `AutocompleteSuggestionTextTests.swift`.

**Tests:**

```swift
func testCutsAtNewlineAndWordLimit() {
    XCTAssertEqual(SuggestionText.clean(" ups for the onboarding flow today\nNext", maxWords: 4), " ups for the onboarding")
}
func testRejectsEmptyOrPunctuationOnly() {
    XCTAssertNil(SuggestionText.clean("  \n", maxWords: 6))
    XCTAssertNil(SuggestionText.clean(" ...", maxWords: 6))
}
func testRejectsPrefaceLeaks() {
    XCTAssertNil(SuggestionText.clean(" Format: chat; App: Slack", maxWords: 6))
}
func testNextChunkIsOneWordWithItsLeadingSpace() {
    XCTAssertEqual(SuggestionText.nextChunk(of: " for the flow"), " for")
    XCTAssertEqual(SuggestionText.nextChunk(of: "ups for"), "ups")
    XCTAssertEqual(SuggestionText.nextChunk(of: " flow."), " flow.")
}
func testRemainderAfterTyping() {
    // User typed "f" while " for the flow" was showing.
    XCTAssertEqual(SuggestionText.remainder(of: " for the flow", afterTyping: " f"), "or the flow")
    XCTAssertNil(SuggestionText.remainder(of: " for the flow", afterTyping: " x"))
}
```

Run → PASS → commit.

**Phase 2 checkpoint:** `swift test` green; the eval runner (Task 0.2) can
optionally switch to building prompts through `AutocompletePrompt` via a tiny
CLI in `compare/` so eval and app share one prompt.

---

## Phase 3 — Engine and models (expand at phase start)

- **3.1 `LlamaEngine` actor** (`PUSHCore/Autocomplete/LlamaEngine.swift`): load/unload, `complete(prompt:maxTokens:) -> AsyncStream<String>`, cancellation per token, KV-cache reuse of the longest common token prefix with the previous request, UTF-8-safe detokenising. Replaces `LlamaSmoke`. Tests: gated on `PUSH_LLAMA_SMOKE_MODEL`; prefix reuse measurably cuts second-call prompt time.
- **3.2 `TypingModel` catalog** (`PUSHCore/Autocomplete/TypingModel.swift`): the three Phase-0 picks with repo, file, pinned revision, byte size, SHA-256, licence. Test: every entry has all fields; URLs are revision-pinned.
- **3.3 `TypingModelStore`** (`PUSH/Autocomplete/`): downloads to `~/Library/Application Support/PUSH/TypingModels/` with progress (real byte progress, unlike speech), resume, SHA-256 verify, delete. Never downloads at launch (same rule as speech).
- **3.4 Lifecycle**: load the selected model when Autocomplete turns on, unload when off; `PushLogger` events only.

## Phase 4 — Live autocomplete (expand at phase start)

- **4.1 `FocusReader`**: focused element, value, selected range, `before`/`after` windows, placeholder, window title, URL host (web area / window `kAXURLAttribute`), caret rect via `kAXBoundsForRangeParameterizedAttribute`; secure-field check. All AX on the main actor with tight timeouts (`AXUIElementSetMessagingTimeout`).
- **4.2 `AutocompleteKeyTap`**: own `CGEvent` tap (keyDown only). Consumes `Tab`/`Esc` only while a suggestion is visible; re-enables itself on `tapDisabledByTimeout`; callback does no work beyond enqueueing.
- **4.3 `GhostTextPanel`**: non-activating, click-through `NSPanel`, `.screenSaver`-safe level, `sharingType` default; draws gray text at the caret rect with font size from caret height.
- **4.4 `AutocompleteCoordinator`**: debounce 150 ms, request identity (focus + text hash + caret), cancel on keystroke, `SuggestionText.remainder` to keep a suggestion alive while the user types into it, hide during dictation and teleprompter, per-app exclusions, never logs text.
- **4.5 Accept**: `Tab` types `nextChunk` via `KeystrokeTyper` (fallback `TextInjector` for apps that failed in Task 0.6); `⌥Tab` accepts all.
- **Verify** in Mail, Slack, Chrome (Gmail), Safari, Notes, Messages; 375-px-wide isn't relevant here, but test on the built-in display and an external one (caret rect coordinates differ per screen).

## Phase 5 — Settings, menu bar, onboarding (expand at phase start)

- **5.1 Settings → Autocomplete pane** (`SettingsView.Pane.autocomplete`): switch, model cards (same look as speech cards), length, excluded apps, accept key.
- **5.2 Menu bar row**: on/off, "Pause for <App>".
- **5.3 Onboarding `.typingModel` step**: real model cards + download; remove the Phase-1 "Coming soon" gate.
- **5.4 Onboarding try-it**: a text field with live suggestions when autocomplete is on.
- **Verify** with screenshots of every new screen, light and dark.

## Phase 6 — More context (each opt-in, off by default; expand at phase start)

- **6.1 Custom instructions** text field → `style` section.
- **6.2 Clipboard**: change-count baseline, 5-minute freshness, shared-word rule.
- **6.3 Screen text**: Screen Recording permission row, ScreenCaptureKit window capture, Vision OCR off the main actor, nearest-lines selection, pixel-hash cache.
- **6.4 Own-writing examples**: local store of the user's accepted/typed sentences, never synced, delete button.
- Re-run the Phase 0 eval with each source on/off before enabling by default anywhere.

## Phase 7 — Release

- Version bump in `PUSH/Info.plist` (build number > live build), release notes,
  `./build_distribution.sh` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
  install the DMG on a clean account and walk onboarding with all three
  combinations, then commit `appcast.xml`. Update `docs/MODELS.md`, `CLAUDE.md`
  (Autocomplete section, insertion exception) and `NOTES.md`.
