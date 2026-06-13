#!/usr/bin/env bash
# Zero-dependency test runner for harness-mini bin/ scripts.
# Usage: bash tests/run.sh
# TDD: these tests are written before (or alongside) the implementation.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin"
PASS=0
FAIL=0

# Hermetic by default: no test should hit the network. The update-check tests
# inject a latest version via HARNESS_LATEST (which short-circuits before the
# network path), so this stays in force even for them.
export HARNESS_NO_NET=1

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
echo "model.sh — resolve a role's model alias (builder upgrades to the top tier when enabled)"
# static tiers are the unchanged "current use" — never upgraded
assert_eq "sonnet" "$(bash "$BIN/model.sh" planner)"   "planner -> sonnet (static tier)"
assert_eq "opus"   "$(bash "$BIN/model.sh" evaluator)" "evaluator -> opus (static tier)"
assert_eq "haiku"  "$(bash "$BIN/model.sh" explorer)"  "explorer -> haiku (static tier)"
assert_eq "haiku"  "$(bash "$BIN/model.sh" gardener)"  "gardener -> haiku (static tier)"
# default (no flag) -> builder keeps its static tier
assert_eq "sonnet" "$(bash "$BIN/model.sh" generator)" "generator stays sonnet when the top tier is not enabled"
# top-model flag -> builder runs on the highest frontier tier (opus)
assert_eq "opus"   "$(HARNESS_TOP_MODEL=1 bash "$BIN/model.sh" generator)" "generator -> top tier (opus) when enabled"
assert_eq "opus"   "$(HARNESS_TOP_MODEL=1 bash "$BIN/model.sh" builder)"   "builder alias -> top tier (opus) when enabled"
# the upgrade is builder-only: other roles never change, even with the flag set
assert_eq "haiku"  "$(HARNESS_TOP_MODEL=1 bash "$BIN/model.sh" explorer)" "explorer stays haiku (upgrade is builder-only)"
# off, and explicit override both win
assert_eq "sonnet" "$(HARNESS_TOP_MODEL=0 bash "$BIN/model.sh" generator)" "HARNESS_TOP_MODEL=0 keeps the builder on sonnet"
assert_eq "haiku"  "$(HARNESS_MODEL_BUILDER=haiku HARNESS_TOP_MODEL=1 bash "$BIN/model.sh" generator)" "HARNESS_MODEL_BUILDER overrides the top-tier upgrade"
# usage contract: --help is 0, no role is a usage error (64)
code=0; out=$(bash "$BIN/model.sh" --help) || code=$?
assert_exit 0 "$code" "model.sh --help exits 0"
assert_contains "$out" "model.sh" "model.sh --help prints usage"
code=0; bash "$BIN/model.sh" >/dev/null 2>&1 || code=$?
assert_exit 64 "$code" "model.sh with no role is a usage error (64)"

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
mkdir -p "$FSRC/skills" "$FSRC/agents" "$FSRC/bin" "$FSRC/docs" "$FSRC/skills/demo"
printf 'skill body\n' > "$FSRC/skills/five-step.md"
printf 'demo body\n'  > "$FSRC/skills/demo/SKILL.md"   # canonical folder-form skill
printf 'agent body\n' > "$FSRC/agents/planner.md"
printf 'echo hi\n'    > "$FSRC/bin/ctx.sh"
printf 'map\n'        > "$FSRC/AGENTS.md"

