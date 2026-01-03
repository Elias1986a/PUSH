# PUSH

Push-to-talk voice to text for macOS with offline AI.

## Features

- **Push-to-talk**: Hold Right Option (⌥) to speak, release to insert text
- **Offline AI**: Uses OpenAI Whisper for accurate speech recognition
- **Works everywhere**: Injects text into any app's text field
- **Privacy-first**: All processing happens locally, no cloud APIs
- **Menu bar app**: Unobtrusive - lives in your menu bar with floating pill UI

## Requirements

- macOS 14.0+
- ~500MB disk space for Whisper model
- Microphone
- Accessibility permissions (for global hotkey + text injection)

## Installation

### Option 1: Download Pre-built App (Coming Soon)
Download the latest release from the [Releases](https://github.com/yourusername/PUSH/releases) page.

### Option 2: Build from Source

**You'll need:**
- Xcode installed (free from the Mac App Store)

**Steps:**

1. **Download the code:**
   - Click the green "Code" button at the top of this page
   - Select "Download ZIP"
   - Unzip the downloaded file

2. **Open in Xcode:**
   - Double-click `Package.swift` in the unzipped folder
   - Wait for Xcode to load the project

3. **Build the app:**
   - In Xcode, click Product → Run (or press ⌘R)
   - The app will build and launch automatically

### First Launch Setup

When you run PUSH for the first time:

1. **Grant Microphone Permission:**
   - A popup will ask for microphone access
   - Click "OK" to allow

2. **Grant Accessibility Permission:**
   - Go to  → System Settings → Privacy & Security → Accessibility
   - Click the lock icon and enter your password
   - Find "PUSH" in the list and enable the checkbox
   - If PUSH isn't in the list, click the "+" button and add it

3. **Download the Whisper Model:**
   - Click the PUSH icon in your menu bar (top-right of screen)
   - Select "Settings"
   - Go to the "Models" tab
   - Choose a model size (Small is recommended for best quality)
   - Click "Download" - this may take a few minutes

4. **You're ready!**
   - Click anywhere in a text field (Notes, Messages, email, etc.)
   - Hold the Right Option (⌥) key
   - Speak your text
   - Release the key and your text will appear!

## How to Use

**Basic Usage:**
1. Click in any text field where you want text to appear
2. Hold down the **Right Option (⌥)** key (bottom-right of keyboard)
3. Speak clearly into your microphone
4. Release the key when done
5. Wait a moment - your transcribed text will appear!

**Visual Feedback:**
- While holding the key, you'll see a floating pill with animated dots
- This shows PUSH is listening to you

**Changing the Hotkey:**
- Click the PUSH menu bar icon
- Go to Settings → General
- Choose a different key from the dropdown

**Choosing a Different Model:**
- Click the PUSH menu bar icon
- Go to Settings → Models
- Select and download the model you prefer

## Whisper Models

PUSH uses OpenAI's Whisper for speech recognition. Choose the model that fits your needs:

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| Whisper Tiny | 75 MB | Very Fast | Good | Quick transcription, slower computers |
| Whisper Base | 150 MB | Fast | Better | Balanced speed and accuracy |
| Whisper Small | 500 MB | Slower | **Best** | **Highest quality (Recommended)** |

**Which should I choose?**
- **Whisper Small** - Recommended for most users. Best transcription quality.
- **Whisper Base** - Good balance if you want faster processing
- **Whisper Tiny** - Choose if you have an older Mac or need very fast results

**Where are models stored?**
```
~/Library/Application Support/PUSH/models/
```

You can delete models you're not using to free up disk space.

## Permissions Explained

PUSH needs two permissions to work:

### Microphone Access
- **Why?** To record your voice when you hold the hotkey
- **When?** Only while you're holding the Right Option key
- **Privacy:** Audio never leaves your computer

### Accessibility Access
- **Why?** To detect when you press the hotkey and to insert text into apps
- **When?** Required for the app to work
- **Privacy:** PUSH only monitors the specific hotkey you choose

**Your privacy is protected:** All voice processing happens on your Mac. Nothing is sent to the internet.

## Tech Stack

Built with:
- **Swift + SwiftUI** - Native macOS app
- **[WhisperKit](https://github.com/argmaxinc/WhisperKit)** - High-quality speech recognition
- **Metal acceleration** - Uses your Mac's GPU for fast processing

## License

MIT
