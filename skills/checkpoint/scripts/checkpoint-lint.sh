#!/usr/bin/env bash
# checkpoint-lint.sh — validate Footprint entries in a checkpoint file.
#
# Every line under a "- Footprint:" section must follow the structured
# notation: file:start-end::STATUS  where STATUS ∈ {WIP, DONE, REVIEW}.
# The keyword "none" (and blank lines) are always accepted.
#
# Usage: checkpoint-lint.sh <checkpoint.md>
# Exit:  0 = clean, 1 = violations (messages on stderr)
# Env:   none
#
# Part of checkpoint-hardening (Discussion #75 / plan 0001-checkpoint-hardening).
set -u

file="${1:-}"

if [ -z "$file" ]; then
  printf 'usage: checkpoint-lint.sh <checkpoint.md>\n' >&2
  exit 1
fi

if [ ! -f "$file" ]; then
  printf 'checkpoint-lint.sh: file not found: %s\n' "$file" >&2
  exit 1
fi

# Pattern: optional leading spaces, a list dash, whitespace, then
# file_path:digits-digits::WIP|DONE|REVIEW  (file path may contain / . _ -)
VALID_RE='^[[:space:]]*-[[:space:]]+[^[:space:]][^:]*:[0-9][0-9]*-[0-9][0-9]*::(WIP|DONE|REVIEW)[[:space:]]*$'

errors=0
in_footprint=0

while IFS= read -r line; do
  # Detect start of Footprint section (the field declaration line itself)
  case "$line" in
    "- Footprint:"*)
      in_footprint=1
      continue
      ;;
    # Any other top-level "- Key:" line ends the Footprint section
    "- "*":"*)
      in_footprint=0
      continue
      ;;
  esac

  # Only inspect lines inside the Footprint section
  [ "$in_footprint" -eq 0 ] && continue

  # Strip leading/trailing whitespace for the value check
  trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  # Blank lines and "none" are always valid
  [ -z "$trimmed" ] && continue
  [ "$trimmed" = "none" ] && continue

  # Must be a list item starting with "- "
  case "$trimmed" in
    "- "*)
      entry="${trimmed#- }"
      ;;
    *)
      # Non-list content inside a Footprint block is a violation
      printf 'LINT: unexpected content in Footprint block (want "- file:start-end::STATUS"): %s\n' \
        "$trimmed" >&2
      errors=$((errors + 1))
      continue
      ;;
  esac

  # Validate the entry against the structured notation
  if ! printf '%s' "$line" | grep -Eq "$VALID_RE"; then
    printf 'LINT: bad Footprint entry (want file:start-end::STATUS, got): %s\n' \
      "$entry" >&2
    errors=$((errors + 1))
  fi
done < "$file"

exit "$errors"
