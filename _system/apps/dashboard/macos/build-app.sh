#!/usr/bin/env bash
#
# Builds the universal macOS app bundle (`Systems42 Dashboard.app`) and DMG
# installer from the Go dashboard and native AppKit menu-bar shell (FR-055,
# DR-007, issue #80 Phases 6 and 7).
#
# Usage:
#   ./_system/apps/dashboard/macos/build-app.sh [--host-only] [--outdir DIR]
#
# Environment variables (optional, used in CI releases):
#   APPLE_SIGN_IDENTITY     Developer ID Application signing identity. When
#                           unset, the bundle is ad-hoc signed (`-`).
#   APPLE_NOTARY_KEY_PATH   Path to App Store Connect API .p8 key file.
#   APPLE_NOTARY_KEY_ID     App Store Connect API Key ID.
#   APPLE_NOTARY_ISSUER_ID  App Store Connect API Issuer ID.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$DASH_DIR/../../.." && pwd)"

HOST_ONLY=0
OUT_DIR="$ROOT_DIR/dist"

while [ $# -gt 0 ]; do
  case "$1" in
    --host-only) HOST_ONLY=1 ;;
    --outdir) shift; OUT_DIR="$1" ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "✗ build-app.sh must run on macOS." >&2
  exit 1
fi

for tool in go swiftc lipo iconutil sips codesign hdiutil; do
  command -v "$tool" >/dev/null 2>&1 || { echo "✗ Required macOS tool not found: $tool" >&2; exit 1; }
done

VERSION="$(tr -d '[:space:]' < "$DASH_DIR/VERSION")"
APP_NAME="Systems42 Dashboard"
APP_BUNDLE="$OUT_DIR/${APP_NAME}.app"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$OUT_DIR"

echo "→ Building ${APP_NAME} ${VERSION}..."

# 1. Build Go dashboard server binary (CGO_ENABLED=0)
GO_BIN="$WORK_DIR/systems42-dashboard"
if [ "$HOST_ONLY" = "1" ]; then
  ARCH_SUFFIX="$(uname -m)"
  (cd "$DASH_DIR" && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$GO_BIN" ./cmd/systems42-dashboard)
else
  ARCH_SUFFIX="universal"
  (cd "$DASH_DIR" && CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o "$WORK_DIR/go-arm64" ./cmd/systems42-dashboard)
  (cd "$DASH_DIR" && CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o "$WORK_DIR/go-amd64" ./cmd/systems42-dashboard)
  lipo -create -output "$GO_BIN" "$WORK_DIR/go-arm64" "$WORK_DIR/go-amd64"
fi

# 2. Compile native AppKit menu-bar launcher (Swift)
SWIFT_BIN="$WORK_DIR/Systems42Dashboard"
SWIFT_SRC="$SCRIPT_DIR/AppDelegate.swift"
if [ "$HOST_ONLY" = "1" ]; then
  swiftc -O -framework Cocoa "$SWIFT_SRC" -o "$SWIFT_BIN"
else
  swiftc -O -target arm64-apple-macos14.0 -framework Cocoa "$SWIFT_SRC" -o "$WORK_DIR/swift-arm64"
  swiftc -O -target x86_64-apple-macos14.0 -framework Cocoa "$SWIFT_SRC" -o "$WORK_DIR/swift-amd64"
  lipo -create -output "$SWIFT_BIN" "$WORK_DIR/swift-arm64" "$WORK_DIR/swift-amd64"
fi

# 3. Generate AppIcon.icns and monochrome menu-bar template icons
ICON_RENDERER="$WORK_DIR/render_icons.swift"
cat > "$ICON_RENDERER" <<'EOF'
import Cocoa

// Renders the Systems42 peaks mark (same geometry as brands/systems42/favicon.svg)
// directly with CoreGraphics so icon generation needs no third-party SVG renderer.
func renderIcon(size: Int, template: Bool, outPath: String) {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap alloc failed") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    if !template {
        // Rounded macOS icon plate
        let pad = s * 0.06
        let rect = CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)
        let bgPath = CGPath(roundedRect: rect, cornerWidth: s * 0.21, cornerHeight: s * 0.21, transform: nil)
        ctx.setFillColor(CGColor(red: 0.97, green: 0.965, blue: 0.945, alpha: 1.0))
        ctx.addPath(bgPath)
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.84, blue: 0.81, alpha: 1.0))
        ctx.setLineWidth(max(1.0, s * 0.012))
        ctx.addPath(bgPath)
        ctx.strokePath()
    }

    // Map 48x48 favicon grid into the icon bounds (flipped Y for CoreGraphics)
    let margin = template ? s * 0.06 : s * 0.18
    let drawSize = s - 2 * margin
    let scale = drawSize / 48.0
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: margin + x * scale, y: margin + (48.0 - y) * scale)
    }

    let green = template ? CGColor(gray: 0, alpha: 1) : CGColor(red: 0.122, green: 0.478, blue: 0.275, alpha: 1)
    let blue  = template ? CGColor(gray: 0, alpha: 1) : CGColor(red: 0.114, green: 0.373, blue: 0.690, alpha: 1)
    let red   = template ? CGColor(gray: 0, alpha: 1) : CGColor(red: 0.690, green: 0.227, blue: 0.227, alpha: 1)

    // Left peak (req42): (3,29) (12.5,6) (22,29)
    ctx.setFillColor(green)
    ctx.beginPath()
    ctx.move(to: pt(3, 29))
    ctx.addLine(to: pt(12.5, 6))
    ctx.addLine(to: pt(22, 29))
    ctx.closePath()
    ctx.fillPath()

    // Right peak (arc42): (26,29) (35.5,6) (45,29)
    ctx.setFillColor(blue)
    ctx.beginPath()
    ctx.move(to: pt(26, 29))
    ctx.addLine(to: pt(35.5, 6))
    ctx.addLine(to: pt(45, 29))
    ctx.closePath()
    ctx.fillPath()

    // Ground bar (Commons): x=3, y=33..45, rx=4
    let barRect = CGRect(
        x: margin + 3 * scale,
        y: margin + (48.0 - 45.0) * scale,
        width: 42 * scale,
        height: 12 * scale
    )
    let barPath = CGPath(roundedRect: barRect, cornerWidth: 4 * scale, cornerHeight: 4 * scale, transform: nil)
    ctx.setFillColor(red)
    ctx.addPath(barPath)
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed")
    }
    try! png.write(to: URL(fileURLWithPath: outPath))
}

