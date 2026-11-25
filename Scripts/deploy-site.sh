#!/bin/zsh
# Publishes the website (docs/index.html + its images) to Cloudflare Pages.
# Only the files the page uses are uploaded, never the rest of docs/.
# --force keeps classic Pages (wrangler 4.168+ otherwise delegates to Workers and fails).
#   ./Scripts/deploy-site.sh                       -> https://menukey.pages.dev
#   SITE_URL=https://menukey.app ./Scripts/deploy-site.sh   (sets canonical/og URLs)
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=menukey
export CLOUDFLARE_ACCOUNT_ID=116092b8ab67eb99b520552e6655f045   # personal account, never Telarron
SITE_URL="${SITE_URL:-https://menukey.pages.dev}"
OUT=site-dist

rm -rf "$OUT"
mkdir -p "$OUT"
cp docs/icon-256.png docs/screenshot-dark.png "$OUT/"
sed "s#https://patrickfreyer.github.io/MenuKey#${SITE_URL}#g" docs/index.html > "$OUT/index.html"
cat > "$OUT/_headers" <<'EOF'
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()
EOF

npx --yes wrangler pages project list 2>/dev/null | grep -q " $PROJECT " ||
  npx --yes wrangler pages project create "$PROJECT" --production-branch main --force
npx --yes wrangler pages deploy "$OUT" --project-name "$PROJECT" --branch main --commit-dirty=true
echo "Live at $SITE_URL"
