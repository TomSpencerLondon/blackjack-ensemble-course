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

# Regenerate the learning-record pages from their markdown sources.
node build-learning-records.mjs

rm -rf "$DIST"
mkdir -p "$DIST/learning-records"
cp index.html "$DIST/"
cp -R lessons reference assets "$DIST/"
# Publish only the rendered learning records (HTML), not the raw .md notes.
cp learning-records/*.html "$DIST/learning-records/"

echo "Deploying $(find "$DIST" -type f | wc -l | tr -d ' ') files to $PROJECT ..."
npx --yes wrangler pages deploy "$DIST" \
  --project-name "$PROJECT" \
  --branch main \
  --commit-dirty=true

echo "Done → https://$PROJECT.pages.dev"
