#!/usr/bin/env bash
# model.sh — resolve which model alias an agent role should run on.
#
# harness-mini assigns each sub-agent a capability TIER, not a fixed version:
# planner/generator -> sonnet, evaluator -> opus, explorer/gardener -> haiku
# (see AGENTS.md "Sub-agents"). Those static defaults are the current use and
# do NOT change here.
#
# The BUILDER (generator) is the one role that can be upgraded to the
# highest-available frontier model tier (`opus`, the top tier the harness names)
# when HARNESS_TOP_MODEL is set; every other role prints its static default. The
# spawning (main) agent passes the printed alias as the sub-agent's model
# override.
#
# Usage:   model.sh <role>     role: planner|generator|builder|evaluator|explorer|gardener
# Prints:  a model alias       e.g. "sonnet", or "opus" for the builder when the top tier is enabled
# Exit:    0 with a usable alias (resolution is best-effort and never blocks);
#          64 on usage error (no role given)
#
# Env:
#   HARNESS_MODEL_BUILDER  force the builder's model (any alias) — highest precedence
#   HARNESS_TOP_MODEL      force upgrade to the highest available model tier
#                          1|on|true|yes -> upgrade · anything else / unset -> static default
set -u

# the highest-available frontier model tier the harness names (above sonnet)
TOP_TIER=opus

usage() {
  cat <<'EOF'
model.sh — resolve the model alias an agent role runs on.

usage: model.sh <role>      role: planner|generator|builder|evaluator|explorer|gardener
prints: a model alias       exit: 0 (always usable; 64 if no role given)

The builder (generator) auto-upgrades to the highest-available frontier model
tier (opus, the top tier the harness names) when HARNESS_TOP_MODEL is set; every
other role keeps its static tier.

env:
  HARNESS_MODEL_BUILDER   force the builder's model (any alias) — wins over the upgrade
  HARNESS_TOP_MODEL       force upgrade to the highest available model tier
                          1|on|true|yes -> upgrade · anything else / unset -> static default

examples:
  model.sh evaluator                       # opus   (static tier, unchanged)
  model.sh generator                       # sonnet (static tier; no upgrade by default)
  HARNESS_TOP_MODEL=1 model.sh generator   # opus   (top tier when enabled)
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

# top_model_enabled — has the operator opted the builder into the top tier?
top_model_enabled() {
  case "$(printf '%s' "${HARNESS_TOP_MODEL:-}" | tr '[:upper:]' '[:lower:]')" in
    1|on|true|yes) return 0 ;;
    *)             return 1 ;;
  esac
}

case "$role" in
  generator|builder|build)
    # builder is the one role that may run on the top frontier tier
    if [ -n "${HARNESS_MODEL_BUILDER:-}" ]; then
      printf '%s\n' "$HARNESS_MODEL_BUILDER"
      exit 0
    fi
    if top_model_enabled; then
      echo "$TOP_TIER"
      exit 0
    fi
    ;;
esac

default_for "$role"
exit 0
