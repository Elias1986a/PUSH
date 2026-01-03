#!/bin/bash
# Script to build a proper macOS app bundle with Swift Package Manager

echo "Building PUSH.app with proper bundle..."

# Build the executable
swift build -c release

# Create app bundle structure
APP_DIR="PUSH-Xcode/PUSH.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy executable
cp .build/release/PUSH "$APP_DIR/Contents/MacOS/"

# Copy Info.plist
cp PUSH.app/Contents/Info.plist "$APP_DIR/Contents/"

# Copy resource bundles (for sound files and other resources)
echo "Copying resource bundles..."
for bundle in .build/release/*.bundle; do
    if [ -e "$bundle" ]; then
        cp -R "$bundle" "$APP_DIR/Contents/Resources/"
    fi
done

# Copy frameworks (WhisperKit, SwiftLlama dependencies)
echo "Copying frameworks..."
for framework in .build/release/*.framework .build/release/*.dylib; do
    if [ -e "$framework" ]; then
        cp -R "$framework" "$APP_DIR/Contents/Frameworks/"
    fi
done

# Fix library paths
echo "Fixing library paths..."

# Fix llama.framework path
install_name_tool -change "@rpath/llama.framework/Versions/Current/llama" \
    "@executable_path/../Frameworks/llama.framework/Versions/Current/llama" \
    "$APP_DIR/Contents/MacOS/PUSH"

# Fix any dylibs
for lib in "$APP_DIR"/Contents/Frameworks/*.dylib; do
    if [ -f "$lib" ]; then
        libname=$(basename "$lib")
        install_name_tool -change "@rpath/$libname" "@executable_path/../Frameworks/$libname" "$APP_DIR/Contents/MacOS/PUSH" 2>/dev/null || true
    fi
done

# Code sign the app with stable certificate (or ad-hoc if not found)
echo "Code signing..."
CERT_NAME="PUSH Developer Certificate"
if security find-certificate -c "$CERT_NAME" &>/dev/null; then
    echo "Using stable certificate: $CERT_NAME"
    codesign --force --deep --sign "$CERT_NAME" "$APP_DIR"
else
    echo "⚠️  Stable certificate not found, using ad-hoc signing"
    echo "Run './create_signing_certificate.sh' to create a stable certificate"
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "✅ App bundle created at: $APP_DIR"
echo ""
echo "To run: open $APP_DIR"
echo ""
echo "⚠️  Make sure to add the app to System Settings > Privacy & Security > Accessibility"
