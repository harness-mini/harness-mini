#!/usr/bin/env bash
# Zero-dependency test runner for harness-mini bin/ scripts.
# Usage: bash tests/run.sh [<group>...|--list]   (no args: full suite)
# TDD: these tests are written before (or alongside) the implementation.
set -u

# --- group selection (0063): tests/run.sh [<group>...|--list] ----------------
# Sections carry a `# @group <name>` tag under their banner; a group extends
# over following untagged banner blocks (merged fixture clusters). No
# arguments runs the file below unchanged. Group arguments run only those
# sections, in file order, evaluated in this shell so the PASS/FAIL counters,
# helper functions and HARNESS_HOME carry over. --list prints every group
# with the assert count it will execute, derived statically from this file
# (call sites expanded by literal for-loops and local fixture functions).
RUNNER_SCRIPT="$0"

print_group_usage() {
  printf 'usage: bash tests/run.sh              run the full suite (default)\n' >&2
  printf '       bash tests/run.sh <group>...   run only these groups, in file order\n' >&2
  printf '       bash tests/run.sh --list       list groups with assert counts\n' >&2
}

init_group_index() {
  GROUP_NAMES=(); GROUP_STARTS=(); GROUP_ENDS=()
  local ban_line=() ban_tag=() n=0 i j b next lt total_lines
  total_lines=$(wc -l < "$RUNNER_SCRIPT" | tr -d ' ')
  for b in $(grep -n '^# ===' "$RUNNER_SCRIPT" | cut -d: -f1); do
    ban_line[$n]="$b"; n=$((n + 1))
  done
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ $((i + 1)) -lt "$n" ]; then next=${ban_line[$((i + 1))]}; else next=$((total_lines + 1)); fi
    ban_tag[$i]=$(sed -n "${ban_line[$i]},${next}p" "$RUNNER_SCRIPT" | sed -n 's/^# @group //p' | head -n 1)
    i=$((i + 1))
  done
  lt=-1; i=0
  while [ "$i" -lt "$n" ]; do
    [ -n "${ban_tag[$i]}" ] && lt=$i
    i=$((i + 1))
  done
  [ "$lt" -lt 0 ] && return 0
  if [ $((lt + 1)) -lt "$n" ]; then FOOTER_START=${ban_line[$((lt + 1))]}; else FOOTER_START=$total_lines; fi
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ -n "${ban_tag[$i]}" ]; then
      j=$((i + 1)); next=""
      while [ "$j" -lt "$n" ]; do
        [ -n "${ban_tag[$j]}" ] && { next=$((ban_line[j] - 1)); break; }
        j=$((j + 1))
      done
      [ -z "$next" ] && next=$((FOOTER_START - 1))
      GROUP_NAMES[${#GROUP_NAMES[@]}]="${ban_tag[$i]}"
      GROUP_STARTS[${#GROUP_STARTS[@]}]="${ban_line[$i]}"
      GROUP_ENDS[${#GROUP_ENDS[@]}]="$next"
    fi
    i=$((i + 1))
  done
}

init_predictor_awk() {
  # NB: bash 3.2 mangles heredocs inside $(); capture via read instead
  IFS= read -r -d '' ASSERT_COUNT_AWK <<'AWK' || true
# Predict how many assert executions a group's lines will perform: assert
# call sites multiplied by the literal iteration counts of enclosing for-
# loops and by the call counts of local fixture functions that contain
# sites. Quoted text is masked first so keywords inside messages ("until-",
# "for a non-harness skill") cannot distort the scan.
{
  lines[NR] = $0
}
END {
  n = NR
  for (r = 1; r <= n; r++) masked[r] = mask_line(lines[r])
  pass1_extents()
  sp = 0; product = 1; ns = 0; curfn = ""; cdepth = 0; pend = ""
  in_heredoc = ""
  for (r = 1; r <= n; r++) {
    line = masked[r]
    if (in_heredoc != "") {
      if (index(line, in_heredoc) == 1) in_heredoc = ""
      track_fn(line)
      continue
    }
    if (pend != "") { line = pend_feed(line) }
    if (line ~ /^[ \t]*#/) { track_fn(line); continue }
    hd = heredoc_start(line)
    if (hd != "") { in_heredoc = hd; track_fn(line); continue }
    if (match(line, /^[A-Za-z_][A-Za-z0-9_]*\(\)/)) { curfn = substr(line, 1, RLENGTH - 2); cdepth = 0 }
    if (curfn != "") { cdepth += brace_delta(line); if (cdepth <= 0) curfn = "" }
    kw = next_incomplete_header(line)
    if (kw > 0) {
      scan_events(substr(line, 1, kw - 1))
      pend = substr(line, kw)
      continue
    }
    scan_events(line)
  }
  for (f = 0; f < nf; f++) {
    fn = ford[f]
    if (fsites[fn] == 0) continue
    calls[fn] = 0
    for (r = 1; r <= n; r++) {
      if (r >= fstart[fn] && r <= fend[fn]) continue
      if (masked[r] ~ /^[ \t]*#/) continue
      p = 0
      while ((p = bfind(masked[r], fn, p + 1)) > 0) calls[fn]++
    }
  }
  total = 0
  for (s = 0; s < ns; s++) {
    mult = 1
    if (sitefn[s] != "") mult = calls[sitefn[s]] + 0
    total += sites[s] * mult
  }
  print total
}

function pass1_extents(   r, line, fname, depth) {
  nf = 0; fname = ""
  for (r = 1; r <= n; r++) {
    line = masked[r]
    if (match(line, /^[A-Za-z_][A-Za-z0-9_]*\(\)/)) {
      fname = substr(line, 1, RLENGTH - 2)
      if (!(fname in fend)) { ford[nf++] = fname; fstart[fname] = r; depth = 0 }
    }
    if (fname != "" && !(fname in fend)) {
      depth += brace_delta(line)
      if (depth <= 0) { fend[fname] = r; fname = "" }
    }
  }
}

function track_fn(line) {
  if (match(line, /^[A-Za-z_][A-Za-z0-9_]*\(\)/)) { curfn = substr(line, 1, RLENGTH - 2); cdepth = 0 }
  if (curfn != "") { cdepth += brace_delta(line); if (cdepth <= 0) curfn = "" }
}

function mask_line(line,   i, L, c, out, in_dq, in_sq, csdepth, esc) {
  out = ""; in_dq = 0; in_sq = 0; csdepth = 0; esc = 0
  L = length(line)
  for (i = 1; i <= L; i++) {
    c = substr(line, i, 1)
    if (esc) { out = out " "; esc = 0; continue }
    if (c == "\\") { out = out " "; esc = 1; continue }
    if (in_sq) { out = out (c == "'" ? "'" : " "); if (c == "'") in_sq = 0; continue }
    if (in_dq && csdepth == 0) {
      if (c == "\"") { in_dq = 0; out = out "\"" }
      else if (c == "$" && substr(line, i, 2) == "$(") { csdepth = 1; out = out "  "; i++ }
      else out = out " "
      continue
    }
    if (in_dq && csdepth > 0) {
      if (c == "\"") out = out "\""
      else if (c == "$" && substr(line, i, 2) == "$(") { csdepth++; out = out "  "; i++ }
      else if (c == ")") { csdepth--; out = out (csdepth == 0 ? " " : ")") }
      else out = out " "
      continue
    }
    if (c == "'") { in_sq = 1; out = out "'"; continue }
    if (c == "\"") { in_dq = 1; out = out "\""; continue }
    out = out c
  }
  return out
}

function heredoc_start(line,   p, rest, d) {
  p = index(line, "<<")
  if (p == 0) return ""
  rest = substr(line, p + 2)
  if (match(rest, /^[ \t]*'[^']*'/)) {
    d = substr(rest, RSTART, RLENGTH); gsub(/^[ \t]*'|'$/, "", d); return d
  }
  if (match(rest, /^[ \t]*"[^"]*"/)) {
    d = substr(rest, RSTART, RLENGTH); gsub(/^[ \t]*"|"$/, "", d); return d
  }
  if (match(rest, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
    d = substr(rest, RSTART, RLENGTH); gsub(/^[ \t]*/, "", d); return d
  }
  return ""
}

function pend_feed(line,   p, i2) {
  p = 0
  while (1) {
    i2 = index(substr(line, p + 1), ";")
    if (i2 == 0) break
    p = p + i2
    rest = substr(line, p)
    if (match(rest, /^;[ \t]*do([^A-Za-z0-9_]|$)/)) {
      push_loop(pend " " substr(line, 1, p + RLENGTH))
      pend = ""
      return substr(line, p + RLENGTH)
    }
  }
  pend = pend " " line
  return ""
}

function brace_delta(line,   i, L, d, c) {
  d = 0; L = length(line)
  for (i = 1; i <= L; i++) {
    c = substr(line, i, 1)
    if (c == "$") { i++; continue }   # skip the brace of ${ / $( forms
    if (c == "{") d++
    if (c == "}") d--
  }
  return d
}

function push_loop(header,   iters) {
  iters = 1
  if (match(header, /[ \t]in[ \t][^;]*/)) {
    iters = countwords(substr(header, RSTART + 3, RLENGTH - 3))
    if (iters < 1) iters = 1
  }
  stack[++sp] = iters; product *= iters
}

function pop_loop() { if (sp > 0) { product /= stack[sp]; sp-- } }

function countwords(s,   n, i, L, c, q) {
  n = 0; i = 1; L = length(s)
  while (i <= L) {
    c = substr(s, i, 1)
    if (c == " " || c == "\t") { i++; continue }
    if (c == "$") { if (substr(s, i, 2) == "$(") return -1; i++; continue }
    if (c == "`") return -1
    n++
    while (i <= L) {
      c = substr(s, i, 1)
      if (c == " " || c == "\t") break
      if (c == "'" || c == "\"") {
        q = c; i++
        while (i <= L && substr(s, i, 1) != q) i++
        i++
        continue
      }
      i++
    }
  }
  return n
}

function bfind(str, word, from,   p, L, ch1, ch2, i2) {
  L = length(str); p = from - 1
  while (1) {
    i2 = index(substr(str, p + 1), word)
    if (i2 == 0) return 0
    p = p + i2
    ch1 = (p > 1) ? substr(str, p - 1, 1) : " "
    ch2 = (p + length(word) <= L) ? substr(str, p + length(word), 1) : " "
    if (ch1 !~ /[A-Za-z0-9_]/ && ch2 !~ /[A-Za-z0-9_]/) return p
  }
}

# loop keywords only: reject flag occurrences like --until
function kwfind(str, word, from,   p) {
  while ((p = bfind(str, word, from)) > 0) {
    if (p > 1 && substr(str, p - 1, 1) == "-") { from = p + 1; continue }
    return p
  }
  return 0
}

function next_incomplete_header(line,   kws, k, p, best) {
  split("for while until", kws, " ")
  best = 0
  for (k = 1; k <= 3; k++) {
    p = kwfind(line, kws[k], 1)
    if (p > 0 && (best == 0 || p < best)) best = p
  }
  if (best == 0) return 0
  if (match(substr(line, best), /^[A-Za-z]+[ \t]+[^;]*;[ \t]*do([^A-Za-z0-9_]|$)/)) return 0
  return best
}

function scan_events(line,   pos, p, kind, plen, a, p2) {
  split("assert_eq assert_exit assert_contains", atoks, " ")
  pos = 1
  while (pos <= length(line)) {
    p = 0; kind = ""; plen = 0
    for (a = 1; a <= 3; a++) {
      p2 = bfind(line, atoks[a], pos)
      if (p2 > 0 && (p == 0 || p2 < p)) { p = p2; kind = "A"; plen = length(atoks[a]) }
    }
    a = bfind(line, "done", pos)
    if (a > 0 && (p == 0 || a < p)) { p = a; kind = "D"; plen = 4 }
    a = next_opener(line, pos)
    if (a > 0 && (p == 0 || a < p)) { p = a; kind = "O"; plen = 0 }
    if (p == 0) break
    if (kind == "A") { sites[ns] = product; sitefn[ns] = curfn; if (curfn != "") fsites[curfn]++; ns++ }
    else if (kind == "D") pop_loop()
    else { plen = opener_length(line, p); push_for_list(line, p) }
    pos = p + plen
  }
}

function next_opener(line, pos,   kws, k, p, best) {
  split("for while until", kws, " ")
  best = 0
  for (k = 1; k <= 3; k++) {
    p = kwfind(line, kws[k], pos)
    if (p > 0 && (best == 0 || p < best)) best = p
  }
  if (best == 0) return 0
  if (!match(substr(line, best), /^[A-Za-z]+[ \t]+[^;]*;[ \t]*do([^A-Za-z0-9_]|$)/)) return 0
  return best
}

function opener_length(line, p) {
  match(substr(line, p), /^[A-Za-z]+[ \t]+[^;]*;[ \t]*do/)
  return RLENGTH
}

function push_for_list(line, p,   rest, iters, liststr) {
  rest = substr(line, p)
  iters = 1
  if (match(rest, /^[A-Za-z]+[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t][^;]*/)) {
    liststr = substr(rest, RSTART, RLENGTH)
    sub(/^[A-Za-z]+[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]/, "", liststr)
    iters = countwords(liststr)
    if (iters < 1) iters = 1
  }
  stack[++sp] = iters; product *= iters
}
AWK
}

group_assert_count() { # <start> <end> — predicted assert executions (static)
  sed -n "$1,$2p" "$RUNNER_SCRIPT" | awk "$ASSERT_COUNT_AWK"
}

if [ "${1:-}" = "--list" ]; then
  init_group_index
  init_predictor_awk
  i=0; total=0
  while [ "$i" -lt "${#GROUP_NAMES[@]}" ]; do
    count=$(group_assert_count "${GROUP_STARTS[$i]}" "${GROUP_ENDS[$i]}")
    printf '%s %s\n' "${GROUP_NAMES[$i]}" "$count"
    total=$((total + count))
    i=$((i + 1))
  done
  printf 'total %s\n' "$total"
  exit 0
fi

SELECTED=""
if [ "$#" -gt 0 ]; then
  init_group_index
  known=" "; i=0
  while [ "$i" -lt "${#GROUP_NAMES[@]}" ]; do
    known="$known${GROUP_NAMES[$i]} "
    i=$((i + 1))
  done
  for requested in "$@"; do
    case "$known" in
      *" $requested "*) ;;
      *)
        printf 'run.sh: unknown test group: %s\n' "$requested" >&2
        print_group_usage
        exit 2
        ;;
    esac
    case " $SELECTED " in
      *" $requested "*) ;;
      *) SELECTED="$SELECTED$requested " ;;
    esac
  done
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin"
HARN="$BIN/harness.sh"
LIB="$BIN/_harness_lib.sh"
PASS=0
FAIL=0

# Hermetic by default: no test should hit the network. The update-check tests
# inject a latest version via HARNESS_LATEST (which short-circuits before the
# network path), so this stays in force even for them.
export HARNESS_NO_NET=1
unset HARNESS_ROOT
HARNESS_HOME="$(mktemp -d)"
export HARNESS_HOME

# --- layout helpers (0059: lock + manifest live in the per-project state dir) --
state_of() { bash -c '. "$1"; state_dir "$2"' _ "$LIB" "$1"; }
lockpath() { local d; d="$(state_of "$1")"; mkdir -p "$d"; printf '%s/harness.lock' "$d"; }
manifestpath() { local d; d="$(state_of "$1")"; mkdir -p "$d"; printf '%s/manifest.md' "$d"; }
# Stand-in for `harness.sh agent install` (issue 005): copy a source tree's
# skills/agents into the default shared targets of a project.
stub_agent_install() { # <src_root> <project>
  mkdir -p "$2/.agents/skills" "$2/.agents/agents"
  cp -R "$1/skills/." "$2/.agents/skills/" 2>/dev/null
  cp -R "$1/agents/." "$2/.agents/agents/" 2>/dev/null
  return 0
}

# --- shared snapshot/fixture helpers (hoisted from the migration section
# in 0063 so any selected group can use them) ---------------------------------
sha() { bash -c '. "$1"; cksum_file "$2"' _ "$LIB" "$1"; }
snap() { # <dir> — every file/symlink with its checksum: a no-diff check for repeat runs
  ( cd "$1" && find . \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(sha "$f")"; done )
}
has() { [ -e "$1" ] || [ -L "$1" ] && echo true || echo false; }
# an OLD-format lock (harness/harness.lock) whose baselines are the files as they are NOW
mklock() { # <project> <version> <rel>...
  local p="$1" v="$2" r; shift 2; mkdir -p "$p/harness"
  { printf 'version: %s\n' "$v"; for r in "$@"; do printf '%s  %s\n' "$(sha "$p/$r")" "$r"; done; } > "$p/harness/harness.lock"
}
# The manifests the old init.sh files GENERATED, byte-for-byte as produced by `git archive HEAD`
# [0058 layout], v0.12.1 and v0.10.0 init output (entry lists shortened to two skills/roles).
real_manifest() { # <0058|0121|0100>
  case "$1" in
  0058) printf '%s\n' '# harness-mini manifest' '' \
          'Skills are under .agents/skills/; role descriptions are under harness/agents/.' \
          'Any coding agent that can read the repo should open the paths below.' '' \
          '## Skills (.agents/skills/)' '- checkpoint/SKILL.md' '- tdd/SKILL.md' '' \
          '## Role descriptions (harness/agents/)' '- explorer.md' '- planner.md' '' \
          '## Map: AGENTS.md   Architecture: ARCHITECTURE.md' ;;
  0121) printf '%s\n' '# harness-mini manifest' '' \
          'Skills and agents are files under .claude/skills/ and .claude/agents/.' \
          'Any coding agent that can read the repo should open the paths below.' '' \
          '## Skills (.claude/skills/)' '- checkpoint/SKILL.md' '- tdd/SKILL.md' '' \
          '## Agents (.claude/agents/)' '- explorer.md' '- planner.md' '' \
          '## Map: AGENTS.md   Architecture: ARCHITECTURE.md' ;;
  0100) printf '%s\n' '# harness-mini manifest (CLI-neutral pointer list)' '' \
          'Claude Code auto-loads skills/agents from .claude/. Other CLIs (codex,' \
          'cursor) should read the files below directly.' '' \
          '## Skills (.claude/skills/)' '- checkpoint/SKILL.md' '- tdd/SKILL.md' '' \
          '## Agents (.claude/agents/)' '- explorer.md' '- planner.md' '' \
          '## Map: AGENTS.md   Architecture: ARCHITECTURE.md' ;;
  esac
}

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

# --- selected run: eval the requested groups in file order, then the footer --
# NB: the eval'd sections run in this shell and may reuse short names like `i`,
# so the dispatch loop keeps to its sel_* namespace.
if [ -n "$SELECTED" ]; then
  sel_total=${#GROUP_NAMES[@]}
  sel_idx=0
  while [ "$sel_idx" -lt "$sel_total" ]; do
    case " $SELECTED " in
      *" ${GROUP_NAMES[$sel_idx]} "*)
        eval "$(sed -n "${GROUP_STARTS[$sel_idx]},${GROUP_ENDS[$sel_idx]}p" "$RUNNER_SCRIPT")"
        ;;
    esac
    sel_idx=$((sel_idx + 1))
  done
  eval "$(sed -n "${FOOTER_START},\$p" "$RUNNER_SCRIPT")"
  exit
fi

# =============================================================================
echo "ctx.sh — context occupancy gate (40%% smart/dumb threshold)"
# @group ctx
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
# @group model
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
# @group trace
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
# @group ralph
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
echo "project-id + layout resolver — <name>-<8 base36>, state dir, progress dir (0059 #1)"
# @group project-id
pid() { bash -c '. "$1"; project_id "$2"' _ "$LIB" "$1"; }
# format: lowercase-hyphenated name, dash, exactly 8 chars of [0-9a-z]
id="$(pid "/nonexistent/x")"
assert_eq "x-alij4br1" "$id" "project_id: base36 of sha256(abs path), 8 chars (known vector)"
assert_eq "my-project-pre2cldf" "$(pid "/nonexistent/My Project")" "project_id: spaces and capitals become a lowercase hyphenated name"
assert_eq "x-alij4br1" "$(pid "/nonexistent/x")" "project_id: deterministic across calls"
assert_eq "x-oxki9m9n" "$(pid "/nonexistent/other/x")" "project_id: same basename, different path, different suffix"
id="$(pid "/nonexistent/日本語")"
case "$id" in project-[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]) ok=true ;; *) ok=false ;; esac
assert_eq "true" "$ok" "project_id: a name with no ascii alphanumerics falls back to 'project' ($id)"
id="$(pid "/")"
case "$id" in project-????????) ok=true ;; *) ok=false ;; esac
assert_eq "true" "$ok" "project_id: empty basename (/) falls back to 'project'"
id="$(pid "/nonexistent/--weird__Name!!.v2--")"
case "$id" in weird-name-v2-[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]) ok=true ;; *) ok=false ;; esac
assert_eq "true" "$ok" "project_id: punctuation runs collapse to single hyphens, edges trimmed ($id)"
PID_LINK_REAL="$(mktemp -d)"; PID_LINK_PARENT="$(mktemp -d)"; ln -s "$PID_LINK_REAL" "$PID_LINK_PARENT/alias"
assert_eq "$(pid "$PID_LINK_REAL" | sed 's/^.*-//')" "$(pid "$PID_LINK_PARENT/alias" | sed 's/^.*-//')" "project_id: a symlinked path resolves to the same suffix as its target"
rm -rf "$PID_LINK_REAL" "$PID_LINK_PARENT"
# layout resolvers
state="$(bash -c '. "$1"; state_dir "$2"' _ "$LIB" "/nonexistent/x")"
assert_eq "$HARNESS_HOME/projects/x-alij4br1" "$state" "state_dir resolves to \$HARNESS_HOME/projects/<project-id>"
prog="$(bash -c '. "$1"; progress_dir "$2"' _ "$LIB" "/nonexistent/x")"
assert_eq "/nonexistent/x/.harness-mini" "$prog" "progress_dir resolves to <project>/.harness-mini"
state="$(HARNESS_HOME=/tmp/other-home bash -c '. "$1"; state_dir "$2"' _ "$LIB" "/nonexistent/x")"
assert_eq "/tmp/other-home/projects/x-alij4br1" "$state" "state_dir honours the HARNESS_HOME override"

# =============================================================================
echo "central runtime — install executables outside projects and select project root"
# @group runtime-install
RUNTIME_PROJECT="$(mktemp -d)"
HARNESS_SRC="$ROOT" bash "$ROOT/init.sh" "$RUNTIME_PROJECT" >/dev/null 2>&1
assert_eq "true" "$([ -x "$HARNESS_HOME/bin/harness.sh" ] && echo true || echo false)" "runtime harness.sh installs under HARNESS_HOME"
assert_eq "false" "$([ -e "$RUNTIME_PROJECT/bin" ] && echo true || echo false)" "fresh project install creates no bin directory"
assert_eq "true" "$([ -f "$HARNESS_HOME/harness/runtime.lock" ] && echo true || echo false)" "runtime gets its own lock"
runtime_lock="$(cat "$HARNESS_HOME/harness/runtime.lock" 2>/dev/null)"
project_lock="$(cat "$(lockpath "$RUNTIME_PROJECT")" 2>/dev/null)"
assert_contains "$runtime_lock" "bin/harness.sh" "runtime lock tracks the centralized executable"
assert_contains "$runtime_lock" "version:" "runtime lock records the runtime version"
runtime_sha="$(printf '%s\n' "$runtime_lock" | awk '$2 == "bin/harness.sh" { print $1; exit }')"
source_sha="$(bash -c '. "$1"; cksum_file "$2"' _ "$ROOT/bin/_harness_lib.sh" "$ROOT/bin/harness.sh")"
installed_sha="$(bash -c '. "$1"; cksum_file "$2"' _ "$ROOT/bin/_harness_lib.sh" "$HARNESS_HOME/bin/harness.sh")"
assert_eq "$source_sha" "$runtime_sha" "runtime lock records the source executable checksum"
assert_eq "$installed_sha" "$runtime_sha" "runtime lock checksum matches the installed executable"
assert_eq "false" "$(printf '%s' "$project_lock" | grep -q 'bin/' && echo true || echo false)" "project lock excludes centralized executables"
assert_eq "false" "$([ -e "$RUNTIME_PROJECT/harness" ] && echo true || echo false)" "fresh install creates no project harness/ directory"
assert_eq "false" "$([ -e "$RUNTIME_PROJECT/.agents" ] && echo true || echo false)" "init installs no skills or agents (host unknown until agent install)"
out="$(bash "$HARNESS_HOME/bin/harness.sh" --root "$RUNTIME_PROJECT" status 2>&1)"
assert_contains "$out" "shared skills: 0" "status counts no skills before agent install"
assert_contains "$out" "agent list" "status points a skill-less project at harness.sh agent list"
out="$(bash "$HARNESS_HOME/bin/harness.sh" --root "$RUNTIME_PROJECT" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: a project without installed skills is a warning, not a failure"
assert_contains "$out" "skills not installed" "doctor tells the user skills are not installed yet"
stub_agent_install "$ROOT" "$RUNTIME_PROJECT"

