#!/bin/bash
# Script to build PUSH for distribution with proper code signing and notarization

set -e  # Exit on error

# Configuration
APP_NAME="PUSH"
# Build the app bundle OUTSIDE iCloud-managed ~/Documents/. iCloud re-plants
# com.apple.fileprovider.fpfs#P and com.apple.FinderInfo on directories faster
# than codesign can run, breaking signing with "detritus not allowed".
DIST_ROOT="${HOME}/Library/Developer/SwiftPackages/PUSH-dist"
SCRATCH_PATH="${HOME}/Library/Developer/SwiftPackages/PUSH-build"
mkdir -p "$DIST_ROOT" "$SCRATCH_PATH"
APP_DIR="${DIST_ROOT}/PUSH.app"
BUILD_DIR="${SCRATCH_PATH}"
BUNDLE_ID="com.push.voicetotext"
DEVELOPER_ID="Developer ID Application: Elias Atalah (B8R5B24PMP)"

# Version is read from Info.plist so it never drifts from the app bundle.
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" PUSH/Info.plist)
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" PUSH/Info.plist)
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" PUSH/Info.plist)
ZIP_NAME="PUSH-v${VERSION}.zip"
DMG_NAME="PUSH-v${VERSION}.dmg"

# Sparkle: framework + CLI tools live in the resolved SPM artifacts.
SPARKLE_DIR="${SCRATCH_PATH}/artifacts/sparkle/Sparkle"
SPARKLE_BIN="${SPARKLE_DIR}/bin"
SPARKLE_FRAMEWORK="${SPARKLE_DIR}/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
APPCAST="appcast.xml"
DOWNLOAD_URL="https://github.com/Elias1986a/PUSH/releases/download/v${VERSION}/${ZIP_NAME}"

echo "🚀 Building PUSH for distribution..."
echo ""

# Step 1: Build the app
# --scratch-path keeps SPM's build dir outside iCloud-synced ~/Documents/.
# But: SPM emits the Moonshine xcframework link path as the literal
# ".build/artifacts/...", which the linker resolves relative to CWD —
# regardless of --scratch-path. So we also create a transient symlink
# .build → $BUILD_DIR for the linker step. iCloud may eventually
# materialize the symlink, but it survives long enough for one build.
echo "📦 Step 1/6: Building release binary..."
ln -sfn "$BUILD_DIR" .build
swift build -c release --scratch-path "$BUILD_DIR"

# Step 2: Create app bundle
echo "📦 Step 2/6: Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy executable (using ditto to strip extended attributes)
ditto --norsrc --noextattr $BUILD_DIR/release/PUSH "$APP_DIR/Contents/MacOS/PUSH"

# Copy Info.plist (using ditto to strip extended attributes)
ditto --norsrc --noextattr PUSH/Info.plist "$APP_DIR/Contents/Info.plist"

