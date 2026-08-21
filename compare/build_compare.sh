#!/bin/bash
# Build, bundle and sign the local engine-comparison tool.
#
# It needs to be a signed .app rather than a bare binary for two reasons: macOS only
# grants microphone access to a bundle with an identifier, and TCC keys that grant to
# the code-signing identity — an ad-hoc signature changes every build and the grant is
# silently lost each time.
set -e

cd "$(dirname "$0")"

# Outside iCloud-synced ~/Documents: the sync engine re-plants extended attributes on
# directories faster than codesign can run, which breaks signing with "detritus not
# allowed". Same reason the app bundles elsewhere.
DIST="${HOME}/Library/Developer/SwiftPackages/PUSHCompare-dist"
APP="${DIST}/PUSHCompare.app"
IDENTITY="Developer ID Application: Elias Atalah (B8R5B24PMP)"

echo "📦 Building..."
swift build -c release

echo "📦 Bundling..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ditto --norsrc --noextattr .build/release/compare "$APP/Contents/MacOS/compare"
ditto --norsrc --noextattr Info.plist "$APP/Contents/Info.plist"

# Resource bundles the engines' SDKs ship (CoreML assets and the like).
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] && ditto --norsrc --noextattr "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done

echo "✍️  Signing..."
xattr -cr "$APP" 2>/dev/null || true
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --options runtime --entitlements compare.entitlements \
        --sign "$IDENTITY" "$APP"
else
    echo "   Developer ID not found — signing ad-hoc (the mic grant will not survive rebuilds)"
    codesign --force --entitlements compare.entitlements --sign - "$APP"
fi
codesign --verify --verbose "$APP" 2>&1 | tail -2

echo ""
echo "✅ $APP"
echo "   open \"$APP\""