# The same central executable must use the requested project's workboard, not
# its own installation directory or another project's state.
mkdir -p "$RUNTIME_PROJECT/.harness-mini/docs/exec-plans/active"
printf '%s\n' '---' 'plan: project-a' 'stage: implement' '---' > "$RUNTIME_PROJECT/.harness-mini/docs/exec-plans/active/project-a.md"
printf '%s\n' '{' '  "plan_id": "project-a",' '  "status": "in_progress",' '  "current_slice_id": "slice-a",' '  "slices": [{"id":"slice-a","passes":false}]' '}' > "$RUNTIME_PROJECT/.harness-mini/docs/exec-plans/active/project-a.json"
PROJECT_B="$(mktemp -d)"
out="$(bash "$HARNESS_HOME/bin/harness.sh" --root "$RUNTIME_PROJECT" status 2>&1)"
assert_contains "$out" "project-a" "central status reads the explicitly selected project"
out="$(bash "$HARNESS_HOME/bin/harness.sh" --root "$PROJECT_B" status 2>&1)"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'project-a')" "central status does not leak another project's workboard"
assert_contains "$out" "path_reason: empty board" "central status uses the second project's root"
out="$(bash "$HARNESS_HOME/bin/harness.sh" --root "$RUNTIME_PROJECT" doctor 2>&1)"
assert_contains "$out" "runtime:" "central doctor reports the runtime version"
assert_contains "$out" "project:" "central doctor reports the selected project version"
assert_contains "$out" "shared skills" "central doctor reports shared skill count"
assert_contains "$out" "manifest healthy" "central doctor validates the project manifest"
assert_contains "$out" "0 missing" "central doctor reports no missing manifest skills"
out="$(bash "$HARNESS_HOME/bin/harness.sh" --root "$RUNTIME_PROJECT" status 2>&1)"
assert_contains "$out" "runtime:" "central status reports the runtime version"
assert_contains "$out" "project:" "central status reports the selected project version"
assert_contains "$out" "shared skills" "central status reports shared skill count"
assert_contains "$out" "manifest healthy" "central status validates the project manifest"
assert_contains "$out" "0 missing" "central status reports no missing manifest skills"
rm -rf "$PROJECT_B" "$RUNTIME_PROJECT"

# =============================================================================
echo "init.sh — additive, idempotent installer with new/existing asymmetry"
# @group init-bootstrap
# Build a fake source tree so installer logic is tested independent of real assets.
FSRC="$(mktemp -d)"; FHOME="$(mktemp -d)"
mkdir -p "$FSRC/skills" "$FSRC/agents" "$FSRC/bin" "$FSRC/docs" "$FSRC/skills/demo/scripts"
printf 'skill body\n' > "$FSRC/skills/sample.md"
printf 'demo body\n'  > "$FSRC/skills/demo/SKILL.md"   # canonical folder-form skill
printf '#!/bin/sh\n' > "$FSRC/skills/demo/scripts/helper.sh"
printf 'agent body\n' > "$FSRC/agents/planner.md"
printf 'echo hi\n'    > "$FSRC/bin/ctx.sh"
printf 'map\n'        > "$FSRC/AGENTS.md"

# --- new (empty) project: generative bootstrap ---
NEW="$(mktemp -d)"
code=0; HARNESS_SRC="$FSRC" HARNESS_HOME="$FHOME" bash "$BIN/../init.sh" "$NEW" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "init succeeds on empty project"
assert_eq "true" "$([ -f "$FHOME/skills/sample.md" ] && echo true || echo false)" "skills are copied to \$HARNESS_HOME/skills"
assert_eq "true" "$([ -f "$FHOME/skills/demo/SKILL.md" ] && echo true || echo false)" "folder-form skill is copied to \$HARNESS_HOME/skills/<name>/SKILL.md"
assert_eq "true" "$([ -f "$FHOME/skills/demo/scripts/helper.sh" ] && echo true || echo false)" "skill-owned scripts are copied recursively with their skill"
assert_eq "true" "$([ -f "$FHOME/agents/planner.md" ] && echo true || echo false)" "agents are copied to \$HARNESS_HOME/agents"
assert_eq "false" "$([ -e "$NEW/.agents" ] && echo true || echo false)" "init writes no project .agents/"
assert_eq "false" "$([ -e "$NEW/harness" ] && echo true || echo false)" "init writes no project harness/"
assert_eq "true" "$([ -f "$(HARNESS_HOME="$FHOME" manifestpath "$NEW")" ] && echo true || echo false)" "manifest.md is written to the per-project state dir"
assert_eq "true" "$([ -f "$NEW/.harness-mini/.gitignore" ] && grep -qx 'trace/runtime/' "$NEW/.harness-mini/.gitignore" && echo true || echo false)" ".harness-mini/.gitignore ignores trace/runtime/"
assert_eq "false" "$([ -e "$NEW/.gitignore" ] && echo true || echo false)" "install does not create a project .gitignore"
plan="$(cat "$NEW"/.harness-mini/docs/exec-plans/active/0001-*.md 2>/dev/null)"
assert_contains "$plan" "stage: intake" "new project seeds an intake-stage plan"
assert_contains "$plan" "founder-check" "new project plan points to founder-check funnel"
assert_eq "false" "$(printf '%s' "$plan" | grep -qi 'five-step' && echo true || echo false)" "new project funnel omits five-step"

# --- existing project: recon graft (no founder funnel) ---
EXIST="$(mktemp -d)"
printf '{}\n' > "$EXIST/package.json"   # marks it as an existing project
code=0; HARNESS_SRC="$FSRC" HARNESS_HOME="$FHOME" bash "$BIN/../init.sh" "$EXIST" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "init succeeds on existing project"
plan="$(cat "$EXIST"/.harness-mini/docs/exec-plans/active/0001-*.md 2>/dev/null)"
assert_contains "$plan" "recon" "existing project seeds a recon plan"
assert_eq "false" "$(printf '%s' "$plan" | grep -q 'founder-check' && echo true || echo false)" "existing project skips founder funnel"
assert_eq "false" "$([ -e "$EXIST/.agents" ] && echo true || echo false)" "existing project gets no project skill dirs either"

# --- additive: never overwrite a user's existing file ---
printf 'MY CUSTOM MAP\n' > "$NEW/AGENTS.md"
HARNESS_SRC="$FSRC" HARNESS_HOME="$FHOME" bash "$BIN/../init.sh" "$NEW" >/dev/null 2>&1
assert_eq "MY CUSTOM MAP" "$(head -n1 "$NEW/AGENTS.md")" "re-run never overwrites user-modified AGENTS.md (block is appended)"

