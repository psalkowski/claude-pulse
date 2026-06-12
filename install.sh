#!/bin/bash
# One-command install for Claude Pulse. Checks prerequisites, builds, and
# installs the app to /Applications. Safe to re-run (upgrades in place).
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Checking prerequisites…"

# Xcode (full Xcode, not just Command Line Tools — WidgetKit needs it).
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "✗ Xcode is required. Install it from the App Store, then run:"
  echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "    sudo xcodebuild -license accept"
  exit 1
fi

# XcodeGen (generates the .xcodeproj from project.yml).
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "▸ Installing xcodegen via Homebrew…"
    brew install xcodegen
  else
    echo "✗ XcodeGen is required. Install Homebrew (https://brew.sh) then: brew install xcodegen"
    exit 1
  fi
fi

# jq is optional — only the scripts/ helpers use it.
command -v jq >/dev/null 2>&1 || echo "  (note: 'brew install jq' if you want to run the scripts/ helpers)"

echo "▸ Generating project…"
xcodegen >/dev/null

# Version stamp from git: marketing version from the latest tag, build number
# from the commit count (what Sparkle compares between installs and releases).
MARKETING_VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
[ -n "$MARKETING_VERSION" ] || MARKETING_VERSION="0.1.0"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null)"
[ -n "$BUILD_NUMBER" ] || BUILD_NUMBER="1"

echo "▸ Building (Release, v$MARKETING_VERSION build $BUILD_NUMBER)…"
xcodebuild -project ClaudePulse.xcodeproj -scheme ClaudePulse \
  -configuration Release -derivedDataPath build \
  MARKETING_VERSION="$MARKETING_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build >/dev/null

APP="build/Build/Products/Release/ClaudePulse.app"
echo "▸ Installing to /Applications…"
pkill -x ClaudePulse 2>/dev/null || true
rm -rf "/Applications/ClaudePulse.app"
cp -R "$APP" /Applications/
open "/Applications/ClaudePulse.app"

echo "✓ Installed. Click the Claude Pulse menubar icon, then 'Add usage token' for"
echo "  each subscription (it shows the exact 'claude setup-token' command to run)."