# --- new (empty) project: generative bootstrap ---
NEW="$(mktemp -d)"
code=0; HARNESS_SRC="$FSRC" bash "$BIN/../init.sh" "$NEW" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "init succeeds on empty project"
assert_eq "true" "$([ -f "$NEW/.claude/skills/five-step.md" ] && echo true || echo false)" "skills install to .claude/skills/"
assert_eq "true" "$([ -f "$NEW/.claude/skills/demo/SKILL.md" ] && echo true || echo false)" "folder-form skill installs to .claude/skills/<name>/SKILL.md"
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
echo "init.sh — seeds the CLI routing gate (CLAUDE.md + .cursor rules; additive/idempotent)"
GSRC="$(mktemp -d)"
mkdir -p "$GSRC/skills" "$GSRC/agents" "$GSRC/bin" "$GSRC/docs"
printf 'map\n' > "$GSRC/AGENTS.md"
# empty project: both native always-on entry files are seeded with the gate
GNEW="$(mktemp -d)"
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$GNEW" >/dev/null 2>&1
assert_eq "true" "$([ -f "$GNEW/CLAUDE.md" ] && echo true || echo false)" "seeds CLAUDE.md"
assert_contains "$(cat "$GNEW/CLAUDE.md")" "harness-mini" "CLAUDE.md carries the routing gate"
assert_contains "$(cat "$GNEW/CLAUDE.md")" "stage-viewer" "CLAUDE.md gate routes through stage-viewer"
assert_eq "true" "$([ -f "$GNEW/.cursor/rules/harness-mini.mdc" ] && echo true || echo false)" "seeds .cursor/rules/harness-mini.mdc"
assert_contains "$(cat "$GNEW/.cursor/rules/harness-mini.mdc")" "alwaysApply: true" "cursor rule is always-applied"
# idempotent: re-run does not duplicate the marker-guarded block
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$GNEW" >/dev/null 2>&1
n=$(grep -cF 'harness-mini:start' "$GNEW/CLAUDE.md")
assert_eq "1" "$n" "re-run does not duplicate the CLAUDE.md gate block"
# additive: a pre-existing CLAUDE.md keeps its content; the gate is appended once
GEX="$(mktemp -d)"
printf 'MY MEMORY\n' > "$GEX/CLAUDE.md"
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$GEX" >/dev/null 2>&1
assert_contains "$(cat "$GEX/CLAUDE.md")" "MY MEMORY" "existing CLAUDE.md content is preserved"
assert_contains "$(cat "$GEX/CLAUDE.md")" "harness-mini:start" "gate is appended to an existing CLAUDE.md"
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$GEX" >/dev/null 2>&1
n=$(grep -cF 'harness-mini:start' "$GEX/CLAUDE.md")
assert_eq "1" "$n" "re-run appends the gate at most once"
rm -rf "$GSRC" "$GNEW" "$GEX"

# =============================================================================
echo "init.sh — mirrors each skill into .cursor/rules/ (#23; agent-requestable, additive/idempotent)"
CSRC="$(mktemp -d)"
mkdir -p "$CSRC/skills/tdd" "$CSRC/skills/no-fm" "$CSRC/agents" "$CSRC/bin" "$CSRC/docs"
printf -- '---\nname: tdd\ndescription: Test-first red-green-refactor loop.\n---\nbody\n' > "$CSRC/skills/tdd/SKILL.md"
printf 'no frontmatter here\n' > "$CSRC/skills/no-fm/SKILL.md"   # skill without a description
printf 'map\n' > "$CSRC/AGENTS.md"
CNEW="$(mktemp -d)"
HARNESS_SRC="$CSRC" bash "$ROOT/init.sh" "$CNEW" >/dev/null 2>&1
rule="$CNEW/.cursor/rules/tdd.mdc"
assert_eq "true" "$([ -f "$rule" ] && echo true || echo false)" "init emits .cursor/rules/<skill>.mdc per skill"
assert_contains "$(cat "$rule")" "alwaysApply: false" "skill rule is agent-requestable (alwaysApply:false)"
assert_contains "$(cat "$rule")" "Test-first red-green-refactor loop." "skill rule carries the skill's description"
assert_contains "$(cat "$rule")" ".claude/skills/tdd/SKILL.md" "skill rule points at the canonical SKILL.md"
# a skill without a description still gets a rule (falls back to its name)
assert_contains "$(cat "$CNEW/.cursor/rules/no-fm.mdc")" "harness-mini skill: no-fm" "description-less skill falls back to its name"
# the always-applied routing gate rule is distinct from the per-skill rules
assert_contains "$(cat "$CNEW/.cursor/rules/harness-mini.mdc")" "alwaysApply: true" "the routing gate rule stays always-applied"
# additive: a user edit to a generated skill rule survives a re-run
printf 'MY EDIT\n' > "$rule"
HARNESS_SRC="$CSRC" bash "$ROOT/init.sh" "$CNEW" >/dev/null 2>&1
assert_eq "MY EDIT" "$(cat "$rule")" "re-run never overwrites a user-edited skill rule"
rm -rf "$CSRC" "$CNEW"

