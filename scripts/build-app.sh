#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE_PATH:-$PROJECT_ROOT/dist/MouseTap.app}"
APP_BUNDLE_ID="com.zmhawk.mousetap"
APP_EXECUTABLE="MouseTap"
APP_VERSION="${APP_VERSION:-1.0.0}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "APP_VERSION must use MAJOR.MINOR.PATCH" >&2
  exit 1
fi

swift build \
  --package-path "$PROJECT_ROOT" \
  --configuration release \
  --product MouseTap

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
"$PROJECT_ROOT/scripts/build-icon.sh"
cp "$PROJECT_ROOT/Assets/MouseTap.icns" "$APP_BUNDLE/Contents/Resources/MouseTap.icns"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.txt" "$APP_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp "$PROJECT_ROOT/LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE"

cp "$PROJECT_ROOT/.build/release/MouseTap" \
  "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>MouseTap</string>
    <key>CFBundleName</key>
    <string>MouseTap</string>
    <key>CFBundleDisplayName</key>
    <string>MouseTap</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F '\"' '/Apple Development:/ { print $1; exit }' \
    | awk '{ print $2 }')"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  echo "No Apple Development identity found; using an ad-hoc signature."
fi

codesign --force --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built and signed: $APP_BUNDLE"
