# PUSH Release Process

This document outlines the complete process for creating a new release of PUSH, including common pitfalls and solutions.

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
