#!/usr/bin/env bash
# Regenerates the PWA icons (web/public/pwa) and Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=swift-env.sh
source scripts/swift-env.sh
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swiftc -o "$work/make-icons" scripts/make-icons.swift
"$work/make-icons" "$PWD" "$work/AppIcon.iconset"
iconutil -c icns -o Resources/AppIcon.icns "$work/AppIcon.iconset"
echo "Wrote web/public/pwa/*.png and Resources/AppIcon.icns"
