#!/usr/bin/env bash
#
# Builds the universal macOS app bundle (`Systems42 Dashboard.app`) and branded
# DMG installer from the Go dashboard and native AppKit menu-bar shell (FR-055,
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
MOUNT_DIR=""
cleanup() {
  if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

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

# 3. Generate AppIcon.icns, menu-bar template icons, and branded DMG background
ICON_RENDERER="$WORK_DIR/render_icons.swift"
cat > "$ICON_RENDERER" <<'EOF'
import Cocoa

// Draws the Systems42 peaks mark (same geometry as brands/systems42/favicon.svg)
// inside `rect` in a non-flipped CoreGraphics context.
func drawPeaksMark(in ctx: CGContext, rect: CGRect, monochrome: Bool) {
    let scale = min(rect.width, rect.height) / 48.0
    let ox = rect.minX + (rect.width - 48.0 * scale) / 2.0
    let oy = rect.minY + (rect.height - 48.0 * scale) / 2.0
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: ox + x * scale, y: oy + (48.0 - y) * scale)
    }

    let green = monochrome ? CGColor(gray: 0, alpha: 1) : CGColor(red: 0.122, green: 0.478, blue: 0.275, alpha: 1)
    let blue  = monochrome ? CGColor(gray: 0, alpha: 1) : CGColor(red: 0.114, green: 0.373, blue: 0.690, alpha: 1)
    let red   = monochrome ? CGColor(gray: 0, alpha: 1) : CGColor(red: 0.690, green: 0.227, blue: 0.227, alpha: 1)

    // Left peak (req42)
    ctx.setFillColor(green)
    ctx.beginPath()
    ctx.move(to: pt(3, 29))
    ctx.addLine(to: pt(12.5, 6))
    ctx.addLine(to: pt(22, 29))
    ctx.closePath()
    ctx.fillPath()

    // Right peak (arc42)
    ctx.setFillColor(blue)
    ctx.beginPath()
    ctx.move(to: pt(26, 29))
    ctx.addLine(to: pt(35.5, 6))
    ctx.addLine(to: pt(45, 29))
    ctx.closePath()
    ctx.fillPath()

    // Ground bar (Commons)
    let barRect = CGRect(
        x: ox + 3 * scale,
        y: oy + (48.0 - 45.0) * scale,
        width: 42 * scale,
        height: 12 * scale
    )
    let barPath = CGPath(roundedRect: barRect, cornerWidth: 4 * scale, cornerHeight: 4 * scale, transform: nil)
    ctx.setFillColor(red)
    ctx.addPath(barPath)
    ctx.fillPath()
}

func makeBitmap(width: Int, height: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap alloc failed") }
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed")
    }
    try! png.write(to: URL(fileURLWithPath: path))
}