# =============================================================================
echo "repo assets — parallel-slices skill exists and is mirrored to .claude/"
assert_eq "true" "$([ -f "$ROOT/skills/parallel-slices/SKILL.md" ] && echo true || echo false)" "parallel-slices skill source exists"
assert_eq "true" "$([ -f "$ROOT/.claude/skills/parallel-slices/SKILL.md" ] && echo true || echo false)" "parallel-slices skill is mirrored to .claude/skills/"

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
echo "version_newer — dependency-free semver compare"
vnew() { bash -c '. "$1"; version_newer "$2" "$3" && echo yes || echo no' _ "$BIN/_harness_lib.sh" "$1" "$2"; }
assert_eq "yes" "$(vnew 0.5.0 0.6.0)"  "version_newer: 0.6.0 > 0.5.0"
assert_eq "no"  "$(vnew 0.5.0 0.5.0)"  "version_newer: equal is not newer"
assert_eq "no"  "$(vnew 0.6.0 0.5.0)"  "version_newer: older is not newer"
assert_eq "yes" "$(vnew 0.9.0 0.10.0)" "version_newer: 0.10.0 > 0.9.0 (numeric, not lexical)"
assert_eq "yes" "$(vnew 0.5.0 0.5.1)"  "version_newer: patch bump is newer"
assert_eq "yes" "$(vnew v0.5.0 v1.0.0)" "version_newer: tolerates a leading v"
assert_eq "no"  "$(vnew '' 0.6.0)"     "version_newer: empty installed is not a trigger"

# =============================================================================
echo "update reminder — surfaced in version / status / doctor (HARNESS_LATEST injects)"
UDIR="$(mktemp -d)"; mkdir -p "$UDIR/harness" "$UDIR/.claude/skills/x" "$UDIR/docs/exec-plans/active"
printf 'version: 0.5.0\n' > "$UDIR/harness/harness.lock"
printf 'AGENTS\n' > "$UDIR/AGENTS.md"
printf 'x\n' > "$UDIR/.claude/skills/x/SKILL.md"   # so doctor has no unrelated FAIL
# version: newer latest -> reminder; equal -> up to date
out="$(HARNESS_ROOT="$UDIR" HARNESS_LATEST=0.6.0 bash "$HARN" version 2>&1)"
assert_contains "$out" "0.6.0" "version reminds when a newer release exists"
assert_contains "$out" "harness.sh update" "version points at the update command"
out="$(HARNESS_ROOT="$UDIR" HARNESS_LATEST=0.5.0 bash "$HARN" version 2>&1)"
assert_contains "$out" "up to date" "version says up to date when current"
# status: newer latest -> update line; offline (no inject) -> silent
out="$(HARNESS_ROOT="$UDIR" HARNESS_LATEST=0.6.0 bash "$HARN" status 2>&1)"
assert_contains "$out" "update: 0.6.0" "status surfaces an available update"
out="$(HARNESS_ROOT="$UDIR" bash "$HARN" status 2>&1)"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'update:')" "status is silent about updates when offline"
# doctor: behind latest -> WARN (exit 0, not a FAIL); current -> ok
out="$(HARNESS_ROOT="$UDIR" HARNESS_LATEST=0.6.0 bash "$HARN" doctor 2>&1)"; code=$?
assert_contains "$out" "0.6.0 available" "doctor warns when behind latest"
assert_exit 0 "$code" "doctor: behind-latest is a WARN, not a FAIL"
out="$(HARNESS_ROOT="$UDIR" HARNESS_LATEST=0.5.0 bash "$HARN" doctor 2>&1)"
assert_contains "$out" "up to date" "doctor reports up to date when current"
rm -rf "$UDIR"

