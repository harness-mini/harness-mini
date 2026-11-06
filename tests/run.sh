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
unset HARNESS_ROOT
HARNESS_HOME="$(mktemp -d)"
export HARNESS_HOME

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
echo "central runtime — install executables outside projects and select project root"
RUNTIME_PROJECT="$(mktemp -d)"
HARNESS_SRC="$ROOT" bash "$ROOT/init.sh" "$RUNTIME_PROJECT" >/dev/null 2>&1
assert_eq "true" "$([ -x "$HARNESS_HOME/bin/harness.sh" ] && echo true || echo false)" "runtime harness.sh installs under HARNESS_HOME"
assert_eq "false" "$([ -e "$RUNTIME_PROJECT/bin" ] && echo true || echo false)" "fresh project install creates no bin directory"
assert_eq "true" "$([ -f "$HARNESS_HOME/harness/runtime.lock" ] && echo true || echo false)" "runtime gets its own lock"
runtime_lock="$(cat "$HARNESS_HOME/harness/runtime.lock" 2>/dev/null)"
project_lock="$(cat "$RUNTIME_PROJECT/harness/harness.lock" 2>/dev/null)"
assert_contains "$runtime_lock" "bin/harness.sh" "runtime lock tracks the centralized executable"
assert_contains "$runtime_lock" "version:" "runtime lock records the runtime version"
runtime_sha="$(printf '%s\n' "$runtime_lock" | awk '$2 == "bin/harness.sh" { print $1; exit }')"
source_sha="$(bash -c '. "$1"; cksum_file "$2"' _ "$ROOT/bin/_harness_lib.sh" "$ROOT/bin/harness.sh")"
installed_sha="$(bash -c '. "$1"; cksum_file "$2"' _ "$ROOT/bin/_harness_lib.sh" "$HARNESS_HOME/bin/harness.sh")"
assert_eq "$source_sha" "$runtime_sha" "runtime lock records the source executable checksum"
assert_eq "$installed_sha" "$runtime_sha" "runtime lock checksum matches the installed executable"
assert_eq "false" "$(printf '%s' "$project_lock" | grep -q 'bin/' && echo true || echo false)" "project lock excludes centralized executables"

# The same central executable must use the requested project's workboard, not
# its own installation directory or another project's state.
mkdir -p "$RUNTIME_PROJECT/docs/exec-plans/active"
printf '%s\n' '---' 'plan: project-a' 'stage: implement' '---' > "$RUNTIME_PROJECT/docs/exec-plans/active/project-a.md"
printf '%s\n' '{' '  "plan_id": "project-a",' '  "status": "in_progress",' '  "current_slice_id": "slice-a",' '  "slices": [{"id":"slice-a","passes":false}]' '}' > "$RUNTIME_PROJECT/docs/exec-plans/active/project-a.json"
PROJECT_B="$(mktemp -d)"
out="$(bash "$HARNESS_HOME/bin/harness.sh" --root "$RUNTIME_PROJECT" status 2>&1)"
assert_contains "$out" "project-a" "central status reads the explicitly selected project"
out="$(bash "$HARNESS_HOME/bin/harness.sh" --root "$PROJECT_B" status 2>&1)"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'project-a')" "central status does not leak another project's workboard"
assert_contains "$out" "path_reason: empty board" "central status uses the second project's root"
rm -rf "$PROJECT_B" "$RUNTIME_PROJECT"

# =============================================================================
echo "init.sh — additive, idempotent installer with new/existing asymmetry"
# Build a fake source tree so installer logic is tested independent of real assets.
FSRC="$(mktemp -d)"
mkdir -p "$FSRC/skills" "$FSRC/agents" "$FSRC/bin" "$FSRC/docs" "$FSRC/skills/demo/scripts"
printf 'skill body\n' > "$FSRC/skills/sample.md"
printf 'demo body\n'  > "$FSRC/skills/demo/SKILL.md"   # canonical folder-form skill
printf '#!/bin/sh\n' > "$FSRC/skills/demo/scripts/helper.sh"
printf 'agent body\n' > "$FSRC/agents/planner.md"
printf 'echo hi\n'    > "$FSRC/bin/ctx.sh"
printf 'map\n'        > "$FSRC/AGENTS.md"

# --- new (empty) project: generative bootstrap ---
NEW="$(mktemp -d)"
code=0; HARNESS_SRC="$FSRC" bash "$BIN/../init.sh" "$NEW" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "init succeeds on empty project"
assert_eq "true" "$([ -f "$NEW/.claude/skills/sample.md" ] && echo true || echo false)" "skills install to .claude/skills/"
assert_eq "true" "$([ -f "$NEW/.claude/skills/demo/SKILL.md" ] && echo true || echo false)" "folder-form skill installs to .claude/skills/<name>/SKILL.md"
assert_eq "true" "$([ -f "$NEW/.claude/skills/demo/scripts/helper.sh" ] && echo true || echo false)" "skill-owned scripts install recursively with their skill"
assert_eq "true" "$([ -f "$NEW/.claude/agents/planner.md" ] && echo true || echo false)" "agents install to .claude/agents/"
assert_eq "true" "$([ -f "$NEW/harness/manifest.md" ] && echo true || echo false)" "neutral harness/manifest.md mirror written"
assert_eq "true" "$([ -f "$NEW/.gitignore" ] && grep -q '.trace/runtime' "$NEW/.gitignore" && echo true || echo false)" "gitignore carries .trace/runtime"
plan="$(cat "$NEW"/docs/exec-plans/active/0001-*.md 2>/dev/null)"
assert_contains "$plan" "stage: intake" "new project seeds an intake-stage plan"
assert_contains "$plan" "founder-check" "new project plan points to founder-check funnel"
assert_eq "false" "$(printf '%s' "$plan" | grep -qi 'five-step' && echo true || echo false)" "new project funnel omits five-step"

