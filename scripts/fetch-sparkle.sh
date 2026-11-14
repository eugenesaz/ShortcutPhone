#!/usr/bin/env bash
# Downloads Sparkle's official prebuilt framework into Vendor/Sparkle.xcframework (gitignored),
# verified against a pinned SHA-256. Package.swift uses it as a local binary target. This avoids
# cloning Sparkle's whole git history just for a binary, and SwiftPM's artifact downloader,
# which hangs on some Macs. To upgrade: change VERSION and SHA256 (the `checksum` in Sparkle's
# Package.swift for that release).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.10.1
SHA256=4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a
DEST=Vendor/Sparkle.xcframework
STAMP=Vendor/.sparkle-version

[ -d "$DEST" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$VERSION" ] && exit 0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 --max-time 120 -o "$work/sparkle.zip" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-for-Swift-Package-Manager.zip"
echo "$SHA256  $work/sparkle.zip" | shasum -a 256 -c --quiet
unzip -q "$work/sparkle.zip" 'Sparkle.xcframework/*' -d "$work/out"
rm -rf "$DEST"
mkdir -p Vendor
mv "$work/out/Sparkle.xcframework" "$DEST"
echo "$VERSION" > "$STAMP"
echo "Fetched Sparkle $VERSION into $DEST"
