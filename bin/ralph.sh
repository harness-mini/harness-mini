#!/usr/bin/env bash
# ralph.sh — the "Ralph Wiggum" long loop: run a unit of work, check whether the
# exit condition is met, and repeat until it is — or until we run out of
# iterations, or a human-judgment flag is raised.
#
# This is the engine behind the ralph-loop skill: an agent does work, an
# evaluator (the --until predicate) decides if it passes, and the loop persists
# across context resets without a human babysitting it.
#
# Usage:  ralph.sh --max N --until '<predicate-cmd>' --cmd '<work-cmd>'
#   --cmd     shell command run each iteration (the work; e.g. invoke an agent)
#   --until   predicate run after each iteration; exit 0 means "done, stop"
#   --max     maximum iterations before giving up (default 10)
# Env:    HARNESS_HUMAN_FLAG  path to a flag file; if it exists the loop stops
#                             and defers to a human.
# Exit:   0 success (predicate satisfied)
#         3 exhausted max iterations
#         4 stopped for human judgment (flag present)
#         64 usage error
set -u

max=10
until_cmd=""
work_cmd=""

while [ $# -gt 0 ]; do
  case "$1" in
    --max)   max="$2"; shift 2 ;;
    --until) until_cmd="$2"; shift 2 ;;
    --cmd)   work_cmd="$2"; shift 2 ;;
    *) echo "ralph.sh: unknown arg: $1" >&2; exit 64 ;;
  esac
done

if [ -z "$until_cmd" ] || [ -z "$work_cmd" ]; then
  echo "usage: ralph.sh --max N --until '<predicate>' --cmd '<work>'" >&2
  exit 64
fi

flag="${HARNESS_HUMAN_FLAG:-}"
i=0
while [ "$i" -lt "$max" ]; do
  # defer to a human if the judgment flag was raised before/between iterations
  if [ -n "$flag" ] && [ -e "$flag" ]; then
    echo "ralph: human-judgment flag present ($flag) — stopping for review" >&2
    exit 4
  fi
  i=$((i + 1))
  echo "ralph: iteration $i/$max" >&2
  sh -c "$work_cmd"
  if sh -c "$until_cmd"; then
    echo "ralph: exit condition met after $i iteration(s)" >&2
    exit 0
  fi
done

echo "ralph: exhausted $max iterations without satisfying predicate" >&2
exit 3