# --- existing project: recon graft (no founder funnel) ---
EXIST="$(mktemp -d)"
printf '{}\n' > "$EXIST/package.json"   # marks it as an existing project
code=0; HARNESS_SRC="$FSRC" bash "$BIN/../init.sh" "$EXIST" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "init succeeds on existing project"
plan="$(cat "$EXIST"/docs/exec-plans/active/0001-*.md 2>/dev/null)"
assert_contains "$plan" "recon" "existing project seeds a recon plan"
assert_eq "false" "$(printf '%s' "$plan" | grep -q 'founder-check' && echo true || echo false)" "existing project skips founder funnel"
assert_eq "true" "$([ -f "$EXIST/.claude/skills/sample.md" ] && echo true || echo false)" "existing project still gets skills installed"

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
assert_contains "$(cat "$GNEW/CLAUDE.md")" "AGENTS.md" "CLAUDE.md gate points at the full map"
assert_eq "true" "$([ -f "$GNEW/.cursor/rules/harness-mini.mdc" ] && echo true || echo false)" "seeds .cursor/rules/harness-mini.mdc"
assert_contains "$(cat "$GNEW/.cursor/rules/harness-mini.mdc")" "alwaysApply: true" "cursor rule is always-applied"
assert_contains "$(cat "$GNEW/.cursor/rules/harness-mini.mdc")" "stage-viewer" "cursor rule routes through stage-viewer"
# idempotent: re-run does not duplicate the marker-guarded block
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$GNEW" >/dev/null 2>&1
n=$(grep -cF 'HARNESS_ROUTING_GATE_BEGIN' "$GNEW/CLAUDE.md")
assert_eq "1" "$n" "re-run does not duplicate the CLAUDE.md gate block"
# additive: a pre-existing CLAUDE.md keeps its content; the gate is appended once
GEX="$(mktemp -d)"
printf 'MY MEMORY\n' > "$GEX/CLAUDE.md"
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$GEX" >/dev/null 2>&1
assert_contains "$(cat "$GEX/CLAUDE.md")" "MY MEMORY" "existing CLAUDE.md content is preserved"
assert_contains "$(cat "$GEX/CLAUDE.md")" "HARNESS_ROUTING_GATE_BEGIN" "gate is appended to an existing CLAUDE.md"
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$GEX" >/dev/null 2>&1
n=$(grep -cF 'HARNESS_ROUTING_GATE_BEGIN' "$GEX/CLAUDE.md")
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
echo "repo assets — parallel-slices skill exists"
assert_eq "true" "$([ -f "$ROOT/skills/parallel-slices/SKILL.md" ] && echo true || echo false)" "parallel-slices skill source exists"

# =============================================================================
echo "tdd skill — one red→green cycle per acceptance criterion (#29)"
assert_contains "$(cat "$ROOT/skills/tdd/SKILL.md")" "One red→green cycle per acceptance criterion" "tdd source requires a failing test per acceptance criterion"

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
printf 'skill body\n' > "$LSRC/skills/sample.md"
printf 'demo body\n'  > "$LSRC/skills/demo/SKILL.md"   # folder-form skill
printf 'agent body\n' > "$LSRC/agents/planner.md"
printf 'echo hi\n'    > "$LSRC/bin/ctx.sh"
printf 'map\n'        > "$LSRC/AGENTS.md"
printf '0.4.2\n'      > "$LSRC/VERSION"
LDEST="$(mktemp -d)"
HARNESS_SRC="$LSRC" bash "$ROOT/init.sh" "$LDEST" >/dev/null 2>&1
lock="$(cat "$LDEST/harness/harness.lock" 2>/dev/null)"
assert_contains "$lock" "version: 0.4.2" "lock records the source VERSION"
assert_contains "$lock" ".claude/skills/sample.md" "lock lists a managed skill by target path"
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
echo "init.sh — routing gate v3 (path-aware, markers, idempotency, v1/v2 migration)"
GSRC="$(mktemp -d)"; mkdir -p "$GSRC/skills" "$GSRC/agents" "$GSRC/bin" "$GSRC/docs"
printf 'gate-skill\n' > "$GSRC/skills/sample.md"
printf 'agent\n'      > "$GSRC/agents/planner.md"
printf 'echo hi\n'    > "$GSRC/bin/ctx.sh"
printf 'map\n'        > "$GSRC/AGENTS.md"
# fresh install: markers + CRITICAL text + status-first + path branching
GDST="$(mktemp -d)"
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$GDST" >/dev/null 2>&1
gmc="$(cat "$GDST/CLAUDE.md" 2>/dev/null)"
assert_contains "$gmc" "HARNESS_ROUTING_GATE_BEGIN" "fresh install seeds the gate markers"
assert_contains "$gmc" "CRITICAL AGENT INSTRUCTION" "gate carries the CRITICAL instruction"
assert_contains "$gmc" "bin/harness.sh status" "gate is status-first"
assert_contains "$gmc" "path: init" "gate branches on path: init"
assert_contains "$gmc" "path: coding" "gate branches on path: coding"
assert_contains "$gmc" "session-init" "gate points at session-init"
assert_contains "$gmc" "session-coding" "gate points at session-coding"
assert_contains "$gmc" "Getting Bearings" "gate carries the one-line bearings pointer"
assert_contains "$gmc" "passes: false" "gate points at the next passes:false slice (coding branch)"
assert_contains "$gmc" "AGENTS.md" "gate points at the full map (AGENTS.md)"
# path-blind check: every instruction to pick a passes:false slice must sit in
# the coding branch (planning boards must not be pushed into product slices)
bad_pick="$(printf '%s' "$gmc" | grep 'passes: false' | grep -vc 'coding' || true)"
assert_eq "0" "$bad_pick" "slice-picking is conditioned on path: coding"
# idempotent: re-run leaves exactly one gate block
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$GDST" >/dev/null 2>&1
assert_eq "1" "$(grep -c 'HARNESS_ROUTING_GATE_BEGIN' "$GDST/CLAUDE.md")" "gate idempotent: still one block"
assert_contains "$(cat "$GDST/CLAUDE.md")" "session-coding" "re-run keeps the v3 content"
# cursor rule seeded, status-first, and path-aware
curs="$(cat "$GDST/.cursor/rules/harness-mini.mdc" 2>/dev/null)"
assert_contains "$curs" "bin/harness.sh status" "cursor rule is status-first"
assert_contains "$curs" "session-init" "cursor rule points at session-init"
assert_contains "$curs" "session-coding" "cursor rule points at session-coding"
assert_contains "$curs" "path" "cursor rule mentions the path branch"
rm -rf "$GDST"
# v1 migration: old marker block is replaced; user content survives
MDST="$(mktemp -d)"
printf '# my project memory\nkeep me\n' > "$MDST/CLAUDE.md"
printf '\n<!-- harness-mini:start -->\nv1 gate text\n<!-- harness-mini:end -->\n' >> "$MDST/CLAUDE.md"
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$MDST" >/dev/null 2>&1
mgmc="$(cat "$MDST/CLAUDE.md")"
assert_contains "$mgmc" "keep me" "v1 migration preserves user content"
assert_contains "$mgmc" "HARNESS_ROUTING_GATE_BEGIN" "v1 migration installs the v3 gate"
assert_eq "0" "$(grep -c 'harness-mini:start' "$MDST/CLAUDE.md")" "v1 migration removes the v1 block"
assert_eq "1" "$(grep -c 'HARNESS_ROUTING_GATE_BEGIN' "$MDST/CLAUDE.md")" "v1 migration leaves one gate block"
assert_contains "$mgmc" "session-coding" "v1 migration lands v3 content"
# migration is also idempotent
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$MDST" >/dev/null 2>&1
assert_eq "1" "$(grep -c 'HARNESS_ROUTING_GATE_BEGIN' "$MDST/CLAUDE.md")" "post-migration re-run stays one block"
assert_contains "$(cat "$MDST/CLAUDE.md")" "keep me" "post-migration re-run still keeps user content"
rm -rf "$MDST"
# v2 -> v3 migration: marked block with stale (path-blind) content is replaced
VDST="$(mktemp -d)"
printf '# my project memory\nkeep me\n' > "$VDST/CLAUDE.md"
{ printf '<!-- HARNESS_ROUTING_GATE_BEGIN -->\n[CRITICAL AGENT INSTRUCTION]\nYou are inside a project managed by harness-mini.\n\n1. Do NOT modify code directly before starting any task. You **MUST** first run the command: `bin/harness.sh status`\n2. Inspect the JSON plans under `docs/exec-plans/active/`, and select the highest-priority slice with `passes: false`.\n3. Follow the principle of progressive exposure strictly: only read code relevant to the current slice. Complete only one Slice per Session.\n4. Do NOT alter or delete the test conditions defined in `steps` inside JSON files.\n<!-- HARNESS_ROUTING_GATE_END -->\n'; } >> "$VDST/CLAUDE.md"
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$VDST" >/dev/null 2>&1
vgmc="$(cat "$VDST/CLAUDE.md")"
assert_contains "$vgmc" "keep me" "v2 migration preserves user content"
assert_eq "1" "$(grep -c 'HARNESS_ROUTING_GATE_BEGIN' "$VDST/CLAUDE.md")" "v2 migration leaves exactly one gate"
assert_contains "$vgmc" "session-init" "v2 migration lands v3 content (session-init)"
assert_contains "$vgmc" "session-coding" "v2 migration lands v3 content (session-coding)"
assert_eq "1" "$(grep -c 'CRITICAL AGENT INSTRUCTION' "$VDST/CLAUDE.md")" "v2 migration drops the stale CRITICAL block"
# v2 migration idempotent
HARNESS_SRC="$GSRC" bash "$ROOT/init.sh" "$VDST" >/dev/null 2>&1
assert_eq "1" "$(grep -c 'HARNESS_ROUTING_GATE_BEGIN' "$VDST/CLAUDE.md")" "v2-migrated re-run stays one block"
assert_contains "$(cat "$VDST/CLAUDE.md")" "keep me" "v2-migrated re-run keeps user content"
rm -rf "$VDST" "$GSRC"

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
echo "harness.sh update — project updates do not install centralized executables"
SOOLD="$(mktemp -d)"; SONEW="$(mktemp -d)"
for d in "$SOOLD" "$SONEW"; do
  mkdir -p "$d/bin" "$d/skills" "$d/agents" "$d/docs"
  printf 'agent\n'    > "$d/agents/planner.md"
  printf 'map\n'      > "$d/AGENTS.md"
