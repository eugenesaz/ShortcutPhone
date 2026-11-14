#!/usr/bin/env bash
# Source this before running `swift build/test`. For tests use scripts/swift-test.sh.
#
# Workaround for a broken Command Line Tools install: stale Swift 5.10
# `*.private.swiftinterface` files in the CLT's ManifestAPI/PluginAPI folders
# shadow the current interfaces, so every Package.swift fails to link.
# If they are present, build a clean copy of those folders (without the stale
# files) and point SwiftPM at it with SWIFTPM_CUSTOM_LIBS_DIR. No-op otherwise.
# Proper fix: reinstall the Command Line Tools.

_spm_src="$(dirname "$(xcrun --find swift)")/../lib/swift/pm"
_spm_stale="$_spm_src/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface"

if [ -f "$_spm_stale" ] && head -2 "$_spm_stale" | grep -q 'Swift version 5\.'; then
  _spm_dst="${XDG_DATA_HOME:-$HOME/.local/share}/swiftpm-libs"
  if [ ! -f "$_spm_dst/.source" ] || [ "$(cat "$_spm_dst/.source")" != "$(swift --version 2>&1 | head -1)" ]; then
    rm -rf "$_spm_dst"
    mkdir -p "$_spm_dst"
    cp -R "$_spm_src/ManifestAPI" "$_spm_src/PluginAPI" "$_spm_dst/"
    find "$_spm_dst" -name '*.private.swiftinterface' -delete
    swift --version 2>&1 | head -1 > "$_spm_dst/.source"
  fi
  export SWIFTPM_CUSTOM_LIBS_DIR="$_spm_dst"
fi

# Swift Build sometimes omits the swift-testing macro plugin when compiling test targets
# with only the Command Line Tools installed ("plugin for module 'TestingMacros' not found").
# Pass its path explicitly (scripts/swift-test.sh does this).
_spm_testing_plugins="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
SWIFT_TEST_FLAGS=""
if [ -d "$_spm_testing_plugins" ]; then
  SWIFT_TEST_FLAGS="-Xswiftc -plugin-path -Xswiftc $(cd "$_spm_testing_plugins" && pwd)"
fi
export SWIFT_TEST_FLAGS
unset _spm_src _spm_stale _spm_dst _spm_testing_plugins
