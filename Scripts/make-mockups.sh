#!/bin/zsh
# Renders docs/screenshot-dark.png and docs/screenshot-light.png from docs/mockup.html.
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE=$(mktemp -d)
for scene in dark light; do
  "$CHROME" --headless=new --hide-scrollbars --user-data-dir="$PROFILE" \
    --window-size=1600,1000 --force-device-scale-factor=2 \
    --screenshot="$PWD/docs/screenshot-$scene.png" "file://$PWD/docs/mockup.html#$scene" 2>/dev/null
done
rm -rf "$PROFILE"
echo "Wrote docs/screenshot-dark.png and docs/screenshot-light.png"
