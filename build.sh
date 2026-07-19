#!/bin/bash
# Build ecsctl Bar.app
set -euo pipefail
cd "$(dirname "$0")"

APP="ecsctl-bar.app"
BIN="ecsctl-bar"

echo "==> compiling..."
swiftc -O -parse-as-library \
  -target arm64-apple-macosx13.0 \
  Sources/main.swift \
  -o "$BIN"

echo "==> bundling..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

echo "==> codesigning (ad-hoc)..."
codesign --force -s - "$APP"

echo "==> done: $PWD/$APP"
echo "    install: cp -R \"$APP\" /Applications/"
