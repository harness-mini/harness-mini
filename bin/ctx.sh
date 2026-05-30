#!/usr/bin/env bash
# ctx.sh — context occupancy estimate against the smart/dumb threshold.
#
# The harness rule (see docs/smart-dumb.md): context below the threshold is the
# "smart" zone where the model reasons sharply; at/above it the model degrades
# ("dumb" zone) and must checkpoint + reset.
#
# Usage:   ctx.sh <used_tokens> [window_tokens]
# Prints:  "<N>%"  (integer percent of window used)
# Exit:    0 if under threshold (smart), 2 if at/over threshold (checkpoint now)
# Env:     HARNESS_CTX_THRESHOLD  (default 40)  — the smart/dumb line in percent
#          HARNESS_CTX_WINDOW     (default 200000) — fallback window if arg omitted
set -u

usage() {
  cat <<'EOF'
ctx.sh — context occupancy vs the smart/dumb threshold (default 40%).

usage: ctx.sh <used_tokens> [window_tokens]
prints: "<N>%"   exit: 0 if under threshold (smart), 2 if at/over (checkpoint now)

env:
  HARNESS_CTX_THRESHOLD   smart/dumb line in percent (default 40)
  HARNESS_CTX_WINDOW      window if 2nd arg omitted (default 200000)

examples:
  ctx.sh 50000 200000                      # 25%  -> exit 0 (smart)
  ctx.sh 80000 200000                      # 40%  -> exit 2 (checkpoint)
  HARNESS_CTX_THRESHOLD=30 ctx.sh 60000    # 30%  -> exit 2 (stricter line)
  HARNESS_CTX_THRESHOLD=60 ctx.sh 120000   # 60%  -> exit 0 (looser line)

See docs/smart-dumb.md for when to move the line.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

used="${1:-}"
window="${2:-${HARNESS_CTX_WINDOW:-200000}}"
threshold="${HARNESS_CTX_THRESHOLD:-40}"

if [ -z "$used" ]; then
  usage >&2
  exit 64
fi
if ! [ "$used" -ge 0 ] 2>/dev/null || ! [ "$window" -gt 0 ] 2>/dev/null; then
  echo "ctx.sh: used and window must be positive integers" >&2
  exit 64
fi

pct=$(( used * 100 / window ))
echo "${pct}%"

if [ "$pct" -ge "$threshold" ]; then
  exit 2
fi
exit 0
