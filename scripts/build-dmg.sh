#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
APP_NAME="Voxa"
SCHEME="${APP_NAME}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
DMG_DIR="${BUILD_DIR}/dmg"
DMG_OUTPUT="${BUILD_DIR}/${APP_NAME}.dmg"

# Read version from Info.plist
VERSION=$(defaults read "${PROJECT_DIR}/Voxa/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.1.0")
DMG_FINAL="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

# ── Cleanup ────────────────────────────────────────────────────
echo "==> Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# ── Archive ────────────────────────────────────────────────────
echo "==> Archiving ${APP_NAME}..."
xcodebuild archive \
    -project "${PROJECT_DIR}/Voxa.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    | tail -5

# ── Export ─────────────────────────────────────────────────────
echo "==> Exporting app bundle..."

# Create export options plist
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
cat > "${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

# Try xcodebuild export; fall back to copying from archive
if ! xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -exportPath "${EXPORT_DIR}" 2>/dev/null; then
    echo "    (export failed, extracting .app from archive directly)"
    mkdir -p "${EXPORT_DIR}"
    cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${APP_PATH}"
fi

if [ ! -d "${APP_PATH}" ]; then
    echo "ERROR: ${APP_PATH} not found after export."
    exit 1
fi

echo "    App bundle: ${APP_PATH}"

# ── Build DMG ──────────────────────────────────────────────────
echo "==> Creating DMG..."
mkdir -p "${DMG_DIR}"
cp -R "${APP_PATH}" "${DMG_DIR}/"

# Add Applications symlink for drag-to-install
ln -s /Applications "${DMG_DIR}/Applications"

# Create DMG
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_OUTPUT}"

mv "${DMG_OUTPUT}" "${DMG_FINAL}"

# ── Cleanup temp artifacts ─────────────────────────────────────
rm -rf "${DMG_DIR}" "${EXPORT_OPTIONS}"

# ── Done ───────────────────────────────────────────────────────
DMG_SIZE=$(du -h "${DMG_FINAL}" | cut -f1)
echo ""
echo "==> Done! DMG created:"
echo "    ${DMG_FINAL} (${DMG_SIZE})"
