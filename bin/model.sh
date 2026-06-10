#!/usr/bin/env bash
# model.sh — resolve which model alias an agent role should run on.
#
# harness-mini assigns each sub-agent a capability TIER, not a fixed version:
# planner/generator -> sonnet, evaluator -> opus, explorer/gardener -> haiku
# (see AGENTS.md "Sub-agents"). Those static defaults are the current use and
# do NOT change here.
#
# Claude Fable 5 is the new top-capability tier, above Opus. Per Anthropic's
# launch note, Fable 5 is included on Pro/Max/Team/Enterprise plans only through
# 2026-06-22; from 2026-06-23 using it needs usage credits, and Anthropic intends
# to restore it to subscriptions later as capacity allows. Availability is
# therefore plan- and time-dependent — it must be DETECTED at runtime, never
# hardcoded.
#
# So this script prints the model alias for a role, and the BUILDER (generator)
# is the one role that auto-upgrades to `fable` WHEN Fable 5 is available to this
# account; every other role prints its static default. The spawning (main) agent
# passes the printed alias as the sub-agent's model override.
#
# Usage:   model.sh <role>     role: planner|generator|builder|evaluator|explorer|gardener
# Prints:  a model alias       e.g. "sonnet", or "fable" for the builder when available
# Exit:    0 with a usable alias (detection is best-effort and never blocks);
#          64 on usage error (no role given)
#
# Env:
#   HARNESS_MODEL_BUILDER  force the builder's model (any alias) — highest precedence
#   HARNESS_FABLE          1|on|true -> available · 0|off|false -> no · auto (default) -> probe
#   HARNESS_NO_NET         if set, skip the availability probe (offline / tests)
#   ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN   used (best-effort) by the `auto` probe
set -u

usage() {
  cat <<'EOF'
model.sh — resolve the model alias an agent role runs on.

usage: model.sh <role>      role: planner|generator|builder|evaluator|explorer|gardener
prints: a model alias       exit: 0 (always usable; 64 if no role given)

The builder (generator) auto-upgrades to `fable` (Claude Fable 5, the top tier)
when Fable 5 is available to this account; every other role keeps its static
tier. Availability is detected best-effort and never blocks.

env:
  HARNESS_MODEL_BUILDER   force the builder's model (any alias) — wins over detection
  HARNESS_FABLE           1|on|true (available) · 0|off|false (no) · auto (default; probe)
  HARNESS_NO_NET          if set, skip the availability probe
  ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN   creds the `auto` probe uses

examples:
  model.sh evaluator                  # opus   (static tier, unchanged)
  model.sh generator                  # fable when available, else sonnet
  HARNESS_FABLE=0 model.sh builder    # sonnet (pin off)
  HARNESS_MODEL_BUILDER=opus model.sh generator   # opus (explicit override)

See AGENTS.md "Sub-agents" for the tier map.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

role="${1:-}"
if [ -z "$role" ]; then
  usage >&2
  exit 64
fi

# static tier defaults — the unchanged "current use"
default_for() {
  case "$1" in
    planner|plan)            echo sonnet ;;
    generator|builder|build) echo sonnet ;;
    evaluator|eval)          echo opus ;;
    explorer|explore)        echo haiku ;;
    gardener|garden)         echo haiku ;;
    *)                       echo sonnet ;;
  esac
}

# fable_available — best-effort: is claude-fable-5 usable by this account?
# Mirrors harness.sh's latest_version: explicit override > offline short-circuit >
# best-effort network. Any unexpected condition resolves to "no" (fall back).
fable_available() {
  case "$(printf '%s' "${HARNESS_FABLE:-auto}" | tr '[:upper:]' '[:lower:]')" in
    1|on|true|yes)  return 0 ;;
    0|off|false|no) return 1 ;;
  esac
  # auto: probe the Models API. Offline / no curl / no creds / not found => "no".
  [ -n "${HARNESS_NO_NET:-}" ] && return 1
  command -v curl >/dev/null 2>&1 || return 1
  local body=""
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    body="$(curl -fsS --max-time 3 https://api.anthropic.com/v1/models \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" 2>/dev/null)"
  elif [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
    body="$(curl -fsS --max-time 3 https://api.anthropic.com/v1/models \
            -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN" \
            -H "anthropic-version: 2023-06-01" \
            -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)"
  else
    return 1
  fi
  printf '%s' "$body" | grep -q 'claude-fable-5'
}

case "$role" in
  generator|builder|build)
    # builder is the one role that may run on the new top tier
    if [ -n "${HARNESS_MODEL_BUILDER:-}" ]; then
      printf '%s\n' "$HARNESS_MODEL_BUILDER"
      exit 0
    fi
    if fable_available; then
      echo fable
      exit 0
    fi
    ;;
esac

default_for "$role"
exit 0
