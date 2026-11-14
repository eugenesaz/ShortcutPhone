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

scripts/fetch-sparkle.sh
swift build -c release --product ShortcutPhone
BIN="$(swift build -c release --show-bin-path)/ShortcutPhone"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
else
  # A local build mustn't offer to replace itself with the latest release every day.
  # "Check for Updates…" still works.
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/starter-config.json "$APP/Contents/Resources/starter-config.json"
cp "$BIN" "$APP/Contents/MacOS/ShortcutPhone"
# Sparkle (automatic updates). Its XPC services are only for sandboxed apps, so they're left out.
SPARKLE="$(find "$(dirname "$BIN")" -maxdepth 3 -name Sparkle.framework -type d | head -1)"
[ -n "$SPARKLE" ] || { echo "Sparkle.framework not found next to $BIN" >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
  "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
cp -R web/dist "$APP/Contents/Resources/web"

if [ "$IDENTITY" != "-" ] && ! security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "Signing identity \"$IDENTITY\" not found. Run ./scripts/make-signing-identity.sh," >&2
  echo "or set CODESIGN_IDENTITY=- for an ad-hoc signature." >&2
  exit 1
fi
# Inside out: Sparkle's helpers, the framework, then the app. Everything carries the same
# signature, so Sparkle accepts updates and macOS keeps the Accessibility permission.
sign() { codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$@"; }
FW="$APP/Contents/Frameworks/Sparkle.framework"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign --entitlements Resources/ShortcutPhone.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed: $IDENTITY)"
