#!/usr/bin/env bash
# init.sh — install harness-mini into a project. ADDITIVE and IDEMPOTENT:
# it only ever creates files that don't already exist, so it is safe to drop
# into an old repo and safe to re-run.
#
# Behaviour is asymmetric by project type:
#   new/empty project  -> generative bootstrap: seed an INTAKE plan that runs the
#                         founder funnel (founder-check -> to-prd).
#   existing project   -> recon graft: seed a RECON plan that maps the codebase
#                         into ARCHITECTURE.md via the Explorer; no founder funnel.
#
# Install layout (host-specific project assets; shared runtime is user-level):
#   skills/  -> .claude/skills/
#   agents/  -> .claude/agents/
#   bin/     -> $HARNESS_HOME/bin/ (not into projects)
#   docs/ AGENTS.md ARCHITECTURE.md -> copied as-is
#   harness/manifest.md            -> pointer list of those files
#
# Usage:  init.sh [target_dir] [--mode new|existing]
# Env:    HARNESS_SRC   source root (default: directory containing this script)
#         HARNESS_HOME  runtime root (default: $HOME/.harness-mini)
#         HARNESS_MODE  force "new" or "existing" (default: auto-detect)
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${HARNESS_SRC:-$SELF_DIR}"
DEST="$PWD"
MODE="${HARNESS_MODE:-}"
HARNESS_HOME="${HARNESS_HOME:-${HOME:?HOME must be set}/.harness-mini}"

# shared helpers (managed-set + lockfile); sourced from this installer's own bin/
# so it works even when HARNESS_SRC points at a stripped-down asset tree.
# shellcheck source=bin/_harness_lib.sh
. "$SELF_DIR/bin/_harness_lib.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    -*) echo "init.sh: unknown flag: $1" >&2; exit 64 ;;
    *)  DEST="$1"; shift ;;
  esac
done

mkdir -p "$DEST" || { echo "init.sh: cannot create target $DEST" >&2; exit 1; }
DEST="$(cd "$DEST" && pwd)"

say() { printf '  %s\n' "$1"; }

# Routing-gate v3 text (see "routing gate" below). Marker-guarded with
# HARNESS_ROUTING_GATE_BEGIN/END; the markers are version-stable, the CONTENT
# is the version. An install seeded with an older gate — v1
# (harness-mini:start/end markers) or a v2 block (markers present but the
# path-aware content absent) — has it REMOVED and the v3 gate appended: there
# is ever exactly one gate.
# Status-first AND path-aware: a cold session runs `bin/harness.sh status`,
# reads its `path:` line, and opens the matching session skill. Only the
# `path: coding` branch picks a `passes: false` slice — planning boards are
# never pushed into product code.
GATE_BEGIN='<!-- HARNESS_ROUTING_GATE_BEGIN -->'
GATE_END='<!-- HARNESS_ROUTING_GATE_END -->'
V1_BEGIN='<!-- harness-mini:start -->'
V1_END='<!-- harness-mini:end -->'

emit_claude_gate() {
  printf '%s\n' "$GATE_BEGIN"
  cat <<'EOF'
[CRITICAL AGENT INSTRUCTION]
You are inside a project managed by harness-mini.

1. Do NOT modify code directly before starting any task. You **MUST** first run the command: `bin/harness.sh status`
2. Read the `path:` line it prints, then open the matching session skill and follow it:
   - `path: init` → open `session-init` — plan-layer work only (founder funnel, PRD, issues, JSON twin). Do NOT edit product code on this path.
   - `path: coding` → open `session-coding` — complete its **Getting Bearings** first turn before any product edit; then implement exactly ONE slice: the highest-priority slice with `passes: false` (prefer the `next:` id from status).
3. Follow the principle of progressive exposure strictly: only read code relevant to the current slice. Complete only one Slice per Session.
4. Do NOT alter or delete the test conditions defined in `steps` inside JSON files.

Full map & lifecycle: AGENTS.md · Workboard: `bin/harness.sh status` · 40% rule: `docs/smart-dumb.md`
EOF
  printf '%s\n' "$GATE_END"
}
emit_cursor_rule() {
  cat <<'EOF'
---
description: harness-mini routing gate — status-first, path-aware, prefer the harness lifecycle and skills
alwaysApply: true
---

This project runs on **harness-mini**. On a fresh session, first run
`bin/harness.sh status`, read its `path:` line, and open the matching skill:
`session-init` (path: init — plan work only, no product code) or
`session-coding` (path: coding — Getting Bearings first, then one
`passes: false` slice from the JSON twins in `docs/exec-plans/active/`).
For non-trivial work — a feature, a multi-step or ambiguous change, anything
cross-cutting — route it through the `stage-viewer` skill first and prefer
harness-mini's lifecycle, skills, and sub-agents (read
`.claude/skills/<name>/SKILL.md`) over ad-hoc tools or other installed
plugins. When a harness skill and another tool both fit, the harness skill
wins. Trivial one-line fixes may skip the ceremony (quick mode).

