# PUSH

Push-to-talk voice to text for macOS with offline AI.

## Features

- **Push-to-talk**: Hold Right Option (⌥) to speak, release to insert text
- **Offline AI**: Uses Whisper for transcription + Qwen for formatting
- **Works everywhere**: Injects text into any app's text field
- **Privacy-first**: All processing happens locally, no cloud APIs
- **Smart formatting**: Punctuation, capitalization, numbered lists

## Requirements

- macOS 14.0+
- ~1.5GB disk space for default models
- Microphone
- Accessibility permissions (for global hotkey + text injection)

## Installation

### Build from source

1. Clone the repo:
   ```bash
   git clone https://github.com/yourusername/PUSH.git
   cd PUSH
   ```

2. Build with Swift Package Manager:
   ```bash
   swift build -c release
   ```

3. Or open in Xcode:
   ```bash
   open Package.swift
   ```

### First launch

1. Grant microphone permission when prompted
2. Grant accessibility permission in System Settings
3. Download the default models in Settings → Models
4. Hold Right Option key to start speaking!

## Usage

1. **Menu bar icon**: Shows PUSH status
2. **Hold Right Option (⌥)**: Start speaking
3. **Release key**: Text gets processed and inserted at cursor

### Hotkey

Default: **Right Option (⌥)** - hold to speak

The hotkey can be changed in Settings → General.

## Models

PUSH uses two AI models:

### Speech Recognition (Whisper)
| Model | Size | Speed |
|-------|------|-------|
| Whisper Tiny | 75 MB | Fastest |
| Whisper Base | 150 MB | **Default** |
| Whisper Small | 500 MB | Most accurate |

Models are downloaded from Hugging Face and stored in:
```
~/Library/Application Support/PUSH/models/
```

## Permissions

PUSH requires:
- **Microphone**: To capture your speech
- **Accessibility**: To detect the global hotkey and inject text

## Tech Stack

- Swift + SwiftUI
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Speech-to-text
- Metal acceleration for fast inference

## License

MIT