done
# the OLD upstream carries the real (pre-fix) CLI so the self-replacement path
# actually executes; the NEW upstream shifts all code DOWN by a padded comment
# after the shebang — so when the running interpreter resumes the swapped file
# at its old byte offset it lands mid-code (crash bait; repro'd pre-fix).
cp "$ROOT/bin/harness.sh"      "$SOOLD/bin/harness.sh"
cp "$ROOT/bin/_harness_lib.sh" "$SOOLD/bin/_harness_lib.sh"
printf '0.1.0\n' > "$SOOLD/VERSION"
{ printf '#!/usr/bin/env bash\n'
  printf '# %.0s' $(seq 1 100); printf '\n'
  tail -n +2 "$ROOT/bin/harness.sh"
} > "$SONEW/bin/harness.sh"
cp "$ROOT/bin/_harness_lib.sh" "$SONEW/bin/_harness_lib.sh"
printf '0.2.0\n' > "$SONEW/VERSION"
SODST="$(mktemp -d)"
HARNESS_SRC="$SOOLD" bash "$ROOT/init.sh" "$SODST" >/dev/null 2>&1
upout="$(HARNESS_NO_NET=1 bash "$HARNESS_HOME/bin/harness.sh" --root "$SODST" update --src "$SONEW" 2>&1)"; code=$?
assert_exit 0 "$code" "project update accepts an explicit project root"
assert_eq "false" "$([ -e "$SODST/bin/harness.sh" ] && echo true || echo false)" "project update does not install a harness executable"
assert_eq "false" "$(printf '%s' "$upout" | grep -q 'update bin/harness.sh' && echo true || echo false)" "project update skips runtime executables"
assert_contains "$(cat "$SODST/harness/harness.lock")" "version: 0.2.0" "lock advanced by the self-updating run"
rm -rf "$SOOLD" "$SONEW" "$SODST"

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
echo "harness.sh status/doctor — JSON twin workboard (dual-file plans)"
WDIR="$(mktemp -d)"
bash "$ROOT/init.sh" "$WDIR" >/dev/null 2>&1   # seeds 0001-intake.md (mode: new)
WMD="$(ls "$WDIR"/docs/exec-plans/active/0001-*.md)"
WTWIN="${WMD%.md}.json"
# installs seed twins now (#64) — fabricate the legacy no-twin state explicitly
rm -f "$WTWIN"
# no twin yet -> status has no workboard line; doctor WARNs (never FAILs)
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"; code=$?
assert_exit 0 "$code" "status fine when a plan has no JSON twin"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'workboard:')" "status: no workboard line without a twin"
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: missing twin is a WARN, not a FAIL"
assert_contains "$out" "no JSON twin" "doctor warns about the missing twin"
# ragged-indentation twin: slice-001 passes, slice-002 next -> workboard line
cat > "$WTWIN" <<'EOF'
{
  "plan_id": "0001-intake",
    "title": "Intake — greenfield bootstrap",
  "status": "in_progress",
      "current_slice_id": "slice-002",
  "slices": [
    { "id": "slice-001", "category": "docs", "description": "d", "steps": ["s"], "passes": true },
 { "id": "slice-002", "category": "api", "description": "d", "steps": ["s"], "passes": false }
  ]
}
EOF
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "workboard: in_progress" "workboard shows the JSON status"
assert_contains "$out" "1/2 pass" "workboard counts passing slices"
assert_contains "$out" "current: slice-002" "workboard shows current_slice_id"
assert_contains "$out" "next: slice-002" "workboard names the next passes:false slice"
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: healthy twin adds no FAIL"
# all slices green -> next says so
sed 's/"passes": false/"passes": true/' "$WTWIN" > "$WTWIN.tmp" && mv "$WTWIN.tmp" "$WTWIN"
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "2/2 pass" "workboard counts all-green slices"
assert_contains "$out" "next: all green" "workboard: no next slice when all pass"
# garbage twin -> status must not crash; doctor warns unparseable
printf 'not json {{{\n' > "$WTWIN"
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"; code=$?
assert_exit 0 "$code" "status fine with an unparseable twin"
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"
assert_contains "$out" "unparseable" "doctor warns on an unparseable twin"
# plan_id-only twin (no status) is not readable either — same bar as status
printf '{ "plan_id": "0001-intake", "slices": [] }\n' > "$WTWIN"
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"
assert_contains "$out" "unparseable" "doctor warns on a twin without a status field"
rm -rf "$WDIR"

