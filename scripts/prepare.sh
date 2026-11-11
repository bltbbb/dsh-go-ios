#!/usr/bin/env bash
# Fetch upstream dsh-go, create the iOS Runner project and apply the overlay.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require git
require flutter
require python3
require pod
require plutil

log "config: upstream=$UPSTREAM_REPO@$UPSTREAM_REF bundle=$BUNDLE_ID ios=$IOS_DEPLOYMENT_TARGET"

# ---------------------------------------------------------------- 1. upstream
if [ ! -d "$UPSTREAM_DIR/.git" ]; then
  log "sparse-cloning upstream (app/ + packages/ only)"
  rm -rf "$UPSTREAM_DIR"
  if ! git clone --depth 1 --filter=blob:none --sparse \
        --branch "$UPSTREAM_REF" "https://github.com/$UPSTREAM_REPO.git" "$UPSTREAM_DIR"; then
    warn "sparse clone failed, falling back to a plain shallow clone"
    rm -rf "$UPSTREAM_DIR"
    git clone --depth 1 "https://github.com/$UPSTREAM_REPO.git" "$UPSTREAM_DIR"
    git -C "$UPSTREAM_DIR" checkout "$UPSTREAM_REF" 2>/dev/null || true
  else
    git -C "$UPSTREAM_DIR" sparse-checkout set app packages
  fi
else
  log "reusing existing checkout at $UPSTREAM_DIR"
fi

[ -f "$APP_DIR/pubspec.yaml" ] || die "upstream app/pubspec.yaml not found"
UPSTREAM_SHA="$(git -C "$UPSTREAM_DIR" rev-parse --short HEAD)"
log "upstream commit: $UPSTREAM_SHA"

# ------------------------------------------------------- 2. flutter create ios
if [ ! -d "$IOS_DIR/Runner.xcodeproj" ]; then
  log "generating iOS Runner skeleton"
  ( cd "$APP_DIR" && flutter create \
      --platforms=ios \
      --org "$(bundle_org)" \
      --project-name "$FLUTTER_PROJECT_NAME" \
      --no-pub \
      . )
else
  log "iOS Runner skeleton already present"
fi

# ------------------------------------------------------------- 3. overlay
log "applying ios-overlay"
cp "$ROOT/ios-overlay/Info.plist"            "$IOS_DIR/Runner/Info.plist"
cp "$ROOT/ios-overlay/AppDelegate.swift"     "$IOS_DIR/Runner/AppDelegate.swift"
cp "$ROOT/ios-overlay/Runner.entitlements"   "$IOS_DIR/Runner/Runner.entitlements"
cp "$ROOT/ios-overlay/Podfile"               "$IOS_DIR/Podfile"
cp "$ROOT/ios-overlay/Contents.json" \
   "$IOS_DIR/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"

# AppFrameworkInfo.plist minimum OS
if [ -f "$IOS_DIR/Flutter/AppFrameworkInfo.plist" ]; then
  plutil -replace MinimumOSVersion -string "$IOS_DEPLOYMENT_TARGET" \
    "$IOS_DIR/Flutter/AppFrameworkInfo.plist"
fi

# Display name
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$IOS_DIR/Runner/Info.plist"

# Podfile / Info.plist deployment target (the Podfile reads the same env var,
# but also bake the value in so Xcode opens with the right setting).
export IOS_DEPLOYMENT_TARGET
python3 - "$IOS_DIR/Podfile" "$IOS_DEPLOYMENT_TARGET" <<'PY'
import re, sys
p, target = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
s = re.sub(r"(ENV\.fetch\('IOS_DEPLOYMENT_TARGET',\s*)'[^']+'",
           rf"\g<1>'{target}'", s)
open(p, "w", encoding="utf-8").write(s)
PY
plutil -replace MinimumOSVersion -string "$IOS_DEPLOYMENT_TARGET" "$IOS_DIR/Runner/Info.plist"

