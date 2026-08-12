#!/usr/bin/env sh
# Cloud Agent install — idempotent dependency refresh after checkout.
#
# harness-mini itself is a zero-dependency POSIX-shell + Markdown harness, so it
# has nothing to build or install. The only dependency work is for the sibling
# website repo (Next.js), and only when it is checked out alongside this repo.
#
# The Cloud Agent runs `install` from the workspace root (not the repo root), so
# resolve paths from this script's own location rather than the caller's cwd.
set -eu

echo "harness-mini: zero-dependency shell harness — no build/install step needed."

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
WEBSITE_SITE="$REPO_ROOT/../harness-mini-website/site"

if [ -d "$WEBSITE_SITE" ]; then
  echo "harness-mini-website detected → installing site dependencies (npm ci)"
  cd "$WEBSITE_SITE"
  npm ci --no-fund --no-audit
else
  echo "harness-mini-website not checked out → skipping site install."
fi
