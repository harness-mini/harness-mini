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
# Install layout (shared skill path; no agent host selection):
#   skills/  -> .agents/skills/
#   agents/  -> harness/agents/
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
mkdir -p "$DEST/.agents/skills" "$DEST/harness/agents" \
         "$DEST/docs/exec-plans/active" "$DEST/docs/exec-plans/completed" \
         "$DEST/docs/references" "$DEST/harness" \
         "$DEST/.trace/checkpoints" "$DEST/.trace/runtime"

# --- install shared skills and neutral role descriptions ---------------------
copy_tree "$SRC/skills" "$DEST/.agents/skills"
copy_tree "$SRC/agents" "$DEST/harness/agents"
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
    echo "Skills are under .agents/skills/; role descriptions are under harness/agents/."
    echo "Any coding agent that can read the repo should open the paths below."
    echo
    echo "## Skills (.agents/skills/)"
    ( cd "$DEST/.agents/skills" 2>/dev/null && {
        for d in */; do [ -f "${d}SKILL.md" ] && printf -- '- %sSKILL.md\n' "$d"; done
        for m in *.md; do [ -f "$m" ] && printf -- '- %s\n' "$m"; done
      } )
    echo
    echo "## Role descriptions (harness/agents/)"
    ( cd "$DEST/harness/agents" 2>/dev/null && ls *.md 2>/dev/null ) | sed 's/^/- /'
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
