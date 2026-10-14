# CLAUDE.md — PUSH

## Project Overview
Users see the name **PUSHTYPE** (since 9.1.0); the bundle id, executable,
`PUSH.app`, prefs domain and Application Support/PUSH stay PUSH.
PUSH is a macOS menu bar app for offline voice-to-text dictation. Hold a hotkey
(or say a wake word), speak, and the transcription is pasted into the focused
text field of any app. All speech recognition runs on-device.

## Tech Stack
- Swift, Swift Package Manager executable target (no Xcode project)
- ASR engines: FluidAudio Parakeet (Streaming = default on English Macs, Ultra
  elsewhere; `WhisperModel.defaultModel`) and
  Nemotron Multilingual. Ultra auto-detects Latin-script European languages;
  `TranscriptLanguage` reads the language back from its text. One engine per
  language: Nemotron offers only what Ultra doesn't (`TranscriptLanguage.ultraCovers`).
  WhisperKit and Moonshine were removed in v7.0.0, TDT v2 in 8.0.5, Unified in
  8.2.5 — don't
  reinstate them without re-measuring; Parakeet won on the ANE, not on CPU.
  Apple Speech was removed in 8.2.0 (last in every benchmark), and Apple's AI
  stays out of the product by the user's choice — use open models.
- Silero VAD via FluidAudio; Sparkle auto-updates; LaunchAtLogin

## Commands
- `swift build` — build
- `swift test` — unit tests (Tests/PUSHTests; text post-processing + context gate)
- `swift run` — run the app
- `./build_distribution.sh` — signed/notarized release ZIP + DMG + Sparkle appcast
  (run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; CLT's
  Foundation breaks FluidAudio)

## Project Structure
- `PUSH/App` — entry point, AppDelegate, shared AppState
- `PUSH/Core` — TranscriptionPipeline+App, HotkeyManager, AudioRecorder, SileroVAD,
  WakeWordListener, ModelLoader, CorrectionsStore/ContextGate, TextInjector
- `PUSHCore` — library target: engine wrappers (ParakeetEngine, ParakeetUnifiedFiles,
  ParakeetStreaming, NemotronMultilingualEngine), TextProcessing, WhisperModel, PushLogger.
  No SwiftUI, no resources (Bundle.module fatal-asserts in distribution builds).
- `PUSH/Views` — MenuBarView, SettingsView, FloatingPillView
- `docs/` — design docs and plans

## Key Notes
- `.build` is a symlink to `~/Library/Developer/SwiftPackages/PUSH-build` —
  iCloud evicts files under ~/Documents and hangs builds; keep the symlink.
- `AppState.activeModel` is the model actually serving transcription;
  `selectedWhisperModel` is the persisted preference. Only `ModelLoader`
  activates/deactivates models — don't load engines directly.
- Text injection is clipboard-paste only (AX APIs are unreliable across apps).
  Exception: Type's accepted words are posted as Unicode key events
  (`KeystrokeTyper`); Catalyst Messages ignores them.
- Never log transcript text (privacy); PushLogger events are operational only.
- Website house style: two spaces after every sentence and the Oxford comma. After editing a page run `python3 website/typography.py` (build_legal.py does it for the legal pages); it is idempotent.
- Feature names users see: **Talk** (voice; never Voice or Dictation as its name) and **TYPE** (all caps), and **PUSH** always in caps ("PUSH to talk", the "PUSH-to-talk key"). Plain words for the act or the category stay (speak, your voice, dictation apps, the "Dictation and autocomplete" tagline). Code identifiers and stored keys keep their names.
- American spelling in anything users see (license, color, behavior; "period", not "full stop"). Stored keys keep their old names (`licence.offered`, the Keychain services): renaming them would orphan saved data.
- Version lives in `PUSH/Info.plist`; commit `appcast.xml` after each release.
  The feed keeps every past release's `<item>`; the build script prepends.
- The chosen model is per-machine and never synced (`CloudSync.mirroredSettingKeys`),
  and launch never downloads: `ModelLoader.activateAtLaunch` loads what is already
  on disk when the saved preference is not, since only the user pressing Download
  should be able to spend 600 MB.
- Nothing under `ModelLoader.load` has a timeout — FluidAudio fetches on
  URLSession's defaults (`timeoutIntervalForResource` is 7 days), so a blocked
  huggingface.co hangs forever without throwing. Activations therefore never wait
  on each other: they cancel the one in flight and are ordered by
  `activationGeneration`, and a `stallWatchdog` reports a load that has gone 90s
  without a byte landing. Don't reintroduce awaiting the previous activation.
- Accessibility is granted by drag: `PermissionGuide.shared.show(.accessibility)`
  opens the list and floats a card holding PUSH as a drag source
  (`PUSH/Core/PermissionGuide/`). Only works from a real `.app`.
- Every window is AppKit's, created by `AppDelegate` (pill), `MenuBarController`
  (status item + popover), `OnboardingWindowController` and
  `SettingsWindowController`. SwiftUI's `MenuBarExtra` cannot produce the
  system's rounded popover chrome, and without it the `Settings` scene stops
  materialising entirely — `showSettingsWindow:` returns true while
  `NSApp.windows` holds no settings window. Don't reinstate either scene.

## Type (inline autocomplete, 9.0)
- `PUSH/Typing` (app side: TypingCoordinator, FocusReader, GhostTextPanel,
  TypingKeyTap) and `PUSHCore/Typing` (pure: TokenHealing, SuggestionJudge,
  SuggestionText, LlamaEngine on llama.cpp). Models: `docs/MODELS.md`.
- Any change to what is suggested: run the replay eval
  (`TypingReplayEvalTests`, header has the command) before and after; it goes
  through the app's own pipeline. Add scenarios for the case you fix.
- Never log typed text. Typing history is opt-in, encrypted, never synced.
- Gray is the default suggestion color; no suggestions in address bars,
  secure/sign-in fields or Mail's header rows.

## `swift run` is not the shipped app
SwiftPM builds a bare executable with no `Info.plist`. Three consequences that
have each cost a debugging session:
- **Separate preferences.** No bundle id, so `UserDefaults.standard` lands in
  domain `PUSH`, while `/Applications/PUSH.app` uses `com.push.voicetotext`.
  Settings changed in one are invisible to the other; `defaults read PUSH`.
- **No `LSUIElement`, no icon.** `AppDelegate` calls `setActivationPolicy(.accessory)`
  explicitly because macOS otherwise assigns `.prohibited` — an app that cannot
  be activated and whose windows cannot become key, which silently broke
  dictation into PUSH's own windows. `AppIconImage` falls back to a bundled PNG.
- **Different TCC identity** from the installed app, so permissions may need
  granting again for the dev build.
Test anything about focus, permissions or first launch with a real `.app`.
