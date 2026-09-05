#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -n "${UPDATE_FEED_URL:-}" || -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  [[ -n "${UPDATE_FEED_URL:-}" && -n "${SPARKLE_PUBLIC_KEY:-}" ]] || { echo "UPDATE_FEED_URL and SPARKLE_PUBLIC_KEY must be supplied together" >&2; exit 2; }
  [[ "$UPDATE_FEED_URL" == https://* ]] || { echo "UPDATE_FEED_URL must use HTTPS" >&2; exit 2; }
  python3 - "$UPDATE_FEED_URL" "$SPARKLE_PUBLIC_KEY" <<'PY'
import base64, sys, urllib.parse
url = urllib.parse.urlparse(sys.argv[1])
try:
    valid = url.scheme == 'https' and bool(url.hostname) and len(base64.b64decode(sys.argv[2], validate=True)) == 32
except ValueError:
    valid = False
if not valid:
    sys.exit('A valid HTTPS host and base64-encoded 32-byte Sparkle public key are required')
PY
fi
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
[[ "$VERSION" =~ ^[0-9]+([.][0-9]+){1,2}([+-][0-9A-Za-z.-]+)?$ ]] || { echo "VERSION must be a semantic version (for example 1.2.3)" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "BUILD_NUMBER must be a positive integer" >&2; exit 2; }

swift build -c release
APP="$ROOT/.build/Interval.app"; CONTENTS="$APP/Contents"
rm -rf "$APP"; mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$ROOT/.build/release/Interval" "$CONTENTS/MacOS/Interval"
SPARKLE="$(find "$ROOT/.build" -path '*/release/Sparkle.framework' -print -quit)"
[[ -d "$SPARKLE" ]] || { echo "Sparkle.framework was not produced" >&2; exit 1; }
ditto "$SPARKLE" "$CONTENTS/Frameworks/Sparkle.framework"

ICON_TMP="$(mktemp -d)"; trap 'rm -rf "$ICON_TMP"' EXIT
cat > "$ICON_TMP/icon.swift" <<'SWIFT'
import AppKit
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    NSColor(calibratedRed: 0.05, green: 0.55, blue: 0.53, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 48, dy: 48), xRadius: 220, yRadius: 220).fill()
    NSColor.white.setStroke()
    let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 230, dy: 230)); ring.lineWidth = 70; ring.stroke()
    let hand = NSBezierPath(); hand.move(to: NSPoint(x: 512, y: 512)); hand.line(to: NSPoint(x: 512, y: 735)); hand.lineWidth = 64; hand.lineCapStyle = .round; hand.stroke()
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
swift "$ICON_TMP/icon.swift" "$ICON_TMP/icon.png"
mkdir "$ICON_TMP/Interval.iconset"
for n in 16 32 128 256 512; do sips -z "$n" "$n" "$ICON_TMP/icon.png" --out "$ICON_TMP/Interval.iconset/icon_${n}x${n}.png" >/dev/null; d=$((n*2)); sips -z "$d" "$d" "$ICON_TMP/icon.png" --out "$ICON_TMP/Interval.iconset/icon_${n}x${n}@2x.png" >/dev/null; done
iconutil -c icns "$ICON_TMP/Interval.iconset" -o "$CONTENTS/Resources/Interval.icns"

python3 - "$CONTENTS/Info.plist" "${UPDATE_FEED_URL:-}" "${SPARKLE_PUBLIC_KEY:-}" "$VERSION" "$BUILD_NUMBER" <<'PY'
import plistlib, sys
p, feed, key, version, build = sys.argv[1:]
d = dict(CFBundleDevelopmentRegion='en', CFBundleExecutable='Interval', CFBundleIdentifier='com.interval.app',
 CFBundleInfoDictionaryVersion='6.0', CFBundleName='Interval', CFBundleDisplayName='Interval', CFBundlePackageType='APPL',
 CFBundleShortVersionString=version, CFBundleVersion=build, CFBundleIconFile='Interval', LSMinimumSystemVersion='26.0',
 NSHighResolutionCapable=True, SUEnableAutomaticChecks=False,
 NSCalendarsFullAccessUsageDescription='Interval reads selected calendars to display events in History and avoid showing reminders during calendar events. It never changes your calendars.')
if feed: d.update(SUFeedURL=feed, SUPublicEDKey=key)
with open(p, 'wb') as f: plistlib.dump(d, f)
PY
plutil -lint "$CONTENTS/Info.plist"
install_name_tool -add_rpath @executable_path/../Frameworks "$CONTENTS/MacOS/Interval" 2>/dev/null || true

IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  SIGN_OPTIONS=(--timestamp=none)
else
  SIGN_OPTIONS=(--timestamp --options runtime)
fi
# Sign nested code from the inside out; --deep is intentionally avoided.
SPARKLE_VERSION="$CONTENTS/Frameworks/Sparkle.framework/Versions/Current"
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$SPARKLE_VERSION/Autoupdate"
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$SPARKLE_VERSION/XPCServices/Installer.xpc"
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$SPARKLE_VERSION/Updater.app"
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$SPARKLE_VERSION/Sparkle"
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$CONTENTS/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP"
