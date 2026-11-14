#!/usr/bin/env bash
# `swift test` with this Mac's toolchain workarounds applied (see swift-env.sh).
# Extra arguments pass through, e.g. ./scripts/swift-test.sh --filter ConfigTests
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=swift-env.sh
source scripts/swift-env.sh
# shellcheck disable=SC2086 # intentional word splitting of flags
exec swift test $SWIFT_TEST_FLAGS "$@"
