#!/bin/bash
# Build AjazzDeck.app — a menu-bar app bundle around the ajazzdeck executable.
# A real bundle (rather than a bare binary) is what lets macOS attach the
# Accessibility permission and what Login Items expects.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${1:-release}
APP="build/AjazzDeck.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product ajazzdeck
swift build -c "$CONFIG" --product ajazzctl
BIN=$(swift build -c "$CONFIG" --show-bin-path)

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ajazzdeck" "$APP/Contents/MacOS/AjazzDeck"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # regenerate: icon/make-icns.sh
cp -R Resources/MaterialSymbols "$APP/Contents/Resources/"     # font, codepoints, Apache-2.0 LICENSE

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>AjazzDeck</string>
    <key>CFBundleDisplayName</key>       <string>Ajazz Deck</string>
    <key>CFBundleIdentifier</key>        <string>local.ajazzdeck</string>
    <key>CFBundleExecutable</key>        <string>AjazzDeck</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHumanReadableCopyright</key>  <string>Local build</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  codesign --force --sign - "$APP"

echo
echo "Built $APP"
echo "CLI  $BIN/ajazzctl"
echo
echo "Launch with:  open $APP"
