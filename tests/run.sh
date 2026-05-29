#!/usr/bin/env bash
# Zero-dependency test runner for harness-mini bin/ scripts.
# Usage: bash tests/run.sh
# TDD: these tests are written before (or alongside) the implementation.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin"
PASS=0
FAIL=0

# --- assertion helpers -------------------------------------------------------
assert_eq() { # <expected> <actual> <msg>
  if [ "$1" = "$2" ]; then
    PASS=$((PASS + 1)); printf '  ok   %s\n' "$3"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: [%s]\n       actual:   [%s]\n' "$3" "$1" "$2"
  fi
}

assert_exit() { # <expected_code> <actual_code> <msg>
  assert_eq "$1" "$2" "$3 (exit code)"
}

assert_contains() { # <haystack> <needle> <msg>
  case "$1" in
    *"$2"*) PASS=$((PASS + 1)); printf '  ok   %s\n' "$3" ;;
    *) FAIL=$((FAIL + 1)); printf '  FAIL %s\n       string [%s] not found in:\n       %s\n' "$3" "$2" "$1" ;;
  esac
}

# =============================================================================
echo "ctx.sh — context occupancy gate (40%% smart/dumb threshold)"
# 50k/200k = 25% -> smart zone, exit 0
out=$(bash "$BIN/ctx.sh" 50000 200000); code=$?
assert_eq "25%" "$out" "ctx 50k/200k prints 25%"
assert_exit 0 "$code" "ctx 25% is smart"
# default window is 200000
out=$(bash "$BIN/ctx.sh" 50000); code=$?
assert_eq "25%" "$out" "ctx default window 200k -> 25%"
# 100k/200k = 50% -> dumb zone, exit 2
out=$(bash "$BIN/ctx.sh" 100000 200000); code=$?
assert_eq "50%" "$out" "ctx 100k/200k prints 50%"
assert_exit 2 "$code" "ctx 50% is dumb (over threshold)"
# 80k/200k = 40% exactly -> crossing the line triggers checkpoint (dumb)
out=$(bash "$BIN/ctx.sh" 80000 200000); code=$?
assert_eq "40%" "$out" "ctx 80k/200k prints 40%"
assert_exit 2 "$code" "ctx 40% triggers checkpoint (>= threshold)"
# threshold overridable
code=0; HARNESS_CTX_THRESHOLD=60 bash "$BIN/ctx.sh" 100000 200000 >/dev/null || code=$?
assert_exit 0 "$code" "ctx 50% is smart when threshold raised to 60"

# =============================================================================
echo "trace.sh — best-effort runtime JSONL append"
TMPT="$(mktemp -d)"
HARNESS_TRACE_DIR="$TMPT" HARNESS_RUN="r-test" \
  bash "$BIN/trace.sh" generator implement tool_call tool=Edit ctx_pct=22 >/dev/null
code=$?
assert_exit 0 "$code" "trace exits 0 (best-effort)"
line="$(cat "$TMPT/r-test.jsonl" 2>/dev/null)"
assert_contains "$line" '"agent":"generator"' "trace records agent"
assert_contains "$line" '"stage":"implement"' "trace records stage"
assert_contains "$line" '"event":"tool_call"' "trace records event"
assert_contains "$line" '"tool":"Edit"' "trace records extra key tool"
assert_contains "$line" '"ctx_pct":22' "trace records numeric ctx_pct unquoted"
assert_contains "$line" '"run":"r-test"' "trace records run id"
assert_contains "$line" '"ts":' "trace records timestamp"
# appends, not overwrites
HARNESS_TRACE_DIR="$TMPT" HARNESS_RUN="r-test" bash "$BIN/trace.sh" generator implement test result=green >/dev/null
n=$(wc -l < "$TMPT/r-test.jsonl" | tr -d ' ')
assert_eq "2" "$n" "trace appends (2 lines)"
# best-effort: unwritable dir still exits 0
code=0; HARNESS_TRACE_DIR="/no/such/dir/at/all" HARNESS_RUN="r-x" bash "$BIN/trace.sh" a b c >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "trace never fails caller even when dir unwritable"
rm -rf "$TMPT"