# --- idempotent: second run exits 0, no duplicate plans ---
code=0; HARNESS_SRC="$FSRC" HARNESS_HOME="$FHOME" bash "$BIN/../init.sh" "$NEW" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "re-run is idempotent (exit 0)"
nplans=$(ls "$NEW"/.harness-mini/docs/exec-plans/active/0001-*.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "1" "$nplans" "re-run does not duplicate the seed plan"

rm -rf "$FSRC" "$NEW" "$EXIST" "$FHOME"

# =============================================================================
echo "init.sh — progress files live in <project>/.harness-mini/ (0059 #2)"
# @group init-progress
PSRC="$(mktemp -d)"; mkdir -p "$PSRC/skills" "$PSRC/agents" "$PSRC/bin" "$PSRC/docs"
printf 'skill\n' > "$PSRC/skills/sample.md"; printf 'agent\n' > "$PSRC/agents/planner.md"
printf 'echo hi\n' > "$PSRC/bin/ctx.sh"; printf 'map\n' > "$PSRC/AGENTS.md"
PNEW="$(mktemp -d)"
HARNESS_SRC="$PSRC" bash "$ROOT/init.sh" "$PNEW" >/dev/null 2>&1
for d in docs/exec-plans/active docs/exec-plans/completed trace/checkpoints trace/evals trace/runtime; do
  assert_eq "true" "$([ -d "$PNEW/.harness-mini/$d" ] && echo true || echo false)" "init creates .harness-mini/$d"
done
assert_eq "false" "$([ -e "$PNEW/.trace" ] && echo true || echo false)" "init creates no project .trace"
assert_eq "true" "$([ -f "$PNEW/.harness-mini/docs/exec-plans/active/0001-intake.json" ] && echo true || echo false)" "seed plan (+ json twin) lands under .harness-mini"
out="$(HARNESS_ROOT="$PNEW" bash "$HARN" status 2>&1)"
assert_contains "$out" "intake  " "status reads active plans from .harness-mini/docs/exec-plans"
assert_contains "$out" "workboard: planned" "status reads the seed JSON twin from .harness-mini"
# an existing project .gitignore is never touched
PGI="$(mktemp -d)"; printf 'node_modules/\n*.log' > "$PGI/.gitignore"; cp "$PGI/.gitignore" "$PGI/.gitignore.orig"
HARNESS_SRC="$PSRC" bash "$ROOT/init.sh" "$PGI" >/dev/null 2>&1
assert_eq "true" "$(cmp -s "$PGI/.gitignore" "$PGI/.gitignore.orig" && echo true || echo false)" "project .gitignore is byte-identical after install"
HARNESS_SRC="$PSRC" bash "$ROOT/init.sh" "$PGI" >/dev/null 2>&1
assert_eq "true" "$(cmp -s "$PGI/.gitignore" "$PGI/.gitignore.orig" && echo true || echo false)" "project .gitignore is byte-identical after re-install"
# readers: doctor / report / garden / eval-gate use .harness-mini/trace
out="$(HARNESS_ROOT="$PNEW" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"
assert_contains "$out" "trace/runtime gitignored" "doctor checks .harness-mini/.gitignore for trace/runtime"
rm -f "$PNEW/.harness-mini/.gitignore"
out="$(HARNESS_ROOT="$PNEW" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"
assert_contains "$out" "trace/runtime not gitignored" "doctor warns when .harness-mini/.gitignore lacks trace/runtime"
# trace.sh + ctx-hook.sh default into .harness-mini/trace/runtime under HARNESS_ROOT
TRD="$(mktemp -d)"
( cd "$TRD" && HARNESS_RUN="r-def" bash "$BIN/trace.sh" main implement ping >/dev/null )
assert_eq "true" "$([ -f "$TRD/.harness-mini/trace/runtime/r-def.jsonl" ] && echo true || echo false)" "trace.sh defaults to .harness-mini/trace/runtime"
HARNESS_ROOT="$TRD" HARNESS_RUN="r-root" bash "$BIN/trace.sh" main implement ping >/dev/null
assert_eq "true" "$([ -f "$TRD/.harness-mini/trace/runtime/r-root.jsonl" ] && echo true || echo false)" "trace.sh honours HARNESS_ROOT for its default dir"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TRD/pass.sh"
( cd "$TRD" && HARNESS_TEST_SCRIPT="$TRD/pass.sh" bash "$BIN/ctx-hook.sh" </dev/null >/dev/null 2>&1 )
assert_eq "true" "$([ -f "$TRD/.harness-mini/trace/runtime/last-green.txt" ] && echo true || echo false)" "ctx-hook stamps .harness-mini/trace/runtime/last-green.txt"
rm -rf "$TRD" "$PSRC" "$PNEW" "$PGI"

# --- .git/info/exclude helper (used by agent install for host skills/agents dirs)
GX="$(mktemp -d)"; git -C "$GX" init -q
gx() { bash -c '. "$1"; shift; git_exclude_add "$@"' _ "$LIB" "$@"; }
gx "$GX" .agents/skills/ .agents/agents/
gx "$GX" .agents/skills/ .claude/skills/
ex="$(cat "$GX/.git/info/exclude")"
assert_contains "$ex" ".agents/skills/" "git_exclude_add lists the skills dir in .git/info/exclude"
assert_contains "$ex" ".claude/skills/" "git_exclude_add appends a new dir on a later call"
assert_eq "1" "$(grep -cx '.agents/skills/' "$GX/.git/info/exclude")" "git_exclude_add is idempotent"
assert_eq "false" "$([ -e "$GX/.gitignore" ] && echo true || echo false)" "git_exclude_add writes no project file"
GXN="$(mktemp -d)"; gx "$GXN" .agents/skills/
assert_eq "false" "$([ -e "$GXN/.git" ] && echo true || echo false)" "git_exclude_add does nothing outside a git repo"
printf 'keep-me\n' >> "$GX/.git/info/exclude"; gx "$GX" .agents/agents/
assert_contains "$(cat "$GX/.git/info/exclude")" "keep-me" "git_exclude_add preserves existing exclude lines"
rm -rf "$GX" "$GXN"

# =============================================================================
echo "init.sh — AGENTS.md marker block + global map/docs split (0059 #3)"
# @group init-agents-md
ASRC="$(mktemp -d)"; AHOME="$(mktemp -d)"
mkdir -p "$ASRC/skills/tdd" "$ASRC/agents" "$ASRC/bin" "$ASRC/docs/templates" "$ASRC/references" \
  "$ASRC/assets" "$ASRC/docs/examples/demo"
printf 'tdd\n' > "$ASRC/skills/tdd/SKILL.md"; printf 'role\n' > "$ASRC/agents/planner.md"
printf 'echo hi\n' > "$ASRC/bin/ctx.sh"; printf 'GLOBAL MAP\n' > "$ASRC/AGENTS.md"
printf 'LIFECYCLE ARCH\n' > "$ASRC/ARCHITECTURE.md"
printf 'principles\n' > "$ASRC/docs/principles.md"; printf 'plan tpl\n' > "$ASRC/docs/templates/quick-plan.md"
printf 'demo\n' > "$ASRC/docs/examples/demo/x.md"; printf 'ref\n' > "$ASRC/references/r.txt"
printf '<svg/>\n' > "$ASRC/assets/banner.svg"
ainit() { HARNESS_SRC="$ASRC" HARNESS_HOME="$AHOME" bash "$ROOT/init.sh" "$1" >/dev/null 2>&1; }
ablock() { bash -c '. "$1"; shift; "$@"' _ "$LIB" "$@"; }

# fresh project: a minimal AGENTS.md holding only the block; nothing else leaks in
AF="$(mktemp -d)"; ainit "$AF"
body="$(cat "$AF/AGENTS.md" 2>/dev/null)"
assert_eq "<!-- harness-mini:begin -->" "$(head -n1 "$AF/AGENTS.md")" "fresh AGENTS.md starts with the begin marker"
assert_eq "<!-- harness-mini:end -->" "$(tail -n1 "$AF/AGENTS.md")" "fresh AGENTS.md ends with the end marker (block only)"
assert_eq "1" "$(grep -c 'harness-mini:begin' "$AF/AGENTS.md")" "exactly one begin marker"
assert_eq "true" "$([ "$(wc -l < "$AF/AGENTS.md" | tr -d ' ')" -le 12 ] && echo true || echo false)" "block stays within ~10 lines"
assert_contains "$body" "$AHOME/bin/harness.sh\" status" "block tells the agent to run harness.sh status first"
assert_contains "$body" "$AHOME/AGENTS.md" "block points at the global map"
assert_contains "$body" "agent list" "block tells the agent to list hosts when skills are missing"
assert_contains "$body" "agent install <host>" "block tells the agent to install for its host"
for f in CLAUDE.md ARCHITECTURE.md docs .trace bin; do
  assert_eq "false" "$([ -e "$AF/$f" ] && echo true || echo false)" "fresh install creates no project $f"
done
# idempotent: re-install leaves the file byte-identical
cp "$AF/AGENTS.md" "$AF/AGENTS.copy"; ainit "$AF"
assert_eq "true" "$(cmp -s "$AF/AGENTS.md" "$AF/AGENTS.copy" && echo true || echo false)" "re-install is idempotent (AGENTS.md unchanged)"
# removing the block from a block-only file removes the file
ablock agents_block_remove "$AF/AGENTS.md"
assert_eq "false" "$([ -e "$AF/AGENTS.md" ] && echo true || echo false)" "removing the block from a block-only file removes it"
rm -rf "$AF"

# existing AGENTS.md: bytes outside the block are identical after install and after removal
AE="$(mktemp -d)"; printf '# My project\n\nRules: be nice.\n' > "$AE/AGENTS.md"; cp "$AE/AGENTS.md" "$AE/orig"
ainit "$AE"
assert_eq "true" "$(head -c "$(wc -c < "$AE/orig" | tr -d ' ')" "$AE/AGENTS.md" | cmp -s - "$AE/orig" && echo true || echo false)" "existing AGENTS.md content is a byte-identical prefix after install"
assert_eq "1" "$(grep -c 'harness-mini:begin' "$AE/AGENTS.md")" "block appended once to an existing AGENTS.md"
cp "$AE/AGENTS.md" "$AE/after1"; ainit "$AE"
assert_eq "true" "$(cmp -s "$AE/AGENTS.md" "$AE/after1" && echo true || echo false)" "re-install leaves an existing AGENTS.md unchanged"
ablock agents_block_remove "$AE/AGENTS.md"
assert_eq "true" "$(cmp -s "$AE/AGENTS.md" "$AE/orig" && echo true || echo false)" "block removal restores the original AGENTS.md byte-for-byte"
rm -rf "$AE"
# no trailing newline, CRLF-free edge: still byte-identical after a round trip
AN="$(mktemp -d)"; printf 'no newline at end' > "$AN/AGENTS.md"; cp "$AN/AGENTS.md" "$AN/orig"
ainit "$AN"
assert_eq "true" "$(head -c "$(wc -c < "$AN/orig" | tr -d ' ')" "$AN/AGENTS.md" | cmp -s - "$AN/orig" && echo true || echo false)" "unterminated last line is preserved as a prefix"
ablock agents_block_remove "$AN/AGENTS.md"
assert_eq "true" "$(cmp -s "$AN/AGENTS.md" "$AN/orig" && echo true || echo false)" "block removal restores a file without trailing newline"
rm -rf "$AN"
# block in the middle of a file: removal keeps everything around it
AM="$(mktemp -d)"; printf 'top\n' > "$AM/AGENTS.md"
ablock agents_block_add "$AM/AGENTS.md" '$HOME/.harness-mini'
printf 'bottom\n' >> "$AM/AGENTS.md"
ablock agents_block_remove "$AM/AGENTS.md"
assert_eq "top
bottom" "$(cat "$AM/AGENTS.md")" "removal keeps user content on both sides of the block"
assert_contains "$(ablock agents_block_text '$HOME/.harness-mini')" '"$HOME/.harness-mini/bin/harness.sh" status' "default block references the runtime through \$HOME"
printf 'broken\n<!-- harness-mini:begin -->\nno end marker\n' > "$AM/broken.md"; cp "$AM/broken.md" "$AM/broken.orig"
code=0; ablock agents_block_remove "$AM/broken.md" || code=$?
assert_exit 1 "$code" "removal refuses a block with no end marker"
assert_eq "true" "$(cmp -s "$AM/broken.md" "$AM/broken.orig" && echo true || echo false)" "a malformed block is left untouched"
rm -rf "$AM"

# global map + static docs under HARNESS_HOME; project architecture under .harness-mini
AG="$(mktemp -d)"; ainit "$AG"
assert_eq "GLOBAL MAP" "$(cat "$AHOME/AGENTS.md")" "the full map lives at \$HARNESS_HOME/AGENTS.md"
assert_eq "LIFECYCLE ARCH" "$(cat "$AHOME/docs/ARCHITECTURE.md")" "harness lifecycle architecture lives at \$HARNESS_HOME/docs/ARCHITECTURE.md"
assert_eq "principles" "$(cat "$AHOME/docs/principles.md")" "static docs live under \$HARNESS_HOME/docs"
assert_eq "plan tpl" "$(cat "$AHOME/docs/templates/quick-plan.md")" "templates live under \$HARNESS_HOME/docs/templates"
assert_eq "demo" "$(cat "$AHOME/docs/examples/demo/x.md")" "examples live under \$HARNESS_HOME/docs/examples"
assert_eq "tdd" "$(cat "$AHOME/skills/tdd/SKILL.md")" "skill sources are copied to \$HARNESS_HOME/skills"
assert_eq "role" "$(cat "$AHOME/agents/planner.md")" "role sources are copied to \$HARNESS_HOME/agents"
for f in references assets docs/references docs/assets docs/exec-plans; do
  assert_eq "false" "$([ -e "$AHOME/$f" ] && echo true || echo false)" "\$HARNESS_HOME/$f is not installed"
done
assert_eq "0" "$(find "$AHOME" "$AG" -name 'r.txt' -o -name 'banner.svg' | wc -l | tr -d ' ')" "references/ and assets/ files appear nowhere in the install trees"
assert_eq "0" "$(grep -c -e 'references/' -e 'assets/' "$AHOME"/*/harness.lock "$AHOME"/*/manifest.md 2>/dev/null | awk -F: '{n+=$NF} END {print n+0}')" "references/ and assets/ are never locked or listed in the manifest"
assert_eq "false" "$([ -e "$AG/docs" ] && echo true || echo false)" "no project docs/ directory"
assert_eq "true" "$([ -f "$AG/.harness-mini/architecture.md" ] && echo true || echo false)" "project architecture lands at .harness-mini/architecture.md"
assert_contains "$(cat "$AG/.harness-mini/architecture.md")" "Domains & layers" "project architecture.md carries the recon target section"
printf 'edited arch\n' > "$AG/.harness-mini/architecture.md"; ainit "$AG"
assert_eq "edited arch" "$(cat "$AG/.harness-mini/architecture.md")" "re-install never overwrites project architecture.md"
printf 'USER EDIT\n' > "$AHOME/AGENTS.md"; ainit "$AG"
assert_eq "USER EDIT" "$(cat "$AHOME/AGENTS.md")" "re-install never overwrites an edited global file"
# an existing project ARCHITECTURE.md and CLAUDE.md are never touched
AX="$(mktemp -d)"; printf 'my arch\n' > "$AX/ARCHITECTURE.md"; printf 'my claude\n' > "$AX/CLAUDE.md"
ainit "$AX"
assert_eq "my arch" "$(cat "$AX/ARCHITECTURE.md")" "project ARCHITECTURE.md is never touched"
assert_eq "my claude" "$(cat "$AX/CLAUDE.md")" "project CLAUDE.md is never touched"
rm -rf "$AG" "$AX" "$ASRC" "$AHOME"

# =============================================================================
echo "init.sh — host-neutral: no host files, no project skills until agent install"
# @group init-host-neutral
NSRC="$(mktemp -d)"; NHOME="$(mktemp -d)"
mkdir -p "$NSRC/skills/tdd" "$NSRC/agents" "$NSRC/bin" "$NSRC/docs"
printf -- '---\nname: tdd\ndescription: Test-first workflow.\n---\nbody\n' > "$NSRC/skills/tdd/SKILL.md"
printf 'role description\n' > "$NSRC/agents/planner.md"
printf 'shared instructions\n' > "$NSRC/AGENTS.md"
NCLAUDE="$(mktemp -d)"
NCURSOR="$(mktemp -d)"
HARNESS_AGENT=claude HARNESS_SRC="$NSRC" HARNESS_HOME="$NHOME" bash "$ROOT/init.sh" "$NCLAUDE" >/dev/null 2>&1
HARNESS_AGENT=cursor HARNESS_SRC="$NSRC" HARNESS_HOME="$NHOME" bash "$ROOT/init.sh" "$NCURSOR" >/dev/null 2>&1
for project in "$NCLAUDE" "$NCURSOR"; do
  assert_eq "false" "$([ -e "$project/.agents" ] && echo true || echo false)" "no skills are installed regardless of host environment"
  assert_eq "false" "$([ -e "$project/harness" ] && echo true || echo false)" "no project harness/ mirror"
  assert_eq "false" "$([ -e "$project/.claude/skills" ] && echo true || echo false)" "no .claude skill mirror is generated"
  assert_eq "false" "$([ -e "$project/.cursor/skills" ] && echo true || echo false)" "no .cursor skill mirror is generated"
  assert_eq "false" "$([ -e "$project/.cursor/rules" ] && echo true || echo false)" "no Cursor rules are generated"
  assert_eq "false" "$([ -e "$project/CLAUDE.md" ] && echo true || echo false)" "no Claude-specific gate is generated"
  assert_contains "$(cat "$(HARNESS_HOME="$NHOME" manifestpath "$project")")" ".agents/skills/" "manifest lists the shared skill root"
  assert_contains "$(cat "$(HARNESS_HOME="$NHOME" manifestpath "$project")")" "tdd/SKILL.md" "manifest lists skills from the source, not from the project"
done
assert_eq "true" "$([ "$(HARNESS_HOME="$NHOME" state_of "$NCLAUDE")" != "$(HARNESS_HOME="$NHOME" state_of "$NCURSOR")" ] && echo true || echo false)" "two projects get different state dirs"
NUNKNOWN="$(mktemp -d)"
code=0; HARNESS_SRC="$NSRC" HARNESS_HOME="$NHOME" bash "$ROOT/init.sh" --agent cursor "$NUNKNOWN" >/dev/null 2>&1 || code=$?
assert_exit 64 "$code" "installer has no host-selection argument"
assert_eq "false" "$([ -e "$NUNKNOWN/.agents" ] && echo true || echo false)" "unsupported host option fails before project mutation"
rm -rf "$NSRC" "$NCLAUDE" "$NCURSOR" "$NUNKNOWN" "$NHOME"

# =============================================================================
echo "repo assets — parallel-slices skill exists"
# @group repo-assets
assert_eq "true" "$([ -f "$ROOT/skills/parallel-slices/SKILL.md" ] && echo true || echo false)" "parallel-slices skill source exists"

# =============================================================================
echo "tdd skill — one red→green cycle per acceptance criterion (#29)"
# @group tdd-skill
assert_contains "$(cat "$ROOT/skills/tdd/SKILL.md")" "One red→green cycle per acceptance criterion" "tdd source requires a failing test per acceptance criterion"

# =============================================================================
echo "harness.sh version — report the installed harness version"
# @group version
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
printf 'version: 9.9.9\nabc123  AGENTS.md\n' > "$(lockpath "$LK")"
out=$(HARNESS_ROOT="$LK" HARNESS_NO_NET=1 bash "$HARN" version 2>/dev/null)
assert_contains "$out" "9.9.9" "version prefers the installed lock over VERSION"
rm -rf "$LK"

# =============================================================================
echo "version_newer — dependency-free semver compare"
# @group version-newer
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
# @group update-reminder
UDIR="$(mktemp -d)"; mkdir -p "$UDIR/harness" "$UDIR/.agents/skills/x" "$UDIR/.harness-mini/docs/exec-plans/active"
printf 'version: 0.5.0\n' > "$(lockpath "$UDIR")"
printf 'AGENTS\n' > "$UDIR/AGENTS.md"
printf 'x\n' > "$UDIR/.agents/skills/x/SKILL.md"   # so doctor has no unrelated FAIL
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
echo "init.sh — per-project harness.lock + manifest.md under the state dir (0059 #4)"
# @group manifest
LSRC="$(mktemp -d)"
mkdir -p "$LSRC/skills" "$LSRC/agents" "$LSRC/bin" "$LSRC/docs" "$LSRC/skills/demo"
printf 'skill body\n' > "$LSRC/skills/sample.md"
printf 'demo body\n'  > "$LSRC/skills/demo/SKILL.md"   # folder-form skill
printf 'agent body\n' > "$LSRC/agents/planner.md"
printf 'echo hi\n'    > "$LSRC/bin/ctx.sh"
printf 'map\n'        > "$LSRC/AGENTS.md"
printf '0.4.2\n'      > "$LSRC/VERSION"
LDEST="$(mktemp -d)"; LHOME="$(mktemp -d)"
HARNESS_SRC="$LSRC" HARNESS_HOME="$LHOME" bash "$ROOT/init.sh" "$LDEST" >/dev/null 2>&1
LSTATE="$LHOME/projects/$(basename "$(HARNESS_HOME="$LHOME" state_of "$LDEST")")"
assert_eq "true" "$([ -f "$LSTATE/harness.lock" ] && echo true || echo false)" "harness.lock is written under \$HARNESS_HOME/projects/<project-id>/"
assert_eq "true" "$([ -f "$LSTATE/manifest.md" ] && echo true || echo false)" "manifest.md is written under \$HARNESS_HOME/projects/<project-id>/"
assert_eq "false" "$([ -e "$LDEST/harness" ] && echo true || echo false)" "no lock, manifest or harness/ directory appears in the project"
lock="$(cat "$LSTATE/harness.lock" 2>/dev/null)"
assert_contains "$lock" "version: 0.4.2" "lock records the source VERSION"
assert_contains "$lock" ".agents/skills/sample.md" "lock lists a managed skill by target path"
assert_contains "$lock" ".agents/skills/demo/SKILL.md" "lock recurses folder-form skills (<name>/SKILL.md)"
assert_contains "$lock" ".agents/agents/planner.md" "lock lists managed agent role files"
assert_eq "0" "$(printf '%s' "$lock" | awk 'NR>1 {print $2}' | grep -vc '^\.agents/\(skills\|agents\)/')" "managed set is skills + agents only (no AGENTS.md, docs, bin, ARCHITECTURE)"
# the lock must record the PRISTINE source checksum, not a user-edited copy
assert_contains "$lock" "$(bash -c '. "$1"; cksum_file "$2"' _ "$BIN/_harness_lib.sh" "$LSRC/skills/sample.md")  .agents/skills/sample.md" "lock stores the pristine upstream checksum"
# additive: a second init does not error and leaves the lock untouched
printf 'sentinel\n' >> "$LSTATE/harness.lock"
code=0; HARNESS_SRC="$LSRC" HARNESS_HOME="$LHOME" bash "$ROOT/init.sh" "$LDEST" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "re-init with a lock present is idempotent"
assert_eq "sentinel" "$(tail -n1 "$LSTATE/harness.lock")" "re-init leaves an existing lock untouched"
# two projects from one source keep separate locks
LDEST2="$(mktemp -d)"; HARNESS_SRC="$LSRC" HARNESS_HOME="$LHOME" bash "$ROOT/init.sh" "$LDEST2" >/dev/null 2>&1
assert_eq "2" "$(find "$LHOME" -name harness.lock | wc -l | tr -d ' ')" "each project gets its own lock file"
rm -rf "$LSRC" "$LDEST" "$LDEST2" "$LHOME"

# =============================================================================
echo "init.sh — neutral instructions are copied without host-specific gates"
# @group init-instructions
GNSRC="$(mktemp -d)"
mkdir -p "$GNSRC/skills" "$GNSRC/agents" "$GNSRC/bin" "$GNSRC/docs"
printf 'map\n' > "$GNSRC/AGENTS.md"
GNDST="$(mktemp -d)"
mkdir -p "$GNDST/.cursor/rules"
printf 'user instructions\n' > "$GNDST/CLAUDE.md"
printf 'user cursor rules\n' > "$GNDST/.cursor/rules/user.mdc"
GNHOME="$(mktemp -d)"
HARNESS_SRC="$GNSRC" HARNESS_HOME="$GNHOME" bash "$ROOT/init.sh" "$GNDST" >/dev/null 2>&1
assert_contains "$(cat "$GNDST/CLAUDE.md")" "user instructions" "existing host file remains untouched"
assert_contains "$(cat "$GNDST/.cursor/rules/user.mdc")" "user cursor rules" "existing Cursor rules remain untouched"
assert_contains "$(cat "$GNDST/AGENTS.md")" "harness-mini:begin" "AGENTS.md block is installed when AGENTS.md is absent"
assert_eq "map" "$(cat "$GNHOME/AGENTS.md")" "the full map is installed globally"
assert_eq "false" "$([ -f "$GNDST/.cursor/rules/harness-mini.mdc" ] && echo true || echo false)" "installer adds no host-specific routing file"
rm -rf "$GNSRC" "$GNDST" "$GNHOME"

# =============================================================================
echo "legacy migration — 0058 layout and pre-0058 layout (0059 #7)"
# @group migration-0058
MS="$(mktemp -d)"; MH="$(mktemp -d)"
mkdir -p "$MS/skills/tdd" "$MS/agents" "$MS/bin" "$MS/docs"
cp "$BIN"/*.sh "$MS/bin/"                     # a real source ships the runtime: migration requires it
printf '0.13.0\n' > "$MS/VERSION"; printf 'NEW tdd\n' > "$MS/skills/tdd/SKILL.md"
printf 'role\n' > "$MS/agents/planner.md"; printf 'map\n' > "$MS/AGENTS.md"; printf 'arch\n' > "$MS/ARCHITECTURE.md"
printf 'principles\n' > "$MS/docs/principles.md"; printf 'assumptions\n' > "$MS/docs/assumptions.md"
mig_init() { HARNESS_SRC="$MS" HARNESS_HOME="$MH" bash "$ROOT/init.sh" "$1" 2>&1; }
mstate() { HARNESS_HOME="$MH" bash -c '. "$1"; state_dir "$2"' _ "$LIB" "$1"; }
BLOCK1="$(bash -c '. "$1"; printf "%s" "$HM_BEGIN"' _ "$LIB")"

# --- (a) a 0058-layout project ------------------------------------------------
PA="$(mktemp -d)"
mkdir -p "$PA/docs/exec-plans/active" "$PA/docs/exec-plans/completed" "$PA/docs/references" \
  "$PA/.trace/checkpoints" "$PA/.trace/evals" "$PA/.trace/runtime" "$PA/harness/agents" \
  "$PA/.agents/skills/tdd" "$PA/.harness-mini/trace/checkpoints"
printf 'plan A\n' > "$PA/docs/exec-plans/active/0001-a.md"
printf '{"plan_id":"0001-a"}\n' > "$PA/docs/exec-plans/active/0001-a.json"
printf 'done plan\n' > "$PA/docs/exec-plans/completed/0002-b.md"
printf 'cp-old-layout\n' > "$PA/.trace/checkpoints/c1.md"
printf 'cp-already-new\n' > "$PA/.harness-mini/trace/checkpoints/c1.md"
printf 'cp2\n' > "$PA/.trace/checkpoints/c2.md"
printf 'ev\n' > "$PA/.trace/evals/e1.md"; printf 'backlog\n' > "$PA/.trace/garden-backlog.md"
printf '{"r":1}\n' > "$PA/.trace/runtime/run.jsonl"
printf 'OLD MAP\n' > "$PA/AGENTS.md"; printf 'OLD ARCH\n' > "$PA/ARCHITECTURE.md"
printf 'old principles\n' > "$PA/docs/principles.md"; printf 'old smart\n' > "$PA/docs/smart-dumb.md"
printf 'old ref\n' > "$PA/docs/references/r.md"; printf 'old assumptions\n' > "$PA/docs/assumptions.md"
printf 'old role\n' > "$PA/harness/agents/planner.md"; printf 'old tdd\n' > "$PA/.agents/skills/tdd/SKILL.md"
real_manifest 0058 > "$PA/harness/manifest.md"
printf 'node_modules/\n.trace/runtime/\n' > "$PA/.gitignore"
mklock "$PA" 0.12.1 AGENTS.md ARCHITECTURE.md docs/principles.md docs/smart-dumb.md docs/references/r.md \
  harness/agents/planner.md .agents/skills/tdd/SKILL.md
printf 'user edit\n' >> "$PA/docs/smart-dumb.md"
gi_sha="$(sha "$PA/.gitignore")"
out="$(mig_init "$PA")"; code=$?
assert_exit 0 "$code" "0058 layout: init exits 0"
assert_eq "plan A" "$(cat "$PA/.harness-mini/docs/exec-plans/active/0001-a.md")" "0058: active plan moved into .harness-mini/"
assert_eq "true" "$(has "$PA/.harness-mini/docs/exec-plans/active/0001-a.json")" "0058: the JSON twin moved with it"
assert_eq "done plan" "$(cat "$PA/.harness-mini/docs/exec-plans/completed/0002-b.md")" "0058: completed plan moved"
assert_eq "false" "$(has "$PA/docs/exec-plans")" "0058: emptied docs/exec-plans removed"
assert_eq "cp2" "$(cat "$PA/.harness-mini/trace/checkpoints/c2.md")" "0058: checkpoint moved to .harness-mini/trace"
assert_eq "ev" "$(cat "$PA/.harness-mini/trace/evals/e1.md")" "0058: eval verdict moved"
assert_eq "backlog" "$(cat "$PA/.harness-mini/trace/garden-backlog.md")" "0058: garden-backlog moved"
assert_eq '{"r":1}' "$(cat "$PA/.harness-mini/trace/runtime/run.jsonl")" "0058: runtime trace moved"
assert_eq "cp-already-new" "$(cat "$PA/.harness-mini/trace/checkpoints/c1.md")" "conflict: the existing destination file is untouched"
assert_eq "cp-old-layout" "$(cat "$PA/.trace/checkpoints/c1.md")" "conflict: the source stays in place (both kept)"
assert_contains "$out" "keep  .trace/checkpoints/c1.md" "conflict is reported as a keep line"
assert_eq "false" "$(has "$PA/.trace/evals")" "emptied .trace/evals removed (rmdir only)"
assert_eq "trace/runtime/" "$(cat "$PA/.harness-mini/.gitignore")" ".harness-mini/.gitignore ignores trace/runtime/"
assert_eq "false" "$(has "$PA/ARCHITECTURE.md")" "0058: lock-clean ARCHITECTURE.md removed"
assert_eq "false" "$(has "$PA/docs/principles.md")" "0058: lock-clean docs/principles.md removed"
assert_eq "false" "$(has "$PA/docs/references")" "0058: lock-clean docs/references removed with its emptied dir"
assert_eq "false" "$(has "$PA/harness/agents")" "0058: lock-clean harness/agents removed"
assert_eq "false" "$(has "$PA/harness/manifest.md")" "0058: generated harness/manifest.md removed"
assert_contains "$out" "migr  removed unchanged ARCHITECTURE.md" "removal is reported as a migr line"
assert_contains "$(cat "$PA/docs/smart-dumb.md")" "user edit" "0058: an edited harness doc is preserved"
assert_contains "$out" "keep  docs/smart-dumb.md" "edited file is reported as a keep line"
assert_eq "old assumptions" "$(cat "$PA/docs/assumptions.md")" "0058: a harness doc the lock never listed is kept"
assert_contains "$out" "docs/assumptions.md (leftover legacy harness file" "unlisted, differing harness doc is reported as a leftover, by path"
assert_eq "true" "$(has "$PA/harness/harness.lock")" "old lock stays while an edited file still needs its baseline"
assert_eq "$BLOCK1" "$(head -n1 "$PA/AGENTS.md")" "0058: clean whole-file AGENTS.md replaced by the marker block"
assert_eq "0" "$(grep -c 'OLD MAP' "$PA/AGENTS.md")" "0058: the stale harness map text is gone"
assert_contains "$out" "migr  replaced the whole-file harness AGENTS.md" "AGENTS.md replacement is reported"
assert_eq "old tdd" "$(cat "$PA/.agents/skills/tdd/SKILL.md")" "0058: .agents/skills (the current target) is left in place"
assert_contains "$(cat "$(mstate "$PA")/harness.lock")" "$(sha "$PA/.agents/skills/tdd/SKILL.md")  .agents/skills/tdd/SKILL.md" "new lock adopts the old baseline of a pristine retained skill"
assert_eq "$gi_sha" "$(sha "$PA/.gitignore")" "0058: project .gitignore is byte-identical"
assert_contains "$out" "stale and harmless" "the stale .trace/runtime/ .gitignore line is mentioned"
for f in CLAUDE.md bin; do assert_eq "false" "$(has "$PA/$f")" "0058: install created no $f"; done

# repeat run: harmless (no tree diff, no new migr action)
s1="$(snap "$PA"; snap "$MH")"
out2="$(mig_init "$PA")"
assert_eq "$s1" "$(snap "$PA"; snap "$MH")" "0058: repeat run changes nothing (project and runtime identical)"
assert_eq "0" "$(printf '%s\n' "$out2" | grep -c '^  migr')" "0058: repeat run reports no migr action"

# update: the adopted baseline lets a pristine retained skill upgrade (no .new)
MS2="$(mktemp -d)"; cp -R "$MS/." "$MS2/"; printf 'NEWER tdd\n' > "$MS2/skills/tdd/SKILL.md"
code=0; HARNESS_HOME="$MH" HARNESS_ROOT="$PA" bash "$HARN" update --src "$MS2" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "0058: update exits 0"
assert_eq "NEWER tdd" "$(cat "$PA/.agents/skills/tdd/SKILL.md")" "0058: a pristine legacy skill is UPDATED, not flagged"
assert_eq "false" "$(has "$PA/.agents/skills/tdd/SKILL.md.new")" "0058: no .new for a pristine legacy skill"
rm -rf "$MS2"

# --- (b) a pre-0058 project with host-specific dirs ----------------------------
PB="$(mktemp -d)"
mkdir -p "$PB/.claude/skills/tdd" "$PB/.claude/skills/edited" "$PB/.claude/agents" "$PB/bin" \
  "$PB/docs/references" "$PB/harness" "$PB/.cursor/rules" "$PB/docs/exec-plans/active"
printf -- '---\ndescription: legacy tdd\n---\nold tdd body\n' > "$PB/.claude/skills/tdd/SKILL.md"
printf 'orig edited\n' > "$PB/.claude/skills/edited/SKILL.md"; printf 'old role\n' > "$PB/.claude/agents/planner.md"
printf 'old harness.sh\n' > "$PB/bin/harness.sh"; printf 'mine\n' > "$PB/bin/mine.sh"
printf 'linked content\n' > "$PB/user-owned"; ln -s ../user-owned "$PB/bin/linked.sh"
printf 'old principles\n' > "$PB/docs/principles.md"; printf 'old ref\n' > "$PB/docs/references/r.md"
printf 'OLD ARCH\n' > "$PB/ARCHITECTURE.md"; printf 'OLD MAP\n' > "$PB/AGENTS.md"
printf 'plan B\n' > "$PB/docs/exec-plans/active/0001-b.md"
bash -c '. "$1"; legacy_claude_gate' _ "$LIB" > "$PB/CLAUDE.md"
bash -c '. "$1"; legacy_cursor_rule' _ "$LIB" > "$PB/.cursor/rules/harness-mini.mdc"
printf -- '---\ndescription: legacy tdd\nalwaysApply: false\n---\n\nharness-mini skill **tdd**. Read `.claude/skills/tdd/SKILL.md` and follow it for this task.\n' > "$PB/.cursor/rules/tdd.mdc"
printf 'user cursor rule\n' > "$PB/.cursor/rules/user.mdc"
real_manifest 0121 > "$PB/harness/manifest.md"
mklock "$PB" 0.11.0 .claude/skills/tdd/SKILL.md .claude/skills/edited/SKILL.md .claude/agents/planner.md \
  bin/harness.sh bin/linked.sh docs/principles.md docs/references/r.md ARCHITECTURE.md AGENTS.md
printf 'edited by user\n' >> "$PB/.claude/skills/edited/SKILL.md"
printf '\n## Recon\nproject facts\n' >> "$PB/ARCHITECTURE.md"
{ printf 'USER HEADER\n\n'; cat "$PB/AGENTS.md"; } > "$PB/AGENTS.tmp" && mv "$PB/AGENTS.tmp" "$PB/AGENTS.md"
out="$(mig_init "$PB")"
assert_eq "false" "$(has "$PB/.claude/skills/tdd")" "pre-0058: lock-clean .claude/skills removed"
assert_contains "$(cat "$PB/.claude/skills/edited/SKILL.md")" "edited by user" "pre-0058: an edited skill is preserved"
assert_eq "false" "$(has "$PB/.claude/agents")" "pre-0058: lock-clean .claude/agents removed"
assert_eq "false" "$(has "$PB/.agents")" "pre-0058: skills are NOT moved into .agents/ (host-aware install replaces them)"
assert_contains "$out" "agent install" "pre-0058: the user is told to run agent list / agent install"
assert_eq "false" "$(has "$PB/bin/harness.sh")" "pre-0058: lock-clean bin/ script removed"
assert_eq "mine" "$(cat "$PB/bin/mine.sh")" "pre-0058: a user script the lock never listed is kept"
assert_eq "true" "$(has "$PB/bin/linked.sh")" "pre-0058: a symlink is kept even when its checksum matches"
assert_eq "false" "$(has "$PB/docs/principles.md")" "pre-0058: lock-clean docs/principles.md removed"
assert_eq "false" "$(has "$PB/docs/references")" "pre-0058: lock-clean docs/references removed"
assert_contains "$(cat "$PB/ARCHITECTURE.md")" "project facts" "pre-0058: an edited ARCHITECTURE.md is preserved"
assert_contains "$out" "keep  ARCHITECTURE.md" "pre-0058: edited ARCHITECTURE.md reported"
assert_eq "false" "$(has "$PB/CLAUDE.md")" "pre-0058: a CLAUDE.md that is exactly the generated gate is removed"
assert_eq "false" "$(has "$PB/.cursor/rules/harness-mini.mdc")" "pre-0058: generated Cursor routing rule removed"
assert_eq "false" "$(has "$PB/.cursor/rules/tdd.mdc")" "pre-0058: generated Cursor skill rule removed"
assert_eq "user cursor rule" "$(cat "$PB/.cursor/rules/user.mdc")" "pre-0058: an unrelated Cursor rule is kept"
assert_eq "false" "$(has "$PB/harness/manifest.md")" "pre-0058: generated manifest removed"
assert_eq "plan B" "$(cat "$PB/.harness-mini/docs/exec-plans/active/0001-b.md")" "pre-0058: plan moved"
assert_eq "USER HEADER" "$(head -n1 "$PB/AGENTS.md")" "edited AGENTS.md: user text stays first"
assert_contains "$(cat "$PB/AGENTS.md")" "OLD MAP" "edited AGENTS.md: existing text untouched"
assert_contains "$(cat "$PB/AGENTS.md")" "$BLOCK1" "edited AGENTS.md: the marker block is appended"
assert_eq "1" "$(grep -cxF "$BLOCK1" "$PB/AGENTS.md")" "edited AGENTS.md: exactly one block"
assert_contains "$out" "keep  AGENTS.md (edited" "edited AGENTS.md: keep note suggests deleting the stale map text"
s1="$(snap "$PB"; snap "$MH")"; out2="$(mig_init "$PB")"
assert_eq "$s1" "$(snap "$PB"; snap "$MH")" "pre-0058: repeat run changes nothing"
assert_eq "0" "$(printf '%s\n' "$out2" | grep -c '^  migr')" "pre-0058: repeat run reports no migr action"

# --- (c) no baseline: nothing harness-owned may be deleted ---------------------
PC="$(mktemp -d)"
mkdir -p "$PC/bin" "$PC/.claude/skills/keep" "$PC/docs/exec-plans/active" "$PC/harness"
printf 'unknown executable\n' > "$PC/bin/keep.sh"; printf 'unknown skill\n' > "$PC/.claude/skills/keep/SKILL.md"
printf 'OLD ARCH\n' > "$PC/ARCHITECTURE.md"; printf 'OLD MAP\n' > "$PC/AGENTS.md"; printf 'plan C\n' > "$PC/docs/exec-plans/active/0001-c.md"
real_manifest 0121 > "$PC/harness/manifest.md"
{ bash -c '. "$1"; legacy_claude_gate' _ "$LIB"; printf 'my own notes\n'; } > "$PC/CLAUDE.md"
printf 'node_modules/\n' > "$PC/.gitignore"; gi_sha="$(sha "$PC/.gitignore")"
out="$(mig_init "$PC")"
for f in bin/keep.sh .claude/skills/keep/SKILL.md ARCHITECTURE.md harness/manifest.md CLAUDE.md; do
  assert_eq "true" "$(has "$PC/$f")" "no baseline: $f is not deleted"
done
assert_contains "$out" "no harness/harness.lock baseline" "no baseline: a keep notice explains why"
assert_contains "$out" "keep  CLAUDE.md" "CLAUDE.md with the gate plus user text is kept and reported"
assert_eq "plan C" "$(cat "$PC/.harness-mini/docs/exec-plans/active/0001-c.md")" "no baseline: plans still move"
assert_contains "$(cat "$PC/AGENTS.md")" "OLD MAP" "no baseline: AGENTS.md text kept"
assert_contains "$(cat "$PC/AGENTS.md")" "$BLOCK1" "no baseline: the marker block is appended to AGENTS.md"
assert_eq "$gi_sha" "$(sha "$PC/.gitignore")" "no baseline: project .gitignore byte-identical"

# --- (d) two projects stay independent -----------------------------------------
PD1="$(mktemp -d)"; PD2="$(mktemp -d)"
for p in "$PD1" "$PD2"; do
  mkdir -p "$p/docs/exec-plans/active" "$p/bin"; printf 'plan in %s\n' "$(basename "$p")" > "$p/docs/exec-plans/active/0001-x.md"
  printf 'old exe\n' > "$p/bin/harness.sh"; mklock "$p" 0.11.0 bin/harness.sh
done
d2_before="$(snap "$PD2")"
mig_init "$PD1" >/dev/null
assert_eq "$d2_before" "$(snap "$PD2")" "two projects: migrating one never touches the other"
assert_eq "false" "$(has "$PD1/bin")" "two projects: the first is migrated"
d1_after="$(snap "$PD1")"
mig_init "$PD2" >/dev/null
assert_eq "$d1_after" "$(snap "$PD1")" "two projects: migrating the second leaves the first unchanged"
assert_eq "plan in $(basename "$PD2")" "$(cat "$PD2/.harness-mini/docs/exec-plans/active/0001-x.md")" "two projects: the second keeps its own plan"
assert_eq "true" "$([ "$(mstate "$PD1")" != "$(mstate "$PD2")" ] && echo true || echo false)" "two projects: separate state dirs"

# --- (e) harness.sh update migrates too ----------------------------------------
PE="$(mktemp -d)"
mkdir -p "$PE/docs/exec-plans/active" "$PE/.trace/checkpoints" "$PE/bin"
printf 'plan E\n' > "$PE/docs/exec-plans/active/0001-e.md"; printf 'cpE\n' > "$PE/.trace/checkpoints/c.md"
printf 'old exe\n' > "$PE/bin/harness.sh"; mklock "$PE" 0.11.0 bin/harness.sh
out="$(HARNESS_HOME="$MH" HARNESS_ROOT="$PE" bash "$HARN" update --src "$MS" 2>&1)"; code=$?
assert_exit 0 "$code" "update on a legacy project exits 0"
assert_contains "$out" "migr  moved docs/exec-plans/active/0001-e.md" "update reports the plan move"
assert_eq "plan E" "$(cat "$PE/.harness-mini/docs/exec-plans/active/0001-e.md")" "update moves plans into .harness-mini/"
assert_eq "cpE" "$(cat "$PE/.harness-mini/trace/checkpoints/c.md")" "update moves checkpoints into .harness-mini/trace"
assert_eq "false" "$(has "$PE/bin")" "update removes a lock-clean legacy bin/"
assert_eq "false" "$(has "$PE/harness")" "update removes the consumed old lock and its emptied harness/ dir"
s1="$(snap "$PE")"; HARNESS_HOME="$MH" HARNESS_ROOT="$PE" bash "$HARN" update --src "$MS" >/dev/null 2>&1
assert_eq "$s1" "$(snap "$PE")" "update repeat run changes nothing in the project"
rm -rf "$MS" "$MH" "$PA" "$PB" "$PC" "$PD1" "$PD2" "$PE"

# =============================================================================
echo "legacy upgrade — the runtime is installed and usable BEFORE anything is removed (B1)"
# @group legacy-upgrade
NEWVER="$(tr -d ' \t\r\n' < "$ROOT/VERSION")"
block_hs() { grep -o '"[^"]*/bin/harness.sh"' "$1/AGENTS.md" 2>/dev/null | head -n1 | tr -d '"'; }
have_tag() { git -C "$ROOT" rev-parse -q --verify refs/tags/v0.12.1 >/dev/null 2>&1; }
# mk_v0121 <project> — the released v0.12.1 layout: the REAL v0.12.1 init.sh from git
mk_v0121() {
  local s; s="$(mktemp -d)"
  git -C "$ROOT" archive v0.12.1 | tar -x -C "$s"
  mkdir -p "$1"; printf '{}\n' > "$1/package.json"; git -C "$1" init -q 2>/dev/null
  ( cd "$1" && HARNESS_HOME="$(mktemp -d)" bash "$s/init.sh" "$1" >/dev/null 2>&1 )
  rm -rf "$s"
}
# assert_upgraded <project> <home> <label> — a working install under <home>, project migrated
assert_upgraded() {
  local p="$1" h="$2" l="$3" hs rc=0
  assert_eq "true" "$(has "$h/bin/harness.sh")" "$l: runtime bin installed at HARNESS_HOME"
  assert_eq "$NEWVER" "$(cat "$h/VERSION" 2>/dev/null)" "$l: runtime VERSION is the new version"
  assert_eq "$NEWVER" "$(sed -n 's/^version: //p' "$h/harness/runtime.lock" 2>/dev/null)" "$l: runtime.lock records the new version"
  assert_eq "true" "$(has "$h/harness/global.lock")" "$l: global.lock written"
  assert_eq "true" "$(has "$h/skills/tdd/SKILL.md")" "$l: global skills installed"
  assert_eq "true" "$(has "$h/AGENTS.md")" "$l: global map installed"
  hs="$(block_hs "$p")"
  assert_eq "$h/bin/harness.sh" "$hs" "$l: AGENTS.md block points at the runtime's harness.sh"
  assert_eq "true" "$(has "$hs")" "$l: the harness.sh the block names exists"
  HARNESS_HOME="$h" bash "$hs" agent list >/dev/null 2>&1 || rc=$?
  assert_exit 0 "$rc" "$l: agent list works"
  assert_contains "$(cd "$p" && HARNESS_HOME="$h" bash "$hs" status 2>&1)" "path:" "$l: status works"
  assert_eq "true" "$(has "$p/.harness-mini/docs/exec-plans/active/0001-recon.md")" "$l: plan migrated into .harness-mini/"
  assert_eq "false" "$(has "$p/bin")" "$l: project bin/ removed (only now that a runtime exists)"
  assert_eq "false" "$(has "$p/harness")" "$l: old harness/ dir gone"
}

if have_tag; then
  # --- (1) update twice: the CHANGELOG's advice for a v0.12.1 project -----------
  BP1="$(mktemp -d)"; BH1="$(mktemp -d)"; mk_v0121 "$BP1"
  assert_eq "true" "$(has "$BP1/bin/harness.sh")" "v0.12.1 fixture: project-local bin/ (no runtime under HARNESS_HOME)"
  ( cd "$BP1" && HARNESS_HOME="$BH1" bash bin/harness.sh update --src "$ROOT" >/dev/null 2>&1 )
  assert_eq "true" "$(has "$BP1/bin/harness.sh")" "update #1 (old code) leaves the project's bin/ in place"
  rc=0; ( cd "$BP1" && HARNESS_HOME="$BH1" bash bin/harness.sh status >/dev/null 2>&1 ) || rc=$?
  assert_exit 0 "$rc" "update #1: the project's own harness still runs"
  out="$(cd "$BP1" && HARNESS_HOME="$BH1" bash bin/harness.sh update --src "$ROOT" 2>&1)"; rc=$?
  assert_exit 0 "$rc" "update #2 exits 0"
  assert_upgraded "$BP1" "$BH1" "v0.12.1 update x2"
  s1="$(snap "$BP1"; snap "$BH1")"
  ( cd "$BP1" && HARNESS_HOME="$BH1" bash "$BH1/bin/harness.sh" update --src "$ROOT" >/dev/null 2>&1 )
  assert_eq "$s1" "$(snap "$BP1"; snap "$BH1")" "v0.12.1 update x3 (from the installed runtime): changes nothing"

  # --- (2) a single update run by the NEW code (source checkout) ----------------
  BP2="$(mktemp -d)"; BH2="$(mktemp -d)"; mk_v0121 "$BP2"
  out="$(HARNESS_HOME="$BH2" HARNESS_ROOT="$BP2" bash "$ROOT/bin/harness.sh" update --src "$ROOT" 2>&1)"; rc=$?
  assert_exit 0 "$rc" "update by new code on a v0.12.1 project exits 0"
  assert_upgraded "$BP2" "$BH2" "v0.12.1 update x1 (new code)"

  # --- (3) init.sh re-run from the new source ------------------------------------
  BP3="$(mktemp -d)"; BH3="$(mktemp -d)"; mk_v0121 "$BP3"
  out="$(HARNESS_HOME="$BH3" bash "$ROOT/init.sh" "$BP3" 2>&1)"; rc=$?
  assert_exit 0 "$rc" "init.sh on a v0.12.1 project exits 0"
  assert_upgraded "$BP3" "$BH3" "v0.12.1 init.sh"
  BP4="$(mktemp -d)"; BH4="$(mktemp -d)"; mk_v0121 "$BP4"
  ( cd "$BP4" && HARNESS_HOME="$BH4" bash bin/harness.sh update --src "$ROOT" >/dev/null 2>&1 )
  out="$(HARNESS_HOME="$BH4" bash "$ROOT/init.sh" "$BP4" 2>&1)"; rc=$?
  assert_exit 0 "$rc" "init.sh after update #1 exits 0"
  assert_upgraded "$BP4" "$BH4" "v0.12.1 update then init.sh"
  rm -rf "$BP1" "$BH1" "$BP2" "$BH2" "$BP3" "$BH3" "$BP4" "$BH4"
else
  echo "  skip v0.12.1 end-to-end (tag v0.12.1 not available in this checkout)"
fi

# --- (4) bootstrap impossible: abort BEFORE deleting or moving anything ----------
# hand-made faithful fixture: lock-clean project bin/, an old lock, a plan, no runtime anywhere
mk_stranded() { # <project> — v0.12.1-shaped project whose only harness is project-local
  mkdir -p "$1/bin" "$1/docs/exec-plans/active" "$1/.claude/skills/tdd" "$1/harness"
  cp "$BIN"/*.sh "$1/bin/"; printf 'plan S\n' > "$1/docs/exec-plans/active/0001-s.md"
  printf 'old tdd\n' > "$1/.claude/skills/tdd/SKILL.md"
  # shellcheck disable=SC2046 # intentional: mklock takes each lock entry as its own arg
  mklock "$1" 0.12.1 $(cd "$1" && ls bin/*.sh) .claude/skills/tdd/SKILL.md
}
STRIPPED="$(mktemp -d)"; printf '9.9.9\n' > "$STRIPPED/VERSION"          # a source with no bin/: cannot bootstrap
SP1="$(mktemp -d)"; SH1="$(mktemp -d)"; mk_stranded "$SP1"; sp_before="$(snap "$SP1")"
out="$(cd "$SP1" && HARNESS_HOME="$SH1" bash bin/harness.sh update --src "$STRIPPED" 2>&1)"; rc=$?
assert_eq "true" "$([ "$rc" -ne 0 ] && echo true || echo false)" "bootstrap impossible: update fails"
assert_eq "$sp_before" "$(snap "$SP1")" "bootstrap impossible: update left the project byte-identical (nothing moved or removed)"
assert_contains "$out" "nothing was" "bootstrap impossible: update explains that nothing was changed"
assert_contains "$out" "init.sh" "bootstrap impossible: update prints the next step"
assert_eq "false" "$(has "$SH1/bin/harness.sh")" "bootstrap impossible: no half-installed runtime"
SP2="$(mktemp -d)"; SH2="$(mktemp -d)"; mk_stranded "$SP2"; sp_before="$(snap "$SP2")"
out="$(HARNESS_SRC="$STRIPPED" HARNESS_HOME="$SH2" bash "$ROOT/init.sh" "$SP2" 2>&1)"; rc=$?
assert_eq "true" "$([ "$rc" -ne 0 ] && echo true || echo false)" "bootstrap impossible: init.sh fails"
assert_eq "$sp_before" "$(snap "$SP2")" "bootstrap impossible: init.sh left the project byte-identical"
assert_contains "$out" "nothing was" "bootstrap impossible: init.sh explains that nothing was changed"
# the same project upgrades fine once a real source is available (hand-made fixture, no git tag needed)
out="$(cd "$SP1" && HARNESS_HOME="$SH1" bash bin/harness.sh update --src "$ROOT" 2>&1)"; rc=$?
assert_exit 0 "$rc" "stranded project: update from a real source exits 0"
assert_eq "true" "$(has "$SH1/bin/harness.sh")" "stranded project: runtime bootstrapped from the source tree"
assert_eq "false" "$(has "$SP1/bin")" "stranded project: project bin/ removed after the runtime exists"
assert_eq "plan S" "$(cat "$SP1/.harness-mini/docs/exec-plans/active/0001-s.md")" "stranded project: plan migrated"
rm -rf "$STRIPPED" "$SP1" "$SH1" "$SP2" "$SH2"

# =============================================================================
echo "init.sh refreshes an older runtime under HARNESS_HOME (M2)"
# a 0058-era runtime: its lock baselines match its files; its harness.sh predates `agent`
OH="$(mktemp -d)"; mkdir -p "$OH/bin" "$OH/harness"
printf '#!/usr/bin/env bash\ncase "$1" in agent) echo "unknown command: agent" >&2; exit 64;; esac\n' > "$OH/bin/harness.sh"
printf '# old lib\n' > "$OH/bin/_harness_lib.sh"; printf '# old ctx\n' > "$OH/bin/ctx.sh"; printf '0.9.0\n' > "$OH/VERSION"
{ printf 'version: 0.9.0\n'; for f in harness.sh _harness_lib.sh ctx.sh; do printf '%s  bin/%s\n' "$(sha "$OH/bin/$f")" "$f"; done; } > "$OH/harness/runtime.lock"
printf 'user tweak\n' >> "$OH/bin/ctx.sh"                       # a user-edited runtime file
OP="$(mktemp -d)"; printf '{}\n' > "$OP/package.json"
out="$(HARNESS_HOME="$OH" bash "$ROOT/init.sh" "$OP" 2>&1)"; rc=$?
assert_exit 0 "$rc" "old runtime + init.sh exits 0"
assert_eq "$(sha "$ROOT/bin/harness.sh")" "$(sha "$OH/bin/harness.sh")" "pristine runtime file upgraded to the new source"
assert_eq "$(sha "$ROOT/bin/_harness_lib.sh")" "$(sha "$OH/bin/_harness_lib.sh")" "pristine runtime lib upgraded"
assert_eq "$NEWVER" "$(cat "$OH/VERSION")" "runtime VERSION updated"
assert_eq "$NEWVER" "$(sed -n 's/^version: //p' "$OH/harness/runtime.lock")" "runtime.lock version updated"
assert_contains "$(tail -n1 "$OH/bin/ctx.sh")" "user tweak" "user-edited runtime file kept"
assert_eq "$(sha "$ROOT/bin/ctx.sh")" "$(sha "$OH/bin/ctx.sh.new")" "user-edited runtime file gets the upstream copy as .new"
assert_contains "$out" "ctx.sh" "the kept runtime file is reported"
rc=0; HARNESS_HOME="$OH" bash "$OH/bin/harness.sh" agent list >/dev/null 2>&1 || rc=$?
assert_exit 0 "$rc" "old runtime + init.sh: agent list works"
assert_eq "true" "$(has "$OH/skills/tdd/SKILL.md")" "old runtime + init.sh: global assets installed"
s1="$(snap "$OH"; snap "$OP")"; out="$(HARNESS_HOME="$OH" bash "$ROOT/init.sh" "$OP" 2>&1)"
assert_eq "$s1" "$(snap "$OH"; snap "$OP")" "old runtime + init.sh: a repeat run changes nothing"
# never downgrade: a newer installed runtime is left alone
NH="$(mktemp -d)"; HARNESS_HOME="$NH" bash "$ROOT/init.sh" "$OP" >/dev/null 2>&1
printf '99.0.0\n' > "$NH/VERSION"; sed -i.bak 's/^version: .*/version: 99.0.0/' "$NH/harness/runtime.lock"; rm -f "$NH/harness/runtime.lock.bak"
printf '# future\n' > "$NH/bin/ctx.sh"
{ printf 'version: 99.0.0\n'; awk '$1 != "version:" && $2 != "bin/ctx.sh"' "$NH/harness/runtime.lock"; printf '%s  bin/ctx.sh\n' "$(sha "$NH/bin/ctx.sh")"; } > "$NH/harness/runtime.lock.t" && mv "$NH/harness/runtime.lock.t" "$NH/harness/runtime.lock"
HARNESS_HOME="$NH" bash "$ROOT/init.sh" "$OP" >/dev/null 2>&1
assert_eq "99.0.0" "$(cat "$NH/VERSION")" "init.sh never downgrades a newer runtime (VERSION)"
assert_eq "# future" "$(cat "$NH/bin/ctx.sh")" "init.sh never downgrades a newer runtime (files)"
rm -rf "$OH" "$OP" "$NH"

# =============================================================================
echo "legacy migration — REAL generated 0058/0.12/0.10 manifests are recognised (M1)"
# @group migration-manifests
# (real_manifest — the generated old-init.sh manifest shape — is defined with the
# shared fixture helpers in the header, ahead of its first use below)
XS="$(mktemp -d)"; XH="$(mktemp -d)"
mkdir -p "$XS/skills/tdd" "$XS/agents" "$XS/docs"; cp -R "$BIN" "$XS/bin"
printf 'NEW tdd\n' > "$XS/skills/tdd/SKILL.md"; printf 'role\n' > "$XS/agents/planner.md"; printf 'map\n' > "$XS/AGENTS.md"
printf '0.13.0\n' > "$XS/VERSION"
x_init() { HARNESS_SRC="$XS" HARNESS_HOME="$XH" bash "$ROOT/init.sh" "$1" 2>&1; }
for variant in 0058 0121 0100; do
  XP="$(mktemp -d)"; mkdir -p "$XP/harness" "$XP/docs"
  printf 'old principles\n' > "$XP/docs/principles.md"
  real_manifest "$variant" > "$XP/harness/manifest.md"
  mklock "$XP" 0.12.1 docs/principles.md
  out="$(x_init "$XP")"
  assert_eq "false" "$(has "$XP/harness/manifest.md")" "manifest $variant: the generated manifest is removed"
  assert_eq "0" "$(printf '%s\n' "$out" | grep -c 'harness/manifest.md (edited')" "manifest $variant: never reported as edited"
  assert_eq "false" "$(has "$XP/harness")" "manifest $variant: harness/ dir is gone once the lock is consumed"
  out2="$(x_init "$XP")"
  assert_eq "0" "$(printf '%s\n' "$out2" | grep -c 'baseline')" "manifest $variant: the no-baseline notice does not repeat on a re-run"
  assert_eq "0" "$(printf '%s\n' "$out2" | grep -c '^  keep')" "manifest $variant: a clean re-run prints no keep line"
  rm -rf "$XP"
done
# a hand-edited manifest is preserved
XP="$(mktemp -d)"; mkdir -p "$XP/harness" "$XP/docs"; printf 'old principles\n' > "$XP/docs/principles.md"
{ real_manifest 0058; printf 'MY OWN NOTES ABOUT THE SKILLS\n'; } > "$XP/harness/manifest.md"
mklock "$XP" 0.12.1 docs/principles.md
out="$(x_init "$XP")"
assert_contains "$(cat "$XP/harness/manifest.md")" "MY OWN NOTES" "an edited manifest is kept"
assert_contains "$out" "keep  harness/manifest.md (edited" "an edited manifest is reported"
out2="$(x_init "$XP")"; out3="$(x_init "$XP")"
assert_eq "$out2" "$out3" "an edited manifest: re-runs are stable"
assert_eq "true" "$([ "$(printf '%s\n' "$out2" | grep -c '^  keep')" -le 1 ] && echo true || echo false)" "an edited manifest: a re-run prints at most one keep line"
rm -rf "$XP"

# =============================================================================
echo "legacy migration — leftovers (docs/assets, docs/references, generated Cursor rules) and noise (m1/m2)"
# the state after the OLD runtime's `update` rewrote the lock: it no longer lists docs/references/*
XP="$(mktemp -d)"; mkdir -p "$XP/docs/references" "$XP/docs/assets" "$XP/.claude/skills/ralph-loop" "$XP/.cursor/rules" "$XP/harness"
mkdir -p "$XS/references" "$XS/assets" "$XS/docs"
printf 'ref one\n' > "$XS/references/r1.txt"; printf 'ref two\n' > "$XS/references/r2.txt"; printf 'svg\n' > "$XS/assets/banner.svg"
printf 'canon assumptions\n' > "$XS/docs/assumptions.md"; printf 'canon walk\n' > "$XS/docs/walkthrough.md"
printf 'ref one\n' > "$XP/docs/references/r1.txt"; printf 'EDITED ref two\n' > "$XP/docs/references/r2.txt"
printf 'svg\n' > "$XP/docs/assets/banner.svg"
printf 'canon assumptions\n' > "$XP/docs/assumptions.md"; printf 'my walkthrough\n' > "$XP/docs/walkthrough.md"
printf -- '---\ndescription: NEW ralph description\n---\nbody\n' > "$XP/.claude/skills/ralph-loop/SKILL.md"
# generated when the skill description was still the old one:
printf -- '---\ndescription: OLD ralph description\nalwaysApply: false\n---\n\nharness-mini skill **ralph-loop**. Read `.claude/skills/ralph-loop/SKILL.md` and follow it for this task.\n' > "$XP/.cursor/rules/ralph-loop.mdc"
printf -- '---\ndescription: OLD ralph description\nalwaysApply: false\n---\n\nMY EXTRA RULE TEXT\n' > "$XP/.cursor/rules/ralph-edited.mdc"
printf -- '---\ndescription: x\nalwaysApply: false\n---\n\nharness-mini skill **mine**. Read `.claude/skills/mine/SKILL.md` and follow it for this task.\n' > "$XP/.cursor/rules/mine.mdc"
mklock "$XP" 0.12.1 .claude/skills/ralph-loop/SKILL.md      # the lock lists neither docs/references nor the doc copies
out="$(x_init "$XP")"
assert_eq "false" "$(has "$XP/docs/assets")" "leftover: an unmodified docs/assets/banner.svg is removed"
assert_eq "false" "$(has "$XP/docs/references/r1.txt")" "leftover: an unmodified docs/references file is removed"
assert_eq "EDITED ref two" "$(cat "$XP/docs/references/r2.txt")" "leftover: an edited docs/references file is kept"
assert_eq "false" "$(has "$XP/docs/assumptions.md")" "leftover: a doc identical to the shared copy is removed"
assert_eq "my walkthrough" "$(cat "$XP/docs/walkthrough.md")" "leftover: a doc that differs from the shared copy is kept"
assert_eq "true" "$(has "$XP/.cursor/rules/ralph-loop.mdc")" "leftover: a rule whose description is not a known generated value is kept (N3)"
assert_contains "$out" ".cursor/rules/ralph-loop.mdc" "leftover: that kept rule is named in the kept notice (N3)"
assert_eq "true" "$(has "$XP/.cursor/rules/ralph-edited.mdc")" "leftover: a rule with edited body is kept"
assert_eq "true" "$(has "$XP/.cursor/rules/mine.mdc")" "leftover: a rule for a non-harness skill is kept"
assert_eq "2" "$(printf '%s\n' "$out" | grep -c 'leftover legacy harness file')" "leftover: every kept file is listed on its own line (N4)"
assert_contains "$out" "docs/walkthrough.md" "leftover: the list names the kept docs"
assert_contains "$out" "docs/references/r2.txt" "leftover: the list names every kept file"
s1="$(snap "$XP"; snap "$XH")"; out2="$(x_init "$XP")"
assert_eq "$s1" "$(snap "$XP"; snap "$XH")" "leftover: a repeat run changes nothing"
assert_eq "true" "$([ "$(printf '%s\n' "$out2" | grep -c '^  keep')" -le 1 ] && echo true || echo false)" "noise: a repeat run prints at most one keep line"
assert_eq "0" "$(printf '%s\n' "$out2" | grep -c 'principles')" "noise: no path is reported twice"
rm -rf "$XP" "$XS" "$XH"

# =============================================================================
echo "doctor/status surface unresolved .new files under HARNESS_HOME (m5)"
# @group update-conflicts
NS="$(mktemp -d)"; NH="$(mktemp -d)"; NP="$(mktemp -d)"
mkdir -p "$NS/skills/tdd" "$NS/agents" "$NS/docs"; cp -R "$BIN" "$NS/bin"
printf 'S\n' > "$NS/skills/tdd/SKILL.md"; printf 'r\n' > "$NS/agents/planner.md"; printf 'map\n' > "$NS/AGENTS.md"; printf 'old\n' > "$NS/docs/principles.md"
printf '0.1.0\n' > "$NS/VERSION"
HARNESS_SRC="$NS" HARNESS_HOME="$NH" bash "$ROOT/init.sh" "$NP" >/dev/null 2>&1
printf 'LOCAL\n' > "$NH/docs/principles.md"; printf 'new\n' > "$NS/docs/principles.md"; printf '0.2.0\n' > "$NS/VERSION"
HARNESS_HOME="$NH" bash "$NH/bin/harness.sh" --root "$NP" update --src "$NS" >/dev/null 2>&1
assert_eq "true" "$(has "$NH/docs/principles.md.new")" "global fixture: an edited global doc received a .new"
out="$(HARNESS_HOME="$NH" bash "$NH/bin/harness.sh" --root "$NP" doctor 2>&1)"
assert_contains "$out" "unresolved .new" "doctor mentions the unresolved .new count"
assert_eq "true" "$(printf '%s\n' "$out" | grep 'unresolved .new' | grep -q '^  warn' && echo true || echo false)" "doctor warns about a global .new"
assert_contains "$(HARNESS_HOME="$NH" bash "$NH/bin/harness.sh" --root "$NP" status 2>&1)" "update conflicts: 1 .new" "status counts a global .new"
rm -rf "$NS" "$NH" "$NP"

# =============================================================================
echo "upgrade polish (0060) — N1: diff subcommand, the .new notice, refusal text"
# @group update-polish
mk_src() { # <dir> <version> — a small source tree that ships the real runtime
  mkdir -p "$1/skills/tdd" "$1/agents" "$1/docs"; cp -R "$BIN" "$1/bin"
  printf -- '---\nname: tdd\ndescription: tdd desc\n---\nS\n' > "$1/skills/tdd/SKILL.md"
  printf 'r\n' > "$1/agents/planner.md"; printf 'map\n' > "$1/AGENTS.md"; printf '%s\n' "$2" > "$1/VERSION"
}
PS="$(mktemp -d)"; PH="$(mktemp -d)"; PP="$(mktemp -d)"
mk_src "$PS" 0.2.0; printf 'one\n' > "$PS/docs/principles.md"
HARNESS_SRC="$PS" HARNESS_HOME="$PH" bash "$ROOT/init.sh" "$PP" >/dev/null 2>&1
HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" --root "$PP" agent install claude >/dev/null 2>&1
printf 'LOCAL\n' > "$PH/docs/principles.md"; printf '# local\n' >> "$PH/bin/ctx.sh"
printf 'LOCAL tdd\n' >> "$PP/.claude/skills/tdd/SKILL.md"
printf 'two\n' > "$PS/docs/principles.md"; printf '# upstream\n' >> "$PS/bin/ctx.sh"; printf 'S2\n' >> "$PS/skills/tdd/SKILL.md"
printf '0.3.0\n' > "$PS/VERSION"
out="$(HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" --root "$PP" update --src "$PS" 2>&1)"; rc=$?
assert_exit 0 "$rc" "update with edited files exits 0"
assert_contains "$out" "!! harness-mini: 3 file(s) were NOT upgraded because you edited them" "notice: prominent banner with the file count"
assert_contains "$out" "managed by harness-mini" "notice: says install-dir files are managed by harness-mini"
assert_contains "$out" "$PH/bin/ctx.sh.new" "notice: lists the runtime .new"
assert_contains "$out" "$PH/docs/principles.md.new" "notice: lists the global .new"
assert_contains "$out" "$PP/.claude/skills/tdd/SKILL.md.new" "notice: lists the project .new"
assert_contains "$out" "/bin/harness.sh\" diff docs/principles.md" "notice: runnable diff line for a global file"
assert_contains "$out" "diff .claude/skills/tdd/SKILL.md --root" "notice: the diff line for a project file carries --root"
assert_eq "3" "$(printf '%s\n' "$out" | grep -c 'see the difference')" "notice: one diff line per file (<= 5 files)"
cmdline="$(printf '%s\n' "$out" | sed -n 's/^ *see the difference: *//p' | grep 'principles' | head -n1)"
run="$(cd "$PP" && eval "$cmdline" 2>&1)"; rc=$?
assert_exit 0 "$rc" "notice: the printed diff line runs as printed"
assert_contains "$run" "-LOCAL" "notice: the printed diff line shows the kept (yours) side"
assert_contains "$run" "+two" "notice: the printed diff line shows the upstream side"
# harness.sh diff
out="$(HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" --root "$PP" diff docs/principles.md 2>&1)"; rc=$?
assert_exit 0 "$rc" "diff: a global file with a .new exits 0"
assert_contains "$out" "-LOCAL" "diff: shows your copy"
assert_contains "$out" "+two" "diff: shows the upstream .new"
assert_contains "$out" "yours" "diff: labels your side"
assert_contains "$out" "upstream" "diff: labels the upstream side"
out="$(HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" --root "$PP" diff bin/ctx.sh 2>&1)"; rc=$?
assert_exit 0 "$rc" "diff: a runtime file with a .new exits 0"
assert_contains "$out" "+# upstream" "diff: a runtime file shows its upstream change"
out="$(HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" --root "$PP" diff .claude/skills/tdd/SKILL.md 2>&1)"; rc=$?
assert_exit 0 "$rc" "diff: a project file with a .new exits 0"
assert_contains "$out" "-LOCAL tdd" "diff: a project file shows your edit"
out="$(HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" --root "$PP" diff "$PH/docs/principles.md" 2>&1)"; rc=$?
assert_exit 0 "$rc" "diff: an absolute path works"
out="$(HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" --root "$PP" diff skills/tdd/SKILL.md 2>&1)"; rc=$?
assert_exit 1 "$rc" "diff: a file without a .new exits 1"
assert_contains "$out" "no .new" "diff: says there is no .new to compare"
out="$(HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" --root "$PP" diff docs/nothing.md 2>&1)"; rc=$?
assert_exit 1 "$rc" "diff: an unknown file exits 1"
assert_contains "$out" "not found" "diff: says the file was not found"
rc=0; HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" --root "$PP" diff >/dev/null 2>&1 || rc=$?
assert_exit 64 "$rc" "diff: no argument is a usage error"
assert_contains "$(HARNESS_HOME="$PH" bash "$PH/bin/harness.sh" help 2>&1)" "diff <" "help documents diff"
# more than 5 files: one generic line
S6="$(mktemp -d)"; H6="$(mktemp -d)"; P6="$(mktemp -d)"; mk_src "$S6" 0.2.0
for i in 1 2 3 4 5 6; do printf 'u%s\n' "$i" > "$S6/docs/d$i.md"; done
HARNESS_SRC="$S6" HARNESS_HOME="$H6" bash "$ROOT/init.sh" "$P6" >/dev/null 2>&1
for i in 1 2 3 4 5 6; do printf 'mine%s\n' "$i" > "$H6/docs/d$i.md"; printf 'v%s\n' "$i" > "$S6/docs/d$i.md"; done
printf '0.3.0\n' > "$S6/VERSION"
out="$(HARNESS_HOME="$H6" bash "$H6/bin/harness.sh" --root "$P6" update --src "$S6" 2>&1)"
assert_contains "$out" "!! harness-mini: 6 file(s) were NOT upgraded" "notice: counts six files"
for i in 1 2 3 4 5 6; do assert_contains "$out" "$H6/docs/d$i.md.new" "notice: lists d$i.md.new"; done
assert_eq "1" "$(printf '%s\n' "$out" | grep -c 'see the difference')" "notice: more than 5 files -> one generic diff line"
# init.sh prints it too, and a clean run stays quiet
printf '0.4.0\n' > "$S6/VERSION"; printf '# more\n' >> "$S6/bin/ctx.sh"; printf '# tweak\n' >> "$H6/bin/ctx.sh"
out="$(HARNESS_SRC="$S6" HARNESS_HOME="$H6" bash "$ROOT/init.sh" "$P6" 2>&1)"
assert_contains "$out" "!! harness-mini:" "notice: init.sh prints it after an upgrade that kept edited files"
assert_contains "$out" "$H6/bin/ctx.sh.new" "notice: init.sh lists the kept runtime file"
QS="$(mktemp -d)"; QH="$(mktemp -d)"; QP="$(mktemp -d)"; mk_src "$QS" 0.2.0
out="$(HARNESS_SRC="$QS" HARNESS_HOME="$QH" bash "$ROOT/init.sh" "$QP" 2>&1)"
assert_eq "0" "$(printf '%s\n' "$out" | grep -c '!!')" "notice: a clean first init prints no notice"
out="$(HARNESS_SRC="$QS" HARNESS_HOME="$QH" bash "$ROOT/init.sh" "$QP" 2>&1)"
assert_eq "0" "$(printf '%s\n' "$out" | grep -c '!!')" "notice: a clean re-run prints no notice"
printf '0.3.0\n' > "$QS/VERSION"
out="$(HARNESS_HOME="$QH" bash "$QH/bin/harness.sh" --root "$QP" update --src "$QS" 2>&1)"
assert_eq "0" "$(printf '%s\n' "$out" | grep -c '!!')" "notice: a clean update prints no notice"
rm -rf "$S6" "$H6" "$P6" "$QS" "$QH" "$QP"
# refusal caused by an edited runtime file (the 0059 L2 N1 repro)
RH="$(mktemp -d)"; mkdir -p "$RH/bin" "$RH/harness"
printf '#!/usr/bin/env bash\ncase "$1" in agent) echo "unknown command: agent" >&2; exit 64;; esac\n' > "$RH/bin/harness.sh"
printf '# old lib\n' > "$RH/bin/_harness_lib.sh"; printf '0.9.0\n' > "$RH/VERSION"
{ printf 'version: 0.9.0\n'; for f in harness.sh _harness_lib.sh; do printf '%s  bin/%s\n' "$(sha "$RH/bin/$f")" "$f"; done; } > "$RH/harness/runtime.lock"
printf '# local\n' >> "$RH/bin/harness.sh"
RP="$(mktemp -d)"; mkdir -p "$RP/docs/exec-plans/active"; printf 'plan\n' > "$RP/docs/exec-plans/active/0001-x.md"
before="$(snap "$RP")"
out="$(HARNESS_HOME="$RH" bash "$ROOT/init.sh" "$RP" 2>&1)"; rc=$?
assert_eq "true" "$([ "$rc" -ne 0 ] && echo true || echo false)" "refusal: init.sh exits non-zero"
assert_eq "$before" "$(snap "$RP")" "refusal: the project is untouched"
assert_contains "$out" "bin/harness.sh.new" "refusal: names the .new file that blocks the upgrade"
assert_contains "$out" "diff" "refusal: shows the diff command"
assert_eq "0" "$(printf '%s\n' "$out" | grep -c 'get the new harness-mini')" "refusal: does not tell the user to re-run init.sh as the fix"
cmdline="$(printf '%s\n' "$out" | sed -n 's/^ *see the difference: *//p' | head -n1)"
run="$(cd "$RP" && eval "$cmdline" 2>&1)"      # plain diff(1): the runtime's own harness.sh is stale here
assert_contains "$run" "-# local" "refusal: the printed diff line runs as printed and shows the user's edit"
out="$(cd "$RP" && HARNESS_HOME="$RH" bash "$ROOT/bin/harness.sh" update --src "$ROOT" 2>&1)"; rc=$?
assert_eq "true" "$([ "$rc" -ne 0 ] && echo true || echo false)" "refusal: update exits non-zero"
assert_contains "$out" "bin/harness.sh.new" "refusal: update names the blocking .new too"
assert_eq "$before" "$(snap "$RP")" "refusal: update leaves the project untouched"
rm -rf "$RH" "$RP"