# =============================================================================
echo "harness.sh status — session path (path: init|coding + path_reason, #57)"
# fixture factory: <root> <slug> <stage> <twin: none|next|green|empty|garbage>
mkplan() {
  printf -- '---\nplan: %s\nseq: 0001\nstage: %s\nowner: main\n---\n# t\n' "$2" "$3" \
    > "$1/docs/exec-plans/active/$2.md"
  case "$4" in
    next)   printf '{ "plan_id": "%s", "status": "in_progress", "current_slice_id": "slice-002",\n  "slices": [ { "id": "slice-001", "passes": true }, { "id": "slice-002", "passes": false } ] }\n' "$2" > "$1/docs/exec-plans/active/$2.json" ;;
    green)  printf '{ "plan_id": "%s", "status": "in_progress", "slices": [ { "id": "slice-001", "passes": true } ] }\n' "$2" > "$1/docs/exec-plans/active/$2.json" ;;
    empty)  printf '{ "plan_id": "%s", "status": "planned", "slices": [] }\n' "$2" > "$1/docs/exec-plans/active/$2.json" ;;
    garbage) printf 'not json {{{\n' > "$1/docs/exec-plans/active/$2.json" ;;
  esac
}
mkboard() { local d; d="$(mktemp -d)"; mkdir -p "$d/harness" "$d/docs/exec-plans/active"; printf 'version: 0.0.0\n' > "$d/harness/harness.lock"; printf '%s' "$d"; }
# 1. empty board
PB="$(mkboard)"
out="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "path: init" "path: init on an empty board"
assert_contains "$out" "path_reason: empty board" "empty-board reason"
rm -rf "$PB"
# 2. planning stage (no twin needed)
PB="$(mkboard)"; mkplan "$PB" 0001-idea prd none
out="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "path: init" "path: init while still planning"
assert_contains "$out" "path_reason: still planning" "planning-stage reason"
rm -rf "$PB"
# 3. implement + next passes:false slice -> coding
PB="$(mkboard)"; mkplan "$PB" 0001-coder implement next
out="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "path: coding" "path: coding with a next slice"
assert_contains "$out" "path_reason: next slice ready" "next-slice reason"
rm -rf "$PB"
# 4. all slices green, plan not closed -> coding wrap-up
PB="$(mkboard)"; mkplan "$PB" 0001-doneish implement green
out="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "path: coding" "path: coding on all-green not closed"
assert_contains "$out" "path_reason: wrap-up" "wrap-up reason"
rm -rf "$PB"
# 5. missing twin at coding stage -> conservative init
PB="$(mkboard)"; mkplan "$PB" 0001-twinless implement none
out="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "path: init" "missing twin degrades to init"
assert_contains "$out" "path_reason: twin missing" "twin-missing reason"
rm -rf "$PB"
# 6. unparseable twin at coding stage -> conservative init
PB="$(mkboard)"; mkplan "$PB" 0001-badtwin implement garbage
out="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "path: init" "unparseable twin degrades to init"
assert_contains "$out" "path_reason: twin unparseable" "twin-unparseable reason"
rm -rf "$PB"
# 7. multi-plan priority: planning + coding-ready -> coding wins
PB="$(mkboard)"; mkplan "$PB" 0001-idea prd none; mkplan "$PB" 0002-coder implement next
out="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "path: coding" "coding-ready plan wins over a planning plan"
assert_contains "$out" "path_reason: next slice ready" "multi-plan picks the ready slice"
rm -rf "$PB"

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
echo "harness.sh status — readiness verdict (ready|warning|blocked) + plan-scoped resumable"
RDY="$(mktemp -d)"; mkdir -p "$RDY/.claude/skills/x" "$RDY/docs/exec-plans/active" \
  "$RDY/.trace/checkpoints" "$RDY/.trace/evals" "$RDY/harness"
printf 'AGENTS\n' > "$RDY/AGENTS.md"
printf 'version: 0.0.0\n' > "$RDY/harness/harness.lock"
printf 'x\n' > "$RDY/.claude/skills/x/SKILL.md"
# healthy install, active plan + matching checkpoint -> ready + resumable yes
printf -- '---\nplan: alpha\nseq: 0001\nstage: implement\n---\n## Now\n- ship slice one\n' \
  > "$RDY/docs/exec-plans/active/0001-alpha.md"
printf -- '---\nplan: alpha\nseq: 001\n---\n' > "$RDY/.trace/checkpoints/alpha-001.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"; code=$?
assert_exit 0 "$code" "status readiness: healthy exits 0"
assert_contains "$out" "ready: ready" "status readiness: ready when install+plan+cp ok"
assert_contains "$out" "ship slice one" "status readiness: next action from plan Now"
assert_contains "$out" "resumable: yes" "status readiness: plan-scoped checkpoint => resumable yes"
# foreign checkpoint alone must NOT make resumable yes (plan-scoped)
rm -f "$RDY/.trace/checkpoints/alpha-001.md"
printf -- '---\nplan: other\nseq: 001\n---\n' > "$RDY/.trace/checkpoints/other-001.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "resumable: partial" "status readiness: foreign checkpoint ignored"
assert_contains "$out" "ready: warning" "status readiness: partial resume => warning"
# no active plan => warning (not blocked), resumable no
rm -f "$RDY/docs/exec-plans/active/"*.md
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "ready: warning" "status readiness: no active plan => warning"
assert_contains "$out" "resumable: no" "status readiness: no plan => resumable no"
# install broken (no AGENTS.md) => blocked
rm -f "$RDY/AGENTS.md"
printf -- '---\nplan: alpha\nseq: 0001\nstage: implement\n---\n' \
  > "$RDY/docs/exec-plans/active/0001-alpha.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "ready: blocked" "status readiness: missing AGENTS.md => blocked"