# Copy app icon
echo "   Copying app icon..."
ditto --norsrc --noextattr ICON/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy resource bundles (using ditto without resource forks)
echo "   Copying resource bundles..."
for bundle in $BUILD_DIR/release/*.bundle; do
    if [ -e "$bundle" ]; then
        ditto --norsrc --noextattr "$bundle" "$APP_DIR/Contents/Resources/$(basename "$bundle")"
    fi
done

# Copy MLX Metal shader libraries (required for Qwen3-ASR/MLX inference)
echo "   Copying Metal shader libraries..."
find $BUILD_DIR/release -name "*.metallib" -exec ditto --norsrc --noextattr {} "$APP_DIR/Contents/Resources/{}" \; 2>/dev/null
# Also check in bundle subdirectories
for metallib in $(find $BUILD_DIR/release -name "*.metallib" 2>/dev/null); do
    ditto --norsrc --noextattr "$metallib" "$APP_DIR/Contents/Resources/$(basename "$metallib")"
done

# Copy frameworks (using ditto without resource forks)
echo "   Copying frameworks..."
for framework in $BUILD_DIR/release/*.framework; do
    if [ -e "$framework" ]; then
        ditto --norsrc --noextattr "$framework" "$APP_DIR/Contents/Frameworks/$(basename "$framework")"
    fi
done
for dylib in $BUILD_DIR/release/*.dylib; do
    if [ -e "$dylib" ]; then
        ditto --norsrc --noextattr "$dylib" "$APP_DIR/Contents/Frameworks/$(basename "$dylib")"
    fi
done

# Sparkle ships as a binary xcframework in the SPM artifacts (not release/),
# so copy it into Frameworks/ explicitly. The app already adds an
# @executable_path/../Frameworks rpath, which resolves @rpath/Sparkle.framework.
echo "   Copying Sparkle.framework..."
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    ditto --norsrc --noextattr "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
else
    echo "   ❌ Sparkle.framework not found at $SPARKLE_FRAMEWORK — run 'swift package resolve' first."
    exit 1
fi

# Fix library paths
echo "   Fixing library paths..."
# Add rpath so the binary can find llama.framework in Frameworks/
install_name_tool -add_rpath "@executable_path/../Frameworks" \
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
# Aggressive attribute removal - try multiple methods
echo "   Removing extended attributes (attempt 1)..."
find "$APP_DIR" -type f -print0 2>/dev/null | xargs -0 xattr -c 2>/dev/null || true
echo "   Removing extended attributes (attempt 2)..."
find "$APP_DIR" -type f -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
find "$APP_DIR" -type f -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true
find "$APP_DIR" -type f -exec xattr -d com.apple.metadata:kMDItemWhereFroms {} \; 2>/dev/null || true
echo "   Removing extended attributes (attempt 3)..."
find "$APP_DIR" -type f -exec xattr -c {} \; 2>/dev/null || true
# iCloud (com.apple.fileprovider.*) and FinderInfo can land on directories too,
# which codesign rejects. Recursive clear handles files + dirs.
echo "   Removing extended attributes (attempt 4 — recursive incl. dirs)..."
xattr -cr "$APP_DIR" 2>/dev/null || true

# Step 3: Code sign with hardened runtime
echo "✍️  Step 3/6: Code signing with Developer ID..."

# Sparkle must be signed inside-out: its XPC services and helper apps first,
# then the framework wrapper. Signing the outer framework before the nested
# helpers leaves them ad-hoc/unsigned and notarization rejects the bundle.
SPK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPK" ]; then
    echo "   Deep-signing Sparkle.framework (XPC services, Autoupdate, Updater.app)..."
    codesign --force --options runtime --sign "$DEVELOPER_ID" "$SPK/Versions/B/XPCServices/Downloader.xpc"
    codesign --force --options runtime --sign "$DEVELOPER_ID" "$SPK/Versions/B/XPCServices/Installer.xpc"
    codesign --force --options runtime --sign "$DEVELOPER_ID" "$SPK/Versions/B/Autoupdate"
    codesign --force --options runtime --sign "$DEVELOPER_ID" "$SPK/Versions/B/Updater.app"
    codesign --force --options runtime --sign "$DEVELOPER_ID" "$SPK"
fi

echo "   Signing frameworks..."
for framework in "$APP_DIR"/Contents/Frameworks/*.framework; do
    if [ -d "$framework" ]; then
        # Sparkle is already deep-signed above; re-signing the wrapper here would
        # not re-sign its nested helpers, so skip it.
        [ "$(basename "$framework")" = "Sparkle.framework" ] && continue
        codesign --force --options runtime --sign "$DEVELOPER_ID" "$framework"
    fi
done

for dylib in "$APP_DIR"/Contents/Frameworks/*.dylib; do
    if [ -f "$dylib" ]; then
        codesign --force --options runtime --sign "$DEVELOPER_ID" "$dylib"
    fi
done

echo "   Signing main app..."
# Final cleanup of app bundle extended attributes
xattr -c "$APP_DIR" 2>/dev/null || true
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
# Only prompt when running interactively. CI / automated runs skip this
# and proceed straight to notarytool, which fails informatively if the
# keychain profile is missing.
if [ -t 0 ]; then
    read -p "Have you stored credentials? Press Enter to continue or Ctrl+C to cancel..."
fi

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

# Create temporary directory for DMG contents (outside iCloud — same reason as APP_DIR)
DMG_TEMP="${DIST_ROOT}/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -R "$APP_DIR" "$DMG_TEMP/"

# Add Applications symlink for drag-and-drop install
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "PUSH" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_NAME"

# Cleanup
rm -rf "$DMG_TEMP"

# Step 7: Generate the Sparkle appcast for the stapled ZIP.
# sign_update emits  sparkle:edSignature="..." length="..."  using the EdDSA
# private key in the login Keychain (created once via Sparkle's generate_keys).
echo "🔏 Generating Sparkle appcast..."
SIG_AND_LENGTH=$("$SPARKLE_BIN/sign_update" "$ZIP_NAME")
PUBDATE=$(LC_ALL=en_US.UTF-8 date "+%a, %d %b %Y %H:%M:%S %z")

cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>PUSH</title>
        <description>Updates for PUSH voice-to-text</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
            <enclosure url="${DOWNLOAD_URL}" type="application/octet-stream" ${SIG_AND_LENGTH} />
        </item>
    </channel>
</rss>
XML
echo "   Wrote $APPCAST (enclosure → $DOWNLOAD_URL)"

echo ""
echo "✅ Distribution build complete!"
echo ""
echo "📦 Files created:"
echo "   - $APP_DIR (signed and notarized)"
echo "   - $ZIP_NAME (for direct download + Sparkle update)"
echo "   - $DMG_NAME (for drag-and-drop install)"
echo "   - $APPCAST (Sparkle update feed)"
echo ""
echo "🚀 Ready to distribute! To publish this update:"
echo "   1. Create the GitHub release (the tag must match the appcast URL):"
echo "        gh release create v${VERSION} --title \"PUSH v${VERSION}\" --generate-notes \"$ZIP_NAME\" \"$DMG_NAME\""
echo "   2. Commit & push the appcast so existing users get the update:"
echo "        git add $APPCAST && git commit -m \"Release v${VERSION}\" && git push"
echo ""
echo "   Existing users will be offered v${VERSION} via Check for Updates / the daily check."
echo ""