# =============================================================================
echo "upgrade polish (0060) — N2: update refuses to downgrade the runtime"
DS="$(mktemp -d)"; DH="$(mktemp -d)"; DP="$(mktemp -d)"; mk_src "$DS" 0.2.0
HARNESS_SRC="$DS" HARNESS_HOME="$DH" bash "$ROOT/init.sh" "$DP" >/dev/null 2>&1
DO="$(mktemp -d)"; mk_src "$DO" 0.1.0
s1="$(snap "$DH"; snap "$DP")"
out="$(HARNESS_HOME="$DH" bash "$DH/bin/harness.sh" --root "$DP" update --src "$DO" 2>&1)"; rc=$?
assert_eq "true" "$([ "$rc" -ne 0 ] && echo true || echo false)" "downgrade: update --src an older source exits non-zero"
assert_contains "$out" "downgrade" "downgrade: the message says it refuses to downgrade"
assert_contains "$out" "--force" "downgrade: the message names --force"
assert_eq "$s1" "$(snap "$DH"; snap "$DP")" "downgrade: refused update changes nothing"
assert_eq "0.2.0" "$(cat "$DH/VERSION")" "downgrade: runtime VERSION unchanged"
out="$(HARNESS_HOME="$DH" bash "$DH/bin/harness.sh" --root "$DP" update --src "$DS" 2>&1)"; rc=$?
assert_exit 0 "$rc" "same version: update still works"
assert_contains "$out" "already up to date" "same version: update reports nothing to do"
mk_src "$DO" 0.3.0
out="$(HARNESS_HOME="$DH" bash "$DH/bin/harness.sh" --root "$DP" update --src "$DO" 2>&1)"; rc=$?
assert_exit 0 "$rc" "upgrade: update to a newer source works"
assert_eq "0.3.0" "$(cat "$DH/VERSION")" "upgrade: runtime VERSION advanced"
mk_src "$DO" 0.1.0
out="$(HARNESS_HOME="$DH" bash "$DH/bin/harness.sh" --root "$DP" update --src "$DO" --force 2>&1)"; rc=$?
assert_exit 0 "$rc" "downgrade: --force allows it"
assert_eq "0.1.0" "$(cat "$DH/VERSION")" "downgrade: --force installs the older runtime"
assert_contains "$(HARNESS_HOME="$DH" bash "$DH/bin/harness.sh" help 2>&1)" "--force" "help documents --force"
rm -rf "$DS" "$DH" "$DP" "$DO"

