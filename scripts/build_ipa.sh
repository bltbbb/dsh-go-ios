#!/usr/bin/env bash
# Compile Runner.app, ad-hoc sign it, and wrap it as a TrollStore-installable .ipa.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require flutter
require codesign
require zip
require plutil

[ -d "$IOS_DIR/Runner.xcodeproj" ] || die "iOS project missing; run scripts/prepare.sh first"

# Fail-safe: Flutter refuses to build a deployable iOS app unless a Development
# Team is configured, even with --no-codesign. Make sure a (dummy) team value is
# present in the Xcode build configs. TrollStore re-signs on install and this
# script ad-hoc signs, so the value is never used for real signing.
for cfg in "$IOS_DIR/Flutter/Release.xcconfig" "$IOS_DIR/Flutter/Debug.xcconfig"; do
  if [ -f "$cfg" ] && ! grep -q '^DEVELOPMENT_TEAM' "$cfg"; then
    printf 'DEVELOPMENT_TEAM = 0000000000\n' >> "$cfg"
  fi
done

# ---------------------------------------------------------------- connectivity_plus iOS 26 API
# See prepare.sh for context. Re-apply here in case pod install copied the plugin
# source into Pods/ or the cache was refreshed.
log "ensuring connectivity_plus iOS 26 API reference is neutralized"
while IFS= read -r -d '' f; do
  if grep -q 'isUltraConstrained' "$f" 2>/dev/null; then
    sed -i.bak 's/path\.isUltraConstrained/false/' "$f"
    log "  patched: $f"
  fi
done < <(find "${PUB_CACHE:-$HOME/.pub-cache}" "$IOS_DIR/Pods" \
          -path '*PathMonitorConnectivityProvider.swift' -print0 2>/dev/null || true)

log "flutter build ios --release --no-codesign"
( cd "$APP_DIR" && flutter build ios --release --no-codesign )

BUILT_APP="$APP_DIR/build/ios/iphoneos/Runner.app"
if [ ! -d "$BUILT_APP" ]; then
  BUILT_APP="$(find "$APP_DIR/build/ios" -maxdepth 4 -name '*.app' -type d 2>/dev/null | head -1 || true)"
fi
[ -n "$BUILT_APP" ] && [ -d "$BUILT_APP" ] || die "Runner.app not found after build"

# Make sure the bundle id / min OS in the built product match the requested values.
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$BUILT_APP/Info.plist"
plutil -replace MinimumOSVersion -string "$IOS_DEPLOYMENT_TARGET" "$BUILT_APP/Info.plist"
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$BUILT_APP/Info.plist"

# ---------------------------------------------------------------- ad-hoc sign
# TrollStore replaces the signature with its CoreTrust-bypassed one during
# installation, but the .ipa must still contain a well-formed signed bundle.
# Sign nested frameworks first, then the outer app with our entitlements.
log "ad-hoc signing nested frameworks"
while IFS= read -r -d '' fw; do
  codesign --force --sign - --timestamp=none --generate-entitlement-der "$fw" \
    >/dev/null 2>&1 || warn "skipped: $fw"
done < <(find "$BUILT_APP" \( -type d -o -type l \) \
           \( -name '*.framework' -o -name '*.dylib' \) -print0)

ENT="$IOS_DIR/Runner/Runner.entitlements"
if [ -f "$ENT" ]; then
  log "ad-hoc signing Runner.app with entitlements"
  codesign --force --deep --sign - --timestamp=none --generate-entitlement-der \
    --entitlements "$ENT" "$BUILT_APP"
else
  codesign --force --deep --sign - --timestamp=none --generate-entitlement-der "$BUILT_APP"
fi
codesign -dv --verbose=1 "$BUILT_APP" 2>&1 | head -8 || true

# ------------------------------------------------------------------- .ipa
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Payload" "$OUT_DIR"
cp -R "$BUILT_APP" "$STAGE_DIR/Payload/Runner.app"
find "$STAGE_DIR" -name '.DS_Store' -delete 2>/dev/null || true

IPA="$OUT_DIR/DSH-Go-TrollStore.ipa"
rm -f "$IPA"
# -y keeps symlinks (Flutter.framework relies on them); -r recurses.
( cd "$STAGE_DIR" && zip -qry "$IPA" Payload )

[ -s "$IPA" ] || die "failed to create .ipa"
echo "signed with   : ad-hoc (-), entitlements: $(basename "${ENT:-none}")" >> "$OUT_DIR/BUILD_INFO.txt"

log "artifact: $IPA ($(du -h "$IPA" | awk '{print $1}'))"
log "sha256  : $(shasum -a 256 "$IPA" | awk '{print $1}')"
log "install : save to Files app -> share to TrollStore"
