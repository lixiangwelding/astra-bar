#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Packaging requires macOS.' >&2; exit 1; }
version="${VERSION:-0.1.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
if [[ "${ARCH:-universal}" == native ]]; then
  swift build -c release
  bin="$(swift build -c release --show-bin-path)"
  architecture="$(uname -m)"
else
  # Build each architecture with SwiftPM's native backend; multi-arch SwiftPM
  # otherwise invokes xcbuild, which is absent from Command Line Tools.
  for arch in arm64 x86_64; do
    swift build -c release --triple "${arch}-apple-macosx13.0" --scratch-path ".build/universal-${arch}"
  done
  arm_bin="$(swift build -c release --triple arm64-apple-macosx13.0 --scratch-path .build/universal-arm64 --show-bin-path)"
  intel_bin="$(swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path .build/universal-x86_64 --show-bin-path)"
  mkdir -p .build/universal-bin
  bin="$(pwd)/.build/universal-bin"
  for product in AstraBar astra-usage; do
    lipo -create "$arm_bin/$product" "$intel_bin/$product" -output "$bin/$product"
    lipo "$bin/$product" -verify_arch arm64 x86_64
  done
  architecture=universal
fi
app="dist/AstraBar.app"
mkdir -p dist
if [[ -e "$app" ]]; then mv "$app" "dist/AstraBar.previous.$(date +%s).app"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/AstraBar" "$app/Contents/MacOS/AstraBar"
cp "$bin/astra-usage" dist/astra-usage
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>AstraBar</string>
<key>CFBundleDisplayName</key><string>AstraBar</string>
<key>CFBundleIdentifier</key><string>io.github.lixiangwelding.astrabar</string>
<key>CFBundleExecutable</key><string>AstraBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"
archive="AstraBar-${version}-macOS-${architecture}.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
printf '\nPackaged %s\nAd-hoc signed; NOT Developer ID signed or notarized.\n' "dist/$archive"
