#!/bin/bash
# Script to build PUSH for distribution with proper code signing and notarization

set -e  # Exit on error

# Configuration
APP_NAME="PUSH"
APP_DIR="PUSH-Xcode/PUSH.app"
BUNDLE_ID="com.push.voicetotext"
DEVELOPER_ID="Developer ID Application: Elias Atalah (B8R5B24PMP)"
ZIP_NAME="PUSH-v1.0.1.zip"
DMG_NAME="PUSH-v1.0.1.dmg"

echo "🚀 Building PUSH for distribution..."
echo ""

# Step 1: Build the app
echo "📦 Step 1/6: Building release binary..."
swift build -c release

# Step 2: Create app bundle
echo "📦 Step 2/6: Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy executable (using ditto to strip extended attributes)
ditto --norsrc --noextattr .build/release/PUSH "$APP_DIR/Contents/MacOS/PUSH"

# Copy Info.plist (using ditto to strip extended attributes)
ditto --norsrc --noextattr PUSH/Info.plist "$APP_DIR/Contents/Info.plist"

# Copy resource bundles (using ditto without resource forks)
echo "   Copying resource bundles..."
for bundle in .build/release/*.bundle; do
    if [ -e "$bundle" ]; then
        ditto --norsrc --noextattr "$bundle" "$APP_DIR/Contents/Resources/$(basename "$bundle")"
    fi
done

# Copy frameworks (using ditto without resource forks)
echo "   Copying frameworks..."
for framework in .build/release/*.framework; do
    if [ -e "$framework" ]; then
        ditto --norsrc --noextattr "$framework" "$APP_DIR/Contents/Frameworks/$(basename "$framework")"
    fi
done
for dylib in .build/release/*.dylib; do
    if [ -e "$dylib" ]; then
        ditto --norsrc --noextattr "$dylib" "$APP_DIR/Contents/Frameworks/$(basename "$dylib")"
    fi
done

# Fix library paths
echo "   Fixing library paths..."
install_name_tool -change "@rpath/llama.framework/Versions/Current/llama" \
    "@executable_path/../Frameworks/llama.framework/Versions/Current/llama" \
    "$APP_DIR/Contents/MacOS/PUSH" 2>/dev/null || true

for lib in "$APP_DIR"/Contents/Frameworks/*.dylib; do
    if [ -f "$lib" ]; then
        libname=$(basename "$lib")
        install_name_tool -change "@rpath/$libname" "@executable_path/../Frameworks/$libname" \
            "$APP_DIR/Contents/MacOS/PUSH" 2>/dev/null || true
    fi
done

# Clean up macOS metadata that interferes with code signing
echo "   Cleaning macOS metadata..."
find "$APP_DIR" -name ".DS_Store" -delete 2>/dev/null || true
chmod -R u+w "$APP_DIR"
# Remove extended attributes from EVERY file (xattr -cr doesn't work reliably)
find "$APP_DIR" -exec xattr -c {} \;

# Step 3: Code sign with hardened runtime
echo "✍️  Step 3/6: Code signing with Developer ID..."
echo "   Signing frameworks..."
for framework in "$APP_DIR"/Contents/Frameworks/*.framework; do
    if [ -d "$framework" ]; then
        codesign --force --options runtime --sign "$DEVELOPER_ID" "$framework"
    fi
done

for dylib in "$APP_DIR"/Contents/Frameworks/*.dylib; do
    if [ -f "$dylib" ]; then
        codesign --force --options runtime --sign "$DEVELOPER_ID" "$dylib"
    fi
done

echo "   Signing main app..."
codesign --force --options runtime --entitlements PUSH/PUSH.entitlements \
    --sign "$DEVELOPER_ID" "$APP_DIR"

echo "   Verifying signature..."
codesign --verify --verbose "$APP_DIR"

# Step 4: Create ZIP for notarization
echo "📦 Step 4/6: Creating ZIP archive..."
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_NAME"

# Step 5: Notarize
echo "📮 Step 5/6: Submitting for notarization..."
echo ""
echo "⚠️  IMPORTANT: You need to store your Apple ID credentials first!"
echo "   Run this command once (replace with your Apple ID):"
echo "   xcrun notarytool store-credentials \"notarytool-profile\" \\"
echo "     --apple-id \"your-apple-id@email.com\" \\"
echo "     --team-id \"B8R5B24PMP\" \\"
echo "     --password \"app-specific-password\""
echo ""
read -p "Have you stored credentials? Press Enter to continue or Ctrl+C to cancel..."

# Submit for notarization
echo "   Uploading to Apple..."
xcrun notarytool submit "$ZIP_NAME" \
    --keychain-profile "notarytool-profile" \
    --wait

# Check if notarization succeeded
if [ $? -eq 0 ]; then
    echo "   ✅ Notarization successful!"

    # Staple the notarization ticket
    echo "   Stapling notarization ticket..."
    xcrun stapler staple "$APP_DIR"

    # Recreate ZIP with stapled app
    rm -f "$ZIP_NAME"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP_NAME"
else
    echo "   ❌ Notarization failed!"
    echo "   Check logs with: xcrun notarytool log <submission-id> --keychain-profile notarytool-profile"
    exit 1
fi

# Step 6: Create DMG (optional, nicer for distribution)
echo "💿 Step 6/6: Creating DMG..."
rm -f "$DMG_NAME"

# Create temporary directory for DMG contents
DMG_TEMP="dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -R "$APP_DIR" "$DMG_TEMP/"

# Create DMG
hdiutil create -volname "PUSH" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_NAME"

# Cleanup
rm -rf "$DMG_TEMP"

echo ""
echo "✅ Distribution build complete!"
echo ""
echo "📦 Files created:"
echo "   - $APP_DIR (signed and notarized)"
echo "   - $ZIP_NAME (for direct download)"
echo "   - $DMG_NAME (for drag-and-drop install)"
echo ""
echo "🚀 Ready to distribute!"
echo "   Upload $ZIP_NAME or $DMG_NAME to GitHub Releases"
echo ""
