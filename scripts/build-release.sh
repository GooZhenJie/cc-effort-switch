#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
app="$("$root/scripts/build-app.sh" | tail -1)"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist")
output="$root/build/release"
mkdir -p "$output"
zip="$output/CcEffortSwitch-$version.zip"
if [[ -e "$zip" ]]; then
  mv "$zip" "$(mktemp -d)/"
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

echo "CcEffortSwitch $version ($build), signed as: $(codesign -d -r- "$app" 2>&1 | sed -nE 's/^(# )?designated => //p')"
echo "Zip: $zip"
shasum -a 256 "$zip"
