# PUSH Distribution Guide

This guide explains how to build and distribute PUSH for free download (notarized for macOS Gatekeeper).

## Prerequisites

### 1. Apple Developer Account
You already have this! ✅

### 2. Set Up Notarization Credentials (One-time setup)

Apple requires an **app-specific password** for notarization:

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. In the **Security** section, click **App-Specific Passwords**
4. Click **Generate an app-specific password**
5. Name it "PUSH Notarization" and copy the generated password

Then store it in your keychain:

```bash
xcrun notarytool store-credentials "notarytool-profile" \
  --apple-id "your-apple-id@email.com" \
  --team-id "B8R5B24PMP" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Replace:
- `your-apple-id@email.com` with your actual Apple ID
- `xxxx-xxxx-xxxx-xxxx` with the app-specific password you just created

You only need to do this once!

## Building for Distribution

### Quick Build

```bash
./build_distribution.sh
```

This script will:
1. ✅ Build the release binary
2. ✅ Create the app bundle
3. ✅ Sign with your Developer ID certificate
4. ✅ Submit to Apple for notarization (~5-10 minutes)
5. ✅ Staple the notarization ticket
6. ✅ Create both ZIP and DMG files

### What You'll Get

After the script completes, you'll have:

- `PUSH-Xcode/PUSH.app` - The signed and notarized app
- `PUSH-v1.0.0.zip` - Ready to upload to GitHub Releases
- `PUSH-v1.0.0.dmg` - Nice drag-and-drop installer

## Creating a GitHub Release

1. Go to your GitHub repository
2. Click **Releases** → **Create a new release**
3. Create a new tag (e.g., `v1.0.0`)
4. Set the release title: "PUSH v1.0.0"
5. Write release notes describing what's new
6. Drag and drop `PUSH-v1.0.0.dmg` (or `.zip`) to the attachments area
7. Click **Publish release**

## What Users Will Experience

When users download and open PUSH:

✅ **No scary warnings** - App is notarized by Apple
✅ **First launch** - macOS asks for Microphone permission
✅ **Accessibility** - Users grant in System Settings → Privacy & Security
✅ **Download models** - Users choose and download Whisper model in app
✅ **Ready to use!**

## Troubleshooting

### "Notarization failed"

Check the logs:
```bash
xcrun notarytool log <submission-id> --keychain-profile "notarytool-profile"
```

Common issues:
- Missing entitlements
- Unsigned frameworks
- Hardened runtime issues

### "Code signing failed"

Make sure your Developer ID certificate is valid:
```bash
security find-identity -v -p codesigning
```

You should see: `Developer ID Application: Elias Atalah (B8R5B24PMP)`

### Building for Development (No Notarization)

For local testing, use the faster build script:
```bash
./build_xcode_project.sh
```

This creates a signed app but doesn't submit for notarization.

## Version Updates

When releasing a new version:

1. Update version in `PUSH/Info.plist`:
   ```xml
   <key>CFBundleShortVersionString</key>
   <string>1.1.0</string>
   <key>CFBundleVersion</key>
   <string>2</string>
   ```

2. Update `ZIP_NAME` and `DMG_NAME` in `build_distribution.sh`:
   ```bash
   ZIP_NAME="PUSH-v1.1.0.zip"
   DMG_NAME="PUSH-v1.1.0.dmg"
   ```

3. Run `./build_distribution.sh`

4. Create new GitHub Release with new version tag

## Auto-Updates (Optional)

If you want to add automatic update checking in the future, consider:
- [Sparkle](https://sparkle-project.org/) - Industry standard for Mac apps
- Requires hosting an `appcast.xml` file with version info
- Can be added later without breaking existing installations

## Support

If users have issues:
- Check they granted Microphone and Accessibility permissions
- Verify they downloaded a Whisper model
- Direct them to GitHub Issues for bug reports
