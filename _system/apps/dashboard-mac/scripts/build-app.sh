#!/usr/bin/env bash
# Builds a release binary and wraps it in build/Systems42 Dashboard Native.app.
# The app is signed ad hoc, not notarized.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$here/../dashboard/VERSION")"
name="Systems42 Dashboard Native"
app="$here/build/$name.app"

# S42_UNIVERSAL=1 builds for Apple Silicon and Intel in one binary.
flags=(-c release)
if [[ "${S42_UNIVERSAL:-}" == "1" ]]; then flags+=(--arch arm64 --arch x86_64); fi

swift build --package-path "$here" "${flags[@]}"
bindir="$(swift build --package-path "$here" "${flags[@]}" --show-bin-path)"
bin="$bindir/Systems42Dashboard"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Systems42Dashboard"
# The diagram page and its libraries. Only Contents/Resources may hold them: a file at the root of
# the .app breaks the signature. DiagramAssets looks there first.
cp -R "$bindir/Systems42Dashboard_Systems42UI.bundle" "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>org.systems42.dashboard.native</string>
  <key>CFBundleExecutable</key><string>Systems42Dashboard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Links of the form systems42://<wiki>/<page id>. They only select a page, see DeepLink.swift. -->
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>org.systems42.dashboard.native.link</string>
    <key>CFBundleURLSchemes</key><array><string>systems42</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Folder</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
  </dict></array>
</dict>
</plist>
PLIST
# An ad-hoc signature seals the bundle, so an Apple Silicon Mac starts it.
codesign --force --deep --sign - "$app"
echo "Built $app"
