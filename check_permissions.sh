#!/bin/bash
# Check current Accessibility permissions for PUSH

echo "🔍 Checking Accessibility Permissions..."
echo ""

# Get list of apps with Accessibility permission
ACCESSIBILITY_DB="/Library/Application Support/com.apple.TCC/TCC.db"

# Check if PUSH is in the Accessibility list
if sudo sqlite3 "$ACCESSIBILITY_DB" "SELECT client FROM access WHERE service = 'kTCCServiceAccessibility' AND client LIKE '%push%';" 2>/dev/null | grep -i push; then
    echo "✅ PUSH found in Accessibility database"
else
    echo "❌ PUSH not found in Accessibility database"
fi

echo ""
echo "📋 All apps with Accessibility permission:"
sudo sqlite3 "$ACCESSIBILITY_DB" "SELECT client FROM access WHERE service = 'kTCCServiceAccessibility';" 2>/dev/null || echo "Could not read TCC database (requires sudo)"

echo ""
echo "🔍 Checking app bundle signature..."
if [ -d "PUSH-Xcode/PUSH.app" ]; then
    echo "Bundle Identifier:"
    codesign -dv --verbose=4 PUSH-Xcode/PUSH.app 2>&1 | grep "Identifier="
    echo ""
    echo "Code Signature:"
    codesign -dv --verbose=4 PUSH-Xcode/PUSH.app 2>&1 | grep "Signature="
else
    echo "❌ PUSH.app not found at PUSH-Xcode/PUSH.app"
fi

echo ""
echo "📝 To add PUSH to Accessibility:"
echo "1. System Settings > Privacy & Security > Accessibility"
echo "2. Click + button"
echo "3. Navigate to: $(pwd)/PUSH-Xcode/PUSH.app"
echo "4. Select and enable the checkbox"
