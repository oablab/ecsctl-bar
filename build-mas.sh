#!/bin/bash
# Build the SANDBOXED prototype of ecsctl-bar (MAS architecture).
# Ad-hoc signed — App Sandbox is still fully enforced at runtime, so this
# validates the MAS architecture locally without App Store Connect.
set -euo pipefail
cd "$(dirname "$0")"

APP="ecsctl-bar-mas.app"
BIN="ecsctl-bar"
# Bundled helper: darwin-arm64 from the tagged ecsctl release (reproducible).
# Refresh with: gh release download vX.Y.Z -R oablab/ecsctl -p "ecsctl-darwin-arm64.tar.gz" -O - | tar xz -C tools/release
# MUST be v0.12.0+ (ECSCTL_CONFIG support — older versions silently ignore it).
ECSCTL="${ECSCTL_BIN:-tools/release/ecsctl}"

[ -x "$ECSCTL" ] || { echo "ecsctl not found at $ECSCTL (set ECSCTL_BIN=)"; exit 1; }
file "$ECSCTL" | grep -q arm64 || { echo "$ECSCTL is not arm64"; exit 1; }

echo "==> compiling..."
swiftc -O -parse-as-library \
  -target arm64-apple-macosx13.0 \
  Sources/*.swift \
  -o "$BIN"

echo "==> bundling (with ecsctl helper)..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
mv "$BIN" "$APP/Contents/MacOS/"
cp "$ECSCTL" "$APP/Contents/Helpers/ecsctl"
cp Info.plist "$APP/Contents/"
# MAS product name is "ecsctl" (bundle id stays dev.pahud.ecsctl-bar)
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ecsctl" \
                        -c "Set :CFBundleName ecsctl" "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || true

echo "==> signing helper (sandbox inherit)..."
codesign --force -s - \
  --entitlements entitlements-inherit.plist \
  "$APP/Contents/Helpers/ecsctl"

echo "==> signing app (app-sandbox + network.client + user-selected files)..."
codesign --force -s - \
  --entitlements entitlements-mas.plist \
  "$APP"

echo "==> verify entitlements:"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -E "app-sandbox|network.client|user-selected" || true

echo "==> done: $PWD/$APP"
echo "    run: open \"$APP\"   (container: ~/Library/Containers/dev.pahud.ecsctl-bar)"
