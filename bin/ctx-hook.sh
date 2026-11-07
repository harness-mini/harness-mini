#!/usr/bin/env bash
# ctx-hook.sh — optional PostToolUse adapter that gives the 40% rule teeth.
# It estimates context occupancy after each tool call and (a) records a
# ctx_pct trace event so `harness.sh report` can chart the trend, and (b) nudges
# the agent to checkpoint when it crosses the smart/dumb line.
#
# Additionally, when HARNESS_TEST_SCRIPT is set and the script passes, this hook
# stamps .harness-mini/trace/runtime/last-green.txt with a trusted timestamp and git revision.
# The checkpoint skill reads that file for the "Last green:" field, eliminating
# LLM hallucination of test status. (Discussion #75 / plan 0001-checkpoint-hardening)
#
# Protocol: JSON on stdin with a `transcript_path`. OPT-IN — wire it from
# the host's hook settings (e.g. Claude Code's settings.json; see ~/.harness-mini/docs/smart-dumb.md). Hosts that don't emit that
# payload ignore it. Behavior of the script is unchanged either way.
#
# HONEST CAVEAT: bytes(transcript)/4 is a heuristic proxy for tokens, not a true
# count (no portable token counter exists). It is good enough to watch the trend
# and fire a checkpoint reminder — exactly what ~/.harness-mini/docs/smart-dumb.md asks of it.
#
# Best-effort: it must NEVER fail the tool call, so every path exits 0.
# Env: HARNESS_CTX_WINDOW    (default 200000)
#      HARNESS_CTX_THRESHOLD  (default 40)
#      HARNESS_TEST_SCRIPT    (optional) path to test runner; when set and green,
#                             stamps .harness-mini/trace/runtime/last-green.txt
#      HARNESS_TRACE_DIR      (default $HARNESS_ROOT/.harness-mini/trace/runtime)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
payload="$(cat 2>/dev/null || true)"

# pull transcript_path out of the hook JSON without a JSON parser (best-effort)
tpath="$(printf '%s' "$payload" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

window="${HARNESS_CTX_WINDOW:-200000}"
threshold="${HARNESS_CTX_THRESHOLD:-40}"

if [ -n "$tpath" ] && [ -f "$tpath" ]; then
  bytes=$(wc -c < "$tpath" 2>/dev/null | tr -d ' ')
  [ -n "$bytes" ] || bytes=0
  est=$((bytes / 4))                       # ~4 bytes/token heuristic
  [ "$window" -gt 0 ] 2>/dev/null || window=200000
  pct=$((est * 100 / window))
  [ "$pct" -gt 100 ] && pct=100

  # record the sample (best-effort; trace.sh swallows its own errors)
  bash "$HERE/trace.sh" main session tool_post ctx_pct="$pct" est=heuristic >/dev/null 2>&1 || true

  # nudge once over the line — to stderr so the agent sees it
  if [ "$pct" -ge "$threshold" ]; then
    printf '⚠ harness-mini: ~%s%% context (est) — at/over the %s%% line; checkpoint & reset while still sharp (~/.harness-mini/docs/smart-dumb.md).\n' \
      "$pct" "$threshold" >&2
  fi
fi

# --- last-green stamp (best-effort; never blocks the tool call) --------------
# When HARNESS_TEST_SCRIPT is set and exits 0, record a trusted snapshot of
# "tests passed at this git revision" so the checkpoint skill can report it
# without relying on LLM memory.
if [ -n "${HARNESS_TEST_SCRIPT:-}" ] && [ -f "${HARNESS_TEST_SCRIPT:-}" ]; then
  if bash "$HARNESS_TEST_SCRIPT" >/dev/null 2>&1; then
    rev="$(git -C "${HARNESS_ROOT:-.}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    snap_dir="${HARNESS_TRACE_DIR:-${HARNESS_ROOT:-.}/.harness-mini/trace/runtime}"
    { mkdir -p "$snap_dir" && printf '%s rev=%s\n' "$ts" "$rev" > "$snap_dir/last-green.txt"; } \
      2>/dev/null || true
  fi
fi

exit 0
