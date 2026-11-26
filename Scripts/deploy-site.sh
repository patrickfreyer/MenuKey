#!/bin/zsh
# Publishes the website (docs/index.html + its images) to Cloudflare Workers (static assets, see wrangler.jsonc).
# Only the files the page uses are uploaded, never the rest of docs/.
#   ./Scripts/deploy-site.sh                       -> https://jumpkey.white-forest-01f3.workers.dev
#   SITE_URL=https://jumpkey.app ./Scripts/deploy-site.sh   (sets canonical/og URLs)
set -euo pipefail
cd "$(dirname "$0")/.."

export CLOUDFLARE_ACCOUNT_ID=116092b8ab67eb99b520552e6655f045   # personal account, never Telarron
SITE_URL="${SITE_URL:-https://jumpkey.white-forest-01f3.workers.dev}"
OUT=site-dist

rm -rf "$OUT"
mkdir -p "$OUT"
cp docs/icon-256.png docs/screenshot-dark.png "$OUT/"
sed "s#https://patrickfreyer.github.io/JumpKey#${SITE_URL}#g" docs/index.html > "$OUT/index.html"
cat > "$OUT/_headers" <<'EOF'
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()
EOF

npx --yes wrangler deploy
echo "Live at $SITE_URL"
