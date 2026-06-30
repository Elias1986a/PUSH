#!/bin/bash
# Reproduces PUSH's app-bundle + code-sign flow for the isolated MLX spike, so
# we can see whether MLX's default.metallib loads from a signed .app (not just
# from `swift run`). Mirrors build_distribution.sh, but ad-hoc signs (sign "-")
# so no Developer ID is required for a local test.
#
# Usage:
#   ./bundle-and-sign.sh            # ad-hoc sign (local test)
#   SIGN_ID="Developer ID Application: ..." ./bundle-and-sign.sh   # real cert
set -euo pipefail
cd "$(dirname "$0")"

APP="MLXSpike.app"
SIGN_ID="${SIGN_ID:--}"   # default: ad-hoc

echo "📦 1/5 Building release..."
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "📦 2/5 Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>mlxspike</string>
  <key>CFBundleIdentifier</key><string>com.push.mlxspike</string>
  <key>CFBundleName</key><string>MLXSpike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
ditto --norsrc --noextattr "$BIN/mlxspike" "$APP/Contents/MacOS/mlxspike"

echo "📦 3/5 Copying SwiftPM resource bundles (the crux: mlx-swift_Cmlx.bundle)..."
shopt -s nullglob
for b in "$BIN"/*.bundle; do
    ditto --norsrc --noextattr "$b" "$APP/Contents/Resources/$(basename "$b")"
done
echo "   Resources now contains:"
ls -1 "$APP/Contents/Resources" | sed 's/^/     /'
echo "   metallibs found:"
find "$APP/Contents/Resources" -name "*.metallib" | sed 's/^/     /' || echo "     (none)"

echo "📦 4/5 Code signing (id: $SIGN_ID), hardened runtime, nested-first..."
# Sign nested code (metallibs + bundles) BEFORE the outer app — this is the
# step build_distribution.sh currently skips for .bundle resources.
find "$APP/Contents/Resources" -name "*.metallib" -print0 | while IFS= read -r -d '' m; do
    codesign --force --options runtime --sign "$SIGN_ID" "$m"
done
find "$APP/Contents/Resources" -name "*.bundle" -print0 | while IFS= read -r -d '' nb; do
    codesign --force --options runtime --sign "$SIGN_ID" "$nb"
done
codesign --force --options runtime --sign "$SIGN_ID" "$APP"
codesign --verify --deep --verbose=2 "$APP"

echo "📦 5/5 Running from the signed app bundle..."
echo "-----------------------------------------------"
"$APP/Contents/MacOS/mlxspike"
echo "-----------------------------------------------"
echo "Tip: also test Gatekeeper translocation — copy $APP to /Applications,"
echo "     then launch it from there, to catch path-resolution differences."
