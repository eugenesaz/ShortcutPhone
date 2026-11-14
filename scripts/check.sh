#!/usr/bin/env bash
# Every gate that must pass before a commit. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=swift-env.sh
source scripts/swift-env.sh

step() { printf '\n==> %s\n' "$*"; }

if [ ! -d web/node_modules ]; then
  step "npm ci"
  npm --prefix web ci
fi

step "sparkle: fetch"; scripts/fetch-sparkle.sh
step "web: lint";      npm --prefix web run lint
step "web: typecheck"; npm --prefix web run typecheck
step "web: test";      npm --prefix web test
step "web: build";     npm --prefix web run build

step "swift: format lint"; swift format lint --strict -r Sources Tests Package.swift scripts/make-icons.swift scripts/sparkle-tool.swift
step "swift: test + Core coverage"; scripts/swift-test-coverage.sh
step "sparkle: appcast"; scripts/sparkle-smoke-test.sh

printf '\nAll checks passed.\n'
