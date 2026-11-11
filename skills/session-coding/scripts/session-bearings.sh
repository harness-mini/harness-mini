#!/usr/bin/env bash
# session-bearings.sh — deterministic first-turn orientation for session-coding.
#
# Prints file-truth workboard fields so a cold agent does not paraphrase plan
# state from memory. Efficiency: one command replaces scattered status + git +
# checkpoint hunting. Determinism: slice id, last-green, and checkpoint resume
# come from disk (Discussion #75).
#
# Usage: session-bearings.sh
# Exit:  0 = coding path, report on stdout
#        2 = not path: coding — use session-init
# Env:   HARNESS_ROOT (default: cwd)
#        HARNESS_HOME (runtime root; default $HOME/.harness-mini)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${HARNESS_ROOT:-$PWD}"
# Source checkout: skills/session-coding/scripts -> repo bin/.
# Installed skill: runtime bin under $HARNESS_HOME.
if [ -f "$HERE/../../../bin/_harness_lib.sh" ]; then
  LIB="$HERE/../../../bin/_harness_lib.sh"
else
  LIB="${HARNESS_HOME:-$HOME/.harness-mini}/bin/_harness_lib.sh"
fi
# shellcheck source=bin/_harness_lib.sh
. "$LIB"

PDIR="$(progress_dir "$ROOT")"
ADIR="$PDIR/docs/exec-plans/active"

p_class=9 pick_md="" pick_plan="" pick_stage="" pick_twin="" pick_slice=""

classify_plan() {
  local f="$1" plan stage twin wb wst wcur wnxt wnp wns wpok pc slice=""
  plan="$(awk -F': *' '/^plan:/{print $2; exit}' "$f")"
  stage="$(awk -F': *' '/^stage:/{print $2; exit}' "$f")"
  [ -z "$plan" ] && plan="$(basename "$f" .md)"
  twin="${f%.md}.json"
  pc=4
  case "$stage" in
    implement|evaluate|checkpoint)
      if [ ! -f "$twin" ]; then
        pc=3
      else
        wb="$(json_wb "$twin")"
        IFS='|' read -r wst wcur wnxt wnp wns wpok <<< "$wb"
        if [ "$wpok" = "1" ] && [ -n "$wst" ]; then
          if [ "$wns" -gt 0 ]; then
            pc=1
            slice="$wnxt"
          elif [ "$wnp" -gt 0 ]; then
            pc=2
            slice="${wcur:-wrap-up}"
          else
            pc=4
          fi
        else
          pc=3
        fi
      fi
      ;;
    *) pc=4 ;;
  esac
  if [ "$pc" -lt "$p_class" ]; then
    p_class="$pc"
    pick_md="$f"
    pick_plan="$plan"
    pick_stage="$stage"
    pick_twin="$twin"
    pick_slice="$slice"
  fi
}

if ls "$ADIR"/*.md >/dev/null 2>&1; then
  for f in "$ADIR"/*.md; do
    [ -f "$f" ] || continue
    classify_plan "$f"
  done
fi

if [ "$p_class" -gt 2 ] || [ -z "$pick_plan" ]; then
  printf 'session-bearings: no coding-ready plan — path is init; use session-init.\n' >&2
  printf 'hint: run "%s" status\n' "$(dirname "$LIB")/harness.sh" >&2
  exit 2
fi

rel() {
  local p="$1"
  case "$p" in
    "$ROOT"/*) printf '%s' "${p#"$ROOT"/}" ;;
    *) printf '%s' "$p" ;;
  esac
}

printf 'root: %s\n' "$(cd "$ROOT" && pwd -P 2>/dev/null || pwd)"
printf 'path: coding\n'
printf 'plan: %s\n' "$pick_plan"
printf 'stage: %s\n' "${pick_stage:-?}"
printf 'twin: %s\n' "$(rel "$pick_twin")"
printf 'selected_slice: %s\n' "${pick_slice:-?}"

if [ -f "$pick_twin" ]; then
  wb="$(json_wb "$pick_twin")"
  IFS='|' read -r wst wcur wnxt wnp wns wpok <<< "$wb"
  wtot=$((wnp + wns))
  if [ "$wpok" = "1" ] && [ -n "$wst" ] && [ "$wtot" -gt 0 ]; then
    printf 'workboard: %s · %s/%s pass · current: %s · next: %s\n' \
      "$wst" "$wnp" "$wtot" "${wcur:--}" "${wnxt:-all green}"
  fi
fi

cp="$(ls "$PDIR"/trace/checkpoints/"$pick_plan"-*.md 2>/dev/null | sort | tail -n1)"
if [ -n "$cp" ]; then
  printf 'last_checkpoint: %s\n' "$(rel "$cp")"
  nxt="$(awk '
    /^## Next \(resume here\)/ { on=1; next }
    on && /^## / { exit }
    on && /^[[:space:]]*-[[:space:]]+/ {
      sub(/^[[:space:]]*-[[:space:]]+/, ""); print; exit
    }
  ' "$cp" 2>/dev/null)"
  [ -n "$nxt" ] && printf 'checkpoint_resume: %s\n' "$nxt"
else
  printf 'last_checkpoint: none\n'
fi

lg="$PDIR/trace/runtime/last-green.txt"
if [ -f "$lg" ]; then
  line="$(head -n1 "$lg" 2>/dev/null | tr -d '\r')"
  [ -n "$line" ] && printf 'last_green: %s\n' "$line" || printf 'last_green: none\n'
else
  printf 'last_green: none\n'
fi

if [ -d "$ROOT/.git" ]; then
  printf 'git_head: %s\n' "$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  printf 'git_log_5:\n'
  git -C "$ROOT" log --oneline -5 2>/dev/null | sed 's/^/  /' || true
fi

if [ -n "${HARNESS_TEST_SCRIPT:-}" ] && [ -f "${HARNESS_TEST_SCRIPT:-}" ]; then
  printf 'baseline_script: %s\n' "$HARNESS_TEST_SCRIPT"
else
  printf 'baseline_script: unset\n'
fi

printf 'agent_next: quote this report, run baseline (baseline_script or plan docs), then implement selected_slice only.\n'
exit 0