# =============================================================================
echo "upgrade polish (0060) — N3: generated .mdc rules are removed only on a known description"
mk_skill() { # <src> <name> [description]
  mkdir -p "$1/skills/$2"
  if [ -n "${3:-}" ]; then printf -- '---\nname: %s\ndescription: %s\n---\nbody\n' "$2" "$3" > "$1/skills/$2/SKILL.md"
  else printf -- '---\nname: %s\n---\nbody\n' "$2" > "$1/skills/$2/SKILL.md"; fi
}
mk_rule() { # <project> <name> <description value>
  mkdir -p "$1/.cursor/rules"
  printf -- '---\ndescription: %s\nalwaysApply: false\n---\n\nharness-mini skill **%s**. Read `.claude/skills/%s/SKILL.md` and follow it for this task.\n' "$3" "$2" "$2" > "$1/.cursor/rules/$2.mdc"
}
CS="$(mktemp -d)"; CH="$(mktemp -d)"; CP="$(mktemp -d)"; mk_src "$CS" 0.13.0
mk_skill "$CS" grill-me "grill desc"; mk_skill "$CS" clean-code "clean desc"; mk_skill "$CS" refactor ""
mkdir -p "$CP/docs/exec-plans/active"; printf 'plan\n' > "$CP/docs/exec-plans/active/0001-x.md"
for n in tdd grill-me clean-code refactor; do mkdir -p "$CP/.claude/skills/$n"; cp "$CS/skills/$n/SKILL.md" "$CP/.claude/skills/$n/SKILL.md"; done
mk_rule "$CP" tdd "tdd desc"
mk_rule "$CP" refactor "harness-mini skill: refactor"
mk_rule "$CP" grill-me "MY OWN DESCRIPTION"
mk_rule "$CP" clean-code "clean desc"; printf 'MY EXTRA TEXT\n' >> "$CP/.cursor/rules/clean-code.mdc"
out="$(HARNESS_SRC="$CS" HARNESS_HOME="$CH" bash "$ROOT/init.sh" "$CP" 2>&1)"; rc=$?
assert_exit 0 "$rc" "rules: init exits 0"
assert_eq "false" "$(has "$CP/.cursor/rules/tdd.mdc")" "rules: a clean rule (description = the skill's) is removed"
assert_contains "$out" "removed unchanged generated .cursor/rules/tdd.mdc" "rules: the clean removal is reported"
assert_eq "false" "$(has "$CP/.cursor/rules/refactor.mdc")" "rules: a clean rule with the fallback description is removed"
assert_eq "true" "$(has "$CP/.cursor/rules/grill-me.mdc")" "rules: a description-only-edited rule is kept"
assert_eq "0" "$(printf '%s\n' "$out" | grep -c 'removed unchanged generated .cursor/rules/grill-me.mdc')" "rules: a kept rule is never reported as removed unchanged"
assert_contains "$out" "keep  .cursor/rules/grill-me.mdc" "rules: the kept description-edited rule is in the kept notice"
assert_eq "true" "$(has "$CP/.cursor/rules/clean-code.mdc")" "rules: a body-edited rule is kept"
assert_contains "$out" "keep  .cursor/rules/clean-code.mdc" "rules: the kept body-edited rule is in the kept notice"
assert_contains "$(cat "$CP/.cursor/rules/grill-me.mdc")" "MY OWN DESCRIPTION" "rules: the kept rule is byte-intact"
rm -rf "$CS" "$CH" "$CP"

# =============================================================================
echo "upgrade polish (0060) — N4: the leftover notice lists every path"
LS="$(mktemp -d)"; LH="$(mktemp -d)"; LP="$(mktemp -d)"; mk_src "$LS" 0.13.0
mkdir -p "$LP/docs/exec-plans/active" "$LP/harness"; printf 'plan\n' > "$LP/docs/exec-plans/active/0001-x.md"
for i in 1 2 3 4 5 6; do printf 'canon%s\n' "$i" > "$LS/docs/d$i.md"; printf 'mine%s\n' "$i" > "$LP/docs/d$i.md"; done
printf 'x\n' > "$LP/harness/manifest.md"; printf 'MY NOTES\n' >> "$LP/harness/manifest.md"
printf 'version: 0.12.1\n' > "$LP/harness/harness.lock"
out="$(HARNESS_SRC="$LS" HARNESS_HOME="$LH" bash "$ROOT/init.sh" "$LP" 2>&1)"; rc=$?
assert_exit 0 "$rc" "leftovers: init exits 0"
for i in 1 2 3 4 5 6; do assert_eq "1" "$(printf '%s\n' "$out" | grep -c "docs/d$i.md")" "leftovers: docs/d$i.md listed once"; done
assert_eq "0" "$(printf '%s\n' "$out" | grep -c '…')" "leftovers: no truncated list"
assert_eq "6" "$(printf '%s\n' "$out" | grep -c 'leftover legacy harness file')" "leftovers: one line per path"
assert_eq "$(printf '%s\n' "$out" | grep 'leftover legacy harness file' | sort)" "$(printf '%s\n' "$out" | grep 'leftover legacy harness file')" "leftovers: listed in sorted order"
# an edited manifest keeps the project legacy; the repeat run must not hide paths behind a count
out2="$(HARNESS_SRC="$LS" HARNESS_HOME="$LH" bash "$ROOT/init.sh" "$LP" 2>&1)"
assert_eq "0" "$(printf '%s\n' "$out2" | grep -cE '[0-9]+ legacy path')" "leftovers: a repeat run prints no count-only summary"
rm -rf "$LS" "$LH" "$LP"
LS="$(mktemp -d)"; LH="$(mktemp -d)"; LP="$(mktemp -d)"; mk_src "$LS" 0.13.0
mkdir -p "$LP/harness"; printf '# harness-mini manifest\nMY NOTES\n' > "$LP/harness/manifest.md"
printf 'version: 0.12.1\n' > "$LP/harness/harness.lock"
HARNESS_SRC="$LS" HARNESS_HOME="$LH" bash "$ROOT/init.sh" "$LP" >/dev/null 2>&1
out2="$(HARNESS_SRC="$LS" HARNESS_HOME="$LH" bash "$ROOT/init.sh" "$LP" 2>&1)"
assert_eq "0" "$(printf '%s\n' "$out2" | grep -cE '[0-9]+ legacy path')" "noise: an unchanged kept set is never summarised as a bare count"
rm -rf "$LS" "$LH" "$LP"