let outDir = CommandLine.arguments[1]
renderIcon(size: 1024, template: false, outPath: outDir + "/icon_1024.png")
renderIcon(size: 18, template: true, outPath: outDir + "/MenuBarIcon.png")
renderIcon(size: 36, template: true, outPath: outDir + "/MenuBarIcon@2x.png")
EOF

swiftc -O -framework Cocoa "$ICON_RENDERER" -o "$WORK_DIR/render_icons"
"$WORK_DIR/render_icons" "$WORK_DIR"

ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"; do
  px="${spec%% *}"
  fname="${spec#* }"
  sips -z "$px" "$px" "$WORK_DIR/icon_1024.png" --out "$ICONSET/$fname" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK_DIR/AppIcon.icns"

# 4. Assemble .app bundle
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Helpers" "$APP_BUNDLE/Contents/Resources"
cp "$SWIFT_BIN" "$APP_BUNDLE/Contents/MacOS/Systems42Dashboard"
cp "$GO_BIN" "$APP_BUNDLE/Contents/Helpers/systems42-dashboard"
chmod 755 "$APP_BUNDLE/Contents/MacOS/Systems42Dashboard" "$APP_BUNDLE/Contents/Helpers/systems42-dashboard"
cp "$WORK_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$WORK_DIR/MenuBarIcon.png" "$APP_BUNDLE/Contents/Resources/MenuBarIcon.png"
cp "$WORK_DIR/MenuBarIcon@2x.png" "$APP_BUNDLE/Contents/Resources/MenuBarIcon@2x.png"
sed "s/__VERSION__/$VERSION/g" "$SCRIPT_DIR/Info.plist.tmpl" > "$APP_BUNDLE/Contents/Info.plist"

# 5. Sign app bundle (Developer ID when configured, else ad-hoc)
if [ -n "${APPLE_SIGN_IDENTITY:-}" ]; then
  echo "→ Signing with Developer ID: $APPLE_SIGN_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$APPLE_SIGN_IDENTITY" \
    "$APP_BUNDLE/Contents/Helpers/systems42-dashboard"
  codesign --force --options runtime --timestamp --sign "$APPLE_SIGN_IDENTITY" \
    "$APP_BUNDLE"
else
  echo "→ Ad-hoc signing (set APPLE_SIGN_IDENTITY for Developer ID signing)"
  codesign --force --sign - "$APP_BUNDLE/Contents/Helpers/systems42-dashboard"
  codesign --force --sign - "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

# 6. Create DMG installer with /Applications drag target
DMG_NAME="Systems42-Dashboard-${VERSION}-${ARCH_SUFFIX}.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"
DMG_STAGE="$WORK_DIR/dmg-stage"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null

if [ -n "${APPLE_SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$APPLE_SIGN_IDENTITY" "$DMG_PATH"
fi

# 7. Notarise and staple when App Store Connect credentials are provided
if [ -n "${APPLE_SIGN_IDENTITY:-}" ] && [ -n "${APPLE_NOTARY_KEY_PATH:-}" ] && [ -n "${APPLE_NOTARY_KEY_ID:-}" ] && [ -n "${APPLE_NOTARY_ISSUER_ID:-}" ]; then
  echo "→ Submitting DMG for Apple notarisation..."
  xcrun notarytool submit "$DMG_PATH" \
    --key "$APPLE_NOTARY_KEY_PATH" \
    --key-id "$APPLE_NOTARY_KEY_ID" \
    --issuer "$APPLE_NOTARY_ISSUER_ID" \
    --wait
  xcrun stapler staple "$DMG_PATH"
fi

(cd "$OUT_DIR" && shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256")

echo "✓ App bundle: $APP_BUNDLE"
echo "✓ DMG image:  $DMG_PATH"
echo "✓ Checksum:   $OUT_DIR/${DMG_NAME}.sha256"
