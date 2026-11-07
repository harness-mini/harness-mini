#!/usr/bin/env bash
# init.sh — install harness-mini into a project. ADDITIVE and IDEMPOTENT:
# it only ever creates files that don't already exist, so it is safe to drop
# into an old repo and safe to re-run.
#
# Behaviour is asymmetric by project type:
#   new/empty project  -> generative bootstrap: seed an INTAKE plan that runs the
#                         founder funnel (founder-check -> to-prd).
#   existing project   -> recon graft: seed a RECON plan that maps the codebase
#                         into .harness-mini/architecture.md via the Explorer; no founder funnel.
#
# Install layout (zero intrusion — the project gets only):
#   .harness-mini/        project progress: docs/exec-plans/{active,completed},
#                         trace/{checkpoints,evals,runtime}, architecture.md, .gitignore
#   AGENTS.md             one <!-- harness-mini:begin/end --> block (created if absent)
# Everything harness-owned lives under $HARNESS_HOME (default ~/.harness-mini):
#   bin/ VERSION harness/runtime.lock   the runtime
#   AGENTS.md docs/ docs/ARCHITECTURE.md   the global map + static docs
#   skills/ agents/                     sources for `harness.sh agent install <host>`
#   <project-id>/{harness.lock,manifest.md}   per-project bookkeeping
# init.sh installs no skills/agents (it cannot know the host) and never edits the
# project's .gitignore, ARCHITECTURE.md or CLAUDE.md.
# An older install (0058 shared layout or the .claude/ layout) is migrated
# automatically: plans/trace move into .harness-mini/, harness-owned files are
# removed only when their checksum matches the old harness/harness.lock; edited
# files are kept and reported (migrate_legacy_layout in bin/_harness_lib.sh).
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

# Install the runtime, or refresh an older one: checksum-guarded exactly like
# `harness.sh update` (pristine files upgraded, user-edited ones kept with a .new,
# VERSION + runtime.lock advanced). An installed runtime that is already at this
# source's version or newer is never touched (no downgrade). Sets REFRESH=refresh
# when an existing home was upgraded, so the globals follow the same guard.
REFRESH=add
install_runtime() {
  local runtime_lock="$HARNESS_HOME/harness/runtime.lock" version installed log rc=0
  version="$(tr -d ' \t\r\n' < "$SRC/VERSION" 2>/dev/null)"
  [ -n "$version" ] || version=unknown
  if [ -f "$runtime_lock" ]; then
    installed="$(lock_version "$runtime_lock")"
    if ! version_newer "$installed" "$version"; then
      say "skip  user runtime (v$installed at $HARNESS_HOME is already current)"
      return 0
    fi
    REFRESH=refresh
  fi
  log="$(mktemp)" || return 1
  sync_runtime "$SRC" "$HARNESS_HOME" "$version" "$log" || rc=$?
  case "$rc" in
    0) if [ "$REFRESH" = refresh ]; then say "update user runtime ($HARNESS_HOME, v${installed:-?} -> v$version)"
       else say "add   user runtime ($HARNESS_HOME, v$version)"; fi
       sed 's/^runtime /  /' "$log" | while IFS= read -r line; do say "$line"; done ;;
    2) say "note  $SRC has no bin/harness.sh: no runtime was installed at $HARNESS_HOME" ;;
  esac
  rm -f "$log"
  [ "$rc" -le 2 ]
}

install_runtime || { echo "init.sh: cannot install runtime at $HARNESS_HOME" >&2; exit 1; }

# Harness-owned files that do not depend on any project live in the runtime
# root: the global map, static docs (docs/ is the distribution source; the
# source-repo-only references/ and assets/ sit outside it), the lifecycle
# ARCHITECTURE.md, and the skill/agent sources the host-aware installer copies.
install_global_assets() {
  local out added
  out="$(sync_globals "$SRC" "$REFRESH")" || return 1
  added="$(printf '%s\n' "$out" | grep -c '^add ')"
  [ "$added" -eq 0 ] || say "add   $added global file(s) under $HARNESS_HOME (map, docs, skills, agents)"
  printf '%s\n' "$out" | grep -v '^add ' | while IFS= read -r line; do [ -z "$line" ] || say "global $line"; done
  return 0
}
install_global_assets || { echo "init.sh: cannot install global assets at $HARNESS_HOME" >&2; exit 1; }

# --- migrate pre-0059 layouts (before AGENTS.md is touched) ------------------
# Moves plans/trace into .harness-mini/ and removes only lock-verified harness
# files; the old harness/harness.lock is its baseline. Silent when nothing legacy.
# It REFUSES (exit 1, project untouched) unless the runtime above is usable — the
# AGENTS.md block must never point at a harness.sh that does not exist.
migrate_legacy_layout "$DEST" "$SRC" || { echo "init.sh: legacy migration failed" >&2; exit 1; }