# =============================================================================
echo "CONTRIBUTING.md points at the current update command (m9)"
# @group contributing
assert_eq "0" "$(grep -c "\`bin/harness.sh update\`" "$ROOT/CONTRIBUTING.md")" "CONTRIBUTING.md no longer names the project-local bin/harness.sh update"

# --- global copies: update refreshes them with the same guard -------------------
echo "harness.sh update — global copies under \$HARNESS_HOME (0059 #7)"
GOLD="$(mktemp -d)"; GNEW="$(mktemp -d)"; GH="$(mktemp -d)"
for d in "$GOLD" "$GNEW"; do mkdir -p "$d/skills/tdd" "$d/skills/pure" "$d/agents" "$d/docs" "$d/bin"; done
printf 'g-old\n' > "$GOLD/skills/tdd/SKILL.md"; printf 'g-new\n' > "$GNEW/skills/tdd/SKILL.md"
printf 'p-same\n' | tee "$GOLD/skills/pure/SKILL.md" > "$GNEW/skills/pure/SKILL.md"
printf 'added\n' > "$GNEW/skills/tdd/extra.md"
printf 'role-old\n' > "$GOLD/agents/planner.md"; printf 'role-new\n' > "$GNEW/agents/planner.md"
printf 'map-old\n' > "$GOLD/AGENTS.md"; printf 'map-new\n' > "$GNEW/AGENTS.md"
printf 'arch-old\n' > "$GOLD/ARCHITECTURE.md"; printf 'arch-new\n' > "$GNEW/ARCHITECTURE.md"
printf 'pr-old\n' > "$GOLD/docs/principles.md"; printf 'pr-new\n' > "$GNEW/docs/principles.md"
printf '0.1.0\n' > "$GOLD/VERSION"; printf '0.2.0\n' > "$GNEW/VERSION"
GP1="$(mktemp -d)"; GP2="$(mktemp -d)"; GP3="$(mktemp -d)"
gh_init() { HARNESS_SRC="$1" HARNESS_HOME="$GH" bash "$ROOT/init.sh" "$2" >/dev/null 2>&1; }
gh_cmd()  { HARNESS_HOME="$GH" bash "$HARN" "$@"; }
gh_init "$GOLD" "$GP1"
assert_contains "$(cat "$GH/harness/global.lock")" "$(sha "$GH/skills/tdd/SKILL.md")  skills/tdd/SKILL.md" "init records the global baseline in global.lock"
gh_cmd agent install claude --root "$GP1" >/dev/null 2>&1
assert_eq "g-old" "$(cat "$GP1/.claude/skills/tdd/SKILL.md")" "agent install copies from the global skills"
printf 'LOCAL EDIT\n' > "$GH/docs/principles.md"
gh_init "$GNEW" "$GP2"
assert_eq "g-old" "$(cat "$GH/skills/tdd/SKILL.md")" "init stays additive: an existing global copy is not refreshed"
out="$(gh_cmd --root "$GP1" update --src "$GNEW" 2>&1)"; code=$?
assert_exit 0 "$code" "update with global refresh exits 0"
assert_eq "g-new"    "$(cat "$GH/skills/tdd/SKILL.md")"      "update refreshes an untouched global skill"
assert_eq "added"    "$(cat "$GH/skills/tdd/extra.md")"      "update adds a new upstream global file"
assert_eq "role-new" "$(cat "$GH/agents/planner.md")"        "update refreshes a global role file"
assert_eq "map-new"  "$(cat "$GH/AGENTS.md")"                "update refreshes the global AGENTS.md map"
assert_eq "arch-new" "$(cat "$GH/docs/ARCHITECTURE.md")"     "update refreshes the global docs/ARCHITECTURE.md"
assert_eq "LOCAL EDIT" "$(cat "$GH/docs/principles.md")"     "update preserves a locally edited global doc"
assert_eq "pr-new"   "$(cat "$GH/docs/principles.md.new")"   "update writes the upstream version beside an edited global as .new"
assert_contains "$out" "global keep docs/principles.md" "update reports the kept global"
assert_contains "$out" "global update skills/tdd/SKILL.md" "update reports the refreshed global"
assert_contains "$(cat "$GH/harness/global.lock")" "version: 0.2.0" "update advances the global.lock version"
assert_contains "$(cat "$GH/harness/global.lock")" "$(sha "$GH/skills/tdd/SKILL.md")  skills/tdd/SKILL.md" "update records the new global baseline"
assert_eq "g-new" "$(cat "$GP1/.claude/skills/tdd/SKILL.md")" "update propagates the new skill to the project's installed target"
gh_cmd agent install claude --root "$GP3" >/dev/null 2>&1
assert_eq "g-new" "$(cat "$GP3/.claude/skills/tdd/SKILL.md")" "a later agent install copies the refreshed global skill"
assert_eq "p-same" "$(cat "$GP3/.claude/skills/pure/SKILL.md")" "agent install: an unchanged skill is carried too"
s1="$(snap "$GH")"; gh_cmd --root "$GP1" update --src "$GNEW" >/dev/null 2>&1
assert_eq "$s1" "$(snap "$GH")" "repeat update leaves the global copies unchanged"
rm -rf "$GOLD" "$GNEW" "$GH" "$GP1" "$GP2" "$GP3"

# =============================================================================
echo "harness.sh update — checksum-guarded sync (ADD / UPDATE / CONFLICT)"
# @group update
# old upstream -> install it (records baseline lock)
# fake versions 0.1.0 -> 0.2.0 must not meet the suite's shared home (real runtime, 0.13.0): that
# would be a runtime downgrade, which update refuses. Use a private home for this section.
HOME_BEFORE_UPD="$HARNESS_HOME"; HARNESS_HOME="$(mktemp -d)"; export HARNESS_HOME
UOLD="$(mktemp -d)"; mkdir -p "$UOLD/skills" "$UOLD/agents" "$UOLD/docs" "$UOLD/skills/fold"
printf 'keep-body\n'  > "$UOLD/skills/keep.md"
printf 'old-upd\n'    > "$UOLD/skills/upd.md"
printf 'old-edit\n'   > "$UOLD/skills/edit.md"
printf 'old-fold\n'   > "$UOLD/skills/fold/SKILL.md"   # folder-form skill, untouched by user
printf 'old-role\n'   > "$UOLD/agents/planner.md"
printf 'old-agents\n' > "$UOLD/AGENTS.md"
printf '0.1.0\n'      > "$UOLD/VERSION"
UDEST="$(mktemp -d)"; UBARE="$(mktemp -d)"
HARNESS_SRC="$UOLD" bash "$ROOT/init.sh" "$UDEST" >/dev/null 2>&1
HARNESS_SRC="$UOLD" bash "$ROOT/init.sh" "$UBARE" >/dev/null 2>&1   # skills never installed here
stub_agent_install "$UOLD" "$UDEST"
# user edits one managed file, and owns plan + trace files
printf 'USER-edit\n' > "$UDEST/.agents/skills/edit.md"
mkdir -p "$UDEST/.harness-mini/docs/exec-plans/active" "$UDEST/.harness-mini/trace/runtime"
printf 'my plan\n' > "$UDEST/.harness-mini/docs/exec-plans/active/0009-mine.md"
printf '{"x":1}\n' > "$UDEST/.harness-mini/trace/runtime/run.jsonl"
# new upstream: keep unchanged, upd changed, edit changed, add brand new
UNEW="$(mktemp -d)"; mkdir -p "$UNEW/skills" "$UNEW/agents" "$UNEW/docs" "$UNEW/skills/fold"
printf 'keep-body\n'  > "$UNEW/skills/keep.md"
printf 'NEW-upd\n'    > "$UNEW/skills/upd.md"
printf 'NEW-edit\n'   > "$UNEW/skills/edit.md"
printf 'brand-new\n'  > "$UNEW/skills/add.md"
printf 'NEW-fold\n'   > "$UNEW/skills/fold/SKILL.md"   # folder-form skill changed upstream
printf 'NEW-role\n'   > "$UNEW/agents/planner.md"
printf 'NEW-map\n'    > "$UNEW/AGENTS.md"
printf '0.2.0\n'      > "$UNEW/VERSION"
cp "$UDEST/AGENTS.md" "$UDEST/AGENTS.before"
code=0; HARNESS_ROOT="$UDEST" HARNESS_NO_NET=1 bash "$HARN" update --src "$UNEW" >/dev/null 2>&1 || code=$?
assert_exit 0 "$code" "update exits 0"
assert_eq "NEW-upd"   "$(cat "$UDEST/.agents/skills/upd.md")"       "UPDATE: untouched managed file is refreshed"
assert_eq "keep-body" "$(cat "$UDEST/.agents/skills/keep.md")"      "UNCHANGED: identical file stays"
assert_eq "USER-edit" "$(cat "$UDEST/.agents/skills/edit.md")"      "CONFLICT: user-edited file is preserved"
assert_eq "NEW-edit"  "$(cat "$UDEST/.agents/skills/edit.md.new" 2>/dev/null)" "CONFLICT: upstream written as .new"
assert_eq "brand-new" "$(cat "$UDEST/.agents/skills/add.md" 2>/dev/null)"      "ADD: new upstream file is installed"
assert_eq "NEW-fold"  "$(cat "$UDEST/.agents/skills/fold/SKILL.md" 2>/dev/null)" "UPDATE: nested folder-form skill is refreshed"
assert_eq "my plan"   "$(cat "$UDEST/.harness-mini/docs/exec-plans/active/0009-mine.md")"    "user exec-plan is never touched"
assert_eq '{"x":1}'   "$(cat "$UDEST/.harness-mini/trace/runtime/run.jsonl")"   "user .trace is never touched"
assert_eq "NEW-role"  "$(cat "$UDEST/.agents/agents/planner.md" 2>/dev/null)" "UPDATE: managed agent role file is refreshed"
assert_contains "$(cat "$(lockpath "$UDEST")")" "version: 0.2.0" "update rewrites the lock version (in the state dir)"
assert_eq "false" "$([ -e "$UDEST/harness" ] && echo true || echo false)" "update creates no project harness/ directory"
assert_eq "true" "$(cmp -s "$UDEST/AGENTS.md" "$UDEST/AGENTS.before" && echo true || echo false)" "update never touches the project AGENTS.md"
out="$(HARNESS_ROOT="$UDEST" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "update conflicts: 1 .new" "status counts .new files for managed targets"
# a project that never installed skills gets no ADD, but its lock still advances
HARNESS_ROOT="$UBARE" HARNESS_NO_NET=1 bash "$HARN" update --src "$UNEW" >/dev/null 2>&1
assert_eq "false" "$([ -e "$UBARE/.agents" ] && echo true || echo false)" "update does not install skills into a project that has none"
assert_contains "$(cat "$(lockpath "$UBARE")")" "version: 0.2.0" "update still advances the lock of a skill-less project"
assert_contains "$(cat "$(lockpath "$UBARE")")" "$(bash -c '. "$1"; cksum_file "$2"' _ "$LIB" "$UNEW/skills/upd.md")  .agents/skills/upd.md" "lock records the pristine upstream checksum for not-yet-installed files"
rm -rf "$UOLD" "$UDEST" "$UNEW" "$UBARE" "$HARNESS_HOME"
HARNESS_HOME="$HOME_BEFORE_UPD"; export HARNESS_HOME

# =============================================================================
echo "harness.sh update — project updates do not install centralized executables"
# @group update-project
SOOLD="$(mktemp -d)"; SONEW="$(mktemp -d)"; SOHOME="$(mktemp -d)"
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
HARNESS_SRC="$SOOLD" HARNESS_HOME="$SOHOME" bash "$ROOT/init.sh" "$SODST" >/dev/null 2>&1
HARNESS_HOME="$SOHOME" HARNESS_NO_NET=1 bash "$SOHOME/bin/harness.sh" --root "$SODST" update --src "$SONEW" >/dev/null 2>&1; code=$?
assert_exit 0 "$code" "project update accepts an explicit project root"
assert_eq "false" "$([ -e "$SODST/bin/harness.sh" ] && echo true || echo false)" "project update does not install a harness executable"
assert_eq "false" "$(grep -q 'bin/' "$(HARNESS_HOME="$SOHOME" lockpath "$SODST")" && echo true || echo false)" "project lock excludes runtime executable checksums"
assert_contains "$(cat "$SOHOME/harness/runtime.lock")" "bin/harness.sh" "runtime executable checksums stay in the runtime lock"
assert_eq "0.2.0" "$(awk -F': *' '/^version:/{print $2; exit}' "$SOHOME/harness/runtime.lock")" "runtime lock advances with its executable update"
assert_eq "$(bash -c '. "$1"; cksum_file "$2"' _ "$ROOT/bin/_harness_lib.sh" "$SONEW/bin/harness.sh")" "$(bash -c '. "$1"; cksum_file "$2"' _ "$ROOT/bin/_harness_lib.sh" "$SOHOME/bin/harness.sh")" "deferred runtime self-update installs the source executable"
assert_contains "$(cat "$(HARNESS_HOME="$SOHOME" lockpath "$SODST")")" "version: 0.2.0" "lock advanced by the self-updating run"
rm -rf "$SOOLD" "$SONEW" "$SODST"
rm -rf "$SOHOME"

# =============================================================================
echo "harness.sh update — runtime and project locks advance independently"
# @group update-locks
RTSRC_OLD="$(mktemp -d)"; RTSRC_NEW="$(mktemp -d)"; RT_HOME="$(mktemp -d)"
cp -R "$ROOT/bin" "$ROOT/skills" "$ROOT/agents" "$ROOT/docs" "$RTSRC_OLD/"
cp "$ROOT/AGENTS.md" "$ROOT/ARCHITECTURE.md" "$RTSRC_OLD/"
printf '0.1.0\n' > "$RTSRC_OLD/VERSION"
cp -R "$RTSRC_OLD/." "$RTSRC_NEW/"
printf '0.2.0\n' > "$RTSRC_NEW/VERSION"
printf 'changed runtime helper\n' >> "$RTSRC_NEW/bin/ctx.sh"
printf 'updated runtime model helper\n' >> "$RTSRC_NEW/bin/model.sh"
printf '\nupdated for runtime lock test\n' >> "$RTSRC_NEW/skills/clean-code/SKILL.md"
RT_A="$(mktemp -d)"; RT_B="$(mktemp -d)"
HARNESS_SRC="$RTSRC_OLD" HARNESS_HOME="$RT_HOME" bash "$ROOT/init.sh" "$RT_A" >/dev/null 2>&1
HARNESS_SRC="$RTSRC_OLD" HARNESS_HOME="$RT_HOME" bash "$ROOT/init.sh" "$RT_B" >/dev/null 2>&1
stub_agent_install "$RTSRC_OLD" "$RT_A"; stub_agent_install "$RTSRC_OLD" "$RT_B"
runtime_new_sha="$(bash -c '. "$1"; cksum_file "$2"' _ "$ROOT/bin/_harness_lib.sh" "$RTSRC_NEW/bin/ctx.sh")"
printf 'user runtime edit\n' >> "$RT_HOME/bin/model.sh"
HARNESS_HOME="$RT_HOME" bash "$RT_HOME/bin/harness.sh" --root "$RT_A" update --src "$RTSRC_NEW" >/dev/null 2>&1
assert_eq "updated for runtime lock test" "$(tail -n 1 "$RT_A/.agents/skills/clean-code/SKILL.md")" "first project update uses shared skill target"
assert_eq "0.1.0" "$(awk -F': *' '/^version:/{print $2; exit}' "$(HARNESS_HOME="$RT_HOME" lockpath "$RT_B")")" "updating one project leaves the other project lock unchanged"
assert_eq "$runtime_new_sha" "$(awk '$2=="bin/ctx.sh"{print $1}' "$RT_HOME/harness/runtime.lock")" "runtime executable checksums advance in the runtime lock"
assert_eq "$runtime_new_sha" "$(bash -c '. "$1"; cksum_file "$2"' _ "$ROOT/bin/_harness_lib.sh" "$RT_HOME/bin/ctx.sh")" "runtime executable on disk matches the upstream source"
assert_eq "user runtime edit" "$(tail -n 1 "$RT_HOME/bin/model.sh")" "edited runtime executable is preserved"
assert_eq "updated runtime model helper" "$(tail -n 1 "$RT_HOME/bin/model.sh.new")" "edited runtime executable receives upstream .new"
assert_eq "false" "$(grep -q 'bin/' "$(HARNESS_HOME="$RT_HOME" lockpath "$RT_A")" && echo true || echo false)" "project lock contains no runtime executable checksums"
assert_eq "false" "$(test -e "$RT_B/harness/runtime.lock" && echo true || echo false)" "project update does not create a project-local runtime lock"
HARNESS_HOME="$RT_HOME" bash "$RT_HOME/bin/harness.sh" --root "$RT_B" update --src "$RTSRC_NEW" >/dev/null 2>&1
assert_eq "updated for runtime lock test" "$(tail -n 1 "$RT_B/.agents/skills/clean-code/SKILL.md")" "second project updates independently through shared skills"
assert_contains "$(cat "$(HARNESS_HOME="$RT_HOME" lockpath "$RT_B")")" "version: 0.2.0" "second project lock advances when that project updates"
rm -rf "$RTSRC_OLD" "$RTSRC_NEW" "$RT_HOME" "$RT_A" "$RT_B"

# =============================================================================
echo "harness.sh release — guarded bump + tag (throwaway repos; --no-push/--no-gh)"
# @group release
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
# @group doctor
DDIR="$(mktemp -d)"
bash "$ROOT/init.sh" "$DDIR" >/dev/null 2>&1          # a healthy fresh install
stub_agent_install "$ROOT" "$DDIR"                  # ...plus `agent install` (stand-in)
out="$(HARNESS_ROOT="$DDIR" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: healthy install exits 0"
assert_contains "$out" "ok" "doctor reports ok checks"
assert_contains "$out" "AGENTS.md" "doctor checks AGENTS.md"
assert_contains "$out" "shared skills" "doctor reports the shared skills count"
assert_contains "$out" "manifest healthy" "doctor reports a healthy shared-path manifest"
assert_contains "$out" "0 missing" "doctor reports zero missing skills"
# an empty shared-path section is not a healthy manifest
EMPTY_MANIFEST="$(mktemp -d)"; mkdir -p "$EMPTY_MANIFEST/harness" "$EMPTY_MANIFEST/.agents/skills"
printf 'version: 0.0.0\n' > "$(lockpath "$EMPTY_MANIFEST")"
printf 'AGENTS\n' > "$EMPTY_MANIFEST/AGENTS.md"
printf '# Manifest\n\n## Skills (.agents/skills/)\n\n## Role descriptions\n' > "$(manifestpath "$EMPTY_MANIFEST")"
printf 'skill\n' > "$EMPTY_MANIFEST/.agents/skills/x.md"
out="$(HARNESS_ROOT="$EMPTY_MANIFEST" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"
assert_contains "$out" "manifest lists no shared skills" "doctor flags an empty shared-skill manifest"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'manifest healthy')" "empty manifest is not reported healthy"
out="$(HARNESS_ROOT="$EMPTY_MANIFEST" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "manifest: no shared skills listed" "status flags an empty shared-skill manifest"
rm -rf "$EMPTY_MANIFEST"
# a manifest-listed skill absent from .agents/skills must be named and block readiness
rm -f "$DDIR/.agents/skills/tdd/SKILL.md"
out="$(HARNESS_ROOT="$DDIR" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 1 "$code" "doctor fails when a manifest-listed shared skill is missing"
assert_contains "$out" "tdd/SKILL.md" "doctor names the missing shared skill"
out="$(HARNESS_ROOT="$DDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "ready: blocked" "status readiness blocks on a manifest-listed missing skill"
cp "$ROOT/skills/tdd/SKILL.md" "$DDIR/.agents/skills/tdd/SKILL.md"
# a .new file is a WARN, not a FAIL → still exit 0
touch "$DDIR/.agents/skills/tdd/SKILL.md.new"
out="$(HARNESS_ROOT="$DDIR" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: a .new file warns but does not fail"
assert_contains "$out" "warn" "doctor warns about unresolved .new"
# missing AGENTS.md is a hard FAIL → exit 1
rm -f "$DDIR/AGENTS.md"
code=0; HARNESS_ROOT="$DDIR" bash "$HARN" doctor >/dev/null 2>&1 || code=$?
assert_exit 1 "$code" "doctor: missing AGENTS.md is a FAIL (exit 1)"
rm -rf "$DDIR"
# source<->mirror divergence (#9): craft a dir with both trees
MDIR="$(mktemp -d)"; mkdir -p "$MDIR/skills/x" "$MDIR/.agents/skills/x" "$MDIR/harness"
printf 'AGENTS\n' > "$MDIR/AGENTS.md"; printf 'version: 0.0.0\n' > "$(lockpath "$MDIR")"
printf 'same\n' > "$MDIR/skills/x/SKILL.md"; printf 'same\n' > "$MDIR/.agents/skills/x/SKILL.md"
# without persisted install targets the local .agents tree is not a managed mirror
printf 'DIVERGED\n' > "$MDIR/.agents/skills/x/SKILL.md"
out="$(HARNESS_ROOT="$MDIR" bash "$HARN" doctor 2>&1)"
assert_eq "false" "$(printf '%s' "$out" | grep -q 'differs from source' && echo true || echo false)" "doctor: no persisted targets, no drift warning"
printf 'default\t.agents/skills\t.agents/agents\tcopy\n' > "$(state_of "$MDIR")/targets"
out="$(HARNESS_ROOT="$MDIR" bash "$HARN" doctor 2>&1)"
assert_contains "$out" "differs from source" "doctor: persisted target diverging from source warns"
printf 'same\n' > "$MDIR/.agents/skills/x/SKILL.md"
out="$(HARNESS_ROOT="$MDIR" bash "$HARN" doctor 2>&1)"
assert_contains "$out" "match source" "doctor: identical installed copy reported ok"
rm -rf "$MDIR"
# source repo (VERSION + skills/ but no lock) is healthy, not a missing-lock FAIL
PDIR="$(mktemp -d)"; mkdir -p "$PDIR/skills/x" "$PDIR/.agents/skills/x"
printf 'AGENTS\n' > "$PDIR/AGENTS.md"; printf '0.0.0\n' > "$PDIR/VERSION"
printf 'same\n' > "$PDIR/skills/x/SKILL.md"; printf 'same\n' > "$PDIR/.agents/skills/x/SKILL.md"
out="$(HARNESS_ROOT="$PDIR" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: source repo without a lock is not a FAIL"
assert_contains "$out" "source repo" "doctor recognizes the source repo (no lock needed)"
rm -rf "$PDIR"

# =============================================================================
echo "harness.sh status — current work state (grep/awk/tail only)"
# @group status
SDIR="$(mktemp -d)"
bash "$ROOT/init.sh" "$SDIR" >/dev/null 2>&1          # lock + seeded active plan
splan="$(awk -F': *' '/^plan:/{print $2; exit}' "$SDIR"/.harness-mini/docs/exec-plans/active/0001-*.md)"
mkdir -p "$SDIR/.harness-mini/trace/checkpoints"
printf -- '---\nplan: %s\nseq: 001\n---\n' "$splan" > "$SDIR/.harness-mini/trace/checkpoints/$splan-001.md"
HARNESS_TRACE_DIR="$SDIR/.harness-mini/trace/runtime" HARNESS_RUN="r-stat" \
  bash "$BIN/trace.sh" main implement test ctx_pct=42 >/dev/null 2>&1
out="$(HARNESS_ROOT="$SDIR" bash "$HARN" status 2>&1)"; code=$?
assert_exit 0 "$code" "status exits 0"
slv="$(awk -F': *' '/^version:/{print $2; exit}' "$(lockpath "$SDIR")")"
assert_contains "$out" "$slv" "status shows the installed version"
assert_contains "$out" "$splan" "status lists the active plan"
assert_contains "$out" "ctx_pct=42" "status surfaces last ctx_pct from the trace tail"
assert_contains "$out" "resumable" "status reports resumability"
rm -rf "$SDIR"

# =============================================================================
echo "harness.sh status/doctor — JSON twin workboard (dual-file plans)"
# @group status-json
WDIR="$(mktemp -d)"
bash "$ROOT/init.sh" "$WDIR" >/dev/null 2>&1   # seeds 0001-intake.md (mode: new)
WMD="$(ls "$WDIR"/.harness-mini/docs/exec-plans/active/0001-*.md)"
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
# several slices on one line — each passes pairs with the id before it
printf '%s\n' '{ "plan_id": "0001-intake", "status": "in_progress", "current_slice_id": "slice-002", "slices": [ { "id": "slice-001", "passes": true }, { "id": "slice-002", "passes": false } ] }' > "$WTWIN"
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "1/2 pass" "compact twin counts each slice"
assert_contains "$out" "next: slice-002" "compact twin names the failing slice, not the last id on the line"
# id on one line, passes on the next
cat > "$WTWIN" <<'EOF'
{
  "plan_id": "0001-intake",
  "status": "in_progress",
  "current_slice_id": "slice-002",
  "slices": [
    { "id": "slice-001",
      "passes": true },
    { "id": "slice-002",
      "passes": false }
  ]
}
EOF
out="$(HARNESS_ROOT="$WDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "1/2 pass" "split-line twin counts each slice"
assert_contains "$out" "next: slice-002" "split-line twin keeps the id until its passes"
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
# @group session-path
# fixture factory: <root> <slug> <stage> <twin: none|next|green|empty|garbage>
mkplan() {
  printf -- '---\nplan: %s\nseq: 0001\nstage: %s\nowner: main\n---\n# t\n' "$2" "$3" \
    > "$1/.harness-mini/docs/exec-plans/active/$2.md"
  case "$4" in
    next)   printf '{ "plan_id": "%s", "status": "in_progress", "current_slice_id": "slice-002",\n  "slices": [ { "id": "slice-001", "passes": true }, { "id": "slice-002", "passes": false } ] }\n' "$2" > "$1/.harness-mini/docs/exec-plans/active/$2.json" ;;
    green)  printf '{ "plan_id": "%s", "status": "in_progress", "slices": [ { "id": "slice-001", "passes": true } ] }\n' "$2" > "$1/.harness-mini/docs/exec-plans/active/$2.json" ;;
    empty)  printf '{ "plan_id": "%s", "status": "planned", "slices": [] }\n' "$2" > "$1/.harness-mini/docs/exec-plans/active/$2.json" ;;
    garbage) printf 'not json {{{\n' > "$1/.harness-mini/docs/exec-plans/active/$2.json" ;;
  esac
}
mkboard() { local d; d="$(mktemp -d)"; mkdir -p "$d/.harness-mini/docs/exec-plans/active"; printf 'version: 0.0.0\n' > "$(lockpath "$d")"; printf '%s' "$d"; }
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
# @group garden
GDIR="$(mktemp -d)"; mkdir -p "$GDIR/.harness-mini/trace/checkpoints" "$GDIR/harness"
printf 'version: 0.0.0\n' > "$(lockpath "$GDIR")"
mkcp() { printf -- '---\nplan: p\nseq: %s\n---\n' "$1" > "$GDIR/.harness-mini/trace/checkpoints/p-$1.md"; }
# 5 committed checkpoints, no backlog yet -> DUE by cadence (default threshold 5)
for i in 001 002 003 004 005; do mkcp "$i"; done
out="$(HARNESS_ROOT="$GDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"; code=$?
assert_exit 0 "$code" "status exits 0 with garden block"
assert_contains "$out" "garden: DUE" "garden DUE at 5 checkpoints since last (cadence)"
assert_contains "$out" "5 checkpoint" "garden line counts checkpoints since last garden"
# stamp gardened-at to the current count -> since 0 -> ok
printf '# Garden backlog\n<!-- gardened-at: 5 -->\n\n## Open\n' > "$GDIR/.harness-mini/trace/garden-backlog.md"
out="$(HARNESS_ROOT="$GDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "garden: ok" "garden ok once gardened-at marks the current count"
# one HIGH-severity open item flips it DUE even with since=0
printf -- '- [ ] 2026-06-03 | a.ts:1 | long-fn | high | x\n' >> "$GDIR/.harness-mini/trace/garden-backlog.md"
out="$(HARNESS_ROOT="$GDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "garden: DUE" "garden DUE on a high-severity backlog item"
assert_contains "$out" "1 backlog item" "garden line counts open backlog items"
# 2 non-high items, gardened-at current -> under both thresholds -> ok
printf '# Garden backlog\n<!-- gardened-at: 5 -->\n\n## Open\n- [ ] d | b.ts:1 | dup | low | x\n- [ ] d | c.ts:1 | dup | med | y\n' > "$GDIR/.harness-mini/trace/garden-backlog.md"
out="$(HARNESS_ROOT="$GDIR" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "garden: ok" "garden ok with <3 non-high items and no cadence overflow"
rm -rf "$GDIR"

# =============================================================================
echo "harness.sh status — readiness verdict (ready|warning|blocked) + plan-scoped resumable"
# @group readiness
RDY="$(mktemp -d)"; mkdir -p "$RDY/.agents/skills/x" "$RDY/.harness-mini/docs/exec-plans/active" \
  "$RDY/.harness-mini/trace/checkpoints" "$RDY/.harness-mini/trace/evals" "$RDY/harness"
printf 'AGENTS\n' > "$RDY/AGENTS.md"
printf 'version: 0.0.0\n' > "$(lockpath "$RDY")"
printf 'x\n' > "$RDY/.agents/skills/x/SKILL.md"
# healthy install, active plan + matching checkpoint -> ready + resumable yes
printf -- '---\nplan: alpha\nseq: 0001\nstage: implement\n---\n## Now\n- ship slice one\n' \
  > "$RDY/.harness-mini/docs/exec-plans/active/0001-alpha.md"
printf -- '---\nplan: alpha\nseq: 001\n---\n' > "$RDY/.harness-mini/trace/checkpoints/alpha-001.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"; code=$?
assert_exit 0 "$code" "status readiness: healthy exits 0"
assert_contains "$out" "ready: ready" "status readiness: ready when install+plan+cp ok"
assert_contains "$out" "ship slice one" "status readiness: next action from plan Now"
assert_contains "$out" "resumable: yes" "status readiness: plan-scoped checkpoint => resumable yes"
# foreign checkpoint alone must NOT make resumable yes (plan-scoped)
rm -f "$RDY/.harness-mini/trace/checkpoints/alpha-001.md"
printf -- '---\nplan: other\nseq: 001\n---\n' > "$RDY/.harness-mini/trace/checkpoints/other-001.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "resumable: partial" "status readiness: foreign checkpoint ignored"
assert_contains "$out" "ready: warning" "status readiness: partial resume => warning"
# no active plan => warning (not blocked), resumable no
rm -f "$RDY/.harness-mini/docs/exec-plans/active/"*.md
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "ready: warning" "status readiness: no active plan => warning"
assert_contains "$out" "resumable: no" "status readiness: no plan => resumable no"
# install broken (no AGENTS.md) => blocked
rm -f "$RDY/AGENTS.md"
printf -- '---\nplan: alpha\nseq: 0001\nstage: implement\n---\n' \
  > "$RDY/.harness-mini/docs/exec-plans/active/0001-alpha.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "ready: blocked" "status readiness: missing AGENTS.md => blocked"
# restore AGENTS; done without eval => blocked
printf 'AGENTS\n' > "$RDY/AGENTS.md"
printf -- '---\nplan: shipit\nseq: 0001\nstage: done\n---\n' \
  > "$RDY/.harness-mini/docs/exec-plans/active/0001-shipit.md"
rm -f "$RDY/.harness-mini/docs/exec-plans/active/0001-alpha.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "ready: blocked" "status readiness: done without eval => blocked"
assert_contains "$out" "evaluate" "status readiness: blocked next-action mentions evaluate"
# passing eval clears the done-gate block (garden/update quiet) -> ready
printf -- '---\nplan: shipit\nseq: 001\ntier: L1\nverdict: pass\n---\n' \
  > "$RDY/.harness-mini/trace/evals/shipit-001.md"
printf -- '---\nplan: shipit\nseq: 001\n---\n' > "$RDY/.harness-mini/trace/checkpoints/shipit-001.md"
out="$(HARNESS_ROOT="$RDY" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "ready: ready" "status readiness: done+pass eval => ready"
rm -rf "$RDY"

# =============================================================================
echo "harness.sh report — aggregate .trace into a metrics summary (grep/awk only)"
# @group report
RPT="$(mktemp -d)"; mkdir -p "$RPT/harness" "$RPT/.harness-mini/trace/runtime" "$RPT/.harness-mini/trace/checkpoints" "$RPT/.harness-mini/trace/evals"
printf 'version: 0.6.0\n' > "$(lockpath "$RPT")"
# a runtime trace: two stage advances + ctx samples, one of which crosses 40%
{
  printf '{"ts":"t","run":"r-a","agent":"main","stage":"prd","event":"stage_advance"}\n'
  printf '{"ts":"t","run":"r-a","agent":"main","stage":"implement","event":"stage_advance","ctx_pct":22}\n'
  printf '{"ts":"t","run":"r-a","agent":"main","stage":"implement","event":"tool_post","ctx_pct":48}\n'
} > "$RPT/.harness-mini/trace/runtime/r-a.jsonl"
# durable eval records: one pass, one fail
printf -- '---\nplan: p\nseq: 001\ntier: L1\nverdict: pass\ncriteria: 3/3\n---\n' > "$RPT/.harness-mini/trace/evals/p-001.md"
printf -- '---\nplan: p\nseq: 002\ntier: L1\nverdict: fail\ncriteria: 2/3\n---\n' > "$RPT/.harness-mini/trace/evals/p-002.md"
printf -- '---\nplan: p\nseq: 001\n---\n' > "$RPT/.harness-mini/trace/checkpoints/p-001.md"
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
# @group eval-gate
EG="$(mktemp -d)"; mkdir -p "$EG/.agents/skills/x" "$EG/.harness-mini/docs/exec-plans/active" "$EG/.harness-mini/trace/evals" "$EG/harness"
printf 'AGENTS\n' > "$EG/AGENTS.md"; printf 'version: 0.0.0\n' > "$(lockpath "$EG")"
printf 'x\n' > "$EG/.agents/skills/x/SKILL.md"
# an active plan that reached `done` but has no evaluation on record -> FAIL
printf -- '---\nplan: shipit\nseq: 0001\nstage: done\n---\n' > "$EG/.harness-mini/docs/exec-plans/active/0001-shipit.md"
out="$(HARNESS_ROOT="$EG" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 1 "$code" "doctor: done plan without a passing eval is a FAIL"
assert_contains "$out" "anti-self-praise" "doctor names the firewall it is enforcing"
# add a passing eval record -> the gate clears
printf -- '---\nplan: shipit\nseq: 001\ntier: L1\nverdict: pass\ncriteria: 2/2\n---\n' > "$EG/.harness-mini/trace/evals/shipit-001.md"
out="$(HARNESS_ROOT="$EG" bash "$HARN" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor: done plan with a passing eval clears the gate"
assert_contains "$out" "evaluation on record" "doctor confirms the eval record"
rm -rf "$EG"

# =============================================================================
echo "ctx-hook.sh — heuristic context gauge for the PostToolUse hook"
# @group ctx-hook
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
# @group repo-gate
am="$ROOT/AGENTS.md"
assert_contains "$(cat "$am")" "MUST FIRST** run" "AGENTS.md gate is status-first (mandatory)"
assert_contains "$(cat "$am")" '$HOME/.harness-mini/bin/harness.sh' "AGENTS.md uses the centralized runtime command"
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
# @group session-init-skill
si="$ROOT/skills/session-init/SKILL.md"
assert_eq "true" "$([ -f "$si" ] && echo true || echo false)" "skills/session-init/SKILL.md exists"
sib="$(cat "$si" 2>/dev/null)"
assert_contains "$sib" "path: init" "skill opens by confirming path: init from status"
assert_contains "$sib" '$HOME/.harness-mini/bin/harness.sh' "skill names the centralized status command"
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
# @group session-coding-skill
sc="$ROOT/skills/session-coding/SKILL.md"
assert_eq "true" "$([ -f "$sc" ] && echo true || echo false)" "skills/session-coding/SKILL.md exists"
scb="$(cat "$sc" 2>/dev/null)"
first_sec="$(printf '%s' "$scb" | grep -m1 '^## ' )"
assert_contains "$first_sec" "Getting Bearings" "first section is the mandatory Getting Bearings"
assert_contains "$scb" "skills/session-coding/scripts/session-bearings.sh" "bearings helper is invoked from the skill"
assert_eq "0" "$(printf '%s' "$scb" | grep -c 'bin/session-bearings.sh')" "bearings helper is not a shared bin path"
assert_contains "$scb" "selected_slice" "bearings: slice from file truth, not memory"
assert_contains "$scb" "do not paraphrase" "bearings: forbid hallucinated workboard fields"
assert_contains "$scb" 'passes": false' "bearings step 3: slice still passes:false in twin"
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
echo "skills/session-coding/scripts/session-bearings.sh — deterministic coding orientation (#75)"
# @group session-bearings
BEAR="$ROOT/skills/session-coding/scripts/session-bearings.sh"
assert_eq "true" "$([ -f "$BEAR" ] && echo true || echo false)" "session-bearings.sh is skill-owned"
assert_eq "false" "$([ -e "$BIN/session-bearings.sh" ] && echo true || echo false)" "session-bearings.sh is absent from shared bin"
PB="$(mkboard)"; mkplan "$PB" 0001-coder implement next
out="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$BEAR" 2>&1)"; code=$?
assert_exit 0 "$code" "session-bearings exits 0 on a coding board"
assert_contains "$out" "path: coding" "report states coding path"
assert_contains "$out" "selected_slice: slice-002" "report picks first passes:false slice"
assert_contains "$out" "workboard:" "report includes workboard line"
# last-green file truth
mkdir -p "$PB/.harness-mini/trace/runtime"
printf '2026-01-01T00:00:00Z rev=deadbeef\n' > "$PB/.harness-mini/trace/runtime/last-green.txt"
out2="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$BEAR" 2>&1)"; code=$?
assert_exit 0 "$code" "session-bearings with last-green"
assert_contains "$out2" "last_green: 2026-01-01T00:00:00Z rev=deadbeef" "last_green read from disk"
rm -rf "$PB"
# init board -> exit 2
PB="$(mkboard)"; mkplan "$PB" 0001-idea prd none
out3="$(HARNESS_ROOT="$PB" HARNESS_NO_NET=1 bash "$BEAR" 2>&1)"; code=$?
assert_exit 2 "$code" "session-bearings exits 2 on init path"
assert_contains "$out3" "session-init" "init path hints session-init"
rm -rf "$PB"

# =============================================================================
echo "bin/session.sh — Outer session runner (P2, #61)"
# @group session-runner
# mkboard/mkplan are defined in the session-path group above and reused here.
SESS="$BIN/session.sh"
# both skills installed in every fixture board, so selection is purely
# path-driven — the runner must pick the right one, not just find one
mkskills() { # <root>
  for s in session-init session-coding; do
    mkdir -p "$1/.agents/skills/$s"
    cp "$ROOT/skills/$s/SKILL.md" "$1/.agents/skills/$s/SKILL.md"
  done
}
# coding board -> session-coding body injected
RB="$(mkboard)"; mkplan "$RB" 0001-coder implement next; mkskills "$RB"
out="$(HARNESS_ROOT="$RB" HARNESS_NO_NET=1 bash "$SESS" 2>&1)"; code=$?
assert_exit 0 "$code" "runner exits 0 on a coding board"
assert_contains "$out" "Getting Bearings" "coding board injects session-coding body"
assert_contains "$out" '$HOME/.harness-mini/bin/harness.sh' "injected body still runs status first"
assert_contains "$out" "path: coding" "wrapper states the session path"
# init board -> session-init body injected (never bearings)
RB2="$(mkboard)"; mkplan "$RB2" 0001-idea prd none; mkskills "$RB2"
out2="$(HARNESS_ROOT="$RB2" HARNESS_NO_NET=1 bash "$SESS" 2>&1)"; code=$?
assert_exit 0 "$code" "runner exits 0 on an init board"
assert_contains "$out2" "plan session" "init board injects session-init body"
assert_eq "0" "$(printf '%s' "$out2" | grep -c 'Getting Bearings')" "init board never gets coding bearings"
# no skills installed in the project yet -> fall back to the global skill sources
RB3="$(mkboard)"; mkplan "$RB3" 0001-coder implement next
out4="$(HARNESS_ROOT="$RB3" HARNESS_NO_NET=1 bash "$SESS" 2>&1)"; code=$?
assert_exit 0 "$code" "runner falls back to \$HARNESS_HOME/skills when the project has none"
assert_contains "$out4" "Getting Bearings" "global fallback injects the same session-coding body"
rm -rf "$RB3"
# centralized runtime defaults to the invoking project, not ~/.harness-mini
RUNTIME="$(mktemp -d)"; mkdir -p "$RUNTIME/bin"
cp "$HARN" "$SESS" "$BIN/_harness_lib.sh" "$RUNTIME/bin/"
( cd "$RB" && HARNESS_NO_NET=1 bash "$RUNTIME/bin/session.sh" ) >"$RUNTIME/out" 2>&1; code=$?
assert_exit 0 "$code" "centralized runner finds project skills without HARNESS_ROOT"
assert_contains "$(cat "$RUNTIME/out")" "Getting Bearings" "centralized runner uses invoking project root"
rm -rf "$RUNTIME"
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
# (.agents/skills is the harness's own install-layout path, not a vendor name.)
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
assert_eq "true" "$([ -f "$SGD/.harness-mini/docs/exec-plans/active/0001-intake.md" ] && echo true || echo false)" "empty board still seeds the intake plan"
# user-owned, differently numbered board: remove the seed, add 0009-oldthing
rm -f "$SGD/.harness-mini/docs/exec-plans/active/0001-intake.md"
printf -- '---\nplan: oldthing\nseq: 0009\nstage: implement\nowner: main\n---\n# Old\n' \
  > "$SGD/.harness-mini/docs/exec-plans/active/0009-oldthing.md"
HARNESS_SRC="$SGSRC" bash "$ROOT/init.sh" "$SGD" >/dev/null 2>&1
assert_eq "0" "$(ls "$SGD"/.harness-mini/docs/exec-plans/active/0001-*.md 2>/dev/null | wc -l | tr -d ' ')" "no spurious 0001 seed beside a non-0001 active plan"
assert_eq "true" "$([ -f "$SGD/.harness-mini/docs/exec-plans/active/0009-oldthing.md" ] && echo true || echo false)" "user plan untouched by re-run"
rm -rf "$SGD"
# existing-project mode still seeds recon
SGE="$(mktemp -d)"; printf '{"name":"x"}\n' > "$SGE/package.json"
HARNESS_SRC="$SGSRC" bash "$ROOT/init.sh" "$SGE" >/dev/null 2>&1
assert_eq "true" "$([ -f "$SGE/.harness-mini/docs/exec-plans/active/0001-recon.md" ] && echo true || echo false)" "existing-project install seeds the recon plan"
rm -rf "$SGE" "$SGSRC"

# =============================================================================
echo "init.sh — seed plans carry their JSON twin (#64)"
# @group seed-plans
TWSRC="$(mktemp -d)"; mkdir -p "$TWSRC/skills" "$TWSRC/agents" "$TWSRC/bin" "$TWSRC/docs"
printf 'skill\n' > "$TWSRC/skills/sample.md"
printf 'agent\n'  > "$TWSRC/agents/planner.md"
printf 'echo hi\n' > "$TWSRC/bin/ctx.sh"
printf 'map\n'     > "$TWSRC/AGENTS.md"
TW1="$(mktemp -d)"
HARNESS_SRC="$TWSRC" bash "$ROOT/init.sh" "$TW1" >/dev/null 2>&1
assert_eq "true" "$([ -f "$TW1/.harness-mini/docs/exec-plans/active/0001-intake.json" ] && echo true || echo false)" "intake seed has its JSON twin"
out="$(HARNESS_ROOT="$TW1" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'no JSON twin')" "new-mode install: doctor has no twin warning"
out="$(HARNESS_ROOT="$TW1" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "workboard: planned" "new-mode install: status shows the seed workboard"
assert_contains "$out" "no slices yet" "seed workboard renders the no-slices line"
rm -rf "$TW1"
TW2="$(mktemp -d)"; printf '{"name":"x"}\n' > "$TW2/package.json"
HARNESS_SRC="$TWSRC" bash "$ROOT/init.sh" "$TW2" >/dev/null 2>&1
assert_eq "true" "$([ -f "$TW2/.harness-mini/docs/exec-plans/active/0001-recon.json" ] && echo true || echo false)" "recon seed has its JSON twin"
out="$(HARNESS_ROOT="$TW2" HARNESS_NO_NET=1 bash "$HARN" doctor 2>&1)"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'no JSON twin')" "existing-mode install: doctor has no twin warning"
out="$(HARNESS_ROOT="$TW2" HARNESS_NO_NET=1 bash "$HARN" status 2>&1)"
assert_contains "$out" "workboard: planned" "existing-mode install: status shows the seed workboard"
rm -rf "$TW2" "$TWSRC"

# =============================================================================
# checkpoint-hardening — slice-001: checkpoint-lint.sh
# Tests written RED (before implementation). Discussion #75 / plan 0001.
echo "checkpoint-lint.sh — validate Footprint entries enforce file:start-end::STATUS"
# @group checkpoint-hardening
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
out3="$(HARNESS_TRACE_DIR="$TMPS/trace" bash "$SNAP" "${src3}:2-2::DONE" 2>/dev/null)"; code=$?
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
mkdir -p "$GR/.harness-mini/trace/checkpoints"
git -C "$GR" init -q
git -C "$GR" config user.email "test@test"
git -C "$GR" config user.name "Test"
printf 'initial\n' > "$GR/file.txt"
git -C "$GR" add file.txt
git -C "$GR" commit -q -m "init"
# write a fake checkpoint so the guard has something to compare against
{ printf '%s\n' "---"; printf '%s\n' "plan: test"; printf '%s\n' "seq: 1"; printf '%s\n' "---"; } > "$GR/.harness-mini/trace/checkpoints/test-001.md"

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

# installed skill path: infer the project root from its shared-skill location
IR="$TMPG/installed"
mkdir -p "$IR/.agents/skills/checkpoint/scripts" "$IR/.harness-mini/trace/checkpoints"
cp "$GUARD" "$IR/.agents/skills/checkpoint/scripts/checkpoint-guard.sh"
git -C "$IR" init -q
git -C "$IR" config user.email "test@test"
git -C "$IR" config user.name "Test"
git -C "$IR" add .agents/skills/checkpoint/scripts/checkpoint-guard.sh
git -C "$IR" commit -q -m "init"
{ printf '%s\n' "---" "plan: test" "seq: 1" "---"; } > "$IR/.harness-mini/trace/checkpoints/test-001.md"
code=0; msg="$(cd "$IR" && bash .agents/skills/checkpoint/scripts/checkpoint-guard.sh 2>&1)" || code=$?
assert_exit 1 "$code" "guard: installed skill discovers project root and suppresses clean checkpoint"
assert_contains "$msg" "suppress" "guard: installed skill root discovery checks project git state"
assert_eq "0" "$(grep -c 'bin/harness.sh' "$GUARD")" "checkpoint guard does not require a project bin executable"

rm -rf "$TMPG"

# =============================================================================
# checkpoint-hardening — slice-004: ctx-hook.sh last-green extension
echo "ctx-hook.sh — auto-stamp last-green.txt when HARNESS_TEST_SCRIPT passes"
# @group ctx-hook-last-green
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

# =============================================================================
echo "harness.sh agent — host-aware skills + agents installer (0059 #5)"
# @group agent-install
AGSRC="$(mktemp -d)"; AGH="$(mktemp -d)"
mkdir -p "$AGSRC/skills/tdd" "$AGSRC/skills/session-init" "$AGSRC/agents" "$AGSRC/bin" "$AGSRC/docs"
printf -- '---\nname: tdd\ndescription: Test first.\n---\nTDD BODY\n' > "$AGSRC/skills/tdd/SKILL.md"
printf -- '---\nname: session-init\ndescription: Plan.\n---\nINIT BODY\n' > "$AGSRC/skills/session-init/SKILL.md"
printf -- '---\nname: planner\ndescription: Plans: "quoted" work.\ntools: Read\n---\nPLANNER ROLE\n' > "$AGSRC/agents/planner.md"
printf 'GARDENER ROLE\n' > "$AGSRC/agents/gardener.md"          # no frontmatter at all
printf 'echo hi\n' > "$AGSRC/bin/ctx.sh"; printf 'map\n' > "$AGSRC/AGENTS.md"; printf '0.1.0\n' > "$AGSRC/VERSION"
ag() { HARNESS_HOME="$AGH" bash "$HARN" "$@"; }
agproj() { # <dir> — a git project with its own .gitignore, harness-initialised
  mkdir -p "$1"; git -C "$1" init -q 2>/dev/null; printf 'node_modules/\n' > "$1/.gitignore"
  HARNESS_SRC="$AGSRC" HARNESS_HOME="$AGH" bash "$ROOT/init.sh" "$1" >/dev/null 2>&1
}

# list: every host once, machine-parsable rows, header hint to pass the OWN host id
out="$(ag agent list 2>&1)"; code=$?
assert_exit 0 "$code" "agent list exits 0"
assert_contains "$out" "agent install" "agent list header tells the host agent to pass its own host id"
for h in antigravity codex cursor claude qoder zcode kimi deepseek pi opencode grok copilot mimo trae codebuddy muse hermes; do
  assert_eq "1" "$(printf '%s\n' "$out" | awk -F'\t' -v h="$h" '$1==h' | wc -l | tr -d ' ')" "agent list has a row for $h"
done
assert_eq "5" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="claude"{print NF}')" "agent list rows are tab-separated with 5 columns"
assert_eq "claude	.claude/skills	.claude/agents	md" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="claude"{print $1"\t"$2"\t"$3"\t"$4}')" "agent list claude row: id, skills dir, agents dir, format"
assert_eq "codex	.agents/skills	.codex/agents	toml" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="codex"{print $1"\t"$2"\t"$3"\t"$4}')" "agent list codex row uses toml"
assert_contains "$(printf '%s\n' "$out" | awk -F'\t' '$1=="deepseek"')" "low" "agent list marks deepseek as low confidence"
assert_contains "$(printf '%s\n' "$out" | awk -F'\t' '$1=="muse"')" "unsupported" "agent list marks muse unsupported"
assert_contains "$(printf '%s\n' "$out" | awk -F'\t' '$1=="hermes"')" "unsupported" "agent list marks hermes unsupported"

# install claude: native dirs, never .agents; lock, targets, manifest, doctor, status agree
P1="$(mktemp -d)/p1"; agproj "$P1"; cp "$P1/.gitignore" "$P1/.gitignore.orig"
out="$(ag agent install claude --root "$P1" 2>&1)"; code=$?
assert_exit 0 "$code" "agent install claude exits 0"
assert_contains "$out" ".claude/skills" "install prints the skills dir it added"
assert_contains "$out" ".claude/agents" "install prints the agents dir it added"
assert_eq "TDD BODY" "$(sed -n 5p "$P1/.claude/skills/tdd/SKILL.md")" "claude skills land in .claude/skills"
assert_eq "true" "$(cmp -s "$AGSRC/agents/planner.md" "$P1/.claude/agents/planner.md" && echo true || echo false)" "a role with name+description is copied byte-for-byte"
assert_eq "false" "$([ -e "$P1/.agents" ] && echo true || echo false)" "claude install writes no .agents dir"
P1S="$(HARNESS_HOME="$AGH" state_of "$P1")"
assert_contains "$(cat "$P1S/targets")" "claude" "targets file records the host"
assert_contains "$(cat "$P1S/harness.lock")" ".claude/skills/tdd/SKILL.md" "lock lists the real skill target"
assert_contains "$(cat "$P1S/harness.lock")" ".claude/agents/gardener.md" "lock lists the real agent target"
assert_eq "0" "$(grep -c '\.agents/' "$P1S/harness.lock")" "lock no longer lists the default targets"
assert_contains "$(cat "$P1S/manifest.md")" "## Skills (.claude/skills/)" "manifest lists the real skill target"
assert_contains "$(cat "$P1S/manifest.md")" "tdd/SKILL.md" "manifest lists the installed skills"
out="$(ag --root "$P1" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor is healthy after agent install claude"
assert_contains "$out" "shared skills in .claude/skills" "doctor reads the persisted skill target"
assert_contains "$out" "manifest healthy" "doctor validates the manifest against the real target"
out="$(ag --root "$P1" status 2>&1)"
assert_contains "$out" "shared skills: 2" "status counts skills at the real target"
assert_eq "0" "$(printf '%s\n' "$out" | grep -c 'ready: blocked')" "status is not blocked after install"
ex="$(cat "$P1/.git/info/exclude")"
assert_eq "1" "$(printf '%s\n' "$ex" | grep -cx '.claude/skills/')" ".git/info/exclude lists .claude/skills/ once"
assert_eq "1" "$(printf '%s\n' "$ex" | grep -cx '.claude/agents/')" ".git/info/exclude lists .claude/agents/ once"
assert_eq "true" "$(cmp -s "$P1/.gitignore" "$P1/.gitignore.orig" && echo true || echo false)" "project .gitignore is unchanged"
# session.sh finds the skill at the persisted target (project copy wins over the global one)
printf -- '---\nname: session-init\n---\nPROJECT-LOCAL INIT\n' > "$P1/.claude/skills/session-init/SKILL.md"
out="$(HARNESS_ROOT="$P1" HARNESS_HOME="$AGH" bash "$BIN/session.sh" 2>&1)"
assert_contains "$out" "PROJECT-LOCAL INIT" "session.sh reads the skill from the persisted target"

# idempotent: re-install adds nothing, keeps one targets line, one exclude entry
cp "$P1S/targets" "$P1S/targets.before"
out="$(ag agent install claude --root "$P1" 2>&1)"; code=$?
assert_exit 0 "$code" "re-install exits 0"
assert_contains "$out" "add   0 file(s)" "re-install adds nothing"
assert_eq "true" "$(cmp -s "$P1S/targets" "$P1S/targets.before" && echo true || echo false)" "re-install leaves the targets file unchanged"
assert_eq "1" "$(grep -cx '.claude/skills/' "$P1/.git/info/exclude")" "re-install keeps a single exclude entry"
assert_contains "$(cat "$P1/.claude/skills/session-init/SKILL.md")" "PROJECT-LOCAL INIT" "re-install never overwrites an existing file"

# alias resolves to the canonical host
P2="$(mktemp -d)/p2"; agproj "$P2"
ag agent install Claude-Code --root "$P2" >/dev/null 2>&1
assert_eq "true" "$([ -f "$P2/.claude/skills/tdd/SKILL.md" ] && echo true || echo false)" "alias claude-code installs the claude targets"

# codex: shared skills, TOML roles
P3="$(mktemp -d)/p3"; agproj "$P3"
ag agent install codex --root "$P3" >/dev/null 2>&1; code=$?
assert_eq "true" "$([ -f "$P3/.agents/skills/tdd/SKILL.md" ] && echo true || echo false)" "codex skills land in shared .agents/skills"
toml="$(cat "$P3/.codex/agents/planner.toml" 2>/dev/null)"
assert_contains "$toml" 'name = "planner"' "codex role has a TOML name"
assert_contains "$toml" 'description = "Plans: \"quoted\" work."' "codex role description is a TOML-escaped string"
assert_contains "$toml" "developer_instructions = '''" "codex role opens a multi-line literal string"
assert_contains "$toml" "PLANNER ROLE" "codex role carries the md body"
assert_eq "0" "$(printf '%s\n' "$toml" | grep -c '^tools:')" "codex role body excludes the YAML frontmatter"
assert_eq "'''" "$(printf '%s\n' "$toml" | tail -n1)" "codex role closes the literal string"
toml="$(cat "$P3/.codex/agents/gardener.toml" 2>/dev/null)"
assert_contains "$toml" 'name = "gardener"' "codex role without frontmatter falls back to the filename"
assert_contains "$toml" "GARDENER ROLE" "codex role without frontmatter keeps its whole body"
assert_eq "false" "$([ -e "$P3/.codex/agents/planner.md" ] && echo true || echo false)" "codex roles are not copied as .md"
printf -- "---\nname: tricky\ndescription: has '''\n---\nbody with ''' inside\n" > "$AGSRC/agents/tricky.md"
P3T="$(mktemp -d)/p3t"; agproj "$P3T"; HARNESS_HOME="$AGH" bash -c 'cp -R "$1/agents/." "$2/agents/"' _ "$AGSRC" "$AGH"
ag agent install codex --root "$P3T" >/dev/null 2>&1
assert_contains "$(cat "$P3T/.codex/agents/tricky.toml")" 'developer_instructions = """' "a body containing ''' falls back to a basic multi-line string"
rm -f "$AGSRC/agents/tricky.md" "$AGH/agents/tricky.md"
out="$(ag --root "$P3" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor is healthy after agent install codex"
out="$(ag --root "$P3" update --src "$AGSRC" 2>&1)"
assert_eq "0" "$(find "$P3" -name '*.new' | wc -l | tr -d ' ')" "update leaves rendered toml roles alone when upstream is unchanged"

# copilot naming; cursor injects name/description into the installed copy only
P4="$(mktemp -d)/p4"; agproj "$P4"
ag agent install github-copilot --root "$P4" >/dev/null 2>&1
assert_eq "true" "$([ -f "$P4/.github/agents/planner.agent.md" ] && echo true || echo false)" "copilot roles are named <name>.agent.md"
assert_eq "true" "$([ -f "$P4/.agents/skills/tdd/SKILL.md" ] && echo true || echo false)" "copilot skills land in shared .agents/skills"
P5="$(mktemp -d)/p5"; agproj "$P5"
ag agent install cursor --root "$P5" >/dev/null 2>&1
g="$(cat "$P5/.cursor/agents/gardener.md" 2>/dev/null)"
assert_contains "$g" "name: gardener" "installed role gains a name from the filename"
assert_contains "$g" "description:" "installed role gains a description"
assert_contains "$g" "GARDENER ROLE" "installed role keeps its body"
assert_eq "GARDENER ROLE" "$(cat "$AGH/agents/gardener.md")" "global role sources are never altered"
assert_eq "true" "$([ -f "$P5/.cursor/skills/tdd/SKILL.md" ] && echo true || echo false)" "cursor skills land in .cursor/skills"
assert_eq "false" "$([ -e "$P5/.agents/skills" ] && echo true || echo false)" "cursor does not use .agents/skills"
assert_contains "$(cat "$P5/.git/info/exclude" 2>/dev/null)" ".cursor/skills/" "cursor skills dir is listed in .git/info/exclude"

# two hosts accumulate in targets, lock, manifest and exclude
ag agent install codex --root "$P1" >/dev/null 2>&1
assert_eq "2" "$(grep -c . "$P1S/targets")" "a second host adds a second targets line"
assert_contains "$(cat "$P1S/harness.lock")" ".claude/skills/tdd/SKILL.md" "lock keeps the first host's targets"
assert_contains "$(cat "$P1S/harness.lock")" ".agents/skills/tdd/SKILL.md" "lock gains the second host's skills"
assert_contains "$(cat "$P1S/harness.lock")" ".codex/agents/planner.toml" "lock gains the rendered toml role"
assert_contains "$(cat "$P1S/manifest.md")" ".claude/skills/ .agents/skills/" "manifest lists both skill targets"
assert_eq "1" "$(grep -cx '.agents/skills/' "$P1/.git/info/exclude")" "exclude gains the second host's dir once"
assert_eq "1" "$(grep -cx '.claude/skills/' "$P1/.git/info/exclude")" "exclude keeps the first host's dir once"
out="$(ag --root "$P1" doctor 2>&1)"; code=$?
assert_exit 0 "$code" "doctor is healthy with two hosts"
assert_contains "$out" "manifest healthy" "doctor checks the manifest at every target"
rm -f "$P1/.agents/skills/session-init/SKILL.md"
out="$(ag --root "$P1" doctor 2>&1)"; code=$?
assert_exit 1 "$code" "doctor fails when a listed skill is missing at any target"
ag agent install codex --root "$P1" >/dev/null 2>&1
assert_eq "true" "$([ -f "$P1/.agents/skills/session-init/SKILL.md" ] && echo true || echo false)" "re-install restores a missing file additively"

# edited file preserved, update produces .new at the real target
cp "$AGSRC/skills/session-init/SKILL.md" "$P1/.claude/skills/session-init/SKILL.md"   # undo the earlier local edit
printf 'MY EDIT\n' > "$P1/.claude/skills/tdd/SKILL.md"
AGNEW="$(mktemp -d)"; cp -R "$AGSRC/." "$AGNEW/"; printf 'UPSTREAM TDD\n' > "$AGNEW/skills/tdd/SKILL.md"; printf '0.2.0\n' > "$AGNEW/VERSION"
ag agent install claude --root "$P1" >/dev/null 2>&1
assert_eq "MY EDIT" "$(cat "$P1/.claude/skills/tdd/SKILL.md")" "re-install preserves an edited file"
ag --root "$P1" update --src "$AGNEW" >/dev/null 2>&1
assert_eq "MY EDIT" "$(cat "$P1/.claude/skills/tdd/SKILL.md")" "update keeps the edited file"
assert_eq "UPSTREAM TDD" "$(cat "$P1/.claude/skills/tdd/SKILL.md.new" 2>/dev/null)" "update writes .new at the persisted claude target"
assert_eq "UPSTREAM TDD" "$(cat "$P1/.agents/skills/tdd/SKILL.md" 2>/dev/null)" "update refreshes an untouched file at the other target"
assert_contains "$(ag --root "$P1" status 2>&1)" "update conflicts: 1 .new" "status counts .new files at persisted targets"
assert_contains "$(cat "$P1S/targets")" "claude" "update keeps the persisted targets"

# unknown / unsupported hosts: nothing written, instructions printed, exit 0
snap() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs cksum 2>/dev/null; cat .git/info/exclude 2>/dev/null); }
P6="$(mktemp -d)/p6"; agproj "$P6"
for h in bogus muse hermes; do
  before="$(snap "$P6")"; sbefore="$(ls -A "$(HARNESS_HOME="$AGH" state_of "$P6")" | tr '\n' ' ')"
  out="$(ag agent install "$h" --root "$P6" 2>&1)"; code=$?
  assert_exit 0 "$code" "$h: self-install fallback exits 0"
  assert_eq "$before" "$(snap "$P6")" "$h: nothing is written to the project"
  assert_eq "$sbefore" "$(ls -A "$(HARNESS_HOME="$AGH" state_of "$P6")" | tr '\n' ' ')" "$h: no targets or lock rewrite"
  assert_contains "$out" "$AGH/skills" "$h: instructions name the skills source path"
  assert_contains "$out" "$AGH/agents" "$h: instructions name the agents source path"
  assert_contains "$out" "Nothing was written" "$h: instructions say nothing was written to the project"
done
code=0; ag agent install --root "$P6" >/dev/null 2>&1 || code=$?
assert_exit 64 "$code" "agent install without a host is a usage error"
code=0; ag agent >/dev/null 2>&1 || code=$?
assert_exit 64 "$code" "agent without a subcommand is a usage error"
rm -rf "$AGSRC" "$AGH" "$AGNEW"

# =============================================================================
echo "source repo layout — dogfood .harness-mini/, references/ + assets/ at root (0059 #6)"
# @group repo-layout
for d in references assets .harness-mini/docs/exec-plans/active .harness-mini/docs/exec-plans/completed \
         .harness-mini/trace/checkpoints .harness-mini/trace/evals; do
  assert_eq "true" "$([ -d "$ROOT/$d" ] && echo true || echo false)" "source repo has $d"
done
for d in docs/references docs/assets docs/exec-plans .trace harness; do
  assert_eq "false" "$([ -e "$ROOT/$d" ] && echo true || echo false)" "source repo no longer has $d"
done
assert_eq "trace/runtime/" "$(cat "$ROOT/.harness-mini/.gitignore")" "dogfood .harness-mini/.gitignore ignores trace/runtime/"
assert_eq "true" "$([ -f "$ROOT/.harness-mini/architecture.md" ] && echo true || echo false)" "dogfood .harness-mini/architecture.md exists"
assert_eq "true" "$([ -f "$ROOT/assets/banner.svg" ] && grep -q 'assets/banner.svg' "$ROOT/README.md" && echo true || echo false)" "README banner points at the root assets/ file"
assert_eq "0" "$(grep -c -e '^\.trace/' "$ROOT/.gitignore")" "repo .gitignore no longer carries the .trace/ line"

# a real install of THIS source never copies references/ or assets/ anywhere
RH="$(mktemp -d)"; RP="$(mktemp -d)"
HARNESS_HOME="$RH" bash "$ROOT/init.sh" "$RP" >/dev/null 2>&1
for d in references assets docs/references docs/assets docs/exec-plans; do
  assert_eq "false" "$([ -e "$RH/$d" ] && echo true || echo false)" "real install: \$HARNESS_HOME/$d absent"
done
assert_eq "true" "$([ -f "$RH/docs/principles.md" ] && echo true || echo false)" "real install: static docs landed under \$HARNESS_HOME/docs"
assert_eq "0" "$(grep -rlE 'references/|assets/banner' "$RH"/projects/*/harness.lock "$RH"/projects/*/manifest.md 2>/dev/null | wc -l | tr -d ' ')" "real install: lock and manifest never list references/ or assets/"
rm -rf "$RH" "$RP"

# source repo dogfoods .harness-mini/: status reads it (independent of which plans are active right now)
RH="$(mktemp -d)"
out="$(cd "$ROOT" && HARNESS_HOME="$RH" HARNESS_ROOT="$ROOT" bash "$HARN" status 2>&1)"
assert_contains "$out" "path:" "status in the source repo reads the workboard under .harness-mini/"
assert_eq "true" "$([ -d "$ROOT/.harness-mini/docs/exec-plans/completed" ] && [ ! -d "$ROOT/docs/exec-plans" ] && echo true || echo false)" "source repo plans live under .harness-mini/, not docs/"
rm -rf "$RH"

# no active instruction points at the legacy project layout
ACTIVE="$ROOT/skills $ROOT/agents $ROOT/AGENTS.md $ROOT/ARCHITECTURE.md $ROOT/README.md $ROOT/CONTRIBUTING.md $ROOT/docs"
assert_eq "0" "$(grep -rF -e '.trace' $ACTIVE | wc -l | tr -d ' ')" "no active doc/skill/agent mentions .trace"
assert_eq "0" "$(grep -rhE 'docs/exec-plans' $ACTIVE | sed 's#\.harness-mini/docs/exec-plans##g' | grep -c 'docs/exec-plans')" "exec-plans are only referenced as .harness-mini/docs/exec-plans"
assert_eq "0" "$(grep -rlE -e 'harness/(harness\.lock|manifest\.md|agents)' -e 'docs/(references|assets)' -e '\.claude/skills' -e 'CLAUDE\.md' $ROOT/skills $ROOT/agents $ROOT/AGENTS.md $ROOT/README.md $ROOT/docs | wc -l | tr -d ' ')" "no active instruction names legacy install paths or CLAUDE.md"

assert_eq "0" "$(grep -rlE -e 'harness-mini/<project-id>' -e 'HARNESS_HOME/<project-id>' $ROOT/skills $ROOT/agents $ROOT/AGENTS.md $ROOT/ARCHITECTURE.md $ROOT/README.md $ROOT/SECURITY.md $ROOT/docs | wc -l | tr -d ' ')" "no active doc names the pre-0061 flat state dir (<project-id> sits under projects/)"

# doctor drift check: respects persisted targets, silent for installed projects
echo "installed_drift — source vs persisted install targets"
DS="$(mktemp -d)"; DH="$(mktemp -d)"
mkdir -p "$DS/skills/tdd" "$DS/agents"; printf 'tdd\n' > "$DS/skills/tdd/SKILL.md"; printf 'role\n' > "$DS/agents/planner.md"
drift() { HARNESS_HOME="$DH" bash -c '. "$1"; installed_drift "$2"' _ "$LIB" "$DS"; }
mkdir -p "$DS/.agents/skills/tdd"; printf 'stale\n' > "$DS/.agents/skills/tdd/SKILL.md"
assert_eq "" "$(drift)" "no persisted targets: a stale local .agents mirror is not compared"
DSTATE="$(HARNESS_HOME="$DH" bash -c '. "$1"; state_dir "$2"' _ "$LIB" "$DS")"; mkdir -p "$DSTATE"
printf 'default\t.agents/skills\t.agents/agents\tcopy\n' > "$DSTATE/targets"
assert_contains "$(drift)" ".agents/skills/tdd/SKILL.md" "persisted target: a differing installed skill is reported"
printf 'tdd\n' > "$DS/.agents/skills/tdd/SKILL.md"
assert_eq "" "$(drift)" "persisted target in sync: no drift (agents dir absent is not drift)"
mkdir -p "$DS/.agents/agents"
assert_contains "$(drift)" ".agents/agents/planner.md" "existing target dir missing a source role is reported"
rm -rf "$DS" "$DH"

# =============================================================================
echo "state dir under projects/ — fresh layout + 0.13.0 flat-layout migration (0061 #82)"
# @group state-dir-projects
SDS="$(mktemp -d)"; SDH="$(mktemp -d)"
mkdir -p "$SDS/skills/tdd" "$SDS/agents" "$SDS/bin" "$SDS/docs"
cp "$BIN"/*.sh "$SDS/bin/"
printf '0.13.0\n' > "$SDS/VERSION"; printf 'tdd\n' > "$SDS/skills/tdd/SKILL.md"
printf 'role\n' > "$SDS/agents/planner.md"; printf 'map\n' > "$SDS/AGENTS.md"
sd_init() { HARNESS_SRC="$SDS" HARNESS_HOME="$SDH" bash "$ROOT/init.sh" "$1" 2>&1; }
sd_hh() { HARNESS_HOME="$SDH" bash "$HARNESS_HOME_RUNTIME" "$@" 2>&1; }
sd_id() { basename "$(HARNESS_HOME="$SDH" state_of "$1")"; }
# the 0.13.0 layout, built by hand: $H/<id>/{harness.lock,manifest.md,targets}
sd_flat() { # <project> <tag> — returns the old state dir path
  local d
  d="$SDH/$(sd_id "$1")"; mkdir -p "$d"
  printf 'version: 0.13.0\n# %s\n' "$2" > "$d/harness.lock"
  printf '# manifest %s\n' "$2" > "$d/manifest.md"
  printf 'default\t.agents/skills\t.agents/agents\tcopy\n' > "$d/targets"
  printf '%s' "$d"
}
HARNESS_HOME_RUNTIME="$SDH/bin/harness.sh"

# fresh install: only the known top-level entries, state under projects/
SDP1="$(mktemp -d)"; sd_init "$SDP1" >/dev/null
SDID1="$(sd_id "$SDP1")"
unexpected=""
for e in "$SDH"/* "$SDH"/.[!.]*; do
  [ -e "$e" ] || continue
  e="${e##*/}"
  case "$e" in projects|bin|docs|skills|agents|harness|AGENTS.md|VERSION) ;; *) unexpected="$unexpected $e" ;; esac
done
assert_eq "" "$unexpected" "fresh install adds no top-level entry besides projects/ and the runtime set"
assert_eq "true" "$([ -f "$SDH/projects/$SDID1/harness.lock" ] && [ -f "$SDH/projects/$SDID1/manifest.md" ] && echo true || echo false)" "fresh install: lock and manifest under projects/<id>/"
assert_eq "$SDID1" "$(ls "$SDH/projects")" "projects/ holds exactly the project's state dir"
out="$(sd_hh --root "$SDP1" agent install claude)"
assert_eq "true" "$([ -s "$SDH/projects/$SDID1/targets" ] && echo true || echo false)" "agent install writes targets under projects/<id>/"
assert_contains "$out" "recorded targets, lock and manifest in $SDH/projects/$SDID1" "agent install names the projects/<id> state dir"
assert_eq "false" "$([ -e "$SDH/$SDID1" ] && echo true || echo false)" "no flat \$HARNESS_HOME/<id> is created"

# 0.13.0 layout migrates via init.sh; runtime dirs untouched; second run silent
SDP2="$(mktemp -d)"; SDID2="$(sd_id "$SDP2")"; sd_flat "$SDP2" two >/dev/null
RTBEFORE="$(snap "$SDH/bin"; snap "$SDH/skills"; snap "$SDH/agents"; snap "$SDH/docs")"
out="$(sd_init "$SDP2")"
assert_contains "$out" "migr  moved state dir to projects/$SDID2" "init reports moving the old state dir"
assert_eq "false" "$([ -e "$SDH/$SDID2" ] && echo true || echo false)" "init: the flat state dir is gone after the move"
assert_eq "version: 0.13.0 # two" "$(tr '\n' ' ' < "$SDH/projects/$SDID2/harness.lock" | sed 's/ $//')" "init: the moved lock is the old one (not regenerated)"
assert_eq "# manifest two" "$(cat "$SDH/projects/$SDID2/manifest.md")" "init: the moved manifest is the old one"
assert_eq "true" "$([ -s "$SDH/projects/$SDID2/targets" ] && echo true || echo false)" "init: targets moved along"
assert_eq "$RTBEFORE" "$(snap "$SDH/bin"; snap "$SDH/skills"; snap "$SDH/agents"; snap "$SDH/docs")" "migration leaves the runtime dirs untouched"
SDSNAP="$(snap "$SDH")"
out="$(sd_init "$SDP2")"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'moved state dir')" "second init: no migration line"
assert_eq "$SDSNAP" "$(snap "$SDH")" "second init: \$HARNESS_HOME unchanged (idempotent)"

# two projects migrate independently; update --root migrates only its own project
SDP3="$(mktemp -d)"; SDP4="$(mktemp -d)"; SDID3="$(sd_id "$SDP3")"; SDID4="$(sd_id "$SDP4")"
sd_flat "$SDP3" three >/dev/null; sd_flat "$SDP4" four >/dev/null
out="$(sd_init "$SDP3")"
assert_eq "true" "$([ -f "$SDH/projects/$SDID3/harness.lock" ] && [ ! -e "$SDH/$SDID3" ] && echo true || echo false)" "project three migrated by init"
assert_eq "true" "$([ -f "$SDH/$SDID4/harness.lock" ] && [ ! -e "$SDH/projects/$SDID4" ] && echo true || echo false)" "project four is untouched while three migrates"
code=0; out="$(sd_hh --root "$SDP4" update --src "$SDS")" || code=$?
assert_exit 0 "$code" "update --root on a 0.13.0-layout project succeeds"
assert_contains "$out" "migr  moved state dir to projects/$SDID4" "update reports moving the old state dir"
assert_eq "true" "$([ -f "$SDH/projects/$SDID4/harness.lock" ] && [ ! -e "$SDH/$SDID4" ] && echo true || echo false)" "project four migrated by update"
assert_contains "$(cat "$SDH/projects/$SDID4/harness.lock")" "version: 0.13.0" "update keeps working from the migrated lock"
SDSNAP="$(snap "$SDH")"
out="$(sd_hh --root "$SDP4" update --src "$SDS")"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'moved state dir')" "second update: no migration line"
assert_eq "$SDSNAP" "$(snap "$SDH")" "second update: \$HARNESS_HOME unchanged (idempotent)"

# an existing target is never overwritten: both kept, one keep notice
SDP5="$(mktemp -d)"; SDID5="$(sd_id "$SDP5")"; OLD5="$(sd_flat "$SDP5" old)"
mkdir -p "$SDH/projects/$SDID5"; printf 'version: 9.9.9\n# new\n' > "$SDH/projects/$SDID5/harness.lock"
OLDSNAP="$(snap "$OLD5")"
out="$(sd_init "$SDP5")"
assert_eq "1" "$(printf '%s' "$out" | grep -c '^  keep  .*projects/'"$SDID5")" "existing target: exactly one keep notice"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'moved state dir')" "existing target: nothing is moved"
assert_eq "version: 9.9.9 # new" "$(tr '\n' ' ' < "$SDH/projects/$SDID5/harness.lock" | sed 's/ $//')" "existing target: its lock is not overwritten"
assert_eq "$OLDSNAP" "$(snap "$OLD5")" "existing target: the old dir is kept as it was"

# id equals a runtime dir name: the helper must never move it (name guard AND lock check)
GH="$(mktemp -d)"; GR="$(mktemp -d)"
for n in bin docs skills agents harness projects; do
  mkdir -p "$GH/$n"; printf 'version: 0.13.0\n' > "$GH/$n/harness.lock"
  before="$(snap "$GH")"
  HARNESS_HOME="$GH" bash -c '. "$1"; say() { :; }; project_id() { printf %s "$3"; }; migrate_state_dir "$2"' _ "$LIB" "$GR" "$n" >/dev/null 2>&1
  assert_eq "$before" "$(snap "$GH")" "id '$n': the runtime dir is never moved (even holding a harness.lock)"
  rm -rf "${GH:?}/$n"
done
mkdir -p "$GH/lockless"; printf 'x\n' > "$GH/lockless/other"
HARNESS_HOME="$GH" bash -c '. "$1"; say() { :; }; project_id() { printf lockless; }; migrate_state_dir "$2"' _ "$LIB" "$GR" >/dev/null 2>&1
assert_eq "true" "$([ -f "$GH/lockless/other" ] && [ ! -e "$GH/projects" ] && echo true || echo false)" "a flat dir without harness.lock is not a state dir and is left alone"
printf 'plain file\n' > "$GH/afile"
HARNESS_HOME="$GH" bash -c '. "$1"; say() { :; }; project_id() { printf afile; }; migrate_state_dir "$2"' _ "$LIB" "$GR" >/dev/null 2>&1
assert_eq "plain file" "$(cat "$GH/afile")" "a plain file named like the id is left alone"
rm -rf "$GH" "$GR"

# read-only commands on a not-yet-migrated project do not report a missing lock
SDP6="$(mktemp -d)"; sd_init "$SDP6" >/dev/null; SDID6="$(sd_id "$SDP6")"
mv "$SDH/projects/$SDID6" "$SDH/$SDID6"
code=0; out="$(sd_hh --root "$SDP6" doctor)" || code=$?
assert_exit 0 "$code" "doctor on an unmigrated project does not fail"
assert_eq "0" "$(printf '%s' "$out" | grep -c 'harness.lock missing')" "doctor on an unmigrated project reports no missing lock"
mv "$SDH/projects/$SDID6" "$SDH/$SDID6" 2>/dev/null
out="$(sd_hh --root "$SDP6" status)"
assert_contains "$out" "project: 0.13.0" "status on an unmigrated project reads the project version"
mv "$SDH/projects/$SDID6" "$SDH/$SDID6" 2>/dev/null
out="$(sd_hh --root "$SDP6" agent install claude)"; code=$?
assert_eq "true" "$([ -s "$SDH/projects/$SDID6/targets" ] && [ ! -e "$SDH/$SDID6" ] && echo true || echo false)" "agent install on an unmigrated project writes into projects/<id>/ (old dir moved first)"
# =============================================================================
echo "tests/groups.tsv + tests/affected.sh — path->group map for the tdd inner loop (0063 #2)"
# @group test-selection
TSEL="$(mktemp -d)"
mkdir -p "$TSEL/bin" "$TSEL/skills/session-coding" "$TSEL/other"
printf 'x\n' > "$TSEL/bin/ctx.sh"; printf 'y\n' > "$TSEL/bin/harness.sh"
printf 's\n' > "$TSEL/skills/session-coding/SKILL.md"; printf 'u\n' > "$TSEL/other/unknown.txt"
git -C "$TSEL" init -q
git -C "$TSEL" config user.email "test@test"; git -C "$TSEL" config user.name "test"
git -C "$TSEL" add -A >/dev/null 2>&1; git -C "$TSEL" commit -qm base >/dev/null 2>&1

# a mapped path fires its group
printf 'changed\n' >> "$TSEL/bin/ctx.sh"
out="$(AFFECTED_REPO="$TSEL" bash "$ROOT/tests/affected.sh" HEAD)"
assert_eq "ctx" "$out" "affected: bin/ctx.sh maps to the ctx group"
git -C "$TSEL" add -A >/dev/null 2>&1; git -C "$TSEL" commit -qm c1 >/dev/null 2>&1

# an unmapped path maps to all
printf 'changed\n' >> "$TSEL/other/unknown.txt"
out="$(AFFECTED_REPO="$TSEL" bash "$ROOT/tests/affected.sh" HEAD)"
assert_eq "all" "$out" "affected: an unmapped path maps to all"
git -C "$TSEL" add -A >/dev/null 2>&1; git -C "$TSEL" commit -qm c2 >/dev/null 2>&1

# a tie at the winning prefix fires all tying groups, in groups.tsv order
printf 'changed\n' >> "$TSEL/skills/session-coding/SKILL.md"
out="$(AFFECTED_REPO="$TSEL" bash "$ROOT/tests/affected.sh" HEAD)"
assert_eq "$(printf 'session-coding-skill\nsession-bearings\nsession-runner')" "$out" \
  "affected: a prefix tie fires all tying groups in tsv order"
git -C "$TSEL" add -A >/dev/null 2>&1; git -C "$TSEL" commit -qm c3 >/dev/null 2>&1

# empty diff prints nothing and exits 0
out="$(AFFECTED_REPO="$TSEL" bash "$ROOT/tests/affected.sh" HEAD)"; code=$?
assert_eq "" "$out" "affected: an empty diff prints nothing"
assert_exit 0 "$code" "affected: an empty diff exits 0"

# a missing ref is a usage error (64)
AFFECTED_REPO="$TSEL" bash "$ROOT/tests/affected.sh" >/dev/null 2>&1; code=$?
assert_exit 64 "$code" "affected: missing ref is a usage error (64)"

# --check: the real tsv and the real runner tags agree
bash "$ROOT/tests/affected.sh" --check >/dev/null 2>&1; code=$?
assert_exit 0 "$code" "affected --check: every tsv group has a @group tag and vice versa"

# --check failure: an orphan tsv group is named, exit non-zero
TSEL_TSV="$(mktemp)"
printf 'no-such-group\tbin/ctx.sh\n' > "$TSEL_TSV"
err="$(AFFECTED_TSV="$TSEL_TSV" bash "$ROOT/tests/affected.sh" --check 2>&1)"; code=$?
assert_exit 1 "$code" "affected --check: an orphan tsv group exits non-zero"
assert_contains "$err" "tsv:no-such-group" "affected --check: names the orphan group"
rm -rf "$TSEL"; rm -f "$TSEL_TSV"

# =============================================================================
# checkpoint-archive-check — slice-001 (0064): plan-archive integrity verifier
echo "checkpoint-archive-check.sh — archive-integrity gate for the checkpoint skill"
# @group checkpoint-archive-check
CAC="$(mktemp -d)"
CAC_SCRIPT="$ROOT/skills/checkpoint/scripts/checkpoint-archive-check.sh"
assert_eq "true" "$([ -f "$CAC_SCRIPT" ] && echo true || echo false)" "archive-check helper is skill-owned"

CAC_PLANS="$CAC/.harness-mini/docs/exec-plans"

cac_plan() {  # <completed|active> <name> <md_stage> <json_status> <passes_true_or_false>
  local dir="$CAC_PLANS/$1"
  mkdir -p "$dir"
  {
    printf '%s\n' "---"
    printf '%s\n' "plan: $2"
    printf '%s\n' "seq: 0099"
    printf '%s\n' "stage: $3"
    printf '%s\n' "---"
    printf '%s\n' "# $2"
  } > "$dir/$2.md"
  {
    printf '%s\n' '{'
    printf '%s\n' "  \"plan_id\": \"$2\","
    printf '%s\n' "  \"status\": \"$4\","
    printf '%s\n' '  "slices": ['
    printf '%s\n' "    { \"id\": \"slice-001\", \"steps\": [\"one step\"], \"passes\": $5 }"
    printf '%s\n' '  ]'
    printf '%s\n' '}'
  } > "$dir/$2.json"
}

# fixture: a committed repo whose exec-plans are consistent — an active plan
# mid-flight plus a completed plan with its twin. Every violation case below
# mutates one field of this clean baseline (and commits the mutation, so only
# the intended dirt remains).
cac_plan completed "0001-shipped" "done" "done" "true"
cac_plan active "0002-wip" "implement" "in_progress" "false"
git -C "$CAC" init -q
git -C "$CAC" config user.email "test@test"; git -C "$CAC" config user.name "test"
git -C "$CAC" add -A >/dev/null 2>&1; git -C "$CAC" commit -qm base >/dev/null 2>&1

# clean + consistent → exit 0, silent (the active plan is mid-flight: active/
# gets the dirty check only, never the stage check)
out="$(bash "$CAC_SCRIPT" "$CAC" 2>&1)"; code=$?
assert_exit 0 "$code" "archive-check: clean consistent fixture exits 0 (active/ not stage-checked)"
assert_eq "" "$out" "archive-check: clean fixture prints nothing"

# a tracked plan file edited without committing is dirty — the exact
# 0062/0063 bug class (git mv stages the rename, the edits stay behind)
printf 'uncommitted edit\n' >> "$CAC/.harness-mini/docs/exec-plans/active/0002-wip.md"
out="$(bash "$CAC_SCRIPT" "$CAC" 2>&1)"; code=$?
assert_exit 1 "$code" "archive-check: a dirty plan file exits 1"
assert_contains "$out" "dirty: .harness-mini/docs/exec-plans/active/0002-wip.md" "archive-check: names the dirty path"

# default root: run with no arg from a subdirectory resolves the git toplevel
( cd "$CAC/.harness-mini" && bash "$CAC_SCRIPT" ) >/dev/null 2>&1; code=$?
assert_exit 1 "$code" "archive-check: no-arg run from a subdir defaults root to the git toplevel"
git -C "$CAC" checkout -q -- .harness-mini/docs/exec-plans/active/0002-wip.md

# completed plan whose frontmatter stage never reached done
cac_plan completed "0001-shipped" "implement" "done" "true"
git -C "$CAC" add -A >/dev/null 2>&1; git -C "$CAC" commit -qm bad-stage >/dev/null 2>&1
out="$(bash "$CAC_SCRIPT" "$CAC" 2>&1)"; code=$?
assert_exit 1 "$code" "archive-check: completed stage != done exits 1"
assert_contains "$out" "0001-shipped: stage is 'implement', want 'done'" "archive-check: names plan + field for a bad stage"

# twin whose status never reached done
cac_plan completed "0001-shipped" "done" "in_progress" "true"
git -C "$CAC" add -A >/dev/null 2>&1; git -C "$CAC" commit -qm bad-status >/dev/null 2>&1
out="$(bash "$CAC_SCRIPT" "$CAC" 2>&1)"; code=$?
assert_exit 1 "$code" "archive-check: twin status != done exits 1"
assert_contains "$out" "0001-shipped: status is 'in_progress', want 'done'" "archive-check: names plan + field for a bad twin status"

# twin still carrying a failing slice
cac_plan completed "0001-shipped" "done" "done" "false"
git -C "$CAC" add -A >/dev/null 2>&1; git -C "$CAC" commit -qm bad-passes >/dev/null 2>&1
out="$(bash "$CAC_SCRIPT" "$CAC" 2>&1)"; code=$?
assert_exit 1 "$code" "archive-check: a passes:false slice in a completed twin exits 1"
assert_contains "$out" "0001-shipped: passes is false, want all true" "archive-check: names plan + field for a failing slice"

# twin absent for a completed md — a completed plan must have its twin
git -C "$CAC" rm -q .harness-mini/docs/exec-plans/completed/0001-shipped.json >/dev/null 2>&1
git -C "$CAC" commit -qm twinless >/dev/null 2>&1
out="$(bash "$CAC_SCRIPT" "$CAC" 2>&1)"; code=$?
assert_exit 1 "$code" "archive-check: a completed md without its twin exits 1"
assert_contains "$out" "0001-shipped: twin 0001-shipped.json is missing" "archive-check: names the missing twin"

# no completed/ dir at all: the invariant check is skipped silently — and this
# fixture is not a git repo, so the run also proves the $PWD default-root fallback
CAC_NR="$(mktemp -d)"
CAC_PLANS="$CAC_NR/.harness-mini/docs/exec-plans"
cac_plan active "0003-wip" "implement" "in_progress" "false"
( cd "$CAC_NR" && bash "$CAC_SCRIPT" ) >/dev/null 2>&1; code=$?
assert_exit 0 "$code" "archive-check: no completed/ dir is skipped (exit 0; cwd fallback outside a repo)"

rm -rf "$CAC" "$CAC_NR"

# =============================================================================
# summary + final cleanup — the tail after the last @group; runs on
# selected runs too, hence the :- guards on section-local fixture vars
rm -rf "${SDS:-}" "${SDH:-}" "${SDP1:-}" "${SDP2:-}" "${SDP3:-}" "${SDP4:-}" "${SDP5:-}" "${SDP6:-}"

rm -rf "$HARNESS_HOME"

# =============================================================================
echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
