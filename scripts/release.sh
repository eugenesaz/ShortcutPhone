#!/usr/bin/env bash
# Builds a release zip: build/ShortcutPhone-<version>.zip, plus its SHA-256.
#   ./scripts/release.sh 0.2.0
# Signs with CODESIGN_IDENTITY (CI sets "ShortcutPhone Release"; see docs/releasing.md).
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: $0 <version, e.g. 0.2.0>}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be X.Y.Z" >&2; exit 1; }

VERSION="$version" scripts/bundle.sh
zip="build/ShortcutPhone-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent build/ShortcutPhone.app "$zip"
shasum -a 256 "$zip" | tee "$zip.sha256"
