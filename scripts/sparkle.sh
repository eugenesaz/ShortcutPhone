#!/usr/bin/env bash
# Compiles and runs scripts/sparkle-tool.swift (Sparkle update keys, signatures, appcast).
#   ./scripts/sparkle.sh generate-key <dir>
#   SPARKLE_PRIVATE_KEY=… ./scripts/sparkle.sh appcast <version> <zip> <url> <notes.md> <public-key>
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=swift-env.sh
source scripts/swift-env.sh
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swiftc -O -o "$work/sparkle-tool" scripts/sparkle-tool.swift 2>/dev/null \
  || swiftc -O -o "$work/sparkle-tool" scripts/sparkle-tool.swift
"$work/sparkle-tool" "$@"
