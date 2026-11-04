#!/usr/bin/env bash
# skill-eval.sh — keyless fixture oracle for skill lift-evals.
#
# Grades the committed with_skill / without_skill transcripts under
# skills/<name>/evals/. No model call and no API key. This is a garden-cadence
# sensor, not a slice gate: skills/evaluate and harness.sh status do not run it.
#
# stdout: JSON summary (pass counts, pass rates, lift)
# stderr: one line per skill, plus failures
# exit:   0 ok, 1 schema or oracle failed, 64 usage
#
# See docs/skill-evals.md.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
ONLY=""

usage() {
  cat <<'EOF'
skill-eval.sh — keyless Wave A skill-lift fixture oracle.

Grades committed with_skill / without_skill transcripts. No model call, no API key.
Not a slice gate: skills/evaluate and harness.sh status do not run this.
Cadence is garden (see docs/skill-evals.md).

usage: skill-eval.sh [--root DIR] [--only SKILL]
stdout: JSON summary (pass rates + lift)
stderr: one line per skill
exit: 0 ok, 1 oracle or schema failed, 64 usage
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) shift ;;
    --root)
      [ $# -ge 2 ] || { usage; exit 64; }
      ROOT="$2"; shift 2 ;;
    --only)
      [ $# -ge 2 ] || { usage; exit 64; }
      ONLY="$2"; shift 2 ;;
    *) usage; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)" || { echo "skill-eval: bad --root" >&2; exit 64; }
case "$ONLY" in
  *[!a-z0-9-]*) echo "skill-eval: bad --only" >&2; exit 64 ;;
esac

WAVE_A="session-init session-coding evaluate stage-viewer to-prd to-issues tdd"
if [ -n "$ONLY" ]; then
  SKILLS="$ONLY"
  WAVE_LABEL="only"
else
  SKILLS="$WAVE_A"
  WAVE_LABEL="A"
fi

fail_n=0
err() { fail_n=$((fail_n + 1)); printf 'skill-eval: %s\n' "$*" >&2; }

rate() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    if (b == 0) { printf "0.000"; exit }
    printf "%.3f", a / b
  }'
}

lift_of() {
  awk -v w="$1" -v o="$2" -v n="$3" 'BEGIN {
    if (n == 0) { printf "+0.000"; exit }
    printf "%+.3f", (w - o) / n
  }'
}

json_key() {
  # $1 line, $2 key → quoted string value, or empty
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*\"${2}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p"
}

json_id() {
  printf '%s\n' "$1" | sed -n 's/^[[:space:]]*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p'
}

is_string_item() {
  printf '%s\n' "$1" | grep -q '^[[:space:]]*"[^"]*",\{0,1\}[[:space:]]*$'
}

string_item() {
  printf '%s\n' "$1" | sed -n 's/^[[:space:]]*"\([^"]*\)",\{0,1\}[[:space:]]*$/\1/p'
}

# parse_check LINE → prints role<TAB>kind<TAB>op<TAB>pattern  or nothing
parse_check() {
  local rest="$1" role="disc" kind op pattern
  case "$rest" in
    saturated\ *) role="sat"; rest="${rest#saturated }" ;;
  esac
  case "$rest" in
    *" "*) ;;
    *) return 1 ;;
  esac
  kind="${rest%% *}"
  rest="${rest#* }"
  case "$rest" in
    *" "*) ;;
    *) return 1 ;;
  esac
  op="${rest%% *}"
  pattern="${rest#* }"
  [ -n "$pattern" ] || return 1
  case "$kind" in
    contract|with|without|both) ;;
    *) return 1 ;;
  esac
  case "$op" in
    present|absent) ;;
    *) return 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$role" "$kind" "$op" "$pattern"
}