# --- scaffold standard directories ------------------------------------------
PROGRESS="$(progress_dir "$DEST")"
STATE="$(state_dir "$DEST")"
mkdir -p "$STATE" "$PROGRESS/docs/exec-plans/active" "$PROGRESS/docs/exec-plans/completed" \
         "$PROGRESS/trace/checkpoints" "$PROGRESS/trace/evals" "$PROGRESS/trace/runtime"
# Ephemeral traces are ignored from INSIDE .harness-mini/ — the project's own
# .gitignore is never edited.
if progress_gitignore_ensure "$DEST"; then say "add   .harness-mini/.gitignore"; fi

# Skills and role descriptions are NOT installed here: init cannot know the host.
# The AGENTS.md block tells the agent to run `harness.sh agent list` then
# `agent install <host>`, which copies from $HARNESS_HOME/skills and /agents.

# --- project instructions: one marker block in AGENTS.md ---------------------
# The user's own ARCHITECTURE.md / CLAUDE.md / .gitignore are never touched.
HOME_REF="$(home_ref)"
if [ -f "$DEST/AGENTS.md" ] && grep -qxF "$HM_BEGIN" "$DEST/AGENTS.md"; then
  say "skip  AGENTS.md (harness-mini block present)"
else
  agents_block_add "$DEST/AGENTS.md" "$HOME_REF" && say "add   AGENTS.md (harness-mini block)"
fi
# Project recon output: the lifecycle architecture itself is global.
if [ ! -f "$PROGRESS/architecture.md" ]; then
  cat > "$PROGRESS/architecture.md" <<'EOF'
# Architecture (this project)

Filled by the recon plan (explorer agent). The harness lifecycle lives in
`~/.harness-mini/docs/ARCHITECTURE.md`; this file is only about this project.

## Domains & layers
(pending recon)
EOF
  say "add   .harness-mini/architecture.md"
fi

# --- manifest: pointer list of the skills/roles an agent install places ------
# Bookkeeping, so it lives in the state dir next to the lock, built from the
# source (nothing is installed in the project yet).
if [ ! -f "$STATE/manifest.md" ]; then
  write_manifest "$SRC" "$STATE" "$(targets_text "$DEST")"
  say "add   manifest.md (state dir: $STATE)"
fi

# --- version lockfile (additive: only on first install) ----------------------
# Records the version + pristine upstream checksums so `harness.sh update` can
# tell user-edited managed files from upstream changes. Left untouched on
# re-run; thereafter maintained by `harness.sh update`.
if [ ! -f "$STATE/harness.lock" ]; then
  src_ver="0.0.0"
  [ -f "$SRC/VERSION" ] && src_ver="$(tr -d ' \t\r\n' < "$SRC/VERSION")"
  write_lock "$SRC" "$STATE" "$src_ver" "$(targets_text "$DEST")" && say "add   harness.lock (state dir, v$src_ver)"
fi
# retained pristine .agents/ files from a legacy install keep their old baseline
legacy_seeds_adopt "$STATE/harness.lock"

# --- seed the first exec-plan (idempotent: only if none exists) -------------
# Guard on ANY active *.md (not just 0001-*): an upgraded install whose plans
# are numbered differently must not gain a spurious bootstrap plan (#63).
if ls "$PROGRESS"/docs/exec-plans/active/*.md >/dev/null 2>&1; then
  say "skip  seed plan (active plan(s) already present)"
else
  if [ "$MODE" = "existing" ]; then
    cat > "$PROGRESS/docs/exec-plans/active/0001-recon.md" <<'EOF'
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
Spawn the **explorer** agent to fill this schema into
`.harness-mini/architecture.md`'s "Domains & layers" section (verify commands by running them where safe):

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
    cat > "$PROGRESS/docs/exec-plans/active/0001-recon.json" <<'EOF'
{
  "plan_id": "0001-recon",
  "title": "Recon graft",
  "status": "planned",
  "current_slice_id": "",
  "slices": []
}
EOF
    say "add   .harness-mini/docs/exec-plans/active/0001-recon.md (+ json twin)"
  else
    cat > "$PROGRESS/docs/exec-plans/active/0001-intake.md" <<'EOF'
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
    cat > "$PROGRESS/docs/exec-plans/active/0001-intake.json" <<'EOF'
{
  "plan_id": "0001-intake",
  "title": "Intake — greenfield bootstrap",
  "status": "planned",
  "current_slice_id": "",
  "slices": []
}
EOF
    say "add   .harness-mini/docs/exec-plans/active/0001-intake.md (+ json twin)"
  fi
fi

echo "harness-mini: done."
dotnew_notice "$DEST"
exit 0
