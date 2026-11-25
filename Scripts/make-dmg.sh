#!/usr/bin/env bash
# Build a shareable Dictora macOS Release DMG.
#
# Usage:
#   ./Scripts/make-dmg.sh
#
# Output:
#   dist/Dictora-<version>.dmg
#
# Notes:
#   Signs with the Apple Development certificate configured in Shared.xcconfig.
#   This is deliberate and not cosmetic: an ad-hoc signature pins every TCC
#   permission to the binary's code hash, so Accessibility access would be
#   revoked by each new build even though System Settings still shows Dictora
#   switched on. A real certificate keys the grant to the identity instead.
#
#   Recipients still need to right-click → Open the first time, because an
#   Apple Development certificate is not notarized. For Gatekeeper-clean
#   distribution you need a Developer ID Application certificate plus Apple
#   notarization — swap the identity below and add an `xcrun notarytool` step.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(
  awk -F' = ' '/^MARKETING_VERSION / { print $2; exit }' Dictora/Configuration/Shared.xcconfig
)"
VERSION="${VERSION:-0.1.0}"

DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
DERIVED="$DIST/DerivedData"
APP_NAME="Dictora"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
VOLUME_NAME="Dictora ${VERSION}"

echo "==> Generating Xcode project"
command -v xcodegen >/dev/null || { echo "xcodegen is required (brew install xcodegen)"; exit 1; }
xcodegen generate

echo "==> Building ${APP_NAME} (Release, macOS)"
rm -rf "$DERIVED"
xcodebuild \
  -project Dictora.xcodeproj \
  -scheme DictoraMac \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" \
  build

APP_SRC="$DERIVED/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "error: expected app missing at $APP_SRC" >&2
  exit 1
fi

# An ad-hoc signature here would silently break Accessibility on every release,
# so fail loudly rather than shipping a build whose permissions won't stick.
if codesign -dv --verbose=2 "$APP_SRC" 2>&1 | grep -q "Signature=adhoc"; then
  echo "error: ${APP_NAME}.app is ad-hoc signed." >&2
  echo "       Accessibility access would be revoked on every rebuild." >&2
  echo "       Set DEVELOPMENT_TEAM in Dictora/Configuration/Shared.xcconfig." >&2
  exit 1
fi

echo "==> Signed as: $(codesign -dv --verbose=2 "$APP_SRC" 2>&1 | awk -F'=' '/^Authority/ { print $2; exit }')"

echo "==> Staging DMG contents"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP_SRC" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

# Drop a short readme for recipients onto the disk image.
cat > "$STAGE/Install Notes.txt" <<EOF
Dictora ${VERSION}
==================

1. Drag Dictora into the Applications folder.
2. Open Dictora from Applications.
3. If macOS says the app can't be opened (Gatekeeper):
   - Control-click Dictora → Open → Open
   - Or: System Settings → Privacy & Security → "Open Anyway"

Then grant Microphone, Speech Recognition, and Accessibility when asked.

Accessibility is required for the Fn shortcut and for typing into other apps.
If Dictora already appears switched on under System Settings → Privacy &
Security → Accessibility but the app still asks for it, press "Repair" in
Dictora: the entry belongs to an older build and has to be cleared first.

Don't need the Fn key? Settings → Anywhere lets you pick a plain keyboard
shortcut instead, and those work without Accessibility access.
EOF

echo "==> Creating $DMG_NAME"
mkdir -p "$DIST"
rm -f "$DIST/$DMG_NAME"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DIST/$DMG_NAME"

# Clean staging / derived data to keep dist tidy; keep the DMG.
rm -rf "$STAGE" "$DERIVED"

echo
echo "Done: $DIST/$DMG_NAME"
ls -lh "$DIST/$DMG_NAME"
echo
echo "Share this file. Recipients: drag Dictora to Applications, then"
echo "Control-click → Open the first time (not notarized)."