# restore AGENTS; done without eval => blocked
printf 'AGENTS\n' > "$RDY/AGENTS.md"
printf -- '---\nplan: shipit\nseq: 0001\nstage: done\n---\n' \
  > "$RDY/docs/exec-plans/active/0001-shipit.md"
rm -f "$RDY/docs/exec-plans/active/0001-alpha.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "ready: blocked" "status readiness: done without eval => blocked"
assert_contains "$out" "evaluate" "status readiness: blocked next-action mentions evaluate"
# passing eval clears the done-gate block (garden/update quiet) -> ready
printf -- '---\nplan: shipit\nseq: 001\ntier: L1\nverdict: pass\n---\n' \
  > "$RDY/.trace/evals/shipit-001.md"
printf -- '---\nplan: shipit\nseq: 001\n---\n' > "$RDY/.trace/checkpoints/shipit-001.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "ready: ready" "status readiness: done+pass eval => ready"
rm -rf "$RDY"

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
echo "ctx-hook.sh — heuristic context gauge for the PostToolUse hook"
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
echo "source repo — AGENTS.md gate contract (one gate, status-first)"
am="$ROOT/AGENTS.md"
assert_contains "$(cat "$am")" "MUST FIRST** run \`bin/harness.sh status\`" "AGENTS.md gate is status-first (mandatory)"
assert_eq "1" "$(grep -ic '^## .*routing gate' "$am")" "AGENTS.md has exactly one routing-gate section"
assert_eq "0" "$(grep -c 'harness.sh version' "$am")" "AGENTS.md gate no longer says version-first"
assert_contains "$(cat "$am")" "Do NOT load the full historical" "AGENTS.md map forbids loading full plan history"
assert_contains "$(cat "$am")" "current_slice_id" "AGENTS.md documents the JSON twin fields"
assert_contains "$(cat "$am")" "session-init" "AGENTS.md gate points at session-init"
assert_contains "$(cat "$am")" "session-coding" "AGENTS.md gate points at session-coding"
ambad="$(printf '%s' "$(cat "$am")" | grep 'passes: false' | grep -vc 'coding' || true)"
assert_eq "0" "$ambad" "AGENTS.md conditions slice-picking on path: coding"

# =============================================================================
echo "source repo — session-init skill (#58: plan-layer playbook, no product code)"
si="$ROOT/skills/session-init/SKILL.md"
assert_eq "true" "$([ -f "$si" ] && echo true || echo false)" "skills/session-init/SKILL.md exists"
sib="$(cat "$si" 2>/dev/null)"
assert_contains "$sib" "path: init" "skill opens by confirming path: init from status"
assert_contains "$sib" "bin/harness.sh status" "skill names the status command"
assert_contains "$sib" "product code" "skill bans product-code edits explicitly"
assert_contains "$sib" "founder-check" "greenfield branch composes founder-check"
assert_contains "$sib" "to-prd" "skill composes to-prd"
assert_contains "$sib" "to-issues" "skill composes to-issues (emits the JSON twin)"
assert_contains "$sib" "checkpoint" "skill ends with a checkpoint"
assert_contains "$sib" "write ban" "skill references the plan-stage write ban"
# the skill must NOT give the builder a way to flip passes (anti-self-praise)
assert_eq "0" "$(printf '%s' "$sib" | grep -c 'flip.*passes.*true\|set.*passes.*true')" "skill never instructs flipping passes to true"
assert_contains "$sib" "stage-viewer" "stage authority stays with stage-viewer"
assert_contains "$(cat "$am")" "session-init" "AGENTS.md skills list mentions session-init"

# =============================================================================
echo "source repo — session-coding skill + Getting Bearings (#59)"
sc="$ROOT/skills/session-coding/SKILL.md"
assert_eq "true" "$([ -f "$sc" ] && echo true || echo false)" "skills/session-coding/SKILL.md exists"
scb="$(cat "$sc" 2>/dev/null)"
first_sec="$(printf '%s' "$scb" | grep -m1 '^## ' )"
assert_contains "$first_sec" "Getting Bearings" "first section is the mandatory Getting Bearings"
assert_contains "$scb" "pwd" "bearings step 1: pwd / project root"
assert_contains "$scb" "git log --oneline -5" "bearings step 2: git log -5"
assert_contains "$scb" "bin/harness.sh status" "bearings step 2: status"
assert_contains "$scb" "latest checkpoint" "bearings step 2: latest checkpoint"
assert_contains "$scb" 'passes": false' "bearings step 3: select the passes:false slice"
assert_contains "$scb" "baseline" "bearings step 4: app baseline green"
assert_contains "$scb" "init.sh" "bearings step 4 names init.sh (to forbid it)"
assert_contains "$scb" "installer" "bearings step 4 calls init.sh the harness installer"
assert_contains "$scb" "regression" "bearings step 4: stop on baseline regression"
assert_contains "$scb" "selected slice" "bearings step 5: tell the user the selected slice"
# bans + after-bearings contract
assert_contains "$scb" "one slice" "one slice per session"
assert_contains "$scb" "steps" "skill references JSON steps as test conditions"
assert_eq "0" "$(printf '%s' "$scb" | grep -c 'flip.*passes.*true\|set.*passes.*true')" "skill never instructs flipping passes to true"
assert_contains "$scb" "stage-viewer" "pass authority stays with stage-viewer"
assert_contains "$scb" "completed/" "skill bans loading completed/ history"
assert_contains "$scb" "tdd" "after-bearings composes tdd"
assert_contains "$scb" "evaluate" "after-bearings routes through evaluate"
assert_contains "$scb" "checkpoint" "session ends with a checkpoint"
assert_contains "$scb" "path: coding" "skill confirms path: coding from status"
assert_contains "$(cat "$am")" "session-coding" "AGENTS.md skills list mentions session-coding"