Map: AGENTS.md · Manifest: harness/manifest.md · 40% rule: docs/smart-dumb.md
EOF
}

# skill_description — print the `description:` value from a SKILL.md's frontmatter
# (the YAML block between the first two `---`). Empty if absent. Used to label the
# generated Cursor rules so Cursor's agent can decide when to pull each skill.
skill_description() { # <skill_md>
  awk '
    NR==1 && $0=="---" { fm=1; next }
    fm && $0=="---"    { exit }
    fm && /^description:/ { sub(/^description:[ \t]*/, ""); print; exit }
  ' "$1"
}

# --- detect project type -----------------------------------------------------
detect_mode() {
  for marker in package.json go.mod Cargo.toml pyproject.toml requirements.txt \
                pom.xml build.gradle Gemfile composer.json; do
    [ -f "$DEST/$marker" ] && { echo existing; return; }
  done
  # any *.csproj or a populated src/ also counts as existing
  ls "$DEST"/*.csproj >/dev/null 2>&1 && { echo existing; return; }
  [ -d "$DEST/src" ] && [ -n "$(ls -A "$DEST/src" 2>/dev/null)" ] && { echo existing; return; }
  echo new
}
[ -z "$MODE" ] && MODE="$(detect_mode)"
echo "harness-mini: installing into $DEST  (mode: $MODE)"

# --- additive copy helpers ---------------------------------------------------
copy_file() { # <src_file> <dest_file>  — never overwrite
  [ -f "$1" ] || return 0
  if [ -e "$2" ]; then say "skip  ${2#$DEST/} (exists)"; return 0; fi
  mkdir -p "$(dirname "$2")" && cp "$1" "$2" && say "add   ${2#$DEST/}"
}
copy_tree() { # <src_dir> <dest_dir>  — additive, recursive
  [ -d "$1" ] || return 0
  ( cd "$1" && find . -type f ) | while read -r rel; do
    copy_file "$1/${rel#./}" "$2/${rel#./}"
  done
}

install_runtime() {
  local runtime_lock="$HARNESS_HOME/harness/runtime.lock" version f target
  version="$(tr -d ' \t\r\n' < "$SRC/VERSION" 2>/dev/null)"
  [ -n "$version" ] || version=unknown
  if [ -f "$runtime_lock" ]; then
    say "skip  user runtime (already initialized at $HARNESS_HOME)"
    return 0
  fi
  mkdir -p "$HARNESS_HOME/bin" || return 1
  for f in "$SRC"/bin/*; do
    [ -f "$f" ] || continue
    target="$HARNESS_HOME/bin/$(basename "$f")"
    if [ ! -e "$target" ]; then
      cp "$f" "$target" || return 1
      chmod +x "$target" 2>/dev/null || true
    fi
  done
  if [ -f "$SRC/VERSION" ] && [ ! -e "$HARNESS_HOME/VERSION" ]; then
    cp "$SRC/VERSION" "$HARNESS_HOME/VERSION" || return 1
  fi
  write_runtime_lock "$SRC" "$HARNESS_HOME" "$version" || return 1
  say "add   user runtime ($HARNESS_HOME, v$version)"
}

install_runtime || { echo "init.sh: cannot install runtime at $HARNESS_HOME" >&2; exit 1; }

# --- scaffold standard directories ------------------------------------------
mkdir -p "$DEST/.claude/skills" "$DEST/.claude/agents" \
         "$DEST/docs/exec-plans/active" "$DEST/docs/exec-plans/completed" \
         "$DEST/docs/references" "$DEST/harness" \
         "$DEST/.trace/checkpoints" "$DEST/.trace/runtime"

# --- install assets (native .claude/ layout) --------------------------------
copy_tree "$SRC/skills" "$DEST/.claude/skills"
copy_tree "$SRC/agents" "$DEST/.claude/agents"
# docs/ rides along EXCEPT exec-plans — that is user space; the source repo's
# own active plans must never seed a fresh install.
( cd "$SRC/docs" 2>/dev/null && find . -type f -not -path './exec-plans/*' ) \
  | while read -r rel; do copy_file "$SRC/docs/${rel#./}" "$DEST/docs/${rel#./}"; done
copy_file "$SRC/AGENTS.md"       "$DEST/AGENTS.md"
copy_file "$SRC/ARCHITECTURE.md" "$DEST/ARCHITECTURE.md"

# --- manifest: pointer list of the installed skill and agent files ----------
if [ ! -f "$DEST/harness/manifest.md" ]; then
  {
    echo "# harness-mini manifest"
    echo
    echo "Skills and agents are files under .claude/skills/ and .claude/agents/."
    echo "Any coding agent that can read the repo should open the paths below."
    echo
    echo "## Skills (.claude/skills/)"
    ( cd "$DEST/.claude/skills" 2>/dev/null && {
        for d in */; do [ -f "${d}SKILL.md" ] && printf -- '- %sSKILL.md\n' "$d"; done
        for m in *.md; do [ -f "$m" ] && printf -- '- %s\n' "$m"; done
      } )
    echo
    echo "## Agents (.claude/agents/)"
    ( cd "$DEST/.claude/agents" 2>/dev/null && ls *.md 2>/dev/null ) | sed 's/^/- /'
    echo
    echo "## Map: AGENTS.md   Architecture: ARCHITECTURE.md"
  } > "$DEST/harness/manifest.md"
  say "add   harness/manifest.md"
