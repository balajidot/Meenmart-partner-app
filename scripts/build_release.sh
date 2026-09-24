#!/usr/bin/env bash
# Builds the release APK that the in-app updater downloads: bumps the pubspec
# build number by 1, then builds one APK for ARM phones only.
#
# Usage: ./scripts/build_release.sh [--no-bump]
#
# - ARM only (armeabi-v7a + arm64-v8a): x86_64 is for emulators and was
#   ~23MB of every download. One APK still serves every staff phone, so a
#   single store_apk_url in settings keeps working.
# - --obfuscate --split-debug-info: smaller libapp.so. Keep the symbols dir
#   of each shipped version; `flutter symbolize` needs it to read a stack
#   trace from that build.
# - After uploading the APK, set store_app_version_code in settings to the
#   new build number (the part after '+').

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PUBSPEC="pubspec.yaml"
BUMP=1
[[ "${1:-}" == "--no-bump" ]] && BUMP=0

if [[ ! -f .env ]]; then
  echo "error: .env not found — the app would start without Supabase keys." >&2
  exit 1
fi

current_version=$(grep -m1 '^version:' "$PUBSPEC" | sed 's/version:[[:space:]]*//' | tr -d '\r')
name="${current_version%+*}"
build="${current_version##*+}"

if [[ "$BUMP" == "1" ]]; then
  new_version="${name}+$((build + 1))"
  sed -i "s/^version:.*/version: ${new_version}/" "$PUBSPEC"
  echo "Version bumped: ${current_version} -> ${new_version}"
else
  new_version="$current_version"
  echo "Version kept: ${new_version}"
fi

SYMBOLS_DIR="build/symbols/${new_version}"

echo "Building release APK (${new_version})..."
flutter build apk --release \
  --target-platform android-arm,android-arm64 \
  --obfuscate --split-debug-info="$SYMBOLS_DIR"

APK="build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$APK" ]]; then
  echo "error: expected APK not found at $APK" >&2
  exit 1
fi

echo ""
echo "Built: $APK ($(du -h "$APK" | cut -f1)) — version $new_version"
echo "SHA-256: $(sha256sum "$APK" | cut -d' ' -f1)"
echo "Dart symbols: $SYMBOLS_DIR (back these up; build/ is not in git)"
echo "Next: upload the APK, then set store_app_version_code = ${new_version##*+} and store_app_version_name = ${new_version%+*}"
