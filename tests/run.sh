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
echo "harness.sh version — report the installed harness version"
HARN="$BIN/harness.sh"
# from the source repo (no lock), version falls back to the root VERSION file
out=$(HARNESS_NO_NET=1 bash "$HARN" version 2>/dev/null); code=$?
assert_exit 0 "$code" "harness version exits 0"
assert_contains "$out" "harness-mini" "version names the project"
assert_contains "$out" "$(cat "$ROOT/VERSION" 2>/dev/null)" "version prints the VERSION file's value"
# unknown subcommand is a usage error
code=0; bash "$HARN" bogus >/dev/null 2>&1 || code=$?
assert_exit 64 "$code" "unknown subcommand is a usage error (64)"
# no subcommand prints usage, non-zero
code=0; bash "$HARN" >/dev/null 2>&1 || code=$?
assert_exit 64 "$code" "no subcommand is a usage error (64)"
# an installed lock takes precedence over the root VERSION file
LK="$(mktemp -d)"; mkdir -p "$LK/harness"
printf 'version: 9.9.9\nabc123  AGENTS.md\n' > "$LK/harness/harness.lock"
out=$(HARNESS_ROOT="$LK" HARNESS_NO_NET=1 bash "$HARN" version 2>/dev/null)
assert_contains "$out" "9.9.9" "version prefers the installed lock over VERSION"
rm -rf "$LK"

# =============================================================================
echo "init.sh — writes harness/harness.lock (version + managed checksums)"
LSRC="$(mktemp -d)"
mkdir -p "$LSRC/skills" "$LSRC/agents" "$LSRC/bin" "$LSRC/docs"
printf 'skill body\n' > "$LSRC/skills/five-step.md"
printf 'agent body\n' > "$LSRC/agents/planner.md"
printf 'echo hi\n'    > "$LSRC/bin/ctx.sh"
printf 'map\n'        > "$LSRC/AGENTS.md"
printf '0.4.2\n'      > "$LSRC/VERSION"
LDEST="$(mktemp -d)"
HARNESS_SRC="$LSRC" bash "$ROOT/init.sh" "$LDEST" >/dev/null 2>&1
lock="$(cat "$LDEST/harness/harness.lock" 2>/dev/null)"
assert_contains "$lock" "version: 0.4.2" "lock records the source VERSION"
assert_contains "$lock" ".claude/skills/five-step.md" "lock lists a managed skill by target path"
assert_contains "$lock" "AGENTS.md" "lock lists managed AGENTS.md"
# the lock must record the PRISTINE source checksum, not a user-edited copy
src_sha="$(bash -c '. "$1"; cksum_file "$2"' _ "$BIN/_harness_lib.sh" "$LSRC/AGENTS.md")"
assert_contains "$lock" "$src_sha  AGENTS.md" "lock stores the pristine upstream checksum"
# additive: a second init does not error and leaves the lock present
code=0; HARNESS_SRC="$LSRC" bash "$ROOT/init.sh" "$LDEST" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "re-init with a lock present is idempotent"
rm -rf "$LSRC" "$LDEST"

