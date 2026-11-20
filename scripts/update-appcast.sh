#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
appcast="$root/appcast.xml"
prefix=""
notes=""
while (( $# > 0 )); do
  case "$1" in
    --download-url-prefix) prefix="$2"; shift 2 ;;
    --appcast) appcast="$2"; shift 2 ;;
    *) notes="$1"; shift ;;
  esac
done
if [[ -z "$notes" || ! -f "$notes" ]]; then
  echo "Usage: scripts/update-appcast.sh <release-notes.md> [--download-url-prefix <url>] [--appcast <path>]" >&2
  exit 1
fi

app="$root/build/CcEffortSwitch.app"
tools="$root/.build/artifacts/sparkle/Sparkle/bin"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
zip="$root/build/release/CcEffortSwitch-$version.zip"
if [[ ! -f "$zip" ]]; then
  echo "$zip is missing. Run scripts/build-release.sh first." >&2
  exit 1
fi
prefix="${prefix:-https://github.com/GooZhenJie/cc-effort-switch/releases/download/v$version/}"

staging="$(mktemp -d)"
cp "$zip" "$staging/"
cp "$notes" "$staging/CcEffortSwitch-$version.md"
if [[ -f "$appcast" ]]; then
  cp "$appcast" "$staging/appcast.xml"
fi

"$tools/generate_appcast" "$staging" \
  --account cc-effort-switch \
  -o "$staging/appcast.xml" \
  --download-url-prefix "$prefix" \
  --embed-release-notes \
  --link "https://github.com/GooZhenJie/cc-effort-switch/releases" \
  --maximum-versions 0 \
  --maximum-deltas 0
cp "$staging/appcast.xml" "$appcast"
echo "Added CcEffortSwitch $version to $appcast, downloading from $prefix"
