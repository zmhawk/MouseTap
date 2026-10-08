#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/dist/Mouse Kit.app"
APP_BUNDLE_ID="com.yujianbo.mousekit"
APP_EXECUTABLE="MouseKit"

swift build \
  --package-path "$PROJECT_ROOT" \
  --configuration release \
  --product mouse-event-probe

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
"$PROJECT_ROOT/scripts/build-icon.sh"
cp "$PROJECT_ROOT/Assets/MouseKit.icns" "$APP_BUNDLE/Contents/Resources/MouseKit.icns"

cp "$PROJECT_ROOT/.build/release/mouse-event-probe" \
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
    <string>MouseKit</string>
    <key>CFBundleName</key>
    <string>Mouse Kit</string>
    <key>CFBundleDisplayName</key>
    <string>Mouse Kit</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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
