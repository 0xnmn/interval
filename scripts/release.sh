#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
: "${CODE_SIGN_IDENTITY:?Developer ID Application identity required}"
: "${NOTARY_PROFILE:?notarytool keychain profile required}"
: "${UPDATE_FEED_URL:?HTTPS update feed required}"
: "${SPARKLE_PUBLIC_KEY:?Sparkle EdDSA public key required}"
: "${VERSION:?Release VERSION required}"
: "${BUILD_NUMBER:?Release BUILD_NUMBER required}"
ARCHIVE_URL_PREFIX="${ARCHIVE_URL_PREFIX:-${UPDATE_FEED_URL%/*}/}"
[[ "$UPDATE_FEED_URL" == https://* && "$ARCHIVE_URL_PREFIX" == https://* ]] || { echo "Update feed and archive URL prefix must use HTTPS" >&2; exit 2; }
[[ "$CODE_SIGN_IDENTITY" == Developer\ ID\ Application:* ]] || { echo "A real Developer ID Application identity is required" >&2; exit 2; }
security find-identity -v -p codesigning | grep -F "$CODE_SIGN_IDENTITY" >/dev/null || { echo "Signing identity is not installed" >&2; exit 2; }
"$ROOT/scripts/build.sh"
DIST="$ROOT/.build/release-artifacts"; rm -rf "$DIST"; mkdir -p "$DIST"
ditto -c -k --keepParent "$ROOT/.build/Interval.app" "$DIST/Interval.zip"
xcrun notarytool submit "$DIST/Interval.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$ROOT/.build/Interval.app"
xcrun stapler validate "$ROOT/.build/Interval.app"
codesign --verify --deep --strict "$ROOT/.build/Interval.app"
spctl --assess --type execute --verbose=2 "$ROOT/.build/Interval.app"
ditto -c -k --keepParent "$ROOT/.build/Interval.app" "$DIST/Interval.zip"
TOOLS="$(find "$ROOT/.build/artifacts" -type d -name bin -ipath '*sparkle*' -print -quit)"
[[ -x "$TOOLS/sign_update" && -x "$TOOLS/generate_appcast" ]] || { echo "Sparkle release tools not found" >&2; exit 1; }
"$TOOLS/sign_update" "$DIST/Interval.zip" > "$DIST/Interval.zip.signature.txt"
"$TOOLS/generate_appcast" --download-url-prefix "${ARCHIVE_URL_PREFIX%/}/" "$DIST"
echo "Release artifacts and appcast generated in $DIST"
