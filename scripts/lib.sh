#!/usr/bin/env bash
# Shared config for prepare.sh / build_ipa.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

export UPSTREAM_DIR="${UPSTREAM_DIR:-$ROOT/upstream}"
export APP_DIR="${APP_DIR:-$UPSTREAM_DIR/app}"
export IOS_DIR="${IOS_DIR:-$APP_DIR/ios}"
export OUT_DIR="${OUT_DIR:-$ROOT/out}"
export STAGE_DIR="${STAGE_DIR:-$ROOT/stage}"

export UPSTREAM_REPO="${UPSTREAM_REPO:-lxsfful/dsh-go}"
export UPSTREAM_REF="${UPSTREAM_REF:-main}"
export BUNDLE_ID="${BUNDLE_ID:-io.github.lxsfful.dshgo.troll}"
export IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.0}"
export APP_NAME="${APP_NAME:-DSH Go}"
export FLUTTER_PROJECT_NAME="${FLUTTER_PROJECT_NAME:-dsh_app}"

log()  { printf '\033[1;34m[ios]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

# Reverse the first two labels of the bundle id for flutter create --org
bundle_org() {
  printf '%s' "$BUNDLE_ID" | awk -F. '{ if (NF >= 3) print $1 "." $2; else print "io.github" }'
}
