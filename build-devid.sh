#!/bin/bash
# Build ecsctl Bar for Developer ID distribution (outside Mac App Store).
# Universal binary + hardened runtime + Developer ID signing.
# Usage: ./build-devid.sh          — build & sign
#        ./build-devid.sh notarize — also submit for notarization + staple
#        (notarize requires ASC_ISSUER_ID env var)
set -euo pipefail
cd "$(dirname "$0")"

APP="ecsctl Bar.app"
BIN="EcsctlBar"
CERT="Developer ID Application: Hung-En Hsieh (UM92U863A8)"
VERSION=$(defaults read "$PWD/Info.plist" CFBundleShortVersionString)
ZIP="ecsctl-Bar-$VERSION-devid.zip"

echo "==> compiling (arm64 + x86_64 universal)..."
swiftc -O -parse-as-library -target arm64-apple-macosx13.0  Sources/main.swift -o "$BIN.arm64"
swiftc -O -parse-as-library -target x86_64-apple-macosx13.0 Sources/main.swift -o "$BIN.x86_64"
lipo -create "$BIN.arm64" "$BIN.x86_64" -output "$BIN"
rm "$BIN.arm64" "$BIN.x86_64"

echo "==> bundling..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp AppIcon.icns "$APP/Contents/Resources/"

echo "==> signing (Developer ID, hardened runtime)..."
codesign --force --options runtime --timestamp \
  --sign "$CERT" \
  "$APP"
codesign --verify --deep --strict "$APP"

echo "==> zipping..."
ditto -c -k --keepParent "$APP" "$ZIP"
echo "    $ZIP"

if [ "${1:-}" = "notarize" ]; then
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID to your App Store Connect issuer ID}"
  echo "==> submitting for notarization..."
  xcrun notarytool submit "$ZIP" \
    --key ~/.appstoreconnect/private_keys/AuthKey_92Z89A669K.p8 \
    --key-id 92Z89A669K \
    --issuer "$ASC_ISSUER_ID" \
    --wait
  echo "==> stapling..."
  xcrun stapler staple "$APP"
  # re-zip with the stapled ticket
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "==> done (stapled): $ZIP"
else
  echo "==> done (not notarized). Run './build-devid.sh notarize' with ASC_ISSUER_ID set."
fi