# =============================================================================
echo "bin/session.sh — Outer session runner (P2, #61)"
# mkboard/mkplan are defined in the session-path group above and reused here.
SESS="$BIN/session.sh"
# both skills installed in every fixture board, so selection is purely
# path-driven — the runner must pick the right one, not just find one
mkskills() { # <root>
  for s in session-init session-coding; do
    mkdir -p "$1/.claude/skills/$s"
    cp "$ROOT/skills/$s/SKILL.md" "$1/.claude/skills/$s/SKILL.md"
  done
}
# coding board -> session-coding body injected
RB="$(mkboard)"; mkplan "$RB" 0001-coder implement next; mkskills "$RB"
out="$(HARNESS_ROOT="$RB" HARNESS_NO_NET=1 bash "$SESS" 2>&1)"; code=$?
assert_exit 0 "$code" "runner exits 0 on a coding board"
assert_contains "$out" "Getting Bearings" "coding board injects session-coding body"
assert_contains "$out" "bin/harness.sh status" "injected body still runs status first"
assert_contains "$out" "path: coding" "wrapper states the session path"
# init board -> session-init body injected (never bearings)
RB2="$(mkboard)"; mkplan "$RB2" 0001-idea prd none; mkskills "$RB2"
out2="$(HARNESS_ROOT="$RB2" HARNESS_NO_NET=1 bash "$SESS" 2>&1)"; code=$?
assert_exit 0 "$code" "runner exits 0 on an init board"
assert_contains "$out2" "plan session" "init board injects session-init body"
assert_eq "0" "$(printf '%s' "$out2" | grep -c 'Getting Bearings')" "init board never gets coding bearings"
# -- host-command mode: message passed as the final argument
out3="$(HARNESS_ROOT="$RB" HARNESS_NO_NET=1 bash "$SESS" -- /bin/echo 2>&1)"; code=$?
assert_exit 0 "$code" "runner -- mode exits 0"
assert_eq "$out" "$out3" "-- mode delivers the same message as stdout mode"
# fresh context: the runner persists nothing on the board
n_before=$(find "$RB2" -type f | wc -l | tr -d ' ')
HARNESS_ROOT="$RB2" HARNESS_NO_NET=1 bash "$SESS" >/dev/null 2>&1
n_after=$(find "$RB2" -type f | wc -l | tr -d ' ')
assert_eq "$n_before" "$n_after" "runner writes no files (fresh context per session)"
# vendor-neutral kernel: no vendor CLI invocation, no host hook mechanism.
# (.claude/skills is the harness's own install-layout path, not a vendor name.)
assert_eq "0" "$(grep -vE '\.claude/' "$SESS" | grep -ciE 'claude|cursor|codex')" "script invokes no vendor CLI"
assert_eq "0" "$(grep -ci 'sessionstart' "$SESS")" "script depends on no session-start hooks"
rm -rf "$RB" "$RB2"
echo "init.sh — seed guard: never seed when any active plan exists (#63)"
SGSRC="$(mktemp -d)"; mkdir -p "$SGSRC/skills" "$SGSRC/agents" "$SGSRC/bin" "$SGSRC/docs"
printf 'skill\n' > "$SGSRC/skills/sample.md"
printf 'agent\n'  > "$SGSRC/agents/planner.md"
printf 'echo hi\n' > "$SGSRC/bin/ctx.sh"
printf 'map\n'     > "$SGSRC/AGENTS.md"
SGD="$(mktemp -d)"
HARNESS_SRC="$SGSRC" bash "$ROOT/init.sh" "$SGD" >/dev/null 2>&1
assert_eq "true" "$([ -f "$SGD/docs/exec-plans/active/0001-intake.md" ] && echo true || echo false)" "empty board still seeds the intake plan"
# user-owned, differently numbered board: remove the seed, add 0009-oldthing
rm -f "$SGD/docs/exec-plans/active/0001-intake.md"
printf -- '---\nplan: oldthing\nseq: 0009\nstage: implement\nowner: main\n---\n# Old\n' \
  > "$SGD/docs/exec-plans/active/0009-oldthing.md"
HARNESS_SRC="$SGSRC" bash "$ROOT/init.sh" "$SGD" >/dev/null 2>&1
assert_eq "0" "$(ls "$SGD"/docs/exec-plans/active/0001-*.md 2>/dev/null | wc -l | tr -d ' ')" "no spurious 0001 seed beside a non-0001 active plan"
assert_eq "true" "$([ -f "$SGD/docs/exec-plans/active/0009-oldthing.md" ] && echo true || echo false)" "user plan untouched by re-run"
rm -rf "$SGD"
# existing-project mode still seeds recon
SGE="$(mktemp -d)"; printf '{"name":"x"}\n' > "$SGE/package.json"
HARNESS_SRC="$SGSRC" bash "$ROOT/init.sh" "$SGE" >/dev/null 2>&1
assert_eq "true" "$([ -f "$SGE/docs/exec-plans/active/0001-recon.md" ] && echo true || echo false)" "existing-project install seeds the recon plan"
rm -rf "$SGE" "$SGSRC"

# =============================================================================
echo "init.sh — seed plans carry their JSON twin (#64)"
TWSRC="$(mktemp -d)"; mkdir -p "$TWSRC/skills" "$TWSRC/agents" "$TWSRC/bin" "$TWSRC/docs"
printf 'skill\n' > "$TWSRC/skills/sample.md"
printf 'agent\n'  > "$TWSRC/agents/planner.md"
printf 'echo hi\n' > "$TWSRC/bin/ctx.sh"
printf 'map\n'     > "$TWSRC/AGENTS.md"
TW1="$(mktemp -d)"
HARNESS_SRC="$TWSRC" bash "$ROOT/init.sh" "$TW1" >/dev/null 2>&1
assert_eq "true" "$([ -f "$TW1/docs/exec-plans/active/0001-intake.json" ] && echo true || echo false)" "intake seed has its JSON twin"
out="$(HARNESS_ROOT="$TW1" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'no JSON twin')" "new-mode install: doctor has no twin warning"
out="$(HARNESS_ROOT="$TW1" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "workboard: planned" "new-mode install: status shows the seed workboard"
assert_contains "$out" "no slices yet" "seed workboard renders the no-slices line"
rm -rf "$TW1"
TW2="$(mktemp -d)"; printf '{"name":"x"}\n' > "$TW2/package.json"
HARNESS_SRC="$TWSRC" bash "$ROOT/init.sh" "$TW2" >/dev/null 2>&1
assert_eq "true" "$([ -f "$TW2/docs/exec-plans/active/0001-recon.json" ] && echo true || echo false)" "recon seed has its JSON twin"
out="$(HARNESS_ROOT="$TW2" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'no JSON twin')" "existing-mode install: doctor has no twin warning"
out="$(HARNESS_ROOT="$TW2" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "workboard: planned" "existing-mode install: status shows the seed workboard"
rm -rf "$TW2" "$TWSRC"

# =============================================================================
# checkpoint-hardening — slice-001: checkpoint-lint.sh
# Tests written RED (before implementation). Discussion #75 / plan 0001.
echo "checkpoint-lint.sh — validate Footprint entries enforce file:start-end::STATUS"
CHECKPOINT_SCRIPTS="$ROOT/skills/checkpoint/scripts"
LINT="$CHECKPOINT_SCRIPTS/checkpoint-lint.sh"
assert_eq "true" "$([ -f "$LINT" ] && echo true || echo false)" "checkpoint lint helper is skill-owned"
assert_eq "false" "$([ -e "$BIN/checkpoint-lint.sh" ] && echo true || echo false)" "checkpoint lint helper is absent from shared bin"
TMPL="$(mktemp -d)"

