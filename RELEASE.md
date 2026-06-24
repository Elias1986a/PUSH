# PUSH Release Process

## Auto-updates (Sparkle)

PUSH ships in-app updates via [Sparkle](https://sparkle-project.org). The menu bar
has a **Check for Updates…** item, and the app checks daily in the background.

**One-time setup (already done):** an EdDSA key pair lives in the login Keychain
(service `https://sparkle-project.org`, created via Sparkle's `generate_keys`). The
matching `SUPublicEDKey` is in `PUSH/Info.plist`. **Do not lose this key** — without
it you cannot sign updates existing users will accept. Back it up with
`Sparkle/bin/generate_keys -x sparkle_private_key.txt` and store it somewhere safe.

**Per release:**
1. Bump `CFBundleShortVersionString` + `CFBundleVersion` in `PUSH/Info.plist`.
2. Run `./build_distribution.sh` — it builds, signs (incl. deep-signing Sparkle's
   helpers), notarizes, staples, makes the DMG, and **regenerates `appcast.xml`**
   with a fresh EdDSA signature for the stapled zip.
3. Follow the two commands it prints at the end:
   - `gh release create v<VERSION> … PUSH-v<VERSION>.zip PUSH-v<VERSION>.dmg`
     (the tag **must** be `v<VERSION>` so it matches the appcast enclosure URL)
   - commit & push `appcast.xml` (the feed is served from
     `raw.githubusercontent.com/Elias1986a/PUSH/main/appcast.xml`)

Existing users are then offered the new version automatically. The version is read
from `Info.plist`, so you no longer hand-edit `ZIP_NAME`/`DMG_NAME` in the script.

## TL;DR - Quick Release Script

**BUILD IN /tmp TO AVOID XATTR ISSUES!** The project directory gets FinderInfo xattrs that break codesigning.
If codesigning fails with “resource fork, Finder information, or similar detritus not allowed,” build in `/tmp` and create the app bundle there (see Quick Release Script).

```bash
# 1. Update versions in: Info.plist, SettingsView.swift, build_distribution.sh
VERSION="2.1.2"  # <-- Change this

# 2. Build
swift build -c release

# 3. Create bundle in /tmp (avoids xattr issues!)
TMP="/tmp/push_build_$$"
APP="$TMP/PUSH.app"
DEV_ID="Developer ID Application: Elias Atalah (B8R5B24PMP)"
mkdir -p "$APP/Contents/"{MacOS,Resources,Frameworks}
cp .build/release/PUSH "$APP/Contents/MacOS/"
cp PUSH/Info.plist "$APP/Contents/"
cp ICON/AppIcon.icns "$APP/Contents/Resources/"
cp -R .build/release/*.bundle "$APP/Contents/Resources/"
cp -R .build/release/llama.framework "$APP/Contents/Frameworks/"
install_name_tool -change "@rpath/llama.framework/Versions/Current/llama" \
    "@executable_path/../Frameworks/llama.framework/Versions/Current/llama" "$APP/Contents/MacOS/PUSH"

# 4. Sign
find "$APP" -exec xattr -c {} \; 2>/dev/null
codesign --force --options runtime --timestamp --sign "$DEV_ID" "$APP/Contents/Frameworks/llama.framework"
codesign --force --options runtime --timestamp --entitlements PUSH/PUSH.entitlements --sign "$DEV_ID" "$APP"

# 5. Notarize
ditto -c -k --keepParent "$APP" "$TMP/PUSH-v$VERSION.zip"
xcrun notarytool submit "$TMP/PUSH-v$VERSION.zip" --keychain-profile "notarytool-profile" --wait
xcrun stapler staple "$APP"

# 6. Create DMG
mkdir "$TMP/dmg" && cp -R "$APP" "$TMP/dmg/"
hdiutil create -volname "PUSH" -srcfolder "$TMP/dmg" -ov -format UDZO "PUSH-v$VERSION.dmg"

# 7. Git & Release
git add PUSH/Info.plist PUSH/Views/SettingsView.swift build_distribution.sh
git commit -m "Release v$VERSION"
git tag "v$VERSION" && git push origin main "v$VERSION"
gh release create "v$VERSION" --title "PUSH v$VERSION" --generate-notes "PUSH-v$VERSION.dmg" "$TMP/PUSH-v$VERSION.zip"
```

---

## Pre-Release Checklist

- [ ] All features/fixes are tested locally
- [ ] Code builds without errors
- [ ] App runs correctly and core functionality works
- [ ] No sensitive data or debug code left in

## Release Process

### 1. Update Version Numbers

Update version in **two** places:

1. **PUSH/Info.plist**
   - `CFBundleShortVersionString`: User-facing version (e.g., "1.0.2")
   - `CFBundleVersion`: Build number (increment by 1)

2. **build_distribution.sh**
   - `ZIP_NAME`: Update to match new version
   - `DMG_NAME`: Update to match new version

### 2. Commit Changes

```bash
git add <changed-files>
git commit -m "fix: Your descriptive commit message

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push
```

### 3. Create Git Tag

```bash
git tag v1.0.X
git push origin v1.0.X
```

### 4. Build Distribution Package

```bash
./build_distribution.sh
```

#### Common Issue: Extended Attributes During Code Signing

**Problem:** Code signing fails with error:
```
resource fork, Finder information, or similar detritus not allowed
```

**Root Cause:** macOS extended attributes (com.apple.FinderInfo, com.apple.fileprovider.fpfs#P, etc.) interfere with code signing.

**Solution:**
1. The build script already handles this, but if issues persist:
```bash
# Clean all extended attributes
find PUSH-Xcode/PUSH.app -exec xattr -c {} \; 2>/dev/null || true

# Remove specific problematic attributes
find PUSH-Xcode/PUSH.app -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find PUSH-Xcode/PUSH.app -exec xattr -d com.apple.fileprovider.fpfs#P {} \; 2>/dev/null || true

# Clean before signing
xattr -c PUSH-Xcode/PUSH.app
```

2. If you see duplicate frameworks (e.g., "llama 2.framework" and "llama.framework"):
```bash
rm -rf ".build/release/llama 2.framework"
```

3. Rebuild from scratch:
```bash
rm -rf PUSH-Xcode/PUSH.app
./build_xcode_project.sh
```

### 5. Handle Notarization (Optional)

The build script will pause for notarization credentials. If you don't have these set up:

**Option A: Skip notarization** (users will need to right-click > Open)
- Press Ctrl+C when prompted
- Manually create DMG:
```bash
rm -rf dmg_temp
mkdir -p dmg_temp
cp -R PUSH-Xcode/PUSH.app dmg_temp/
hdiutil create -volname "PUSH" -srcfolder dmg_temp -ov -format UDZO PUSH-v1.0.X.dmg
rm -rf dmg_temp
```

**Option B: Set up notarization** (one-time setup)
```bash
xcrun notarytool store-credentials "notarytool-profile" \
  --apple-id "your-apple-id@email.com" \
  --team-id "B8R5B24PMP" \
  --password "app-specific-password"
```

Note: You need an [App-Specific Password](https://support.apple.com/en-us/HT204397) from Apple ID settings.

### 6. Create GitHub Release

```bash
gh release create v1.0.X \
  --title "v1.0.X - Brief description" \
  --notes "## What's New/Fixed

- Your changes here
- More changes

## Installation

Download and run the DMG file below. If macOS blocks the app:
1. Right-click the app and select \"Open\"
2. Or go to System Settings > Privacy & Security and allow the app

## Notes

This release is code-signed but not notarized (if applicable)." \
  PUSH-v1.0.X.dmg \
  PUSH-v1.0.X.zip
```

### 7. Verify Release

1. Go to the release URL
2. Download the DMG
3. Test installation on a clean system if possible
4. Verify the app runs and version number is correct

## Common Mistakes to Avoid

### ❌ Forgetting to update build_distribution.sh
Always update both `ZIP_NAME` and `DMG_NAME` to match the new version.

### ❌ Not cleaning extended attributes
Extended attributes from macOS Finder/iCloud cause code signing to fail. The build script handles this, but be aware if you encounter issues.

### ❌ Not testing the fix first
Always test your changes locally before creating a release. Run the app and verify the fix works.

### ❌ Inconsistent version numbers
Make sure `Info.plist` and `build_distribution.sh` have matching version numbers.

### ❌ Not incrementing build number
Even for small fixes, increment `CFBundleVersion` in Info.plist.

## Troubleshooting

### Build fails with "resource fork" error
See "Common Issue: Extended Attributes During Code Signing" above.

### Code signing fails with "no identity found"
For local development, this is expected. The build_xcode_project.sh uses a self-signed certificate.
For distribution, make sure you have "Developer ID Application: Elias Atalah (B8R5B24PMP)" in your keychain.

### App crashes on launch
1. Check permissions (Accessibility, Microphone)
2. Check logs: `log show --predicate 'process == "PUSH"' --last 30s --style compact`
3. Check debug log: `cat /tmp/push_debug.log`

### Version number doesn't update in app
1. Make sure you updated Info.plist
2. Clean build: `rm -rf PUSH-Xcode/PUSH.app .build`
3. Rebuild: `./build_xcode_project.sh`

## Quick Reference

### File Locations
- Version info: `PUSH/Info.plist`
- Build script: `build_distribution.sh`
- App bundle: `PUSH-Xcode/PUSH.app`
- Distribution files: `PUSH-v*.dmg` and `PUSH-v*.zip` (root directory)

### Useful Commands
```bash
# Check current version
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" PUSH/Info.plist

# List extended attributes
xattr -lr PUSH-Xcode/PUSH.app

# Verify code signature
codesign --verify --verbose PUSH-Xcode/PUSH.app

# Check what's signed
codesign -dvv PUSH-Xcode/PUSH.app

# View recent app logs
log show --predicate 'process == "PUSH"' --last 5m --style compact
```

## Release Notes Template

```markdown
## What's New
- New feature description

## What's Fixed
- Bug fix description

## Installation

Download and run the DMG file below. If macOS blocks the app:
1. Right-click the app and select "Open"
2. Or go to System Settings > Privacy & Security and allow the app

## Notes
- Any special notes for this release
```
