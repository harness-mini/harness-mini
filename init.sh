#!/usr/bin/env bash
# init.sh — install harness-mini into a project. ADDITIVE and IDEMPOTENT:
# it only ever creates files that don't already exist, so it is safe to drop
# into an old repo and safe to re-run.
#
# Behaviour is asymmetric by project type:
#   new/empty project  -> generative bootstrap: seed an INTAKE plan that runs the
#                         founder funnel (founder-check -> five-step -> to-prd).
#   existing project   -> recon graft: seed a RECON plan that maps the codebase
#                         into ARCHITECTURE.md via the Explorer; no founder funnel.
#
# Install layout (decision: native .claude/ + neutral mirror):
#   skills/  -> .claude/skills/    (auto-discovered by Claude Code)
#   agents/  -> .claude/agents/    (auto-discovered by Claude Code)
#   bin/ docs/ AGENTS.md ARCHITECTURE.md  -> copied as-is
#   harness/manifest.md            -> neutral pointer list for other CLIs
#
# Usage:  init.sh [target_dir] [--mode new|existing]
# Env:    HARNESS_SRC   source root (default: directory containing this script)
#         HARNESS_MODE  force "new" or "existing" (default: auto-detect)
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${HARNESS_SRC:-$SELF_DIR}"
DEST="$PWD"
MODE="${HARNESS_MODE:-}"

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

# --- scaffold standard directories ------------------------------------------
mkdir -p "$DEST/.claude/skills" "$DEST/.claude/agents" "$DEST/bin" \
         "$DEST/docs/exec-plans/active" "$DEST/docs/exec-plans/completed" \
         "$DEST/docs/references" "$DEST/harness" \
         "$DEST/.trace/checkpoints" "$DEST/.trace/runtime"

# --- install assets (native .claude/ layout) --------------------------------
copy_tree "$SRC/skills" "$DEST/.claude/skills"
copy_tree "$SRC/agents" "$DEST/.claude/agents"
copy_tree "$SRC/bin"    "$DEST/bin"
copy_tree "$SRC/docs"   "$DEST/docs"
copy_file "$SRC/AGENTS.md"       "$DEST/AGENTS.md"
copy_file "$SRC/ARCHITECTURE.md" "$DEST/ARCHITECTURE.md"
chmod +x "$DEST"/bin/*.sh 2>/dev/null || true

# --- neutral mirror manifest (for non-Claude CLIs) --------------------------
if [ ! -f "$DEST/harness/manifest.md" ]; then
  {
    echo "# harness-mini manifest (CLI-neutral pointer list)"
    echo
    echo "Claude Code auto-loads skills/agents from .claude/. Other CLIs (codex,"
    echo "cursor) should read the files below directly."
    echo
    echo "## Skills (.claude/skills/)"
    ( cd "$DEST/.claude/skills" 2>/dev/null && ls *.md 2>/dev/null ) | sed 's/^/- /'
    echo
    echo "## Agents (.claude/agents/)"
    ( cd "$DEST/.claude/agents" 2>/dev/null && ls *.md 2>/dev/null ) | sed 's/^/- /'
    echo
    echo "## Map: AGENTS.md   Architecture: ARCHITECTURE.md"
  } > "$DEST/harness/manifest.md"
  say "add   harness/manifest.md"
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
if ls "$DEST"/docs/exec-plans/active/0001-*.md >/dev/null 2>&1; then
  say "skip  seed plan (active plan already present)"
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

This harness was grafted onto an existing project. Before any new work:

## Now (resume here)
- Spawn the **explorer** agent to map the codebase into `ARCHITECTURE.md`:
  domains, layers, test command, build command, entry points.
- Do NOT run the founder funnel — this project already exists.

## Next
- Wait for the user to point at a requirement, then advance the stage
  (`stage-viewer`) to `prd` and decompose with `to-issues`.

## Decisions
- (record here)
EOF
    say "add   docs/exec-plans/active/0001-recon.md"
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
2. Run **five-step**: question every requirement, delete, simplify,
   accelerate, automate — in that order.
3. Run **to-prd**: write the executable PRD.
4. Run **to-issues**: decompose into atomic, testable issues.

## Next
- Advance stage (`stage-viewer`) to `implement`; the generator builds one
  vertical slice via `tdd` + `slice-coding`.

## Decisions
- (record here)
EOF
    say "add   docs/exec-plans/active/0001-intake.md"
  fi
fi

echo "harness-mini: done."
exit 0
