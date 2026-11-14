#!/usr/bin/env bash
# Runs every Swift test with coverage on, then fails if ShortcutPhoneCore's line coverage is
# below MIN_CORE_COVERAGE (default 85). Used by check.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
MIN="${MIN_CORE_COVERAGE:-85}"

# Stale .profraw files from earlier runs would be merged into this run's numbers.
find .build -type d -name codecov -prune -exec rm -rf {} + 2>/dev/null || true
marker="$(mktemp)"
trap 'rm -f "$marker"' EXIT

scripts/swift-test.sh --enable-code-coverage

profdata="$(find .build -name default.profdata -path '*codecov*' -newer "$marker" | head -1)"
# The newest test binary holding the Core tests. It may predate the marker when nothing needed
# rebuilding. Swift Build makes one bundle per test target (ShortcutPhoneCoreTests.xctest); the
# classic SwiftPM build system (Xcode on CI) makes one for the package (ShortcutPhonePackageTests).
binary="$(find .build -type f \( \
  -path '*ShortcutPhoneCoreTests.xctest/Contents/MacOS/ShortcutPhoneCoreTests' -o \
  -path '*ShortcutPhonePackageTests.xctest/Contents/MacOS/ShortcutPhonePackageTests' \) \
  -exec stat -f '%m %N' {} + | sort -rn | head -1 | cut -d' ' -f2-)"
if [ -z "$profdata" ] || [ -z "$binary" ]; then
  echo "coverage: no profile data or Core test binary found" >&2
  find .build -maxdepth 6 \( -name '*.profdata' -o -name '*.xctest' \) >&2 || true
  exit 1
fi

report="$(xcrun llvm-cov report "$binary" -instr-profile "$profdata" "$PWD/Sources/ShortcutPhoneCore")"
# TOTAL row: name, regions, missed, cover, functions, missed, executed, lines, missed, cover…
lines="$(awk '$1 == "TOTAL" { gsub("%", "", $10); print $10 }' <<<"$report")"
if [ -z "$lines" ]; then
  echo "coverage: could not read the llvm-cov report" >&2
  echo "$report" >&2
  exit 1
fi
if awk -v got="$lines" -v min="$MIN" 'BEGIN { exit !(got + 0 < min + 0) }'; then
  echo "$report"
  echo "coverage: ShortcutPhoneCore line coverage ${lines}% is below ${MIN}%" >&2
  exit 1
fi
echo "coverage: ShortcutPhoneCore line coverage ${lines}% (minimum ${MIN}%)"
