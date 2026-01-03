# PUSH - Voice to Text for macOS

## Overview
Native macOS menu bar app for push-to-talk voice transcription with offline AI formatting.

## Core Requirements
- **Hotkey:** Hold Right Option (⌥) to record, release to process and insert
- **Transcription:** Whisper.cpp (offline)
- **Formatting:** Qwen 3 via llama.cpp (offline) - adds punctuation, capitalization, list formatting
- **Text injection:** Accessibility API into any active text field
- **UI:** Menu bar icon + minimal floating pill when listening

## Tech Stack
- Swift + SwiftUI
- whisper.cpp (via WhisperKit or direct bindings)
- llama.cpp (Swift bindings for Qwen inference)
- macOS Accessibility API

## Models (Curated List)

| Model | Size | Default |
|-------|------|---------|
| Whisper tiny.en | ~75MB | |
| Whisper base.en | ~150MB | ✓ |
| Whisper small.en | ~500MB | |
| Qwen 3 0.6B | ~400MB | |
| Qwen 3 1.7B | ~1.2GB | ✓ |
| Qwen 3 4B | ~2.5GB | |

Storage: `~/Library/Application Support/PUSH/models/`

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
│   │   ├── WhisperEngine.swift         # whisper.cpp wrapper
│   │   ├── QwenEngine.swift            # llama.cpp wrapper
│   │   └── ModelManager.swift          # Download, storage, loading
│   ├── Resources/
│   │   └── Assets.xcassets
│   └── Info.plist
└── Libraries/                           # whisper.cpp, llama.cpp
```

## Implementation Phases

### Phase 1: Project Setup
- Create Xcode project with SwiftUI lifecycle
- Configure as menu bar app (LSUIElement)
- Set up Info.plist for microphone and accessibility permissions
- Integrate whisper.cpp and llama.cpp as Swift packages or local builds

### Phase 2: Core Infrastructure
- `HotkeyManager.swift` - Global hotkey monitoring using CGEvent/NSEvent
- `AudioRecorder.swift` - AVAudioEngine microphone capture to buffer
- `TextInjector.swift` - Accessibility API to paste/type into active field

### Phase 3: ML Engines
- `WhisperEngine.swift` - Load whisper.cpp model, transcribe audio buffer
- `QwenEngine.swift` - Load llama.cpp model, format text with prompt
- `ModelManager.swift` - Download models from HuggingFace, track progress, manage storage

### Phase 4: UI
- `MenuBarView.swift` - Status icon, dropdown menu (Settings, Quit)
- `FloatingPillView.swift` - Minimal overlay showing "Listening..." / "Processing..."
- `SettingsView.swift` - General (hotkey, start at login), Models (selection + download)

### Phase 5: Pipeline Integration
- `TranscriptionPipeline.swift` - Orchestrate: audio → whisper → qwen → inject
- Wire up hotkey → pipeline → UI state changes
- Handle errors gracefully (no model, permission denied, etc.)

### Phase 6: Polish
- Start at login (LaunchAtLogin)
- First-launch onboarding (download default models)
- App icon and branding

## Qwen Formatting Prompt
```
You are a text formatter. Take the raw speech transcription and output
properly formatted text with correct punctuation, capitalization, and
paragraph breaks.

Rules:
- Fix punctuation (periods, commas, question marks)
- Capitalize properly (sentences, names, "I")
- Format numbered lists properly (1. 2. 3.)
- Use context for homophones (their/there/they're, your/you're, here/hear)
- Do NOT add, remove, or rephrase words
- Handle dictation commands: "new line" → newline, "period" → .

Output ONLY the formatted text, nothing else.
```

## User Flow
1. App runs in menu bar (icon visible)
2. User holds Right Option key
3. Floating pill appears: "Listening..."
4. User speaks
5. User releases Right Option key
6. Pill changes: "Processing..."
7. Whisper transcribes → Qwen formats
8. Formatted text inserted at cursor
9. Pill disappears

## Deferred (v2+)
- Custom model URLs from Hugging Face
- Symbol dictation for coding ("open paren" → `(`)
- Technical term casing (JavaScript, API, JSON)
- Multi-language support
- Real-time transcription display