func renderIcon(size: Int, template: Bool, outPath: String) {
    let s = CGFloat(size)
    let rep = makeBitmap(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    if !template {
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

    let margin = template ? s * 0.06 : s * 0.18
    drawPeaksMark(in: ctx, rect: CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin), monochrome: template)
    NSGraphicsContext.restoreGraphicsState()
    writePNG(rep, to: outPath)
}

// Renders a 660x400 (72 DPI logical points, crisp 2x pixels) branded DMG canvas
// with Systems42 logo header and drag-to-Applications arrow between (185, 225) and (475, 225).
func renderDMGBackground(version: String, outPath: String) {
    let w: CGFloat = 660
    let h: CGFloat = 400
    let rep = makeBitmap(width: Int(w), height: Int(h))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Warm paper background matching Systems42 palette
    ctx.setFillColor(CGColor(red: 0.969, green: 0.965, blue: 0.945, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    // Subtle top accent bar (three Systems42 colours)
    ctx.setFillColor(CGColor(red: 0.122, green: 0.478, blue: 0.275, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: h - 5, width: w / 3.0, height: 5))
    ctx.setFillColor(CGColor(red: 0.114, green: 0.373, blue: 0.690, alpha: 1.0))
    ctx.fill(CGRect(x: w / 3.0, y: h - 5, width: w / 3.0, height: 5))
    ctx.setFillColor(CGColor(red: 0.690, green: 0.227, blue: 0.227, alpha: 1.0))
    ctx.fill(CGRect(x: 2.0 * w / 3.0, y: h - 5, width: w / 3.0 + 1, height: 5))

    // Header: Systems42 peaks mark + title + version
    drawPeaksMark(in: ctx, rect: CGRect(x: 158, y: h - 86, width: 44, height: 44), monochrome: false)

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0),
    ]
    NSAttributedString(string: "Systems42 Dashboard", attributes: titleAttrs)
        .draw(at: NSPoint(x: 214, y: h - 66))

    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(calibratedRed: 0.42, green: 0.43, blue: 0.45, alpha: 1.0),
    ]
    NSAttributedString(string: "Release \(version)  ·  Read-only desktop app for Systems42 wikis", attributes: subAttrs)
        .draw(at: NSPoint(x: 215, y: h - 84))

    // Hairline divider under header
    ctx.setStrokeColor(CGColor(red: 0.86, green: 0.85, blue: 0.82, alpha: 1.0))
    ctx.setLineWidth(1.0)
    ctx.move(to: CGPoint(x: 40, y: h - 104))
    ctx.addLine(to: CGPoint(x: w - 40, y: h - 104))
    ctx.strokePath()

    // Subtle rounded card wells behind the two Finder icons (icon center Y in Finder is 225 -> CG Y = 400 - 225 = 175)
    let cardColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.65)
    let cardBorder = CGColor(red: 0.85, green: 0.84, blue: 0.80, alpha: 1.0)
    for cx in [185.0, 475.0] as [CGFloat] {
        let box = CGRect(x: cx - 78, y: 92, width: 156, height: 162)
        let path = CGPath(roundedRect: box, cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.setFillColor(cardColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(cardBorder)
        ctx.setLineWidth(1.0)
        ctx.addPath(path)
        ctx.strokePath()
    }

    // Center drag arrow (between x=282 and x=378 at CG y=175)
    ctx.setStrokeColor(CGColor(red: 0.36, green: 0.39, blue: 0.43, alpha: 0.75))
    ctx.setLineWidth(3.0)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 294, y: 175))
    ctx.addLine(to: CGPoint(x: 364, y: 175))
    ctx.move(to: CGPoint(x: 350, y: 187))
    ctx.addLine(to: CGPoint(x: 365, y: 175))
    ctx.addLine(to: CGPoint(x: 350, y: 163))
    ctx.strokePath()

    // Footer instruction
    let hintText = NSAttributedString(
        string: "Drag Systems42 Dashboard into Applications to install",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 0.34, green: 0.36, blue: 0.39, alpha: 1.0),
        ]
    )
    let hintSize = hintText.size()
    hintText.draw(at: NSPoint(x: (w - hintSize.width) / 2.0, y: 36))

    NSGraphicsContext.restoreGraphicsState()
    writePNG(rep, to: outPath)
}

let outDir = CommandLine.arguments[1]
let version = CommandLine.arguments[2]
renderIcon(size: 1024, template: false, outPath: outDir + "/icon_1024.png")
renderIcon(size: 18, template: true, outPath: outDir + "/MenuBarIcon.png")
renderIcon(size: 36, template: true, outPath: outDir + "/MenuBarIcon@2x.png")
renderDMGBackground(version: version, outPath: outDir + "/dmg-bg.png")
EOF

swiftc -O -framework Cocoa "$ICON_RENDERER" -o "$WORK_DIR/render_icons"
"$WORK_DIR/render_icons" "$WORK_DIR" "$VERSION"

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

# 6. Create branded DMG installer (custom volume icon + Finder canvas + /Applications target)
VOL_NAME="${APP_NAME} ${VERSION}"
DMG_NAME="Systems42-Dashboard-${VERSION}-${ARCH_SUFFIX}.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"
DMG_RW="$WORK_DIR/rw.dmg"

APP_SIZE_MB="$(du -sm "$APP_BUNDLE" | awk '{print $1}')"
DMG_SIZE_MB=$(( APP_SIZE_MB + 25 ))

rm -f "$DMG_RW" "$DMG_PATH"
hdiutil create -volname "$VOL_NAME" -size "${DMG_SIZE_MB}m" -fs HFS+ -ov "$DMG_RW" >/dev/null

MOUNT_DIR=""
ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW")"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUT" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
  echo "✗ Failed to attach temporary DMG." >&2
  exit 1
fi
MOUNT_VOL_NAME="$(basename "$MOUNT_DIR")"

mkdir -p "$MOUNT_DIR/.background"
cp -R "$APP_BUNDLE" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"
cp "$WORK_DIR/dmg-bg.png" "$MOUNT_DIR/.background/background.png"
cp "$WORK_DIR/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"

if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MOUNT_DIR" || true
  SetFile -a V "$MOUNT_DIR/.VolumeIcon.icns" || true
  SetFile -a V "$MOUNT_DIR/.background" || true
fi

# Style the Finder window (non-fatal if running without an interactive Finder GUI)
if command -v osascript >/dev/null 2>&1; then
  if ! osascript <<OSA >/dev/null
tell application "Finder"
  tell disk "$MOUNT_VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {160, 140, 820, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 104
    set background picture of opts to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {185, 225}
    set position of item "Applications" of container window to {475, 225}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
  then
    echo "→ Note: skipped Finder window layout (no GUI Finder session)"
  fi
fi

sync
hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNT_DIR=""

hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

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
