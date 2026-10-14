#!/usr/bin/env bash
# Builds ElementXResources.bundle (asset catalog, localisations, sounds) for hosts that link ElementX as a SwiftPM
# library: the xtool standalone build (StandaloneApp) and apps embedding Element X. Copy the bundle into the root of
# the .app; `Bundle.elementXResources` finds it there. The Xcode project compiles these resources itself.
#
# Usage: build-resources-bundle.sh <output-dir>   (ACTOOL: actool or the Linux reimplementation, default `actool`)
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$1/ElementXResources.bundle"
rm -rf "$out"
mkdir -p "$out"
"${ACTOOL:-actool}" "$root/ElementX/Resources/Assets.xcassets" --compile "$out" --platform iphoneos \
    --minimum-deployment-target 18.5 --output-partial-info-plist "$out/.partial.plist" > /dev/null
rm -f "$out/.partial.plist"
cp -R "$root"/ElementX/Resources/Localizations/*.lproj "$out/"
cp "$root"/ElementX/Resources/Sounds/* "$out/"
cat > "$out/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>io.element.elementx.resources</string>
	<key>CFBundleName</key><string>ElementXResources</string>
	<key>CFBundlePackageType</key><string>BNDL</string>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
</dict>
</plist>
PLIST
