#!/usr/bin/env bash
# checkpoint-snapshot.sh — snapshot the exact source lines named in a
# structured Footprint entry, writing the result to .trace/runtime/.
#
# Usage: checkpoint-snapshot.sh "file/path:start-end::STATUS"
# Output: path to the written snapshot file (stdout)
# Exit:   0 = success, 1 = error (message on stderr)
# Env:    HARNESS_TRACE_DIR (default .trace/runtime)
#
# The snapshot path is deterministic: same entry → same path, so callers
# can compare or cache without extra bookkeeping.
#
# Boundary defense: out-of-bounds line ranges are rejected before the
# filesystem is touched, returning a structured error the agent can act on.
#
# Part of checkpoint-hardening (Discussion #75 / plan 0001-checkpoint-hardening).
set -u

entry="${1:-}"

if [ -z "$entry" ]; then
  printf 'usage: checkpoint-snapshot.sh "file:start-end::STATUS"\n' >&2
  exit 1
fi

# Parse: everything before the last :: is "file:range"; after is STATUS
# Strip the ::STATUS suffix first
file_and_range="${entry%::*}"

# file is everything before the last colon (supports paths with slashes)
range="${file_and_range##*:}"
src="${file_and_range%:*}"

start="${range%-*}"
end="${range#*-}"

# Validate that we got numeric start/end
case "$start$end" in
  *[!0-9]*)
    printf 'checkpoint-snapshot.sh: cannot parse range from entry: %s\n' "$entry" >&2
    exit 1
    ;;
esac

if [ ! -f "$src" ]; then
  printf 'checkpoint-snapshot.sh: file not found: %s\n' "$src" >&2
  exit 1
fi

max_line="$(wc -l < "$src" | tr -d ' \t')"

# Boundary defense — reject before hitting the filesystem
if [ "$start" -lt 1 ] || [ "$end" -gt "$max_line" ] || [ "$start" -gt "$end" ]; then
  printf 'checkpoint-snapshot.sh: out of bounds — requested %s-%s but file has %s lines: %s\n' \
    "$start" "$end" "$max_line" "$src" >&2
  exit 1
fi

# Deterministic output path: hash of the entry string (no external tools needed)
# Use cksum (POSIX) to get a stable numeric hash
hash="$(printf '%s' "$entry" | cksum | awk '{print $1}')"
dir="${HARNESS_TRACE_DIR:-.trace/runtime}"
out="$dir/snap-${hash}.txt"

mkdir -p "$dir"
sed -n "${start},${end}p" "$src" > "$out"

printf '%s\n' "$out"
