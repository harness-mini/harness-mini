#!/usr/bin/env bash
# trace.sh — append one runtime trace event as JSONL. BEST-EFFORT: it must never
# fail the calling agent, so every error path still exits 0.
#
# Runtime traces are ephemeral (.trace/runtime/, gitignored) — the per-run
# observability stack. Committed institutional memory lives in .trace/checkpoints/
# (written by the checkpoint skill), not here.
#
# Usage:  trace.sh <agent> <stage> <event> [key=value ...]
# Extra key=value pairs are added to the JSON object. Values that look like
# integers are emitted unquoted; everything else is emitted as a JSON string.
# Env:    HARNESS_TRACE_DIR (default .trace/runtime)
#         HARNESS_RUN       (default a generated run id)
set -u

agent="${1:-unknown}"
stage="${2:-unknown}"
event="${3:-unknown}"
shift 3 2>/dev/null || true

dir="${HARNESS_TRACE_DIR:-.trace/runtime}"
run="${HARNESS_RUN:-r-$(date +%s)-$$}"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

json_escape() { # escape backslashes and double quotes for JSON strings
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

line='{"ts":"'"$ts"'","run":"'"$(json_escape "$run")"'","agent":"'"$(json_escape "$agent")"'","stage":"'"$(json_escape "$stage")"'","event":"'"$(json_escape "$event")"'"'
for kv in "$@"; do
  key="${kv%%=*}"
  val="${kv#*=}"
  if printf '%s' "$val" | grep -Eq '^-?[0-9]+$'; then
    line="$line,\"$(json_escape "$key")\":$val"          # numeric, unquoted
  else
    line="$line,\"$(json_escape "$key")\":\"$(json_escape "$val")\""
  fi
done
line="$line}"

# best-effort write — swallow every failure
{ mkdir -p "$dir" && printf '%s\n' "$line" >> "$dir/${run}.jsonl"; } 2>/dev/null || true
exit 0