# =============================================================================
echo "harness.sh update — checksum-guarded sync (ADD / UPDATE / CONFLICT)"
# old upstream -> install it (records baseline lock)
UOLD="$(mktemp -d)"; mkdir -p "$UOLD/skills" "$UOLD/agents" "$UOLD/docs"
printf 'keep-body\n'  > "$UOLD/skills/keep.md"
printf 'old-upd\n'    > "$UOLD/skills/upd.md"
printf 'old-edit\n'   > "$UOLD/skills/edit.md"
printf 'old-agents\n' > "$UOLD/AGENTS.md"
printf '0.1.0\n'      > "$UOLD/VERSION"
UDEST="$(mktemp -d)"
HARNESS_SRC="$UOLD" bash "$ROOT/init.sh" "$UDEST" >/dev/null 2>&1
# user edits one managed file, and owns plan + trace files
printf 'USER-edit\n' > "$UDEST/.claude/skills/edit.md"
mkdir -p "$UDEST/docs/exec-plans/active" "$UDEST/.trace/runtime"
printf 'my plan\n' > "$UDEST/docs/exec-plans/active/0009-mine.md"
printf '{"x":1}\n' > "$UDEST/.trace/runtime/run.jsonl"
# new upstream: keep unchanged, upd changed, edit changed, add brand new
UNEW="$(mktemp -d)"; mkdir -p "$UNEW/skills" "$UNEW/agents" "$UNEW/docs"
printf 'keep-body\n'  > "$UNEW/skills/keep.md"
printf 'NEW-upd\n'    > "$UNEW/skills/upd.md"
printf 'NEW-edit\n'   > "$UNEW/skills/edit.md"
printf 'brand-new\n'  > "$UNEW/skills/add.md"
printf 'old-agents\n' > "$UNEW/AGENTS.md"
printf '0.2.0\n'      > "$UNEW/VERSION"
code=0; HARNESS_ROOT="$UDEST" HARNESS_NO_NET=1 bash "$HARN" update --src "$UNEW" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "update exits 0"
assert_eq "NEW-upd"   "$(cat "$UDEST/.claude/skills/upd.md")"       "UPDATE: untouched managed file is refreshed"
assert_eq "keep-body" "$(cat "$UDEST/.claude/skills/keep.md")"      "UNCHANGED: identical file stays"
assert_eq "USER-edit" "$(cat "$UDEST/.claude/skills/edit.md")"      "CONFLICT: user-edited file is preserved"
assert_eq "NEW-edit"  "$(cat "$UDEST/.claude/skills/edit.md.new" 2>/dev/null)" "CONFLICT: upstream written as .new"
assert_eq "brand-new" "$(cat "$UDEST/.claude/skills/add.md" 2>/dev/null)"      "ADD: new upstream file is installed"
assert_eq "my plan"   "$(cat "$UDEST/docs/exec-plans/active/0009-mine.md")"    "user exec-plan is never touched"
assert_eq '{"x":1}'   "$(cat "$UDEST/.trace/runtime/run.jsonl")"   "user .trace is never touched"
assert_contains "$(cat "$UDEST/harness/harness.lock")" "version: 0.2.0" "update rewrites the lock version"
rm -rf "$UOLD" "$UDEST" "$UNEW"

# =============================================================================
echo "harness.sh release — guarded bump + tag (throwaway repos; --no-push/--no-gh)"
mkrepo() { # <dir> <version> <tests-exit> — a minimal source repo
  git -C "$1" init -q
  printf '%s\n' "$2" > "$1/VERSION"
  mkdir -p "$1/tests"; printf 'exit %s\n' "$3" > "$1/tests/run.sh"
  printf '# Changelog\n\n## [Unreleased]\n- a change\n' > "$1/CHANGELOG.md"
  git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm init >/dev/null 2>&1
}
# happy path
RREPO="$(mktemp -d)"; mkrepo "$RREPO" 0.1.0 0
code=0; HARNESS_ROOT="$RREPO" HARNESS_NO_NET=1 bash "$HARN" release 0.2.0 --no-push --no-gh >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "release happy path exits 0"
assert_eq "0.2.0" "$(tr -d '[:space:]' < "$RREPO/VERSION")" "release bumps VERSION"
assert_contains "$(cat "$RREPO/CHANGELOG.md")" "## [0.2.0]" "release rolls a CHANGELOG section"
assert_contains "$(git -C "$RREPO" tag)" "v0.2.0" "release creates the git tag"
# refuses bad semver
code=0; HARNESS_ROOT="$RREPO" bash "$HARN" release 1.2 --no-push --no-gh >/dev/null 2>&1 || code=$?
assert_exit 64 "$code" "release rejects non-semver version"
# refuses a dirty tree (RREPO is clean after release; dirty it)
printf 'x\n' >> "$RREPO/VERSION"
code=0; HARNESS_ROOT="$RREPO" bash "$HARN" release 0.3.0 --no-push --no-gh >/dev/null 2>&1 || code=$?
assert_exit 1 "$code" "release refuses a dirty working tree"
# refuses red tests
RRED="$(mktemp -d)"; mkrepo "$RRED" 0.1.0 1
code=0; HARNESS_ROOT="$RRED" bash "$HARN" release 0.2.0 --no-push --no-gh >/dev/null 2>&1 || code=$?
assert_exit 1 "$code" "release refuses when tests are red"
assert_eq "0.1.0" "$(tr -d '[:space:]' < "$RRED/VERSION")" "red-test release leaves VERSION untouched"
# dry-run mutates nothing
RDRY="$(mktemp -d)"; mkrepo "$RDRY" 0.1.0 0
code=0; HARNESS_ROOT="$RDRY" bash "$HARN" release 0.2.0 --dry-run --no-push --no-gh >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "release --dry-run exits 0"
assert_eq "0.1.0" "$(tr -d '[:space:]' < "$RDRY/VERSION")" "dry-run does not bump VERSION"
assert_eq "" "$(git -C "$RDRY" tag)" "dry-run creates no tag"
rm -rf "$RREPO" "$RRED" "$RDRY"

# =============================================================================
echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
