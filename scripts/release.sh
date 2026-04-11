#!/usr/bin/env bash
#
# Bumps the build number in pubspec.yaml, swaps in .env.production, and
# runs a Flutter release build. The original .env is restored on exit,
# even if the build fails.
#
# Usage:
#   scripts/release.sh [target]
#
# Targets (default: appbundle):
#   apk        -> flutter build apk --release
#   appbundle  -> flutter build appbundle --release
#   ipa        -> flutter build ipa --release
#   ios        -> flutter build ios --release
#   all        -> appbundle + ipa
#
# The build number is the integer after "+" in the pubspec version
# (e.g. 1.0.0+7 -> 1.0.0+8). The version name is left untouched.
#
# Requires .env.production to exist at the repo root.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$ROOT_DIR/pubspec.yaml"
ENV_FILE="$ROOT_DIR/.env"
ENV_PROD_FILE="$ROOT_DIR/.env.production"
ENV_BACKUP="$ROOT_DIR/.env.release-backup"
TARGET="${1:-appbundle}"

if [[ ! -f "$ENV_PROD_FILE" ]]; then
  echo ".env.production not found at $ENV_PROD_FILE" >&2
  echo "Create it before running a release build." >&2
  exit 1
fi

restore_env() {
  if [[ -f "$ENV_BACKUP" ]]; then
    mv "$ENV_BACKUP" "$ENV_FILE"
    echo "Restored original .env"
  fi
}
trap restore_env EXIT

if [[ ! -f "$PUBSPEC" ]]; then
  echo "pubspec.yaml not found at $PUBSPEC" >&2
  exit 1
fi

current_line="$(grep -E '^version:\s' "$PUBSPEC" | head -n1)"
current_version="$(echo "$current_line" | sed -E 's/^version:[[:space:]]*//')"

if [[ ! "$current_version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]]; then
  echo "Unexpected version format in pubspec.yaml: '$current_version'" >&2
  echo "Expected something like 1.0.0+1" >&2
  exit 1
fi

name="${BASH_REMATCH[1]}"
build="${BASH_REMATCH[2]}"
next_build=$((build + 1))
next_version="${name}+${next_build}"

# In-place replace, portable between macOS and Linux sed.
sed -i.bak -E "s/^version:[[:space:]]*.*/version: ${next_version}/" "$PUBSPEC"
rm -f "${PUBSPEC}.bak"

echo "Bumped version: ${current_version} -> ${next_version}"

# Swap in .env.production for the build. Back up the existing .env so the
# trap can restore it on exit.
if [[ -f "$ENV_FILE" ]]; then
  cp "$ENV_FILE" "$ENV_BACKUP"
fi
cp "$ENV_PROD_FILE" "$ENV_FILE"
echo "Using .env.production for release build"

cd "$ROOT_DIR"

case "$TARGET" in
  apk)
    flutter build apk --release
    ;;
  appbundle)
    flutter build appbundle --release
    ;;
  ipa)
    flutter build ipa --release
    ;;
  ios)
    flutter build ios --release
    ;;
  all)
    flutter build appbundle --release
    flutter build ipa --release
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    echo "Use one of: apk, appbundle, ipa, ios, all" >&2
    exit 1
    ;;
esac
