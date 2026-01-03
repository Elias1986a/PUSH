# PUSH - Setup Guide

This guide will help you set up PUSH after building it from source.

## Quick Start

### 1. Grant Permissions

PUSH needs two permissions to work properly:

#### Microphone Permission
1. When you first launch PUSH, macOS will ask for microphone access
2. Click **OK** or **Allow**

#### Accessibility Permission
1. Open **System Settings** (click the  menu → System Settings)
2. Go to **Privacy & Security** → **Accessibility**
3. You may need to click the 🔒 lock icon and enter your password
4. Look for "PUSH" in the list:
   - If it's there, make sure the checkbox is **enabled** ✓
   - If it's not there, click the **+** button and find the PUSH app to add it

### 2. Download a Whisper Model

1. Look for the microphone icon in your **menu bar** (top-right corner of your screen)
2. Click on it and select **Settings**
3. Go to the **Models** tab
4. Choose a model:
   - **Whisper Small** - Recommended for best quality (500 MB)
   - **Whisper Base** - Faster, still accurate (150 MB)
   - **Whisper Tiny** - Fastest option (75 MB)
5. Click **Download** and wait for it to complete

### 3. Test It Out!

1. Open any app where you can type (Notes, Messages, Mail, etc.)
2. Click in a text field
3. **Hold down** the **Right Option (⌥)** key (bottom-right of your keyboard)
4. You'll see a floating pill with animated dots - this means PUSH is listening
5. **Speak** your message clearly
6. **Release** the Right Option key
7. Wait a moment and your text should appear!

## Troubleshooting

### "PUSH keeps asking for Accessibility permission"
- Make sure you granted permission to the correct PUSH app
- In System Settings → Privacy & Security → Accessibility, verify PUSH is in the list and enabled
- Try removing PUSH from the list (click the - button) and adding it again

### "I don't see the menu bar icon"
- Make sure PUSH is actually running - check Activity Monitor
- Try quitting and restarting PUSH
- The icon is small and looks like a microphone

### "The microphone doesn't seem to work"
- Check System Settings → Privacy & Security → Microphone
- Make sure PUSH is in the list and enabled
- Try speaking louder and more clearly
- Make sure your Mac's microphone is working (test with Voice Memos app)

### "No text appears when I release the key"
- Make sure you downloaded a Whisper model (see step 2 above)
- Make sure you clicked in a text field before holding the hotkey
- Check that you're holding the correct key (Right Option by default)
- Try speaking more slowly and clearly

### "The model won't download"
- Check your internet connection
- The download can take several minutes depending on which model and your connection speed
- Try quitting PUSH and downloading again

## For Developers

### Rebuilding After Code Changes

If you've made changes to the code:

```bash
cd /path/to/PUSH
./build_xcode_project.sh
```

This script will:
1. Build the release binary
2. Create the .app bundle
3. Copy necessary frameworks
4. Code sign the application

### File Locations

- **App Bundle**: `PUSH-Xcode/PUSH.app`
- **Downloaded Models**: `~/Library/Application Support/PUSH/models/`
- **Source Code**: Main `PUSH/` directory

### Checking Code Signature

To verify the app is properly signed:
```bash
codesign -dv PUSH-Xcode/PUSH.app
```

You should see `com.push.voicetotext` as the identifier.

## Need Help?

If you're still having trouble, please [open an issue](https://github.com/yourusername/PUSH/issues) with:
- Your macOS version
- Which step you're stuck on
- Any error messages you see
