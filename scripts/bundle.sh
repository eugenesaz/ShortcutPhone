#!/usr/bin/env bash
# Build build/ShortcutPhone.app: web build + Swift release build + bundle + codesign.
# CODESIGN_IDENTITY overrides the signing identity; "-" means ad-hoc.
# VERSION (e.g. 0.2.0) sets the app's version; Resources/Info.plist's is used otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=swift-env.sh
source scripts/swift-env.sh

IDENTITY="${CODESIGN_IDENTITY:-ShortcutPhone Local}"
APP=build/ShortcutPhone.app

[ -d web/node_modules ] || npm --prefix web ci
npm --prefix web run build

swift build -c release --product ShortcutPhone
BIN="$(swift build -c release --show-bin-path)/ShortcutPhone"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/starter-config.json "$APP/Contents/Resources/starter-config.json"
cp "$BIN" "$APP/Contents/MacOS/ShortcutPhone"
cp -R web/dist "$APP/Contents/Resources/web"

if [ "$IDENTITY" != "-" ] && ! security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "Signing identity \"$IDENTITY\" not found. Run ./scripts/make-signing-identity.sh," >&2
  echo "or set CODESIGN_IDENTITY=- for an ad-hoc signature." >&2
  exit 1
fi
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed: $IDENTITY)"