# =============================================================================
echo "init.sh — writes harness/harness.lock (version + managed checksums)"
LSRC="$(mktemp -d)"
mkdir -p "$LSRC/skills" "$LSRC/agents" "$LSRC/bin" "$LSRC/docs" "$LSRC/skills/demo"
printf 'skill body\n' > "$LSRC/skills/five-step.md"
printf 'demo body\n'  > "$LSRC/skills/demo/SKILL.md"   # folder-form skill
printf 'agent body\n' > "$LSRC/agents/planner.md"
printf 'echo hi\n'    > "$LSRC/bin/ctx.sh"
printf 'map\n'        > "$LSRC/AGENTS.md"
printf '0.4.2\n'      > "$LSRC/VERSION"
LDEST="$(mktemp -d)"
HARNESS_SRC="$LSRC" bash "$ROOT/init.sh" "$LDEST" >/dev/null 2>&1
lock="$(cat "$LDEST/harness/harness.lock" 2>/dev/null)"
assert_contains "$lock" "version: 0.4.2" "lock records the source VERSION"
assert_contains "$lock" ".claude/skills/five-step.md" "lock lists a managed skill by target path"
assert_contains "$lock" ".claude/skills/demo/SKILL.md" "lock recurses folder-form skills (<name>/SKILL.md)"
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
UOLD="$(mktemp -d)"; mkdir -p "$UOLD/skills" "$UOLD/agents" "$UOLD/docs" "$UOLD/skills/fold"
printf 'keep-body\n'  > "$UOLD/skills/keep.md"
printf 'old-upd\n'    > "$UOLD/skills/upd.md"
printf 'old-edit\n'   > "$UOLD/skills/edit.md"
printf 'old-fold\n'   > "$UOLD/skills/fold/SKILL.md"   # folder-form skill, untouched by user
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
UNEW="$(mktemp -d)"; mkdir -p "$UNEW/skills" "$UNEW/agents" "$UNEW/docs" "$UNEW/skills/fold"
printf 'keep-body\n'  > "$UNEW/skills/keep.md"
printf 'NEW-upd\n'    > "$UNEW/skills/upd.md"
printf 'NEW-edit\n'   > "$UNEW/skills/edit.md"
printf 'brand-new\n'  > "$UNEW/skills/add.md"
printf 'NEW-fold\n'   > "$UNEW/skills/fold/SKILL.md"   # folder-form skill changed upstream
printf 'old-agents\n' > "$UNEW/AGENTS.md"
printf '0.2.0\n'      > "$UNEW/VERSION"
code=0; HARNESS_ROOT="$UDEST" HARNESS_NO_NET=1 bash "$HARN" update --src "$UNEW" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "update exits 0"
assert_eq "NEW-upd"   "$(cat "$UDEST/.claude/skills/upd.md")"       "UPDATE: untouched managed file is refreshed"
assert_eq "keep-body" "$(cat "$UDEST/.claude/skills/keep.md")"      "UNCHANGED: identical file stays"
assert_eq "USER-edit" "$(cat "$UDEST/.claude/skills/edit.md")"      "CONFLICT: user-edited file is preserved"
assert_eq "NEW-edit"  "$(cat "$UDEST/.claude/skills/edit.md.new" 2>/dev/null)" "CONFLICT: upstream written as .new"
assert_eq "brand-new" "$(cat "$UDEST/.claude/skills/add.md" 2>/dev/null)"      "ADD: new upstream file is installed"
assert_eq "NEW-fold"  "$(cat "$UDEST/.claude/skills/fold/SKILL.md" 2>/dev/null)" "UPDATE: nested folder-form skill is refreshed"
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
echo "harness.sh doctor — install health (3-severity, soft exit)"
DDIR="$(mktemp -d)"
bash "$ROOT/init.sh" "$DDIR" >/dev/null 2>&1          # a healthy fresh install
out="$(HARNESS_ROOT="$DDIR" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: healthy install exits 0"
assert_contains "$out" "ok" "doctor reports ok checks"
assert_contains "$out" "AGENTS.md" "doctor checks AGENTS.md"
# a .new file is a WARN, not a FAIL → still exit 0
touch "$DDIR/.claude/skills/tdd/SKILL.md.new"
out="$(HARNESS_ROOT="$DDIR" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: a .new file warns but does not fail"
assert_contains "$out" "warn" "doctor warns about unresolved .new"
# missing AGENTS.md is a hard FAIL → exit 1
rm -f "$DDIR/AGENTS.md"
code=0; HARNESS_ROOT="$DDIR" bash "$HARN" doctor >/dev/null 2>&1 || code=$?
assert_exit 1 "$code" "doctor: missing AGENTS.md is a FAIL (exit 1)"
rm -rf "$DDIR"
# source<->mirror divergence (#9): craft a dir with both trees
MDIR="$(mktemp -d)"; mkdir -p "$MDIR/skills/x" "$MDIR/.claude/skills/x" "$MDIR/harness"
printf 'AGENTS\n' > "$MDIR/AGENTS.md"; printf 'version: 0.0.0\n' > "$MDIR/harness/harness.lock"
printf 'same\n' > "$MDIR/skills/x/SKILL.md"; printf 'same\n' > "$MDIR/.claude/skills/x/SKILL.md"
out="$(HARNESS_ROOT="$MDIR" bash "$HARN" doctor 2>&1)"
assert_contains "$out" "mirror" "doctor: identical source/mirror reported ok"
printf 'DIVERGED\n' > "$MDIR/.claude/skills/x/SKILL.md"
out="$(HARNESS_ROOT="$MDIR" bash "$HARN" doctor 2>&1)"
assert_contains "$out" "diverge" "doctor: source/mirror divergence warns"
rm -rf "$MDIR"
# source repo (VERSION + skills/ but no lock) is healthy, not a missing-lock FAIL
PDIR="$(mktemp -d)"; mkdir -p "$PDIR/skills/x" "$PDIR/.claude/skills/x"
printf 'AGENTS\n' > "$PDIR/AGENTS.md"; printf '0.0.0\n' > "$PDIR/VERSION"
printf 'same\n' > "$PDIR/skills/x/SKILL.md"; printf 'same\n' > "$PDIR/.claude/skills/x/SKILL.md"
out="$(HARNESS_ROOT="$PDIR" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: source repo without a lock is not a FAIL"
assert_contains "$out" "source repo" "doctor recognizes the source repo (no lock needed)"
rm -rf "$PDIR"

