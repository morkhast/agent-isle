#!/usr/bin/env bash
# Local patch workflow: move our commits onto the newest release tag, rebuild, reinstall.
# Run after the app announces "Update available". Stops on rebase conflicts.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

git fetch -q --tags origin
BASE="$(git describe --tags --abbrev=0 HEAD)"
LATEST="$(git tag --sort=-v:refname | grep -E '^v[0-9]' | head -1)"
echo "Built on: $BASE  Latest release: $LATEST"

if [ "$BASE" != "$LATEST" ]; then
  git rebase --onto "$LATEST" "$BASE"
fi

bash Scripts/bundle.sh

osascript -e 'quit app id "com.devlab.agentisle.dev"' || true
while pgrep -x AgentIsle >/dev/null; do sleep 0.5; done
/usr/bin/trash "/Applications/Agent Isle.app" 2>/dev/null || true
ditto "build/Agent Isle.app" "/Applications/Agent Isle.app"
open "/Applications/Agent Isle.app"
echo "Installed: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/Agent Isle.app/Contents/Info.plist')"
