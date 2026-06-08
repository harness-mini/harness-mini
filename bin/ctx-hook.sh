#!/usr/bin/env bash
# ctx-hook.sh — optional Claude Code PostToolUse adapter that gives the 40% rule
# teeth. It estimates context occupancy after each tool call and (a) records a
# ctx_pct trace event so `harness.sh report` can chart the trend, and (b) nudges
# the agent to checkpoint when it crosses the smart/dumb line.
#
# This is the ONE Claude-Code-specific file in the harness: it speaks CC's hook
# protocol (JSON on stdin with a `transcript_path`). It is OPT-IN — wire it up in
# .claude/settings.json yourself (see docs/smart-dumb.md). Other CLIs ignore it;
# the harness stays CLI-agnostic.
#
# HONEST CAVEAT: bytes(transcript)/4 is a heuristic proxy for tokens, not a true
# count (no portable token counter exists). It is good enough to watch the trend
# and fire a checkpoint reminder — exactly what docs/smart-dumb.md asks of it.
#
# Best-effort: it must NEVER fail the tool call, so every path exits 0.
# Env: HARNESS_CTX_WINDOW (default 200000) · HARNESS_CTX_THRESHOLD (default 40)
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
    printf '⚠ harness-mini: ~%s%% context (est) — at/over the %s%% line; checkpoint & reset while still sharp (docs/smart-dumb.md).\n' \
      "$pct" "$threshold" >&2
  fi
fi

exit 0
