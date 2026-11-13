#!/usr/bin/env bash
# checkpoint-archive-check.sh — archive-integrity gate for the checkpoint skill.
#
# At checkpoint time, verifies the exec-plans tree is fully committed and that
# every archived plan is internally consistent. A `git mv` stages only the
# rename — the `stage:`/`passes` content edits stay in the working tree, and
# stale metadata landing on main makes `harness.sh status` lie to cold
# sessions (shipped twice: PRs #91 and #94).
#
# Usage: checkpoint-archive-check.sh [root]
#   root defaults to the git toplevel (cwd fallback outside a repo); plans
#   live under <root>/.harness-mini/docs/exec-plans/.
# Exit:  0 = clean and consistent (silent)
#        1 = violations, each named on stderr (or an unusable root)
# Env:   none
#
# Checks:
#   A. dirty tree — `git status --porcelain` under exec-plans/ must be empty.
#      Staged renames AND uncommitted content edits both count. Skipped when
#      root is not inside a git work tree.
#   B. completed invariant — every completed/*.md is `stage: done`; its twin
#      .json exists, reads "status": "done", and carries no "passes": false
#      slice. Plans predating the twin contract (seq < 47, or no numeric seq)
#      are exempt from the twin requirement — legacy completed records are
#      never retroactively failed (same precedent as check_eval_gate).
#      active/ and other dirs are NOT stage-checked (their stages
#      legitimately vary mid-lifecycle); a missing completed/ dir skips the
#      check silently.
#
# Part of checkpoint-archive-check (plan 0064-checkpoint-archive-check).
set -u

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
plans_dir="$root/.harness-mini/docs/exec-plans"
completed_dir="$plans_dir/completed"
violations=0

# frontmatter_field <file> <key> — value of the first `key:` line
# (trailing-whitespace tolerant, per the checkpoint script family)
frontmatter_field() {
  awk -F': *' -v key="$2" '
    $0 ~ "^" key ":" {
      v = $2
      sub(/[[:space:]]+$/, "", v)
      print v
      exit
    }
  ' "$1"
}

# twin_status <twin.json> — the plan twin's top-level "status" value
# (first key wins; same awk idiom as json_wb in _harness_lib.sh)
twin_status() {
  awk '
    /"status"[ \t]*:[ \t]*"/ {
      s = $0
      sub(/.*"status"[ \t]*:[ \t]*"/, "", s)
      sub(/".*/, "", s)
      print s
      exit
    }
  ' "$1"
}

# has_failing_slice <twin.json> — success iff some slice has "passes": false
has_failing_slice() {
  grep -Eq '"passes"[[:space:]]*:[[:space:]]*false' "$1"
}

# is_legacy_seq <seq> — success iff the plan predates the twin contract
# (0047 was the first plan emitted with a twin); seq is decimal even when
# zero-padded, and an absent/non-numeric seq counts as legacy
is_legacy_seq() {
  case "$1" in
    ''|*[!0-9]*) return 0 ;;
    *) [ "$1" -lt 47 ] ;;
  esac
}

if [ ! -d "$root" ]; then
  printf 'checkpoint-archive-check.sh: not a directory: %s\n' "$root" >&2
  exit 1
fi

# Check A — nothing under exec-plans/ may be uncommitted
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # stderr suppressed: a missing plans dir makes git warn on the pathspec
  dirty="$(git -C "$root" status --porcelain -- .harness-mini/docs/exec-plans/ 2>/dev/null)"
  if [ -n "$dirty" ]; then
    # porcelain v1 lines are "XY <path>"; report the path column only
    # (a rename keeps its "old -> new" pair, naming both ends)
    printf '%s\n' "$dirty" | while IFS= read -r dirty_line; do
      [ -n "$dirty_line" ] || continue
      printf 'dirty: %s\n' "${dirty_line#???}" >&2
    done
    violations=$((violations + 1))
  fi
fi

# Check B — every archived plan reached done, in both twin files
if [ -d "$completed_dir" ]; then
  for plan_md in "$completed_dir"/*.md; do
    [ -f "$plan_md" ] || continue
    plan="${plan_md##*/}"
    plan="${plan%.md}"
    stage="$(frontmatter_field "$plan_md" stage)"
    if [ "$stage" != "done" ]; then
      printf "%s: stage is '%s', want 'done'\n" "$plan" "$stage" >&2
      violations=$((violations + 1))
    fi
    plan_twin="$completed_dir/$plan.json"
    if [ ! -f "$plan_twin" ]; then
      if is_legacy_seq "$(frontmatter_field "$plan_md" seq)"; then
        continue
      fi
      printf '%s: twin %s.json is missing\n' "$plan" "$plan" >&2
      violations=$((violations + 1))
      continue
    fi
    status="$(twin_status "$plan_twin")"
    if [ "$status" != "done" ]; then
      printf "%s: status is '%s', want 'done'\n" "$plan" "$status" >&2
      violations=$((violations + 1))
    fi
    if has_failing_slice "$plan_twin"; then
      printf '%s: passes is false, want all true\n' "$plan" >&2
      violations=$((violations + 1))
    fi
  done
fi

if [ "$violations" -gt 0 ]; then
  exit 1
fi
exit 0