# =============================================================================
echo "ralph.sh — long loop until predicate / max-iters / human flag"
MARK="$(mktemp -u)"
rm -f "$MARK"
# stops when --until passes; --cmd creates the marker on first run
code=0; bash "$BIN/ralph.sh" --max 5 --until "test -f $MARK" --cmd "touch $MARK" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "ralph stops 0 when until-predicate becomes true"
rm -f "$MARK"
# never satisfied -> hits max, exits non-zero (3 = exhausted)
code=0; bash "$BIN/ralph.sh" --max 2 --until "false" --cmd "true" >/dev/null 2>&1 || code=$?
assert_exit 3 "$code" "ralph exits 3 when max iterations exhausted"
# human flag present -> stops early, exit 4 (needs judgment)
FLAG="$(mktemp)"
code=0; HARNESS_HUMAN_FLAG="$FLAG" bash "$BIN/ralph.sh" --max 9 --until "false" --cmd "true" >/dev/null 2>&1 || code=$?
assert_exit 4 "$code" "ralph exits 4 when human-judgment flag is set"
rm -f "$FLAG"

# =============================================================================
echo "init.sh — additive, idempotent installer with new/existing asymmetry"
# Build a fake source tree so installer logic is tested independent of real assets.
FSRC="$(mktemp -d)"
mkdir -p "$FSRC/skills" "$FSRC/agents" "$FSRC/bin" "$FSRC/docs"
printf 'skill body\n' > "$FSRC/skills/five-step.md"
printf 'agent body\n' > "$FSRC/agents/planner.md"
printf 'echo hi\n'    > "$FSRC/bin/ctx.sh"
printf 'map\n'        > "$FSRC/AGENTS.md"

# --- new (empty) project: generative bootstrap ---
NEW="$(mktemp -d)"
code=0; HARNESS_SRC="$FSRC" bash "$BIN/../init.sh" "$NEW" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "init succeeds on empty project"
assert_eq "true" "$([ -f "$NEW/.claude/skills/five-step.md" ] && echo true || echo false)" "skills install to .claude/skills/"
assert_eq "true" "$([ -f "$NEW/.claude/agents/planner.md" ] && echo true || echo false)" "agents install to .claude/agents/"
assert_eq "true" "$([ -f "$NEW/harness/manifest.md" ] && echo true || echo false)" "neutral harness/manifest.md mirror written"
assert_eq "true" "$([ -f "$NEW/.gitignore" ] && grep -q '.trace/runtime' "$NEW/.gitignore" && echo true || echo false)" "gitignore carries .trace/runtime"
plan="$(cat "$NEW"/docs/exec-plans/active/0001-*.md 2>/dev/null)"
assert_contains "$plan" "stage: intake" "new project seeds an intake-stage plan"
assert_contains "$plan" "founder-check" "new project plan points to founder-check funnel"

# --- existing project: recon graft (no founder funnel) ---
EXIST="$(mktemp -d)"
printf '{}\n' > "$EXIST/package.json"   # marks it as an existing project
code=0; HARNESS_SRC="$FSRC" bash "$BIN/../init.sh" "$EXIST" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "init succeeds on existing project"
plan="$(cat "$EXIST"/docs/exec-plans/active/0001-*.md 2>/dev/null)"
assert_contains "$plan" "recon" "existing project seeds a recon plan"
assert_eq "false" "$(printf '%s' "$plan" | grep -q 'founder-check' && echo true || echo false)" "existing project skips founder funnel"
assert_eq "true" "$([ -f "$EXIST/.claude/skills/five-step.md" ] && echo true || echo false)" "existing project still gets skills installed"

# --- additive: never overwrite a user's existing file ---
printf 'MY CUSTOM MAP\n' > "$NEW/AGENTS.md"
HARNESS_SRC="$FSRC" bash "$BIN/../init.sh" "$NEW" >/dev/null 2>&1
assert_eq "MY CUSTOM MAP" "$(cat "$NEW/AGENTS.md")" "re-run never overwrites user-modified file"

# --- idempotent: second run exits 0, no duplicate plans ---
code=0; HARNESS_SRC="$FSRC" bash "$BIN/../init.sh" "$NEW" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "re-run is idempotent (exit 0)"
nplans=$(ls "$NEW"/docs/exec-plans/active/0001-*.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "1" "$nplans" "re-run does not duplicate the seed plan"

rm -rf "$FSRC" "$NEW" "$EXIST"

# =============================================================================
echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