fi

# --- routing gate: seed each CLI's native always-on entry file ---------------
# Additive + idempotent + upgradeable. CLAUDE.md is user space: only the
# marker-guarded gate block is ever written. Older gates are replaced: a v1
# block (harness-mini:start/end) or a v2 block (markers present but no
# `session-coding` — i.e. path-blind) is stripped and the v3 gate appended
# (exactly one gate). .cursor/rules/harness-mini.mdc is harness-owned: created
# if absent; regenerated whenever it predates the path-aware wording.
# strip_block <begin_marker> <end_marker> <file> — drop marker-to-marker lines.
strip_block() {
  awk -v b="$1" -v e="$2" '
    $0 == b { skip=1 }
    !skip   { print }
    $0 == e { skip=0 }
  ' "$3"
}
# swap_gate <from-label> — strip any older gate shape, append v3, keep one gate.
swap_gate() {
  if strip_block "$V1_BEGIN" "$V1_END" "$DEST/CLAUDE.md" \
     | strip_block "$GATE_BEGIN" "$GATE_END" /dev/stdin > "$DEST/CLAUDE.md.gate.tmp"; then
    mv "$DEST/CLAUDE.md.gate.tmp" "$DEST/CLAUDE.md"
    { printf '\n'; emit_claude_gate; } >> "$DEST/CLAUDE.md"
    say "upgr  CLAUDE.md routing gate $1 -> v3 (old stripped, v3 appended)"
  else
    rm -f "$DEST/CLAUDE.md.gate.tmp"
    say "warn  CLAUDE.md gate strip failed — left untouched"
  fi
}
if [ ! -f "$DEST/CLAUDE.md" ]; then
  emit_claude_gate > "$DEST/CLAUDE.md"
  say "add   CLAUDE.md (routing gate v3)"
elif grep -qF "$GATE_BEGIN" "$DEST/CLAUDE.md" 2>/dev/null; then
  if grep -q 'session-coding' "$DEST/CLAUDE.md" 2>/dev/null; then
    say "skip  CLAUDE.md routing gate (v3 present)"
  else
    swap_gate v2
  fi
elif grep -qF "$V1_BEGIN" "$DEST/CLAUDE.md" 2>/dev/null; then
  swap_gate v1
else
  { printf '\n'; emit_claude_gate; } >> "$DEST/CLAUDE.md"
  say "add   CLAUDE.md routing gate v3 (appended)"
fi
if [ ! -f "$DEST/.cursor/rules/harness-mini.mdc" ]; then
  mkdir -p "$DEST/.cursor/rules"
  emit_cursor_rule > "$DEST/.cursor/rules/harness-mini.mdc"
  say "add   .cursor/rules/harness-mini.mdc"
elif grep -q 'session-coding' "$DEST/.cursor/rules/harness-mini.mdc" 2>/dev/null; then
  say "skip  .cursor/rules/harness-mini.mdc (path-aware)"
else
  # harness-owned file still carrying pre-v3 (path-blind) wording -> regenerate
  emit_cursor_rule > "$DEST/.cursor/rules/harness-mini.mdc"
  say "upgr  .cursor/rules/harness-mini.mdc (v3, path-aware)"
fi