# helper: write a checkpoint with arbitrary Footprint block content.
# Uses cat + heredoc-free technique to avoid printf '---' flag interpretation.
write_cp() {  # <file> <footprint_lines_or_"none">
  local f="$1" fp="$2"
  {
    printf '%s\n' "---"
    printf '%s\n' "plan: test"
    printf '%s\n' "seq: 1"
    printf '%s\n' "---"
    printf '%s\n' "## Task state"
    printf '%s\n' "- Footprint: $fp"
    printf '%s\n' "- Last green: none"
    printf '%s\n' "- Open issues: none"
  } > "$f"
}

write_cp_block() {  # <file> <indented footprint entry line>
  local f="$1" entry="$2"
  {
    printf '%s\n' "---"
    printf '%s\n' "plan: test"
    printf '%s\n' "seq: 1"
    printf '%s\n' "---"
    printf '%s\n' "## Task state"
    printf '%s\n' "- Footprint:"
    printf '%s\n' "  - $entry"
    printf '%s\n' "- Last green: none"
    printf '%s\n' "- Open issues: none"
  } > "$f"
}

# clean — no Footprint entries at all (field value on the same line = "none")
write_cp "$TMPL/cp1.md" "none"
code=0; bash "$LINT" "$TMPL/cp1.md" 2>/dev/null || code=$?
assert_exit 0 "$code" "lint: none footprint exits 0"

# clean — blank (all-whitespace) Footprint placeholder
write_cp "$TMPL/cp2.md" ""
code=0; bash "$LINT" "$TMPL/cp2.md" 2>/dev/null || code=$?
assert_exit 0 "$code" "lint: empty Footprint field exits 0"

# clean — valid WIP entry
write_cp_block "$TMPL/cp3.md" "src/api.py:45-80::WIP"
code=0; bash "$LINT" "$TMPL/cp3.md" 2>/dev/null || code=$?
assert_exit 0 "$code" "lint: valid WIP entry exits 0"

# clean — valid DONE entry
write_cp_block "$TMPL/cp4.md" "bin/harness.sh:1-20::DONE"
code=0; bash "$LINT" "$TMPL/cp4.md" 2>/dev/null || code=$?
assert_exit 0 "$code" "lint: valid DONE entry exits 0"

# clean — valid REVIEW entry
write_cp_block "$TMPL/cp5.md" "lib/util.js:1-5::REVIEW"
code=0; bash "$LINT" "$TMPL/cp5.md" 2>/dev/null || code=$?
assert_exit 0 "$code" "lint: valid REVIEW entry exits 0"

# violation — prose instead of notation
write_cp_block "$TMPL/cp6.md" "I changed server/api.py around line 45 to fix rate limiting"
code=0; err="$(bash "$LINT" "$TMPL/cp6.md" 2>&1)"; code=$?
assert_exit 1 "$code" "lint: prose footprint exits 1"
assert_contains "$err" "LINT" "lint: prose violation prints LINT message"

# violation — missing :: delimiter
write_cp_block "$TMPL/cp7.md" "src/api.py:45-80:WIP"
code=0; bash "$LINT" "$TMPL/cp7.md" 2>/dev/null || code=$?
assert_exit 1 "$code" "lint: missing :: delimiter exits 1"

# violation — unknown STATUS token
write_cp_block "$TMPL/cp8.md" "src/api.py:45-80::FIXME"
code=0; bash "$LINT" "$TMPL/cp8.md" 2>/dev/null || code=$?
assert_exit 1 "$code" "lint: unknown STATUS token exits 1"

# usage: no args → usage error
code=0; bash "$LINT" 2>/dev/null || code=$?
assert_exit 1 "$code" "lint: no args exits 1 (usage)"

# best-effort: missing file → exits 1 gracefully
code=0; bash "$LINT" /tmp/nonexistent-cp-file-xyz.md 2>/dev/null || code=$?
assert_exit 1 "$code" "lint: missing file exits 1"

rm -rf "$TMPL"

# =============================================================================
# checkpoint-hardening — slice-002: checkpoint-snapshot.sh
echo "checkpoint-snapshot.sh — deterministic line-range snapshot with boundary defense"
SNAP="$CHECKPOINT_SCRIPTS/checkpoint-snapshot.sh"
assert_eq "true" "$([ -f "$SNAP" ] && echo true || echo false)" "checkpoint snapshot helper is skill-owned"
assert_eq "false" "$([ -e "$BIN/checkpoint-snapshot.sh" ] && echo true || echo false)" "checkpoint snapshot helper is absent from shared bin"
TMPS="$(mktemp -d)"

# usage: no args → exits 1
code=0; bash "$SNAP" 2>/dev/null || code=$?
assert_exit 1 "$code" "snapshot: no args exits 1 (usage)"

# missing file → exits 1 with error
code=0; err="$(bash "$SNAP" "no_such_file.py:1-5::WIP" 2>&1)"; code=$?
assert_exit 1 "$code" "snapshot: missing file exits 1"
assert_contains "$err" "not found" "snapshot: missing file prints 'not found'"

# out-of-bounds range → exits 1 with error
src="$TMPS/small.py"
printf 'line1\nline2\nline3\n' > "$src"
code=0; err="$(bash "$SNAP" "${src}:1-10::WIP" 2>&1)"; code=$?
assert_exit 1 "$code" "snapshot: out-of-bounds range exits 1"
assert_contains "$err" "out of bounds" "snapshot: out-of-bounds prints 'out of bounds'"

# valid range → exits 0, writes snapshot
# valid range → exits 0, writes snapshot
src2="$TMPS/api.py"
printf 'line1\nline2\nline3\nline4\nline5\n' > "$src2"
out="$(HARNESS_TRACE_DIR="$TMPS/trace" bash "$SNAP" "${src2}:2-4::WIP" 2>/dev/null)"; code=$?
assert_exit 0 "$code" "snapshot: valid range exits 0"
assert_contains "$out" ".txt" "snapshot: prints path to snapshot file"
[ -f "$out" ] && snap_content="$(cat "$out")" || snap_content=""
assert_eq "line2
line3
line4" "$snap_content" "snapshot: content matches exact lines 2-4"

# deterministic path: same input → same output path
out2="$(HARNESS_TRACE_DIR="$TMPS/trace" bash "$SNAP" "${src2}:2-4::WIP" 2>/dev/null)"
assert_eq "$out" "$out2" "snapshot: same input produces same output path (deterministic)"

