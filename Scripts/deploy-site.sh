#!/bin/zsh
# Builds the website (Scripts/build-site.py: home page + guides) and publishes it to
# Cloudflare Workers static assets (see wrangler.jsonc). Only site-dist/ is uploaded.
#   ./Scripts/deploy-site.sh                       -> https://jumpkey.patrickfreyer.com
#   SITE_URL=https://other.example ./Scripts/deploy-site.sh   (sets canonical/og URLs)
set -euo pipefail
cd "$(dirname "$0")/.."

export CLOUDFLARE_ACCOUNT_ID=116092b8ab67eb99b520552e6655f045   # personal account, never Telarron
SITE_URL="${SITE_URL:-https://jumpkey.patrickfreyer.com}"
python3 Scripts/build-site.py "$SITE_URL"

npx --yes wrangler deploy
echo "Live at $SITE_URL"
