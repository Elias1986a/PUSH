# PUSH - Voice to Text App

## Installation & Setup

### 1. Remove Old Permissions
1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Find any existing "PUSH" entries in the list
3. Click the `-` button to remove them

### 2. Add New App
1. In the same Accessibility settings window, click the `+` button
2. Navigate to: `/Users/kingpin/Documents/GitHub/PUSH/PUSH-Xcode/PUSH.app`
3. Select it and click **Open**
4. Make sure the checkbox next to PUSH is **enabled**

### 3. Add Microphone Permission (if needed)
1. Open **System Settings** > **Privacy & Security** > **Microphone**
2. Enable PUSH if it appears there

### 4. Launch the App
```bash
open /Users/kingpin/Documents/GitHub/PUSH/PUSH-Xcode/PUSH.app
```

You should see:
- A microphone icon in the menu bar
- Console logs showing "Started listening for Right Option key"

### 5. Test Push-to-Talk
1. Click in any text field (Notes, Messages, etc.)
2. **Hold** the Right Option (⌥) key
3. Speak your text
4. **Release** the Right Option key
5. Text should appear after processing

## Troubleshooting

### App keeps asking for Accessibility permission
- Make sure you added the `.app` bundle from `PUSH-Xcode/PUSH.app`, not the SPM executable
- Check that the bundle identifier is `com.push.voicetotext` (run `codesign -dv PUSH.app`)

### No menu bar icon appears
- Check Console.app for error messages
- Make sure `LSUIElement` is set to `true` in Info.plist (hides dock icon)

### Microphone not working
- Check System Settings > Privacy & Security > Microphone
- Grant permission to PUSH

### Models not downloading
- First launch will download ~150MB Whisper model
- Check internet connection
- View progress in Console.app

## Rebuilding

If you make code changes:

```bash
cd /Users/kingpin/Documents/GitHub/PUSH
./build_xcode_project.sh
```

This will:
1. Build the release binary
2. Create a proper .app bundle
3. Copy frameworks
4. Code sign the app

## File Locations

- **App Bundle**: `PUSH-Xcode/PUSH.app`
- **Models**: `~/Library/Application Support/PUSH/models/`
- **Source Code**: `PUSH/` directory
