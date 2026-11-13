#!/usr/bin/env bash
# affected.sh — which test groups does a change set touch? (0063 slice-002)
# Usage:
#   tests/affected.sh <git-ref>   print the groups a <ref>..worktree diff touches
#   tests/affected.sh --check     cross-validate groups.tsv vs run.sh @group tags
#
# Diff: `git diff --name-only <ref>` — the named ref against the WORKING TREE
# (staged + unstaged; untracked files are not seen). Empty diff prints nothing
# and exits 0. A path matching no groups.tsv prefix maps to `all` (proven-or-
# full, same philosophy as the session path).
#
# Matching: per changed path the LONGEST matching prefix in groups.tsv wins;
# groups tying at the winning prefix length all fire. Matches are deduped and
# printed in groups.tsv order.
#
# Self-test overrides: AFFECTED_REPO (default: this repo) and AFFECTED_TSV
# (default: tests/groups.tsv) let the suite point the tool at fixture repos.
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
TSV="${AFFECTED_TSV:-$SELF_DIR/groups.tsv}"
REPO="${AFFECTED_REPO:-$SELF_DIR/..}"
RUNNER="$SELF_DIR/run.sh"

print_usage() {
  printf 'usage: tests/affected.sh <git-ref>   groups touched by <ref>..worktree diff\n' >&2
  printf '       tests/affected.sh --check     validate groups.tsv vs run.sh tags\n' >&2
}

if [ "${1:-}" = "--check" ]; then
  [ -f "$TSV" ] || { printf 'affected.sh: missing %s\n' "$TSV" >&2; exit 1; }
  tsv_groups=$(awk -F'\t' '!/^#/ && NF >= 2 { print $1 }' "$TSV" | sort -u)
  tag_groups=$(sed -n 's/^# @group //p' "$RUNNER")
  orphans=""
  for g in $tsv_groups; do
    case "$(printf '%s\n' "$tag_groups" | grep -Fx "$g")" in
      "$g") ;;
      *) orphans="$orphans tsv:$g" ;;
    esac
  done
  for g in $tag_groups; do
    case "$(printf '%s\n' "$tsv_groups" | grep -Fx "$g")" in
      "$g") ;;
      *) orphans="$orphans tag:$g" ;;
    esac
  done
  if [ -n "$orphans" ]; then
    printf 'affected.sh: orphan group entries:%s\n' "$orphans" >&2
    exit 1
  fi
  exit 0
fi

if [ "$#" -ne 1 ]; then
  print_usage
  exit 64
fi
ref="$1"

paths=$(git -C "$REPO" diff --name-only "$ref") || {
  printf 'affected.sh: git diff against %s failed\n' "$ref" >&2
  exit 1
}
[ -z "$paths" ] && exit 0
[ -f "$TSV" ] || { printf 'affected.sh: missing %s\n' "$TSV" >&2; exit 1; }

# groups.tsv into parallel arrays, file order preserved
GRP_NAMES=(); GRP_PREFIX=()
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  grp=${line%%$'\t'*}
  prefix=${line#*$'\t'}
  GRP_NAMES[${#GRP_NAMES[@]}]="$grp"
  GRP_PREFIX[${#GRP_PREFIX[@]}]="$prefix"
done < "$TSV"

hit=""; all_flag=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  best=0; winners=""
  i=0
  while [ "$i" -lt "${#GRP_NAMES[@]}" ]; do
    prefix=${GRP_PREFIX[$i]}
    case "$p" in
      "$prefix"*)
        len=${#prefix}
        if [ "$len" -gt "$best" ]; then
          best=$len; winners=" ${GRP_NAMES[$i]} "
        elif [ "$len" -eq "$best" ] && [ "$best" -gt 0 ]; then
          case "$winners" in *" ${GRP_NAMES[$i]} "*) ;; *) winners="$winners ${GRP_NAMES[$i]} " ;; esac
        fi
        ;;
    esac
    i=$((i + 1))
  done
  if [ "$best" -eq 0 ]; then
    all_flag=1
  else
    hit="$hit$winners"
  fi
done <<EOF
$paths
EOF

if [ "$all_flag" -eq 1 ]; then
  echo all
  exit 0
fi

i=0; printed=" "
while [ "$i" -lt "${#GRP_NAMES[@]}" ]; do
  g=${GRP_NAMES[$i]}
  case " $printed " in
    *" $g "*) ;;                       # a group with several prefixes prints once
    *)
      case " $hit " in
        *" $g "*) printf '%s\n' "$g"; printed="$printed$g " ;;
      esac
      ;;
  esac
  i=$((i + 1))
done
exit 0
