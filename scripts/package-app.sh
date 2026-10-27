#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

identity="$root/Sources/ShotNTranslateCore/AppReleaseIdentity.swift"
metadata="$(python3 - "$identity" <<'PY'
import re
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text()

def grab(name: str) -> str:
    match = re.search(rf'public static let {name} = "([^"]+)"', text)
    if not match:
        raise SystemExit(f"Could not read {name}")
    return match.group(1)

def grab_int(name: str) -> str:
    match = re.search(rf"public static let {name} = (\d+)", text)
    if not match:
        raise SystemExit(f"Could not read {name}")
    return match.group(1)

print(grab("applicationName"))
print(grab("bundleIdentifier"))
print(grab("marketingVersion"))
print(grab_int("buildNumber"))
PY
)"
app_name="$(printf '%s\n' "$metadata" | sed -n '1p')"
bundle_id="$(printf '%s\n' "$metadata" | sed -n '2p')"
version="$(printf '%s\n' "$metadata" | sed -n '3p')"
build="$(printf '%s\n' "$metadata" | sed -n '4p')"

swift build -c release --product ShotNTranslate
bin_dir="$(swift build -c release --product ShotNTranslate --show-bin-path)"
app="$root/dist/$app_name.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/ShotNTranslate" "$app/Contents/MacOS/ShotNTranslate"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>tr</string>
  <key>CFBundleDisplayName</key>
  <string>$app_name</string>
  <key>CFBundleExecutable</key>
  <string>ShotNTranslate</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleName</key>
  <string>$app_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$build</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Seçilen ekran bölgesindeki yazıyı okuyup çevirmek için ekran görüntüsü alınır.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

# A stable local certificate keeps Screen Recording permission across rebuilds.
bash "$root/scripts/sign-app.sh" "$app" "$bundle_id"

echo "$app"
