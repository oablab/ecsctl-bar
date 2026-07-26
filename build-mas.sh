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
codesign --force -s "${SIGN_APP_ID:--}" \
  --entitlements entitlements-inherit.plist \
  "$APP/Contents/Helpers/ecsctl"

if [ -n "${PROFILE:-}" ]; then
  # ---- Real MAS signing (requires the App Store provisioning profile) ----
  # PROFILE=path/to/ecsctl_appstore.provisionprofile
  # SIGN_APP_ID default: Apple Distribution; SIGN_PKG_ID: installer identity
  SIGN_APP_ID="${SIGN_APP_ID:-Apple Distribution: Hsieh Hong En (UM92U863A8)}"
  SIGN_PKG_ID="${SIGN_PKG_ID:-3rd Party Mac Developer Installer: Hsieh Hong En (UM92U863A8)}"
  TEAM_ID="UM92U863A8"
  BUNDLE_ID="dev.pahud.ecsctl-bar"

  echo "==> embedding provisioning profile..."
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

  echo "==> generating distribution entitlements..."
  cat > /tmp/entitlements-mas-dist.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.network.client</key><true/>
    <key>com.apple.security.files.user-selected.read-only</key><true/>
    <key>com.apple.security.files.bookmarks.app-scope</key><true/>
    <key>com.apple.application-identifier</key><string>$TEAM_ID.$BUNDLE_ID</string>
    <key>com.apple.developer.team-identifier</key><string>$TEAM_ID</string>
</dict>
</plist>
EOF

  echo "==> re-signing helper + app with $SIGN_APP_ID..."
  codesign --force --timestamp -s "$SIGN_APP_ID" \
    --entitlements entitlements-inherit.plist \
    "$APP/Contents/Helpers/ecsctl"
  codesign --force --timestamp -s "$SIGN_APP_ID" \
    --entitlements /tmp/entitlements-mas-dist.plist \
    "$APP"
  rm /tmp/entitlements-mas-dist.plist

  echo "==> building installer pkg..."
  productbuild --component "$APP" /Applications \
    --sign "$SIGN_PKG_ID" "ecsctl-mas.pkg"
  echo "==> done: $PWD/ecsctl-mas.pkg (upload via foldic asc_upload.py)"
else
  echo "==> signing app (ad-hoc, sandbox enforced — local prototype)..."
  codesign --force -s - \
    --entitlements entitlements-mas.plist \
    "$APP"

  echo "==> verify entitlements:"
  codesign -d --entitlements - "$APP" 2>/dev/null | grep -E "app-sandbox|network.client|user-selected" || true
fi

echo "==> done: $PWD/$APP"
echo "    run: open \"$APP\"   (container: ~/Library/Containers/dev.pahud.ecsctl-bar)"
