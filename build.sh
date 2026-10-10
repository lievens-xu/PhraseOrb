#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/语句球.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$OUTPUT_DIR/build"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx13.0" \
    -framework AppKit -framework SwiftUI "$PROJECT_DIR/Sources/main.swift" \
    -o "$OUTPUT_DIR/build/PhraseOrb-$arch"
done
lipo -create "$OUTPUT_DIR/build/PhraseOrb-arm64" "$OUTPUT_DIR/build/PhraseOrb-x86_64" \
  -output "$APP_DIR/Contents/MacOS/PhraseOrb"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "$PROJECT_DIR/AppIcon.icns" ]]; then
  cp "$PROJECT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP_DIR"
print "Built: $APP_DIR"
