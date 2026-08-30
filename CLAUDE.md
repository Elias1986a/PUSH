# CLAUDE.md — PUSH

## Project Overview
PUSH is a macOS menu bar app for offline voice-to-text dictation. Hold a hotkey
(or say a wake word), speak, and the transcription is pasted into the focused
text field of any app. All speech recognition runs on-device.

## Tech Stack
- Swift, Swift Package Manager executable target (no Xcode project)
- ASR engines: FluidAudio Parakeet (TDT v2 / Unified / Streaming) + Apple Speech
  (macOS 26+). WhisperKit and Moonshine were removed in v7.0.0 — don't reinstate
  them without re-measuring; Parakeet won on the ANE, not on CPU.
- Silero VAD via FluidAudio; Sparkle auto-updates; LaunchAtLogin

## Commands
- `swift build` — build
- `swift test` — unit tests (Tests/PUSHTests; text post-processing + context gate)
- `swift run` — run the app
- `./build_distribution.sh` — signed/notarized release ZIP + DMG + Sparkle appcast
  (requires the Xcode-beta toolchain; CLT's Foundation breaks FluidAudio)

## Project Structure
- `PUSH/App` — entry point, AppDelegate, shared AppState
- `PUSH/Core` — TranscriptionPipeline+App, HotkeyManager, AudioRecorder, SileroVAD,
  WakeWordListener, ModelLoader, CorrectionsStore/ContextGate, TextInjector
- `PUSHCore` — library target: engine wrappers (ParakeetEngine, ParakeetUnified,
  ParakeetStreaming, AppleSpeechEngine), TextProcessing, WhisperModel, PushLogger.
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
- Never log transcript text (privacy); PushLogger events are operational only.
- Version lives in `PUSH/Info.plist`; commit `appcast.xml` after each release.