# ------------------------------------------------- 4. icon from Android assets
ANDROID_ICON="$(find "$APP_DIR/android/app/src/main/res" -name 'ic_launcher.png' \
                -path '*xxxhdpi*' 2>/dev/null | head -1 || true)"
if [ -n "$ANDROID_ICON" ] && command -v sips >/dev/null 2>&1; then
  log "reusing Android launcher icon as iOS AppIcon"
  sips -s format png -Z 1024 "$ANDROID_ICON" \
    --out "$IOS_DIR/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png" \
    >/dev/null 2>&1 || warn "icon conversion skipped"
fi

# ------------------------------------------------------- 5. pbxproj patching
log "patching project.pbxproj"
python3 "$ROOT/scripts/patch_pbxproj.py" \
  --pbxproj "$IOS_DIR/Runner.xcodeproj/project.pbxproj" \
  --bundle-id "$BUNDLE_ID" \
  --deployment-target "$IOS_DEPLOYMENT_TARGET"

# ------------------------------------------------------- 6. Dart-side patches
log "adapting pubspec.yaml"
python3 "$ROOT/scripts/patch_pubspec.py" --app-dir "$APP_DIR"

# ------------------------------------ 7. generate Swift channel fallbacks
# Append the generated stubs to AppDelegate.swift instead of adding a new .swift
# file: Flutter's generated pbxproj lists source files explicitly, and a new
# file would silently never be compiled.
log "generating Swift MethodChannel / EventChannel fallbacks"
mkdir -p "$STAGE_DIR"
python3 "$ROOT/scripts/gen_channel_stubs.py" \
  --app-dir "$APP_DIR" \
  --out "$STAGE_DIR/IosChannelStubs.swift"
cat "$STAGE_DIR/IosChannelStubs.swift" >> "$IOS_DIR/Runner/AppDelegate.swift"

# ------------------------------------------------------------- 8. deps
log "flutter pub get"
( cd "$APP_DIR" && flutter pub get )

log "pod install (this may take a few minutes)"
( cd "$IOS_DIR" && pod install --repo-update )

# ------------------------------------ 8b. fix connectivity_plus iOS 26 API
# connectivity_plus 7.3.2 references NWPath.isUltraConstrained, an API introduced
# in the iOS 26.0 SDK. The CI macOS runner only ships up to the iOS 18.x SDK, so
# the Swift compiler cannot resolve the symbol (it is not declared in the SDK
# headers) even though it is guarded by `#available(iOS 26.0, *)`. Neutralize the
# reference so the app compiles; the .satellite connectivity type is unused here.
log "neutralizing connectivity_plus iOS 26 API reference"
CONN_FILE="$(find "${PUB_CACHE:-$HOME/.pub-cache}" \
  -path '*connectivity_plus*/Sources/connectivity_plus/PathMonitorConnectivityProvider.swift' \
  2>/dev/null | head -1 || true)"
if [ -n "$CONN_FILE" ]; then
  if grep -q 'isUltraConstrained' "$CONN_FILE"; then
    sed -i.bak 's/path\.isUltraConstrained/false/' "$CONN_FILE"
    log "  patched: $CONN_FILE"
  else
    log "  already patched: $CONN_FILE"
  fi
else
  warn "connectivity_plus source not found in pub cache; skipping patch"
fi

mkdir -p "$OUT_DIR"
cat > "$OUT_DIR/BUILD_INFO.txt" <<EOF
upstream      : $UPSTREAM_REPO@$UPSTREAM_REF ($UPSTREAM_SHA)
bundle id     : $BUNDLE_ID
display name  : $APP_NAME
ios target    : $IOS_DEPLOYMENT_TARGET
flutter       : $(flutter --version 2>/dev/null | head -1)
built at      : $(date -u +'%Y-%m-%dT%H:%M:%SZ')
EOF

log "prepare done. next: bash scripts/build_ipa.sh"