# --- Cursor skill mirror: one agent-requestable rule per skill (#23) ---------
# Cursor does not read .claude/skills/ on its own. Emit a
# thin .cursor/rules/<name>.mdc per skill — `alwaysApply: false` + the skill's
# `description:` — so Cursor's agent can pull a skill on demand by its description
# (progressive-disclosure parity). Each rule points at the canonical SKILL.md
# rather than copying its body: single source of truth, no drift. Additive +
# idempotent + harness-owned like the gate: created only if absent, never in the
# checksum-managed set, so a user's edits and `update` are both safe.
if [ -d "$DEST/.claude/skills" ]; then
  mkdir -p "$DEST/.cursor/rules"
  for skdir in "$DEST/.claude/skills"/*/; do
    [ -f "${skdir}SKILL.md" ] || continue
    name="$(basename "$skdir")"
    rule="$DEST/.cursor/rules/$name.mdc"
    if [ -e "$rule" ]; then say "skip  .cursor/rules/$name.mdc (exists)"; continue; fi
    desc="$(skill_description "${skdir}SKILL.md")"
    [ -n "$desc" ] || desc="harness-mini skill: $name"
    {
      printf -- '---\n'
      printf 'description: %s\n' "$desc"
      printf 'alwaysApply: false\n'
      printf -- '---\n\n'
      printf 'harness-mini skill **%s**. Read `.claude/skills/%s/SKILL.md` and follow it for this task.\n' "$name" "$name"
    } > "$rule"
    say "add   .cursor/rules/$name.mdc"
  done
fi

# --- version lockfile (additive: only on first install) ----------------------
# Records the version + pristine upstream checksums so `harness.sh update` can
# tell user-edited managed files from upstream changes. Left untouched on
# re-run; thereafter maintained by `harness.sh update`.
if [ ! -f "$DEST/harness/harness.lock" ]; then
  src_ver="0.0.0"
  [ -f "$SRC/VERSION" ] && src_ver="$(tr -d ' \t\r\n' < "$SRC/VERSION")"
  write_lock "$SRC" "$DEST" "$src_ver" && say "add   harness/harness.lock (v$src_ver)"
fi

# --- .gitignore: ensure ephemeral runtime traces are ignored (additive) ------
if [ ! -f "$DEST/.gitignore" ] || ! grep -q '\.trace/runtime' "$DEST/.gitignore" 2>/dev/null; then
  printf '.trace/runtime/\n' >> "$DEST/.gitignore"
  say "add   .gitignore (.trace/runtime/)"
fi

# --- seed the first exec-plan (idempotent: only if none exists) -------------
# Guard on ANY active *.md (not just 0001-*): an upgraded install whose plans
# are numbered differently must not gain a spurious bootstrap plan (#63).
if ls "$DEST"/docs/exec-plans/active/*.md >/dev/null 2>&1; then
  say "skip  seed plan (active plan(s) already present)"
else
  if [ "$MODE" = "existing" ]; then
    cat > "$DEST/docs/exec-plans/active/0001-recon.md" <<'EOF'
---
plan: recon
seq: 0001
stage: intake
owner: main
---
# Recon graft

This harness was grafted onto an existing project. Before any new work, map the
ground. Do NOT run the greenfield funnel — this project already exists.

## Now (resume here)
Spawn the **explorer** agent to fill this schema into `ARCHITECTURE.md`'s
"Domains & layers" section (verify commands by running them where safe):

- [ ] Entry points (file:line)
- [ ] Test command
- [ ] Build command
- [ ] Lint / typecheck command
- [ ] Main domains
- [ ] Layer structure actually in use
- [ ] Where product behaviour lives
- [ ] Where tests live (+ naming)
- [ ] Risky dirs to avoid
- [ ] Generated / vendor dirs (do not edit)
- [ ] One recommended first vertical slice

## Next
- Once mapped, wait for the user to point at a requirement, then advance the stage
  (`stage-viewer`) to `prd` and decompose with `to-issues`.

## Decisions
- (record here)
EOF
    cat > "$DEST/docs/exec-plans/active/0001-recon.json" <<'EOF'
{
  "plan_id": "0001-recon",
  "title": "Recon graft",
  "status": "planned",
  "current_slice_id": "",
  "slices": []
}
EOF
    say "add   docs/exec-plans/active/0001-recon.md (+ json twin)"
  else
    cat > "$DEST/docs/exec-plans/active/0001-intake.md" <<'EOF'
---
plan: intake
seq: 0001
stage: intake
owner: main
---
# Intake — greenfield bootstrap

A brand-new project. Run the founder funnel before writing any code.

## Now (resume here)
1. Run **founder-check**: who is the user, the smallest valuable slice,
   the riskiest assumption, the build-measure-learn loop.
2. Run **to-prd**: write the executable PRD.
3. Run **to-issues**: decompose into atomic, testable issues.

## Next
- Advance stage (`stage-viewer`) to `implement`; the generator builds one
  vertical slice via `tdd` + `slice-coding`.

## Decisions
- (record here)
EOF
    cat > "$DEST/docs/exec-plans/active/0001-intake.json" <<'EOF'
{
  "plan_id": "0001-intake",
  "title": "Intake — greenfield bootstrap",
  "status": "planned",
  "current_slice_id": "",
  "slices": []
}
EOF
    say "add   docs/exec-plans/active/0001-intake.md (+ json twin)"
  fi
fi

echo "harness-mini: done."
exit 0