# =============================================================================
echo "harness.sh status — current work state (grep/awk/tail only)"
SDIR="$(mktemp -d)"
bash "$ROOT/init.sh" "$SDIR" >/dev/null 2>&1          # lock + seeded active plan
splan="$(awk -F': *' '/^plan:/{print $2; exit}' "$SDIR"/docs/exec-plans/active/0001-*.md)"
mkdir -p "$SDIR/.trace/checkpoints"
printf -- '---\nplan: %s\nseq: 001\n---\n' "$splan" > "$SDIR/.trace/checkpoints/$splan-001.md"
HARNESS_TRACE_DIR="$SDIR/.trace/runtime" HARNESS_RUN="r-stat" \
  bash "$BIN/trace.sh" main implement test ctx_pct=42 >/dev/null 2>&1
out="$(HARNESS_ROOT="$SDIR" bash "$HARN" status 2>&1)"; code=$?
assert_exit 0 "$code" "status exits 0"
slv="$(awk -F': *' '/^version:/{print $2; exit}' "$SDIR/harness/harness.lock")"
assert_contains "$out" "$slv" "status shows the installed version"
assert_contains "$out" "$splan" "status lists the active plan"
assert_contains "$out" "ctx_pct=42" "status surfaces last ctx_pct from the trace tail"
assert_contains "$out" "resumable" "status reports resumability"
rm -rf "$SDIR"

