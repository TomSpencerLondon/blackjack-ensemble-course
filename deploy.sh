#!/usr/bin/env bash
# Publish the course to Cloudflare Pages.
# Stages only the web assets (no internal notes) into dist/, then deploys.
#
# Usage: ./deploy.sh
# Requires: wrangler authenticated (npx wrangler login).
set -euo pipefail
cd "$(dirname "$0")"

PROJECT="blackjack-ensemble-course"
DIST="dist"

rm -rf "$DIST"
mkdir -p "$DIST"
cp index.html "$DIST/"
cp -R lessons reference assets "$DIST/"

echo "Deploying $(find "$DIST" -type f | wc -l | tr -d ' ') files to $PROJECT ..."
npx --yes wrangler pages deploy "$DIST" \
  --project-name "$PROJECT" \
  --branch main \
  --commit-dirty=true

echo "Done → https://$PROJECT.pages.dev"
