# PUSH - Voice to Text for macOS

## Overview
Native macOS menu bar app for push-to-talk voice transcription with offline AI.

## Core Requirements
- **Hotkey:** Hold Right Option (⌥) to record, release to process and insert
- **Transcription:** Whisper via WhisperKit (offline, high-quality speech recognition)
- **Text injection:** Accessibility API into any active text field
- **UI:** Menu bar icon + minimal floating pill when listening

## Tech Stack
- Swift + SwiftUI
- WhisperKit (OpenAI Whisper models)
- macOS Accessibility API

## Models (Curated List)

| Model | Size | Default | Notes |
|-------|------|---------|-------|
| Whisper Tiny | ~75MB | | Fastest, good for older Macs |
| Whisper Base | ~150MB | | Balanced speed/quality |
| Whisper Small | ~500MB | ✓ | Best quality (recommended) |

Storage: `~/Library/Application Support/PUSH/models/`

**Note:** Whisper Small provides excellent transcription quality with proper punctuation and capitalization built-in, eliminating the need for a separate formatting model.

## Required Permissions
- Microphone access
- Accessibility (global hotkey + text injection)

## Project Structure
```
PUSH/
├── PUSH.xcodeproj
├── PUSH/
│   ├── App/
│   │   ├── PUSHApp.swift              # Entry point, menu bar setup
│   │   └── AppDelegate.swift           # Lifecycle, permissions
│   ├── Views/
│   │   ├── MenuBarView.swift           # Menu bar dropdown
│   │   ├── FloatingPillView.swift      # Listening indicator
│   │   └── SettingsView.swift          # Settings window
│   ├── Core/
│   │   ├── HotkeyManager.swift         # Global hotkey listener
│   │   ├── AudioRecorder.swift         # Microphone capture
│   │   ├── TextInjector.swift          # Accessibility API injection
│   │   └── TranscriptionPipeline.swift # Orchestrates the flow
│   ├── ML/
│   │   ├── WhisperEngine.swift         # WhisperKit wrapper
│   │   └── ModelManager.swift          # Download, storage, loading
│   ├── Resources/
│   │   └── Assets.xcassets
│   └── Info.plist
└── Libraries/                           # WhisperKit dependency
```

## Implementation Phases

### Phase 1: Project Setup ✓
- Create Xcode project with SwiftUI lifecycle
- Configure as menu bar app (LSUIElement)
- Set up Info.plist for microphone and accessibility permissions
- Integrate WhisperKit as Swift package

### Phase 2: Core Infrastructure ✓
- `HotkeyManager.swift` - Global hotkey monitoring using CGEvent/NSEvent
- `AudioRecorder.swift` - AVAudioEngine microphone capture to buffer
- `TextInjector.swift` - Accessibility API to paste/type into active field

### Phase 3: ML Engine ✓
- `WhisperEngine.swift` - WhisperKit integration, transcribe audio buffer
- `ModelManager.swift` - Download Whisper models, track progress, manage storage

### Phase 4: UI ✓
- `MenuBarView.swift` - Status icon, dropdown menu (Settings, Quit)
- `FloatingPillView.swift` - Minimal overlay showing "Listening..." with animated dots
- `SettingsView.swift` - General (hotkey), Models (Whisper model selection + download)

### Phase 5: Pipeline Integration ✓
- `TranscriptionPipeline.swift` - Orchestrate: audio → whisper → inject
- Wire up hotkey → pipeline → UI state changes
- Handle errors gracefully (no model, permission denied, etc.)
- Audio filtering to skip silence/blank recordings

### Phase 6: Polish ✓
- Optional Nextel chirp sound when recording starts
- Proper macOS app bundle with code signing
- Menu bar notifications for errors
- Build script for development

## User Flow
1. App runs in menu bar (microphone icon visible)
2. User clicks in any text field
3. User holds Right Option key (or configured hotkey)
4. Optional Nextel chirp plays (if enabled)
5. Floating pill appears with animated bouncing dots
6. User speaks clearly
7. User releases Right Option key
8. Pill shows "Processing..."
9. Whisper transcribes audio (with built-in punctuation/capitalization)
10. Formatted text inserted at cursor via clipboard
11. Pill disappears

## Deferred (v2+)
- Custom model URLs from Hugging Face
- Symbol dictation for coding ("open paren" → `(`)
- Technical term casing (JavaScript, API, JSON)
- Multi-language support
- Real-time transcription display