# =============================================================================
echo "harness.sh status — garden trigger (cadence + smell backlog)"
GDIR="$(mktemp -d)"; mkdir -p "$GDIR/.trace/checkpoints" "$GDIR/harness"
printf 'version: 0.0.0\n' > "$GDIR/harness/harness.lock"
mkcp() { printf -- '---\nplan: p\nseq: %s\n---\n' "$1" > "$GDIR/.trace/checkpoints/p-$1.md"; }
# 5 committed checkpoints, no backlog yet -> DUE by cadence (default threshold 5)
for i in 001 002 003 004 005; do mkcp "$i"; done
out="$(HARNESS_ROOT="$GDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"; code=$?
assert_exit 0 "$code" "status exits 0 with garden block"
assert_contains "$out" "garden: DUE" "garden DUE at 5 checkpoints since last (cadence)"
assert_contains "$out" "5 checkpoint" "garden line counts checkpoints since last garden"
# stamp gardened-at to the current count -> since 0 -> ok
printf '# Garden backlog\n<!-- gardened-at: 5 -->\n\n## Open\n' > "$GDIR/.trace/garden-backlog.md"
out="$(HARNESS_ROOT="$GDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "garden: ok" "garden ok once gardened-at marks the current count"
# one HIGH-severity open item flips it DUE even with since=0
printf -- '- [ ] 2026-06-03 | a.ts:1 | long-fn | high | x\n' >> "$GDIR/.trace/garden-backlog.md"
out="$(HARNESS_ROOT="$GDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "garden: DUE" "garden DUE on a high-severity backlog item"
assert_contains "$out" "1 backlog item" "garden line counts open backlog items"
# 2 non-high items, gardened-at current -> under both thresholds -> ok
printf '# Garden backlog\n<!-- gardened-at: 5 -->\n\n## Open\n- [ ] d | b.ts:1 | dup | low | x\n- [ ] d | c.ts:1 | dup | med | y\n' > "$GDIR/.trace/garden-backlog.md"
out="$(HARNESS_ROOT="$GDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "garden: ok" "garden ok with <3 non-high items and no cadence overflow"
rm -rf "$GDIR"

# =============================================================================
echo "harness.sh report — aggregate .trace into a metrics summary (grep/awk only)"
RPT="$(mktemp -d)"; mkdir -p "$RPT/harness" "$RPT/.trace/runtime" "$RPT/.trace/checkpoints" "$RPT/.trace/evals"
printf 'version: 0.6.0\n' > "$RPT/harness/harness.lock"
# a runtime trace: two stage advances + ctx samples, one of which crosses 40%
{
  printf '{"ts":"t","run":"r-a","agent":"main","stage":"prd","event":"stage_advance"}\n'
  printf '{"ts":"t","run":"r-a","agent":"main","stage":"implement","event":"stage_advance","ctx_pct":22}\n'
  printf '{"ts":"t","run":"r-a","agent":"main","stage":"implement","event":"tool_post","ctx_pct":48}\n'
} > "$RPT/.trace/runtime/r-a.jsonl"
# durable eval records: one pass, one fail
printf -- '---\nplan: p\nseq: 001\ntier: L1\nverdict: pass\ncriteria: 3/3\n---\n' > "$RPT/.trace/evals/p-001.md"
printf -- '---\nplan: p\nseq: 002\ntier: L1\nverdict: fail\ncriteria: 2/3\n---\n' > "$RPT/.trace/evals/p-002.md"
printf -- '---\nplan: p\nseq: 001\n---\n' > "$RPT/.trace/checkpoints/p-001.md"
out="$(HARNESS_ROOT="$RPT" HARNESS_NO_NET=1 bash "$HARN" report 2>&1)"; code=$?
assert_exit 0 "$code" "report exits 0"
assert_contains "$out" "stage advance" "report counts stage advances"
assert_contains "$out" "48" "report surfaces the max ctx_pct sample"
assert_contains "$out" "over 40" "report counts context crossings of the 40% line"
assert_contains "$out" "1 pass" "report counts eval passes"
assert_contains "$out" "1 fail" "report counts eval fails (rework loops)"
assert_contains "$out" "checkpoint" "report counts checkpoints"
# scoping to a single run id still works
out="$(HARNESS_ROOT="$RPT" HARNESS_NO_NET=1 bash "$HARN" report r-a 2>&1)"; code=$?
assert_exit 0 "$code" "report <run> exits 0"
assert_contains "$out" "r-a" "report <run> names the scoped run"
rm -rf "$RPT"