# check_file FILE OP PATTERN → 0 if the oracle holds
check_file() {
  local file="$1" op="$2" pattern="$3" hit=1
  [ -f "$file" ] || return 1
  grep -F -q -e "$pattern" "$file" || hit=0
  if [ "$op" = "present" ]; then
    [ "$hit" -eq 1 ]
  else
    [ "$hit" -eq 0 ]
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

load_skill() {
  # $1 skill name. Fills $WORK/$skill/skill_name and cases/<name>/.
  local skill="$1" ev="$ROOT/skills/$skill/evals/evals.json"
  local dest="$WORK/$skill" line cur="" in=none sn name id style trigger prompt exp
  mkdir -p "$dest/cases"
  if [ ! -f "$ev" ]; then
    err "$skill: missing evals/evals.json"
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$cur" ]; then
      sn="$(json_key "$line" skill_name)"
      if [ -n "$sn" ]; then
        printf '%s\n' "$sn" > "$dest/skill_name"
      fi
    fi
    name="$(json_key "$line" name)"
    if [ -n "$name" ]; then
      cur="$name"
      in=none
      case "$name" in
        *[!a-z0-9-]*|-*|*-)
          err "$skill: bad case name [$name]"
          cur=""
          continue ;;
      esac
      if [ -d "$dest/cases/$name" ]; then
        err "$skill: duplicate case [$name]"
        continue
      fi
      mkdir -p "$dest/cases/$name"
      printf '%s\n' "$name" > "$dest/cases/$name/name"
      continue
    fi
    if [ -n "$cur" ] && [ -d "$dest/cases/$cur" ]; then
      id="$(json_id "$line")"
      [ -n "$id" ] && printf '%s\n' "$id" > "$dest/cases/$cur/id"
      style="$(json_key "$line" style)"
      [ -n "$style" ] && printf '%s\n' "$style" > "$dest/cases/$cur/style"
      trigger="$(json_key "$line" trigger)"
      [ -n "$trigger" ] && printf '%s\n' "$trigger" > "$dest/cases/$cur/trigger"
      prompt="$(json_key "$line" prompt)"
      [ -n "$prompt" ] && printf '%s\n' "$prompt" > "$dest/cases/$cur/prompt"
      exp="$(json_key "$line" expected_output)"
      [ -n "$exp" ] && printf '%s\n' "$exp" > "$dest/cases/$cur/expected_output"
    fi
    case "$line" in
      *'"checks"'*) in=checks ;;
      *'"files"'*) in=files ;;
      *'"assertions"'*) in=assertions ;;
    esac
    if [ -n "$cur" ] && [ "$in" != "none" ] && is_string_item "$line"; then
      printf '%s\n' "$(string_item "$line")" >> "$dest/cases/$cur/$in"
    fi
    case "$line" in
      *']'*) in=none ;;
    esac
  done < "$ev"
  sn="$(cat "$dest/skill_name" 2>/dev/null || true)"
  if [ "$sn" != "$skill" ]; then
    err "$skill: skill_name [$sn] does not match the directory"
    return 1
  fi
  return 0
}

