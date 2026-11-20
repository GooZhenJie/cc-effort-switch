#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
app="$("$root/scripts/build-app.sh" | tail -1)"
target="/Applications/CcEffortSwitch.app"

osascript -e 'tell application id "io.github.goozhenjie.cc-effort-switch" to quit' 2>/dev/null || true
if [[ -d "$target" ]]; then
  mv "$target" "$HOME/.Trash/CcEffortSwitch $(date +%Y-%m-%d\ %H.%M.%S).app"
fi
cp -R "$app" "$target"
open "$target"