# =============================================================================
echo "harness.sh doctor — eval-gate teeth (a done plan needs a passing eval record)"
EG="$(mktemp -d)"; mkdir -p "$EG/.claude/skills/x" "$EG/docs/exec-plans/active" "$EG/.trace/evals" "$EG/harness"
printf 'AGENTS\n' > "$EG/AGENTS.md"; printf 'version: 0.0.0\n' > "$EG/harness/harness.lock"
printf 'x\n' > "$EG/.claude/skills/x/SKILL.md"
# an active plan that reached `done` but has no evaluation on record -> FAIL
printf -- '---\nplan: shipit\nseq: 0001\nstage: done\n---\n' > "$EG/docs/exec-plans/active/0001-shipit.md"
out="$(HARNESS_ROOT="$EG" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 1 "$code" "doctor: done plan without a passing eval is a FAIL"
assert_contains "$out" "anti-self-praise" "doctor names the firewall it is enforcing"
# add a passing eval record -> the gate clears
printf -- '---\nplan: shipit\nseq: 001\ntier: L1\nverdict: pass\ncriteria: 2/2\n---\n' > "$EG/.trace/evals/shipit-001.md"
out="$(HARNESS_ROOT="$EG" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: done plan with a passing eval clears the gate"
assert_contains "$out" "evaluation on record" "doctor confirms the eval record"
rm -rf "$EG"

# =============================================================================
echo "ctx-hook.sh — heuristic context gauge for the Claude Code PostToolUse hook"
HK="$BIN/ctx-hook.sh"
HKT="$(mktemp -d)"
big="$HKT/big.jsonl"; head -c 4000 /dev/zero | tr '\0' x > "$big"   # ~4000 bytes -> ~1000 est tokens
# window 1000 -> est 1000/1000 = 100% -> over the 40% line: writes ctx_pct + warns
errf="$HKT/err"
out="$(printf '{"transcript_path":"%s"}' "$big" \
  | HARNESS_TRACE_DIR="$HKT/run" HARNESS_RUN="r-hook" HARNESS_CTX_WINDOW=1000 \
    bash "$HK" 2>"$errf")"; code=$?
assert_exit 0 "$code" "ctx-hook exits 0 (best-effort, never blocks the tool)"
line="$(cat "$HKT/run/r-hook.jsonl" 2>/dev/null)"
assert_contains "$line" '"ctx_pct":' "ctx-hook emits a ctx_pct trace event"
assert_contains "$(cat "$errf" 2>/dev/null)" "checkpoint" "ctx-hook nudges to checkpoint when over the line"
# a tiny transcript -> under the line -> traces but does not warn
small="$HKT/small.jsonl"; printf '{}\n' > "$small"; errf2="$HKT/err2"
printf '{"transcript_path":"%s"}' "$small" \
  | HARNESS_TRACE_DIR="$HKT/run2" HARNESS_RUN="r-hook2" HARNESS_CTX_WINDOW=1000 \
    bash "$HK" >/dev/null 2>"$errf2"
assert_eq "0" "$(grep -c checkpoint "$errf2" 2>/dev/null | tr -d ' ')" "ctx-hook stays quiet under the 40% line"
# missing/garbage payload still exits 0 (best-effort)
code=0; printf 'not json' | bash "$HK" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "ctx-hook never fails the caller on a bad payload"
rm -rf "$HKT"

# =============================================================================
echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
