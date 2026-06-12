#!/usr/bin/env bash
# Regenerate the macOS app-icon PNGs and the GitHub brand mark from the source
# SVGs in Branding/. Run after editing Branding/claude-pulse-icon.svg or
# Branding/claude-pulse-mark.svg. Requires librsvg (`brew install librsvg`).
set -euo pipefail

cd "$(dirname "$0")/.."

ICON_SVG="Branding/claude-pulse-icon.svg"
MARK_SVG="Branding/claude-pulse-mark.svg"
SOCIAL_SVG="Branding/claude-pulse-social.svg"
ICONSET="ClaudePulse/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found — install with: brew install librsvg" >&2
  exit 1
fi

echo "Rendering app-icon PNGs into $ICONSET"
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$size" -h "$size" "$ICON_SVG" -o "$ICONSET/icon_${size}.png"
done

echo "Rendering GitHub brand mark"
rsvg-convert -w 1024 -h 1024 "$MARK_SVG" -o "Branding/claude-pulse-mark.png"
rsvg-convert -w 512  -h 512  "$MARK_SVG" -o "docs/images/logo.png"

echo "Rendering GitHub social-preview card"
mkdir -p .github
rsvg-convert -w 1280 -h 640 "$SOCIAL_SVG" -o ".github/social-preview.png"

echo "Done."
