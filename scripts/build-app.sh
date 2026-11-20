#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
identity="${CC_EFFORT_SWITCH_SIGN_IDENTITY:-}"
if [[ -z "$identity" && -f "$root/Signing.local" ]]; then
  identity="$(sed -n 's/^CC_EFFORT_SWITCH_SIGN_IDENTITY=//p' "$root/Signing.local")"
fi
identity="${identity:--}"

swift build --package-path "$root" -c release --arch arm64
products="$(swift build --package-path "$root" -c release --arch arm64 --show-bin-path)"

app="$root/build/CcEffortSwitch.app"
if [[ -e "$app" ]]; then
  mv "$app" "$(mktemp -d)/"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
xcrun actool "$root/Resources/AppIcon.icon" --compile "$app/Contents/Resources" \
  --app-icon AppIcon --platform macosx --minimum-deployment-target 15.0 \
  --output-partial-info-plist "$(mktemp -d)/partial.plist" >/dev/null
cp "$products/CcEffortSwitch" "$app/Contents/MacOS/CcEffortSwitch"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
ditto "$products/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"

sign() {
  codesign --force --timestamp=none --sign "$identity" "$@"
}
sparkle="$app/Contents/Frameworks/Sparkle.framework"
sign "$sparkle/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
sign "$sparkle/Versions/B/Autoupdate"
sign "$sparkle/Versions/B/Updater.app"
sign "$sparkle"
sign "$app"
codesign --verify --deep --strict "$app"
echo "$app"
