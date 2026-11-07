#!/usr/bin/env bash
# checkpoint-guard.sh — idempotency guard for the checkpoint skill.
#
# Prevents token-draining checkpoint recursion by suppressing a checkpoint
# write when no tracked file has changed since the last committed checkpoint.
#
# Usage: checkpoint-guard.sh
# Exit:  0 = proceed (write the checkpoint), 1 = suppress (nothing changed)
# Env:   HARNESS_ROOT (default: four levels above this skill's script directory)
#        HARNESS_CHECKPOINT_DIR (default: $HARNESS_ROOT/.harness-mini/trace/checkpoints)
#
# Decision rules:
#   • No previous checkpoint → always proceed (first checkpoint is always valid).
#   • git not available, or not inside a git repo → always proceed (safe default).
#   • Any working-tree or staged changes → proceed.
#   • No changes at all → suppress with a stderr message.
#
# Part of checkpoint-hardening (Discussion #75 / plan 0001-checkpoint-hardening).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$HERE/../../../.." && pwd)}"
CP_DIR="${HARNESS_CHECKPOINT_DIR:-$HARNESS_ROOT/.harness-mini/trace/checkpoints}"

# No previous checkpoint → always proceed
if ! ls "$CP_DIR"/*.md >/dev/null 2>&1; then
  exit 0
fi

# Not a git repo or git not available → always proceed (safe default)
if ! git -C "$HARNESS_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Count changed and staged files
changed="$(git -C "$HARNESS_ROOT" diff --name-only 2>/dev/null | wc -l | tr -d ' \t')"
staged="$(git -C "$HARNESS_ROOT" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' \t')"

if [ "$changed" -eq 0 ] && [ "$staged" -eq 0 ]; then
  printf 'harness-mini: checkpoint suppress — no tracked file changes since last checkpoint; skipping.\n' >&2
  exit 1
fi

exit 0