# single-line range (start == end)
src3="$TMPS/util.sh"
printf 'alpha\nbeta\ngamma\n' > "$src3"
HARNESS_TRACE_DIR="$TMPS/trace" out3="$(bash "$SNAP" "${src3}:2-2::DONE" 2>/dev/null)"; code=$?
assert_exit 0 "$code" "snapshot: single-line range exits 0"
assert_eq "beta" "$(cat "$out3")" "snapshot: single-line snapshot content correct"

rm -rf "$TMPS"

# =============================================================================
# checkpoint-hardening — slice-003: checkpoint-guard.sh
echo "checkpoint-guard.sh — suppress no-op checkpoints when nothing changed"
GUARD="$CHECKPOINT_SCRIPTS/checkpoint-guard.sh"
assert_eq "true" "$([ -f "$GUARD" ] && echo true || echo false)" "checkpoint guard helper is skill-owned"
assert_eq "false" "$([ -e "$BIN/checkpoint-guard.sh" ] && echo true || echo false)" "checkpoint guard helper is absent from shared bin"
TMPG="$(mktemp -d)"

# no previous checkpoint + no git → proceed (exit 0)
code=0
HARNESS_CHECKPOINT_DIR="$TMPG/checkpoints" HARNESS_ROOT="$TMPG" \
  bash "$GUARD" 2>/dev/null || code=$?
assert_exit 0 "$code" "guard: no prior checkpoint → proceed (exit 0)"

# set up a fake git repo for changed-file tests
GR="$TMPG/repo"
mkdir -p "$GR/.trace/checkpoints"
git -C "$GR" init -q
git -C "$GR" config user.email "test@test"
git -C "$GR" config user.name "Test"
printf 'initial\n' > "$GR/file.txt"
git -C "$GR" add file.txt
git -C "$GR" commit -q -m "init"
# write a fake checkpoint so the guard has something to compare against
{ printf '%s\n' "---"; printf '%s\n' "plan: test"; printf '%s\n' "seq: 1"; printf '%s\n' "---"; } > "$GR/.trace/checkpoints/test-001.md"

# no changes since last checkpoint → suppress (exit 1)
code=0; msg="$(HARNESS_ROOT="$GR" bash "$GUARD" 2>&1)"; code=$?
assert_exit 1 "$code" "guard: no file changes → suppress (exit 1)"
assert_contains "$msg" "suppress" "guard: suppression prints 'suppress' message"

# working-tree change → proceed (exit 0)
printf 'modified\n' >> "$GR/file.txt"
code=0
HARNESS_ROOT="$GR" bash "$GUARD" 2>/dev/null || code=$?
assert_exit 0 "$code" "guard: working-tree change → proceed (exit 0)"

# staged change (clean working tree) → proceed (exit 0)
git -C "$GR" checkout -- file.txt  # restore working tree
git -C "$GR" add file.txt          # stage it (re-adding same file is a no-op diff-wise, so use a new file)
printf 'staged\n' > "$GR/staged.txt"
git -C "$GR" add "$GR/staged.txt"
code=0
HARNESS_ROOT="$GR" bash "$GUARD" 2>/dev/null || code=$?
assert_exit 0 "$code" "guard: staged change → proceed (exit 0)"

# installed skill path: infer the project root from the nearest bin/harness.sh
IR="$TMPG/installed"
mkdir -p "$IR/bin" "$IR/.claude/skills/checkpoint/scripts" "$IR/.trace/checkpoints"
printf '# harness entry\n' > "$IR/bin/harness.sh"
cp "$GUARD" "$IR/.claude/skills/checkpoint/scripts/checkpoint-guard.sh"
git -C "$IR" init -q
git -C "$IR" config user.email "test@test"
git -C "$IR" config user.name "Test"
git -C "$IR" add bin/harness.sh .claude/skills/checkpoint/scripts/checkpoint-guard.sh
git -C "$IR" commit -q -m "init"
{ printf '%s\n' "---" "plan: test" "seq: 1" "---"; } > "$IR/.trace/checkpoints/test-001.md"
code=0; msg="$(cd "$IR" && bash .claude/skills/checkpoint/scripts/checkpoint-guard.sh 2>&1)" || code=$?
assert_exit 1 "$code" "guard: installed skill discovers project root and suppresses clean checkpoint"
assert_contains "$msg" "suppress" "guard: installed skill root discovery checks project git state"

rm -rf "$TMPG"

# =============================================================================
# checkpoint-hardening — slice-004: ctx-hook.sh last-green extension
echo "ctx-hook.sh — auto-stamp last-green.txt when HARNESS_TEST_SCRIPT passes"
HOOK="$BIN/ctx-hook.sh"
TMPH="$(mktemp -d)"

# passing test script → stamps last-green.txt
pass_script="$TMPH/pass.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$pass_script"; chmod +x "$pass_script"
HARNESS_TEST_SCRIPT="$pass_script" HARNESS_TRACE_DIR="$TMPH/trace" \
  bash "$HOOK" </dev/null >/dev/null 2>/dev/null
lg="$TMPH/trace/last-green.txt"
assert_eq "true" "$([ -f "$lg" ] && echo true || echo false)" "ctx-hook: passing tests create last-green.txt"
lg_content="$(cat "$lg" 2>/dev/null)"
assert_contains "$lg_content" "rev=" "ctx-hook: last-green.txt contains rev= field"

# failing test script → no last-green.txt (or existing one unchanged)
rm -f "$lg"
fail_script="$TMPH/fail.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fail_script"; chmod +x "$fail_script"
HARNESS_TEST_SCRIPT="$fail_script" HARNESS_TRACE_DIR="$TMPH/trace" \
  bash "$HOOK" </dev/null >/dev/null 2>/dev/null
assert_eq "false" "$([ -f "$lg" ] && echo true || echo false)" "ctx-hook: failing tests do not create last-green.txt"

# HARNESS_TEST_SCRIPT unset → no last-green.txt created, hook still exits 0
code=0
HARNESS_TRACE_DIR="$TMPH/trace2" bash "$HOOK" </dev/null >/dev/null 2>/dev/null || code=$?
assert_exit 0 "$code" "ctx-hook: unset HARNESS_TEST_SCRIPT exits 0 (best-effort)"
assert_eq "false" "$([ -f "$TMPH/trace2/last-green.txt" ] && echo true || echo false)" \
  "ctx-hook: no last-green.txt when HARNESS_TEST_SCRIPT unset"

# hook always exits 0 — even when test script missing
HARNESS_TEST_SCRIPT="/tmp/no_such_script_xyz.sh" HARNESS_TRACE_DIR="$TMPH/trace3" \
  bash "$HOOK" </dev/null >/dev/null 2>/dev/null
assert_exit 0 "$?" "ctx-hook: missing test script still exits 0 (best-effort)"

rm -rf "$TMPH"
rm -rf "$HARNESS_HOME"

# =============================================================================
echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