grade_skill() {
  # prints a JSON object (no trailing comma) and a human line on stderr.
  # sets GS_CASES GS_WITH GS_WITHOUT via globals.
  local skill="$1" base="$ROOT/skills/$skill" dest="$WORK/$skill"
  local cdir name style trigger ncheck=0 nassert=0 nsat=0
  local with_fail without_fail hard sat_cases=0
  local role kind op pattern side f rel
  local parsed
  GS_CASES=0
  GS_WITH=0
  GS_WITHOUT=0
  GS_SAT=0
  if ! load_skill "$skill"; then
    printf '{"skill":"%s","cases":0,"pass_with":0,"pass_without":0,"saturated":0,"lift":"+0.000"}' "$skill"
    printf '%s  cases=0  FAILED schema\n' "$skill" >&2
    return 0
  fi
  ids="$dest/ids"
  : > "$ids"
  for cdir in "$dest"/cases/*; do
    [ -d "$cdir" ] || continue
    name="$(cat "$cdir/name")"
    GS_CASES=$((GS_CASES + 1))
    for field in id style trigger prompt expected_output; do
      if [ ! -s "$cdir/$field" ]; then
        err "$skill/$name: missing $field"
      fi
    done
    style="$(cat "$cdir/style" 2>/dev/null || true)"
    trigger="$(cat "$cdir/trigger" 2>/dev/null || true)"
    case "$style" in
      happy|trigger|adversarial|saturated) ;;
      *) err "$skill/$name: bad style [$style]" ;;
    esac
    case "$trigger" in
      should_fire|should_not_fire) ;;
      *) err "$skill/$name: bad trigger [$trigger]" ;;
    esac
    if [ -s "$cdir/id" ]; then
      printf '%s\n' "$(cat "$cdir/id")" >> "$ids"
    fi
    nassert=0
    if [ -f "$cdir/assertions" ]; then
      nassert=$(grep -c . "$cdir/assertions" || true)
    fi
    [ "$nassert" -ge 1 ] || err "$skill/$name: need at least one assertion"
    if [ -f "$cdir/files" ]; then
      while IFS= read -r rel || [ -n "$rel" ]; do
        [ -n "$rel" ] || continue
        case "$rel" in
          ..|/*|../*|*/../*|*/..) err "$skill/$name: bad file path [$rel]"; continue ;;
        esac
        if [ ! -s "$base/$rel" ]; then
          err "$skill/$name: missing input [$rel]"
        fi
      done < "$cdir/files"
    fi
    ncheck=0
    nsat=0
    with_fail=0
    without_fail=0
    hard=0
    for side in with without; do
      f="$base/evals/fixtures/$name/${side}_skill/reply.md"
      if [ ! -s "$f" ]; then
        err "$skill/$name: missing evals/fixtures/$name/${side}_skill/reply.md"
        hard=1
      fi
    done
    if [ -f "$cdir/checks" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        ncheck=$((ncheck + 1))
        parsed="$(parse_check "$line" || true)"
        if [ -z "$parsed" ]; then
          err "$skill/$name: bad check [$line]"
          continue
        fi
        role="${parsed%%	*}"
        parsed="${parsed#*	}"
        kind="${parsed%%	*}"
        parsed="${parsed#*	}"
        op="${parsed%%	*}"
        pattern="${parsed#*	}"
        if [ "$role" = "sat" ]; then
          nsat=$((nsat + 1))
        fi
        if [ "$kind" = "contract" ]; then
          if ! check_file "$base/SKILL.md" "$op" "$pattern"; then
            err "$skill/$name: contract failed ($op) [$pattern]"
          fi
          continue
        fi
        if [ "$hard" -eq 1 ]; then
          continue
        fi
        for side in with without; do
          if [ "$kind" != "both" ] && [ "$kind" != "$side" ]; then
            continue
          fi
          f="$base/evals/fixtures/$name/${side}_skill/reply.md"
          if ! check_file "$f" "$op" "$pattern"; then
            if [ "$side" = "with" ]; then
              with_fail=$((with_fail + 1))
            else
              without_fail=$((without_fail + 1))
            fi
          fi
        done
      done < "$cdir/checks"
    fi
    [ "$ncheck" -ge 1 ] || err "$skill/$name: need at least one check"
    if [ "$style" = "saturated" ]; then
      [ "$nsat" -ge 1 ] || err "$skill/$name: saturated case needs a saturated check"
      if [ "$hard" -eq 0 ] && { [ "$with_fail" -ne 0 ] || [ "$without_fail" -ne 0 ]; }; then
        err "$skill/$name: saturated case must pass on both arms"
      fi
    elif [ "$hard" -eq 0 ]; then
      if [ "$with_fail" -ne 0 ]; then
        err "$skill/$name: with_skill failed $with_fail check(s)"
      fi
      if [ "$without_fail" -eq 0 ]; then
        err "$skill/$name: no lift (baseline also satisfied every check)"
      fi
    fi
    if [ "$hard" -eq 0 ] && [ "$with_fail" -eq 0 ]; then
      GS_WITH=$((GS_WITH + 1))
    fi
    if [ "$hard" -eq 0 ] && [ "$without_fail" -eq 0 ]; then
      GS_WITHOUT=$((GS_WITHOUT + 1))
    fi
    if [ "$style" = "saturated" ]; then
      sat_cases=$((sat_cases + 1))
    fi
  done
  if [ "$GS_CASES" -lt 3 ]; then
    err "$skill: need at least 3 cases (found $GS_CASES)"
  fi
  if [ -s "$ids" ]; then
    dup="$(sort "$ids" | uniq -d | tr '\n' ' ')"
    [ -z "$dup" ] || err "$skill: duplicate id(s) [$dup]"
  fi
  GS_SAT=$sat_cases
  printf '{"skill":"%s","cases":%s,"pass_with":%s,"pass_without":%s,"saturated":%s,"lift":"%s"}' \
    "$skill" "$GS_CASES" "$GS_WITH" "$GS_WITHOUT" "$GS_SAT" \
    "$(lift_of "$GS_WITH" "$GS_WITHOUT" "$GS_CASES")"
  printf '%s  cases=%s  with=%s  without=%s  saturated=%s  lift=%s\n' \
    "$skill" "$GS_CASES" "$GS_WITH" "$GS_WITHOUT" "$GS_SAT" \
    "$(lift_of "$GS_WITH" "$GS_WITHOUT" "$GS_CASES")" >&2
}

total_cases=0
total_with=0
total_without=0
total_sat=0
skills_json=""
sep=""
mkdir -p "$WORK/out"

for skill in $SKILLS; do
  # Redirect, do not use $(...): a subshell would drop the counters.
  grade_skill "$skill" > "$WORK/out/$skill.json"
  skills_json="${skills_json}${sep}$(cat "$WORK/out/$skill.json")"
  sep=","
  total_cases=$((total_cases + GS_CASES))
  total_with=$((total_with + GS_WITH))
  total_without=$((total_without + GS_WITHOUT))
  total_sat=$((total_sat + GS_SAT))
done

if [ "$fail_n" -eq 0 ]; then
  ok_json=true
  printf 'skill-eval: ok mode=fixture-oracle wave=%s cases=%s lift=%s\n' \
    "$WAVE_LABEL" "$total_cases" "$(lift_of "$total_with" "$total_without" "$total_cases")" >&2
else
  ok_json=false
  printf 'skill-eval: failed (%s)\n' "$fail_n" >&2
fi

cat <<EOF
{
  "mode": "fixture-oracle",
  "live": false,
  "cadence": "garden",
  "wave": "$WAVE_LABEL",
  "ok": $ok_json,
  "cases": $total_cases,
  "pass_with": $total_with,
  "pass_without": $total_without,
  "saturated_cases": $total_sat,
  "pass_rate_with": "$(rate "$total_with" "$total_cases")",
  "pass_rate_without": "$(rate "$total_without" "$total_cases")",
  "lift": "$(lift_of "$total_with" "$total_without" "$total_cases")",
  "skills": [${skills_json}]
}
EOF

[ "$fail_n" -eq 0 ]
exit $?
