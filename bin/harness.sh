#!/usr/bin/env bash
# harness.sh — the front-door CLI for harness-mini. Thin glue over the
# convention: report the installed version, pull a newer version into this
# project without clobbering your edits, and (in the source repo) cut releases.
#
# Usage:
#   harness.sh version                 show installed version (+ latest, best-effort)
#   harness.sh update [--src DIR] [--force]  refresh the runtime, the global copies and this project's
#                                      managed files (checksum-guarded); migrates a legacy layout;
#                                      refuses to downgrade the runtime unless --force
#   harness.sh diff <relpath|path>     show how your kept file differs from its upstream <file>.new
#   harness.sh agent list              the supported hosts (id, skills dir, agents dir, format)
#   harness.sh agent install <host>    install skills + role files for YOUR host into the project
#   harness.sh doctor | status | report   install health · work state · trace metrics
#   harness.sh release <x.y.z> [opts]  bump + tag + GitHub release (source repo only)
#
# Env:
#   HARNESS_ROOT   project root (default: current directory; override with --root)
#   HARNESS_REPO   owner/repo for latest-version checks (default harness-mini/harness-mini)
#   HARNESS_NO_NET if set, skip all network (offline; tests)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=bin/_harness_lib.sh
. "$HERE/_harness_lib.sh"

HARNESS_ROOT="${HARNESS_ROOT:-$PWD}"
# Per-project bookkeeping (lock + manifest) lives in $HARNESS_HOME/projects/<project-id>/,
# never in the project tree. Re-derived once the project root is final.
LOCK=""

say()  { printf '  %s\n' "$1"; }
die()  { echo "harness.sh: $1" >&2; exit "${2:-1}"; }

# installed_version — version recorded in the lock, else the root VERSION file.
installed_version() {
  if [ -f "$LOCK" ]; then
    lock_version "$LOCK"
  elif [ -f "$RUNTIME_ROOT/VERSION" ]; then
    read_version "$RUNTIME_ROOT/VERSION"
  elif [ -f "$HARNESS_ROOT/VERSION" ]; then
    read_version "$HARNESS_ROOT/VERSION"
  else
    echo "unknown"
  fi
}

runtime_version() {
  if [ -f "$RUNTIME_ROOT/harness/runtime.lock" ]; then
    lock_version "$RUNTIME_ROOT/harness/runtime.lock"
  elif [ -f "$RUNTIME_ROOT/VERSION" ]; then
    read_version "$RUNTIME_ROOT/VERSION"
  else
    echo "unknown"
  fi
}

# manifest_file <root> — the project's manifest, next to its lock.
manifest_file() { printf '%s/manifest.md' "$(state_dir "$1")"; }

project_version() {
  local root="$1" version="" lockf
  lockf="$(state_dir "$root")/harness.lock"
  [ ! -f "$lockf" ] || version="$(lock_version "$lockf")"
  if [ -z "$version" ] && [ -f "$root/VERSION" ]; then
    version="$(read_version "$root/VERSION")"
  fi
  printf '%s' "${version:-uninitialized}"
}

# shared_skill_count <root> — distinct skills across the persisted skill
# targets (a skill present at two targets counts once); a source checkout
# without installed targets counts its own skills/.
shared_skill_count() {
  local root="$1" dirs d
  dirs="$(existing_skill_dirs "$root")"
  if [ -z "$dirs" ] && [ -d "$root/skills" ]; then dirs="skills"; fi
  [ -n "$dirs" ] || { printf '0'; return; }
  for d in $dirs; do
    ( cd "$root/$d" && { find . -type f -name SKILL.md; find . -maxdepth 1 -type f -name '*.md'; } 2>/dev/null )
  done | sort -u | wc -l | tr -d ' '
}

manifest_skill_entries() {
  awk '
    /^## Skills \(/ { in_skills=1; next }
    /^## / { in_skills=0 }
    in_skills && /^- / { sub(/^- /, ""); print }
  ' "$1" 2>/dev/null
}

# missing_manifest_skills <root> — manifest entries absent from ANY skill target.
missing_manifest_skills() {
  local root="$1" entry mf d dirs
  mf="$(manifest_file "$root")"
  [ -f "$mf" ] || return 0
  dirs="$(target_skill_dirs "$root")"
  while IFS= read -r entry; do
    case "$entry" in
      ""|/*|../*|*/../*|*/..)
        printf '%s\n' "$entry (invalid path)"
        ;;
      *)
        for d in $dirs; do
          [ -f "$root/$d/$entry" ] || { printf '%s\n' "$entry"; break; }
        done
        ;;
    esac
  done < <(manifest_skill_entries "$mf")
}

# latest_version — best-effort newest published tag for HARNESS_REPO (no "v").
# HARNESS_LATEST overrides (explicit pin / offline tests); HARNESS_NO_NET
# short-circuits so the caller never hangs offline-on-purpose.
latest_version() {
  [ -n "${HARNESS_LATEST:-}" ] && { printf '%s' "${HARNESS_LATEST#v}"; return 0; }
  [ -n "${HARNESS_NO_NET:-}" ] && return 0
  local repo="${HARNESS_REPO:-harness-mini/harness-mini}" tag=""
  if command -v gh >/dev/null 2>&1; then
    tag="$(gh release view --repo "$repo" --json tagName -q .tagName 2>/dev/null)"
  fi
  if [ -z "$tag" ] && command -v git >/dev/null 2>&1; then
    tag="$(git ls-remote --tags "https://github.com/$repo.git" 2>/dev/null \
           | sed 's#.*refs/tags/##; s/\^{}//' | grep '^v[0-9]' | sort -V | tail -1)"
  fi
  printf '%s' "${tag#v}"
}

cmd_version() {
  local v latest; v="$(installed_version)"
  echo "harness-mini ${v:-unknown} (installed)"
  latest="$(latest_version)"
  [ -z "$latest" ] && return 0
  if version_newer "$v" "$latest"; then
    echo "latest: $latest — run \`harness.sh update\`"
  else
    echo "up to date."
  fi
}

# json_wb <twin.json> — distill a plan's JSON twin into one |-separated line:
#   status | current_slice_id | next-pass:false-slice | npass | nfail | plan_id-seen(0|1)
# awk only (zero-dependency; no jq). Tolerates any indentation and compact
# one-line slice objects (exact-key matching: "id" never collides with
# plan_id/current_slice_id). "|" delimiter so EMPTY fields survive `read`
# (IFS-whitespace would collapse them and shift columns). plan_id-seen=0 or
# empty status => not a readable twin.
json_wb() {
  awk '
    /"plan_id":[ \t]*"/          { pid=1 }
    /"status":[ \t]*"/           { s=$0; sub(/.*"status":[ \t]*"*/,"",s);  sub(/".*/,"",s); st=s }
    /"current_slice_id":[ \t]*"/ { s=$0; sub(/.*"current_slice_id":[ \t]*"*/,"",s); sub(/".*/,"",s); cur=s }
    /"id":[ \t]*"/               { s=$0; sub(/.*"id":[ \t]*"*/,"",s);     sub(/".*/,"",s); id=s }
    /"passes":[ \t]*true/        { np++; id="" }
    /"passes":[ \t]*false/       { ns++; if (nxt=="") nxt=id; id="" }
    END { printf "%s|%s|%s|%d|%d|%d\n", st, cur, nxt, np+0, ns+0, pid+0 }
  ' "$1"
}

# update_runtime <source_root> <version> <log_file> — install/refresh the runtime at
# $HARNESS_HOME from the source tree (sync_runtime in the lib). No runtime.lock there
# yet means a BOOTSTRAP — e.g. a v0.12.1 project whose only harness is its own bin/.
# Sets the caller's deferred_runtime_* when the running script itself is to be swapped
# last. Returns 2 when the source has no bin/harness.sh (nothing installable).
update_runtime() {
  local self rc=0
  self="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
  sync_runtime "$1" "$(harness_home)" "$2" "$3" "$self" || rc=$?
  deferred_runtime_src="$RUNTIME_DEFER_SRC"; deferred_runtime_dst="$RUNTIME_DEFER_DST"
  return $rc
}

# cmd_update [--src DIR] [--force] — refresh what the harness owns, checksum-guarded. A source
# older than the installed runtime is refused (nothing changed) unless --force. In order:
#   1. runtime   $HARNESS_HOME/bin + VERSION        (runtime.lock; the running script swaps last;
#                installed from the source tree when absent — a bootstrap)
#   2. globals   map, docs, skills, agents sources  (global.lock — separate from runtime.lock)
#   3. migration a pre-0059 project layout moves into .harness-mini/ (plans, trace; unchanged
#                harness files are removed by checksum, edited ones kept) — silent when none.
#                REFUSED (nothing touched) unless step 1 left a usable runtime.
#   4. project   the skills + role files `agent install <host>` placed in this project
#                (harness.lock under $HARNESS_HOME/projects/<project-id>/)
# Per file (base = lock baseline, cur = on disk, new = upstream):
#   absent          -> ADD       missing managed file
#   new == cur      -> UNCHANGED  already matches upstream
#   cur == base     -> UPDATE     upstream changed, user untouched -> overwrite
#   otherwise       -> CONFLICT   user-edited & diverged -> keep, write <file>.new
# Only the managed set (skills + roles, keyed by target path in the project lock) is
# iterated; a target that was never installed is recorded but not created. User space
# (.harness-mini/ progress, project code, your .gitignore) is never touched. Any <file>.new
# left behind (here or by an earlier run) is announced once at the end: see dotnew_notice.
cmd_update() {
  local src="" force=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --src) src="$2"; shift 2 ;;
      --force) force=1; shift ;;
      *) die "update: unknown arg: $1" 64 ;;
    esac
  done
  src="${src:-${HARNESS_SRC:-}}"

  local tmpclone=""
  if [ -z "$src" ]; then
    [ -n "${HARNESS_NO_NET:-}" ] && die "update: no --src and network disabled" 64
    command -v git >/dev/null 2>&1 || die "update: need git to fetch upstream (or pass --src DIR)" 64
    local repo="${HARNESS_REPO:-harness-mini/harness-mini}"
    tmpclone="$(mktemp -d)"
    git clone --depth 1 "https://github.com/$repo.git" "$tmpclone" >/dev/null 2>&1 \
      || { rm -rf "$tmpclone"; die "update: clone of $repo failed (pass --src DIR)" 1; }
    src="$tmpclone"
  fi
  [ -d "$src" ] || die "update: source not found: $src" 64

  local src_ver="0.0.0"
  [ -f "$src/VERSION" ] && src_ver="$(read_version "$src/VERSION")"
  # No downgrade of the runtime (the same version_newer test init.sh uses), unless --force.
  local rt_ver; rt_ver="$(lock_version "$(harness_home)/harness/runtime.lock")"
  if [ -z "$force" ] && version_newer "$src_ver" "$rt_ver"; then
    [ -z "$tmpclone" ] || rm -rf "$tmpclone"
    die "update: refusing to downgrade the runtime at $(harness_home) (installed v$rt_ver, source v$src_ver); nothing was changed. Pass --force to install it anyway." 1
  fi
  echo "updating harness-mini $(installed_version) -> $src_ver"

  local newlock log pairs
  local deferred_runtime_src="" deferred_runtime_dst=""
  newlock="$(mktemp)"; log="$(mktemp)"
  printf 'version: %s\n' "$src_ver" > "$newlock"
  local urc=0
  update_runtime "$src" "$src_ver" "$log" || urc=$?
  [ "$urc" -le 2 ] || die "update: runtime refresh failed" 1
  [ "$urc" -ne 2 ] || printf 'runtime none: %s has no bin/harness.sh, so it cannot install a runtime\n' "$src" >> "$log"
  # Global copies (map, docs, skills, agents) follow the same guard as project
  # files: untouched copies are refreshed, local edits get a .new sibling.
  sync_globals "$src" refresh | sed 's/^/global /' >> "$log" || die "update: global refresh failed" 1
  # A pre-0059 project layout is migrated first (silent when there is none). The
  # migration refuses to run unless the runtime installed above is usable.
  migrate_legacy_layout "$HARNESS_ROOT" "$src" || die "update: legacy migration failed" 1
  # The running runtime script is never part of the project set (executables
  # live in $RUNTIME_ROOT); update_runtime defers swapping it to the very end.
  local targets stage
  targets="$(targets_text "$HARNESS_ROOT")"; stage="$(mktemp -d)"
  pairs="$(HM_STAGE="$stage" emit_managed_pairs "$src" "$targets")"
  while IFS="$(printf '\t')" read -r s rel; do
    local dst="$HARNESS_ROOT/$rel" new base cur rec seed
    new="$(cksum_file "$s")"
    base="$(lock_sha "$LOCK" "$rel")"
    if [ -f "$dst" ]; then cur="$(cksum_file "$dst")"; else cur=""; fi
    seed="$(legacy_seed_sha "$rel")"                # pristine file adopted from a legacy lock
    if [ -n "$seed" ] && [ "$cur" = "$seed" ]; then base="$seed"; fi

    if [ ! -f "$dst" ] && [ ! -d "$HARNESS_ROOT/$(managed_root_of "$rel" "$targets")" ]; then
      rec="$new"                                    # target never installed: record only
    elif [ ! -f "$dst" ]; then
      mkdir -p "$(dirname "$dst")"; cp "$s" "$dst"; rec="$new"
      printf 'add    %s\n' "$rel" >> "$log"
    elif [ "$new" = "$cur" ]; then
      rec="$new"                                    # already matches upstream
    elif [ -n "$base" ] && [ "$cur" = "$base" ]; then
      cp "$s" "$dst"; rec="$new"                    # upstream changed, user untouched
      printf 'update %s\n' "$rel" >> "$log"
    else                                            # diverged: protect user edits
      if [ "$new" != "$base" ] || [ ! -f "$dst.new" ]; then
        cp "$s" "$dst.new"
        printf 'keep   %s (you edited it) -> wrote %s.new\n' "$rel" "$rel" >> "$log"
      else
        printf 'keep   %s (already flagged)\n' "$rel" >> "$log"
      fi
      rec="$new"
    fi
    printf '%s  %s\n' "$rec" "$rel" >> "$newlock"
  done <<< "$pairs"
  rm -rf "$stage"

  mkdir -p "$(dirname "$LOCK")" && mv "$newlock" "$LOCK" || die "update: cannot write $LOCK" 1
  if [ -s "$log" ]; then sed 's/^/  /' "$log"; else echo "  already up to date."; fi
  rm -f "$log"
  [ -n "$tmpclone" ] && rm -rf "$tmpclone"
  dotnew_notice "$HARNESS_ROOT"
  if [ -n "$deferred_runtime_src" ]; then
    # bash reads scripts lazily: overwriting the executing file mid-run would
    # resume the NEW file at the OLD byte offset. Swap last, then exit at once.
    cp "$deferred_runtime_src" "$deferred_runtime_dst"
    exit 0
  fi
  return 0
}

# changelog_section <file> <version> — print the body of a version's section.
changelog_section() {
  awk -v v="$2" '
    $0 ~ "^## \\[" v "\\]" { grab=1; next }
    grab && /^## / { exit }
    grab { print }' "$1" 2>/dev/null
}

# cmd_release <x.y.z> [--dry-run] [--no-push] [--no-gh] — source-repo only.
# Gates on semver + green tests + (non-dry) a clean tree, then bumps VERSION,
# rolls CHANGELOG.md, commits, tags v<x.y.z>, pushes, and cuts a GitHub release.
cmd_release() {
  local version="" dry="" nopush="" nogh=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=1; shift ;;
      --no-push) nopush=1; shift ;;
      --no-gh)   nogh=1; shift ;;
      -*) die "release: unknown flag: $1" 64 ;;
      *)  [ -z "$version" ] && { version="$1"; shift; } || die "release: unexpected arg: $1" 64 ;;
    esac
  done
  [ -n "$version" ] || die "release: usage: release <x.y.z> [--dry-run] [--no-push] [--no-gh]" 64
  printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "release: '$version' is not semver x.y.z" 64
  [ -f "$HARNESS_ROOT/VERSION" ] || die "release: run this in the harness source repo (no VERSION here)" 64
  git -C "$HARNESS_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "release: $HARNESS_ROOT is not a git repo" 64

  local cur; cur="$(installed_version)"
  echo "release: harness-mini $cur -> $version${dry:+  (dry-run)}"

  # gate: tests must be green
  if [ -f "$HARNESS_ROOT/tests/run.sh" ]; then
    if bash "$HARNESS_ROOT/tests/run.sh" >/dev/null 2>&1; then say "✓ tests green"
    else die "tests are red — fix before releasing" 1; fi
  fi
  # gate: clean tree (enforced only for a real release)
  if [ -z "$dry" ] && [ -n "$(git -C "$HARNESS_ROOT" status --porcelain 2>/dev/null)" ]; then
    die "working tree not clean — commit or stash first" 1
  fi

  if [ -n "$dry" ]; then
    say "would bump VERSION $cur -> $version"
    say "would roll CHANGELOG.md"
    say "would commit + tag v$version"
    [ -z "$nopush" ] && say "would git push (+ tag)"
    [ -z "$nogh" ]   && say "would gh release create v$version"
    return 0
  fi

  # bump VERSION + roll CHANGELOG (Unreleased -> a dated version section)
  printf '%s\n' "$version" > "$HARNESS_ROOT/VERSION"
  local today; today="$(date +%Y-%m-%d)"
  if [ -f "$HARNESS_ROOT/CHANGELOG.md" ]; then
    awk -v ver="$version" -v d="$today" '
      !done && /^## \[Unreleased\]/ { print "## [Unreleased]"; print ""; print "## [" ver "] - " d; done=1; next }
      { print }' "$HARNESS_ROOT/CHANGELOG.md" > "$HARNESS_ROOT/CHANGELOG.md.tmp" \
      && mv "$HARNESS_ROOT/CHANGELOG.md.tmp" "$HARNESS_ROOT/CHANGELOG.md"
  else
    printf '# Changelog\n\n## [Unreleased]\n\n## [%s] - %s\n- Release v%s\n' "$version" "$today" "$version" \
      > "$HARNESS_ROOT/CHANGELOG.md"
  fi
  say "✓ VERSION $cur -> $version"
  say "✓ CHANGELOG.md rolled"

  git -C "$HARNESS_ROOT" add VERSION CHANGELOG.md >/dev/null 2>&1
  git -C "$HARNESS_ROOT" commit -m "release: v$version" >/dev/null 2>&1 && say "✓ commit" || say "  (nothing to commit)"
  git -C "$HARNESS_ROOT" tag "v$version" && say "✓ tag v$version" || die "tag v$version already exists" 1

  if [ -z "$nopush" ] && git -C "$HARNESS_ROOT" remote | grep -q .; then
    git -C "$HARNESS_ROOT" push >/dev/null 2>&1 && git -C "$HARNESS_ROOT" push origin "v$version" >/dev/null 2>&1 \
      && say "✓ git push (+ tag)" || say "  (push skipped/failed — push manually)"
  fi
  if [ -z "$nogh" ] && command -v gh >/dev/null 2>&1 && git -C "$HARNESS_ROOT" remote | grep -q .; then
    local notes; notes="$(changelog_section "$HARNESS_ROOT/CHANGELOG.md" "$version")"
    ( cd "$HARNESS_ROOT" && gh release create "v$version" --title "v$version" --notes "${notes:-Release v$version}" ) >/dev/null 2>&1 \
      && say "✓ gh release v$version" || say "  (gh release skipped/failed — create manually)"
  fi
  return 0
}

# --- agent: host-aware skills + role-file installer ---------------------------
# The running agent names its OWN host; the table in _harness_lib.sh (host_row)
# maps it to the dirs it reads. Sources are the global copies init.sh placed in
# $HARNESS_HOME; the project is only ever added to, never overwritten.

agent_list() {
  local tab; tab="$(printf '\t')"
  echo "# harness-mini hosts. Pass YOUR OWN host id:  harness.sh agent install <id> [--root DIR]"
  echo "# columns (TAB-separated): id, skills dir, agents dir, agents format, confidence/notes"
  echo "# aliases: claude-code, github-copilot, codex-cli, z-code, mimo-code, dsh, deepseek-harness"
  echo "# unsupported/unknown hosts: nothing is installed; you copy the sources yourself."
  local h
  for h in $HOST_IDS; do host_row "$h"; done
}

# agent_self_install <host> <why> — what to do when the installer cannot place
# files for this host. Writes nothing; exit status stays 0 (not an error).
agent_self_install() {
  local home; home="$(harness_home)"
  echo "harness-mini: cannot install for host '$1': $2."
  echo "Nothing was written to the project."
  echo
  echo "Install them yourself, from the harness-mini sources:"
  echo "  skills: $home/skills/<name>/SKILL.md  (+ nested resources)"
  echo "          -> copy each skill folder into a skills directory your host recognises"
  echo "  roles:  $home/agents/<name>.md        (sub-agent role descriptions: YAML name/description + body)"
  echo "          -> convert/copy into your host's own agent or role format, if it has one"
  echo "Never overwrite files you or the user already have. Run \`harness.sh agent list\` to see supported hosts."
}

agent_install() {
  local host="${1:-}" row id st at fmt note home root="$HARNESS_ROOT" state
  [ -n "$host" ] || die "agent install: usage: agent install <host> [--root DIR]  (see: agent list)" 64
  home="$(harness_home)"
  if ! row="$(host_row "$host")"; then
    agent_self_install "$host" "not a recognised host"; return 0
  fi
  IFS="$(printf '\t')" read -r id st at fmt note <<< "$row"
  if [ "$fmt" = none ]; then
    agent_self_install "$id" "${note#unsupported: }"; return 0
  fi
  [ -d "$home/skills" ] || [ -d "$home/agents" ] \
    || die "agent install: no skills/agents sources under $home (run init.sh first)" 1
  state="$(state_dir "$root")"

  local stage pairs s rel added=0 kept=0 dst
  stage="$(mktemp -d)" || die "agent install: cannot create scratch dir" 1
  pairs="$(HM_STAGE="$stage" emit_managed_pairs "$home" "$(printf '%s' "$row" | cut -f1-4)")"
  while IFS="$(printf '\t')" read -r s rel; do
    [ -n "$rel" ] || continue
    dst="$root/$rel"
    if [ -e "$dst" ]; then kept=$((kept + 1)); continue; fi
    mkdir -p "$(dirname "$dst")" && cp "$s" "$dst" || { rm -rf "$stage"; die "agent install: cannot write $rel" 1; }
    added=$((added + 1))
  done <<< "$pairs"
  rm -rf "$stage"

  git_exclude_add "$root" "$st/" "$at/"
  targets_add "$state" "$(printf '%s' "$row" | cut -f1-4)" || die "agent install: cannot write targets" 1
  local rows ver; rows="$(targets_text "$root")"; ver="$(installed_version)"
  write_lock "$home" "$state" "$ver" "$rows" || die "agent install: cannot write lock" 1
  write_manifest "$home" "$state" "$rows" || die "agent install: cannot write manifest" 1

  echo "harness-mini: installed for $id"
  echo "  skills: $st/   agents: $at/ ($fmt)"
  echo "  add   $added file(s)   keep  $kept existing file(s) untouched"
  echo "  recorded targets, lock and manifest in $state"
}

cmd_agent() {
  local sub="${1:-}"; [ $# -eq 0 ] || shift
  case "$sub" in
    list)    agent_list ;;
    install) agent_install "$@" ;;
    *) die "agent: usage: agent list | agent install <host>" 64 ;;
  esac
}

# cmd_diff <relpath|path> — how YOUR kept copy of a file differs from the upstream copy
# `update`/`init` left next to it as <file>.new. A relative path is looked up under
# $HARNESS_HOME (bin/harness.sh, skills/tdd/SKILL.md, docs/…) and then under the project
# root; an absolute path is used as is. Exit 0 when a diff was printed, 1 when there is
# nothing to compare (no such file, or no .new).
cmd_diff() {
  local arg="${1:-}" h p c kept=""
  [ -n "$arg" ] || die "diff: usage: diff <relpath-or-path> [--root DIR]" 64
  [ $# -le 1 ] || die "diff: unexpected arg: $2" 64
  arg="${arg%.new}"
  case "$arg" in
    /*) h="$arg"; p="$arg" ;;
    *)  h="$(harness_home)/$arg"; p="$HARNESS_ROOT/$arg" ;;
  esac
  for c in "$h" "$p"; do
    if [ -f "$c" ] && [ -f "$c.new" ]; then kept="$c"; break; fi
  done
  if [ -z "$kept" ]; then
    if [ -f "$h" ] || [ -f "$p" ]; then die "diff: no .new next to $arg — nothing to compare (it was not left by an update)" 1; fi
    die "diff: not found: $arg (looked under $(harness_home) and $HARNESS_ROOT)" 1
  fi
  echo "# --- yours (kept)   +++ upstream (.new)   — take upstream with: mv \"$kept.new\" \"$kept\""
  local rc=0
  diff -u -L "$kept (yours)" -L "$kept.new (upstream)" "$kept" "$kept.new" || rc=$?
  [ "$rc" -le 1 ] || die "diff: diff(1) failed (exit $rc)" 1
  [ "$rc" -ne 0 ] || echo "# no differences: the .new is identical to your file — delete it"
  return 0
}

# dotnew_where <n_global> — " (n under $HARNESS_HOME)" when some .new files sit in the runtime.
dotnew_where() { [ "$1" -eq 0 ] || printf ' (%s under %s)' "$1" "$(harness_home)"; }

# cmd_doctor — install health. 3 severities (ok/warn/fail); exit 1 iff any FAIL.
cmd_doctor() {
  local root="$HARNESS_ROOT" pdir fails=0 warns=0
  pdir="$(progress_dir "$root")"
  emit() { # <sev> <msg>
    case "$1" in
      ok)   printf '  ok   %s\n' "$2" ;;
      warn) printf '  warn %s\n' "$2"; warns=$((warns + 1)) ;;
      fail) printf '  fail %s\n' "$2"; fails=$((fails + 1)) ;;
    esac
  }

  [ -f "$root/AGENTS.md" ] && emit ok "AGENTS.md present" || emit fail "AGENTS.md missing"
  emit ok "runtime: $(runtime_version)"
  local pver; pver="$(project_version "$root")"
  [ "$pver" = "uninitialized" ] && emit warn "project: uninitialized" \
                                || emit ok "project: $pver"
  if [ -f "$LOCK" ]; then
    emit ok "harness.lock present (v$pver)"
  elif [ -f "$root/VERSION" ] && [ -d "$root/skills" ]; then
    emit ok "source repo (VERSION $pver; no lock needed)"
  else
    emit fail "harness.lock missing in $(state_dir "$root") (run init.sh)"
  fi

  # update check (best-effort; never a FAIL) — skip silently when offline/unknown.
  local latest; latest="$(latest_version)"
  if [ -n "$latest" ]; then
    version_newer "$(installed_version)" "$latest" \
      && emit warn "harness-mini $latest available (installed $(installed_version)) — run harness.sh update" \
      || emit ok "harness-mini up to date ($(installed_version))"
  fi

  # Installed projects read their persisted skill targets (state_dir/targets,
  # default .agents/skills); a source checkout falls back to its own skills/.
  local skill_dirs skill_label="" d
  skill_dirs="$(existing_skill_dirs "$root")"
  if [ -z "$skill_dirs" ] && [ -d "$root/skills" ]; then skill_dirs="skills"; fi
  local skill_total; skill_total="$(shared_skill_count "$root")"
  if [ -n "$skill_dirs" ]; then
    local nfolders=0 nflat=0
    for d in $skill_dirs; do
      skill_label="${skill_label:+$skill_label, }$d"
      nfolders=$((nfolders + $(find "$root/$d" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')))
      nflat=$((nflat + $(find "$root/$d" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')))
    done
    emit ok "$skill_total shared skills in $skill_label"
    [ "$nfolders" -gt 0 ] && emit ok "$nfolders skills in <name>/SKILL.md shape" \
                          || emit fail "$skill_label has no <name>/SKILL.md"
    [ "$nflat" -gt 0 ] && emit warn "$nflat flat .md skill(s) in $skill_label (old shape)"
  else
    # init installs no skills (it cannot know the host): a normal first state.
    emit warn "skills not installed — run harness.sh agent list, then agent install <host>"
  fi

  # The manifest describes the installed shared skills, so it is only checked
  # once they exist.
  local mf; mf="$(manifest_file "$root")"
  if [ -z "$(existing_skill_dirs "$root")" ]; then
    :
  elif [ -f "$mf" ]; then
    if grep -q '^## Skills (' "$mf"; then
      local listed missing missing_count
      listed="$(manifest_skill_entries "$mf" | wc -l | tr -d ' ')"
      missing="$(missing_manifest_skills "$root")"
      missing_count="$(printf '%s\n' "$missing" | awk 'NF {n++} END {print n+0}')"
      if [ "$listed" -eq 0 ]; then
        emit warn "manifest lists no shared skills"
      elif [ "$missing_count" -eq 0 ]; then
        emit ok "manifest healthy ($listed listed, 0 missing)"
      else
        emit fail "manifest missing $missing_count skill(s): $(printf '%s' "$missing" | tr '\n' ', ' | sed 's/, $//')"
      fi
    else
      emit warn "manifest.md has no skills section"
    fi
  else
    emit warn "manifest.md missing in $(state_dir "$root")"
  fi

  ls "$pdir"/docs/exec-plans/active/*.md >/dev/null 2>&1 \
    && emit ok "active exec-plan present" || emit warn "no active exec-plan"

  # dual-file twins: each active MD plan should carry a same-basename .json
  # workboard (WARN only, never FAIL — the MD stays the lifecycle authority and
  # status degrades gracefully to MD-only without the twin).
  local pf2 twin2 wb2 wpid2 wst2
  for pf2 in "$pdir"/docs/exec-plans/active/*.md; do
    [ -f "$pf2" ] || continue
    twin2="${pf2%.md}.json"
    if [ ! -f "$twin2" ]; then
      emit warn "$(basename "$pf2" .md): no JSON twin — workboard blind ($(harness_home)/docs/templates/full-plan.md)"
    else
      # "Readable" = same bar status applies: plan_id seen AND a status value.
      wb2="$(json_wb "$twin2")"
      wpid2="$(printf '%s' "$wb2" | awk -F'|' '{print $6}')"
      wst2="$(printf '%s' "$wb2" | awk -F'|' '{print $1}')"
      { [ "$wpid2" = "1" ] && [ -n "$wst2" ]; } \
        || emit warn "$(basename "$pf2" .md): JSON twin unparseable — fix fields or delete it"
    fi
  done

  { [ -f "$pdir/.gitignore" ] && grep -qx 'trace/runtime/' "$pdir/.gitignore"; } \
    && emit ok ".harness-mini trace/runtime gitignored" || emit warn ".harness-mini trace/runtime not gitignored (add trace/runtime/ to .harness-mini/.gitignore)"

  local nnew nglob; nnew="$(count_dotnew "$root")"; nglob="$(count_dotnew_home)"
  [ $((nnew + nglob)) -eq 0 ] && emit ok "no unresolved .new files" \
                    || emit warn "$((nnew + nglob)) unresolved .new file(s) from update$(dotnew_where "$nglob") — resolve & delete"

  if [ -f "$root/VERSION" ] && [ -f "$LOCK" ]; then
    local fv lv; fv="$(read_version "$root/VERSION")"; lv="$(installed_version)"
    [ "$fv" = "$lv" ] && emit ok "VERSION matches lock ($lv)" \
                      || emit warn "VERSION ($fv) != lock ($lv)"
  fi

  # source<->installed drift: only a source checkout (skills/ + agents/ at the
  # root) that persisted install targets has anything to compare; an installed
  # project, or a checkout with no `agent install`, skips this check.
  local drift; drift="$(installed_drift "$root")"
  if [ -n "$drift" ]; then
    emit warn "installed copy differs from source ($(printf '%s' "$drift" | wc -l | tr -d ' ') file(s), e.g. $(printf '%s' "$drift" | head -n1)) — re-run harness.sh agent install <host>"
  elif [ -s "$(state_dir "$root")/targets" ] && [ -d "$root/skills" ]; then
    emit ok "installed skills/roles match source"
  fi

  # eval-gate (anti-self-praise teeth): an active plan that reached `done` must
  # have a passing evaluation on record (.harness-mini/trace/evals/<plan>-*.md, verdict: pass).
  # Scoped to active/ so legacy completed/ plans are never retroactively failed.
  local pf stg plan r rec
  for pf in "$pdir"/docs/exec-plans/active/*.md; do
    [ -f "$pf" ] || continue
    stg="$(awk -F': *' '/^stage:/{print $2; exit}' "$pf")"
    [ "$stg" = "done" ] || continue
    plan="$(awk -F': *' '/^plan:/{print $2; exit}' "$pf")"
    [ -z "$plan" ] && plan="$(basename "$pf" .md)"
    rec=""
    for r in "$pdir"/trace/evals/"$plan"-*.md; do
      [ -f "$r" ] && grep -q '^verdict: pass' "$r" && { rec="$r"; break; }
    done
    [ -n "$rec" ] && emit ok "$plan done: evaluation on record" \
                  || emit fail "$plan marked done with no passing evaluation — anti-self-praise gate"
  done

  if [ "$fails" -eq 0 ]; then
    printf 'doctor: healthy (%s warning(s))\n' "$warns"
  else
    printf 'doctor: %s problem(s), %s warning(s)\n' "$fails" "$warns"
  fi
  [ "$fails" -eq 0 ]
}

# cmd_status — current work state for cold resume. grep/awk/tail only; always 0.
# Ends with a single readiness verdict (OpenHarness dry-run idea, Mini-shaped):
#   ready: <ready|warning|blocked> — <one next action>
cmd_status() {
  local root="$HARNESS_ROOT" pdir
  pdir="$(progress_dir "$root")"
  echo "harness-mini $(installed_version)"
  echo "runtime: $(runtime_version)"
  local pver; pver="$(project_version "$root")"
  echo "project: $pver"
  local nskills; nskills="$(shared_skill_count "$root")"
  echo "shared skills: $nskills"
  local manifest_missing="" manifest_count=0 mf
  mf="$(manifest_file "$root")"
  if [ -z "$(existing_skill_dirs "$root")" ]; then
    echo "manifest: skills not installed"
  elif [ -f "$mf" ] && grep -q '^## Skills (' "$mf"; then
    manifest_missing="$(missing_manifest_skills "$root")"
    manifest_count="$(manifest_skill_entries "$mf" | wc -l | tr -d ' ')"
    if [ "$manifest_count" -eq 0 ]; then
      echo "manifest: no shared skills listed"
    elif [ -z "$manifest_missing" ]; then
      echo "manifest healthy: $manifest_count listed, 0 missing"
    else
      echo "manifest missing skills: $(printf '%s' "$manifest_missing" | tr '\n' ', ' | sed 's/, $//')"
    fi
  else
    echo "manifest: missing .agents/skills section"
  fi

  # update check (best-effort) — remind on entry if a newer harness-mini exists.
  # Silent when offline/unknown so the cold-resume view stays fast & quiet.
  local _latest _behind=no
  _latest="$(latest_version)"
  if [ -n "$_latest" ] && version_newer "$(installed_version)" "$_latest"; then
    echo "update: $_latest available — run \`harness.sh update\`"
    _behind=yes
  fi

  local f plan stage cp nplans=0 nplans_with_cp=0 first_plan="" first_stage="" first_file=""
  local twin wb wst wcur wnxt wnp wns wpok wtot
  # session path — one machine answer to "is this session plan bootstrap or
  # incremental coding?" (discussion #55 / issue #57). Derived ONLY from file
  # truth: MD stage + JSON twin. Priority across plans (first plan wins within
  # a class): a coding-provable plan beats a planning one, because the gate's
  # question is "may this session write product code". A missing/unparseable
  # twin at a coding stage is conservative init — coding must be PROVEN.
  #   class 1 coding next slice ready      (coding stage + twin has passes:false)
  #   class 2 coding wrap-up               (coding stage + twin all green, plan open)
  #   class 3 init  twin missing|unparseable (conservative: coding unprovable)
  #   class 4 init  still planning         (intake|prd|issues, or twin w/o slices)
  local p_class=9 p_reason="empty board" pc pr
  if ls "$pdir"/docs/exec-plans/active/*.md >/dev/null 2>&1; then
    echo "active plans:"
    for f in "$pdir"/docs/exec-plans/active/*.md; do
      [ -f "$f" ] || continue
      plan="$(awk -F': *' '/^plan:/{print $2; exit}' "$f")"
      stage="$(awk -F': *' '/^stage:/{print $2; exit}' "$f")"
      [ -z "$plan" ] && plan="$(basename "$f" .md)"
      printf '  %-24s stage: %s\n' "$plan" "${stage:-?}"
      cp="$(ls "$pdir"/trace/checkpoints/"$plan"-*.md 2>/dev/null | sort | tail -n1)"
      [ -n "$cp" ] && printf '     last checkpoint: %s\n' "$(basename "$cp" .md)"
      # JSON twin -> one workboard line (the "what to do next" a cold session
      # reads first). Absent or unreadable twin: silently degrade to MD-only.
      twin="${f%.md}.json"
      if [ -f "$twin" ]; then
        wb="$(json_wb "$twin")"
        IFS='|' read -r wst wcur wnxt wnp wns wpok <<< "$wb"
        if [ "$wpok" = "1" ] && [ -n "$wst" ]; then
          wtot=$((wnp + wns))
          if [ "$wtot" -gt 0 ]; then
            printf '     workboard: %s · %s/%s pass · current: %s · next: %s\n' \
              "$wst" "$wnp" "$wtot" "${wcur:--}" "${wnxt:-all green}"
          else
            printf '     workboard: %s · no slices yet\n' "$wst"
          fi
        fi
      fi
      # classify this plan for the session path
      case "$stage" in
        implement|evaluate|checkpoint)
          if [ ! -f "$twin" ]; then pc=3; pr="twin missing"
          else
            wb="$(json_wb "$twin")"
            IFS='|' read -r wst wcur wnxt wnp wns wpok <<< "$wb"
            if [ "$wpok" = "1" ] && [ -n "$wst" ]; then
              if [ "$wns" -gt 0 ]; then pc=1; pr="next slice ready"
              elif [ "$wnp" -gt 0 ]; then pc=2; pr="wrap-up"
              else pc=4; pr="still planning"    # twin has no slices yet
              fi
            else pc=3; pr="twin unparseable"; fi
          fi ;;
        intake|prd|issues) pc=4; pr="still planning" ;;
        *) pc=4; pr="still planning" ;;   # unknown stage: coding unprovable
      esac
      if [ "$pc" -lt "$p_class" ]; then p_class="$pc"; p_reason="$pr"; fi
      nplans=$((nplans + 1))
      [ -n "$cp" ] && nplans_with_cp=$((nplans_with_cp + 1))
      if [ -z "$first_plan" ]; then
        first_plan="$plan"; first_stage="${stage:-?}"; first_file="$f"
      fi
    done
  else
    echo "active plans: none"
  fi

  # session path verdict — the line gate v2 and the session-* skills branch on
  local p_path=init; [ "$p_class" -le 2 ] && p_path=coding
  printf 'path: %s\n' "$p_path"
  printf 'path_reason: %s\n' "$p_reason"

  local nnew nglob; nnew="$(count_dotnew "$root")"; nglob="$(count_dotnew_home)"
  nnew=$((nnew + nglob))
  echo "update conflicts: $nnew .new file(s)$(dotnew_where "$nglob")"

  local newest last cpct ev run
  newest="$(ls -t "$pdir"/trace/runtime/*.jsonl 2>/dev/null | head -n1)"
  if [ -n "$newest" ]; then
    last="$(tail -n1 "$newest" 2>/dev/null)"
    cpct="$(printf '%s' "$last" | sed -n 's/.*"ctx_pct":\([0-9][0-9]*\).*/\1/p')"
    ev="$(printf '%s' "$last" | sed -n 's/.*"event":"\([^"]*\)".*/\1/p')"
    run="$(printf '%s' "$last" | sed -n 's/.*"run":"\([^"]*\)".*/\1/p')"
    printf 'last trace: ctx_pct=%s event=%s (%s)\n' "${cpct:-?}" "${ev:-?}" "${run:-?}"
  else
    echo "last trace: none"
  fi

  # garden trigger — cadence (committed checkpoints since the last sweep) + the
  # smell backlog. grep/ls/sed only, like the rest of status. DUE iff there are
  # >= HARNESS_GARDEN_EVERY (default 5) checkpoints since last garden, OR any
  # high-severity open item, OR >= 3 open items in .harness-mini/trace/garden-backlog.md.
  local bl="$pdir/trace/garden-backlog.md" total gat since open high gdue
  total=$(ls "$pdir"/trace/checkpoints/*.md 2>/dev/null | wc -l | tr -d ' ')
  gat=0; open=0; high=0
  if [ -f "$bl" ]; then
    gat=$(sed -n 's/.*gardened-at: *\([0-9][0-9]*\).*/\1/p' "$bl" | head -n1)
    [ -z "$gat" ] && gat=0
    open=$(grep -Ec '^- \[ \]' "$bl" 2>/dev/null); [ -z "$open" ] && open=0
    high=$(grep -Ec '^- \[ \].*\| *high *\|' "$bl" 2>/dev/null); [ -z "$high" ] && high=0
  fi
  since=$((total - gat)); [ "$since" -lt 0 ] && since=0
  if [ "$since" -ge "${HARNESS_GARDEN_EVERY:-5}" ] || [ "$high" -gt 0 ] || [ "$open" -ge 3 ]; then
    gdue=DUE
  else
    gdue=ok
  fi
  printf 'garden: %s (%s checkpoint(s) since last; %s backlog item(s))\n' "$gdue" "$since" "$open"

  # resumable — plan-scoped: only checkpoints matching an active plan's slug count
  local resume=no
  if [ "$nplans" -eq 0 ]; then
    echo "resumable: no (no active plan)"
    resume=no
  elif [ "$nplans_with_cp" -eq "$nplans" ]; then
    echo "resumable: yes (active plan + checkpoint)"
    resume=yes
  else
    echo "resumable: partial (plan, no checkpoint yet)"
    resume=partial
  fi

  # readiness verdict — one line; blocked > warning > ready (grill #1 → A)
  local level=ready next="" done_plan="" r

  if [ ! -f "$root/AGENTS.md" ]; then
    level=blocked; next="restore AGENTS.md (re-run init.sh)"
  elif [ -n "$manifest_missing" ]; then
    level=blocked; next="restore missing shared skill(s) listed in the project manifest"
  elif [ "$nskills" -eq 0 ]; then
    level=blocked; next="install skills: harness.sh agent list, then agent install <host>"
  else
    for f in "$pdir"/docs/exec-plans/active/*.md; do
      [ -f "$f" ] || continue
      stage="$(awk -F': *' '/^stage:/{print $2; exit}' "$f")"
      [ "$stage" = "done" ] || continue
      plan="$(awk -F': *' '/^plan:/{print $2; exit}' "$f")"
      [ -z "$plan" ] && plan="$(basename "$f" .md)"
      local evf has_pass=no
      for evf in "$pdir"/trace/evals/"$plan"-*.md; do
        [ -f "$evf" ] && grep -q '^verdict: pass' "$evf" && { has_pass=yes; break; }
      done
      if [ "$has_pass" != "yes" ]; then
        level=blocked
        done_plan="$plan"
        next="run evaluate for $plan (anti-self-praise gate)"
        break
      fi
    done
  fi

  if [ "$level" != "blocked" ]; then
    if [ "$nplans" -eq 0 ]; then
      level=warning; next="open a plan ($(harness_home)/docs/templates/quick-plan.md or full-plan.md)"
    elif [ "$nnew" -gt 0 ]; then
      level=warning; next="resolve $nnew .new file(s) from update"
    elif [ "$gdue" = "DUE" ]; then
      level=warning; next="dispatch gardener (garden: DUE)"
    elif [ "$_behind" = "yes" ]; then
      level=warning; next="run harness.sh update ($_latest available)"
    elif [ "$resume" = "partial" ]; then
      level=warning; next="write a checkpoint for $first_plan before continuing"
    else
      # ready — prefer the plan's ## Now first bullet
      next="$(awk '
        /^## Now/ { in_now=1; next }
        in_now && /^## / { exit }
        in_now && /^[[:space:]]*-[[:space:]]+/ {
          sub(/^[[:space:]]*-[[:space:]]+/, ""); print; exit
        }
      ' "$first_file" 2>/dev/null)"
      [ -n "$next" ] || next="continue $first_plan at stage $first_stage"
    fi
  fi

  printf 'ready: %s — %s\n' "$level" "$next"
  return 0
}

# cmd_report [run] — aggregate .harness-mini/trace into a metrics summary so thresholds are
# tuned by data, not vibes. grep/awk/sed/ls only; always exits 0. No arg = all
# runs; <run> scopes the runtime trace to one run id.
cmd_report() {
  local root="$HARNESS_ROOT" run="${1:-}" thr="${HARNESS_CTX_THRESHOLD:-40}" pdir
  pdir="$(progress_dir "$root")"
  local rt="$pdir/trace/runtime" glob files="" f
  if [ -n "$run" ]; then
    echo "harness-mini report — run $run"
    glob="$rt/$run.jsonl"
  else
    echo "harness-mini report (all runs)"
    glob="$rt/*.jsonl"
  fi
  for f in $glob; do [ -f "$f" ] && files="$files $f"; done

  # stage advances (+ the last stage reached)
  local advances=0 last=""
  if [ -n "$files" ]; then
    advances=$(grep -h '"event":"stage_advance"' $files 2>/dev/null | wc -l | tr -d ' ')
    last=$(grep -h '"event":"stage_advance"' $files 2>/dev/null | tail -n1 \
           | sed -n 's/.*"stage":"\([^"]*\)".*/\1/p')
  fi
  printf 'stage advances: %s (last: %s)\n' "$advances" "${last:-none}"

  # context occupancy trend vs the 40% line
  local samples=""
  [ -n "$files" ] && samples=$(grep -ho '"ctx_pct":[0-9]*' $files 2>/dev/null | sed 's/.*://')
  if [ -n "$samples" ]; then
    local cnt nmax over
    cnt=$(printf '%s\n' "$samples" | grep -c .)
    nmax=$(printf '%s\n' "$samples" | sort -n | tail -n1)
    over=$(printf '%s\n' "$samples" | awk -v t="$thr" '$1>=t{c++} END{print c+0}')
    printf 'context: %s sample(s), max %s%%, %s over %s%%\n' "$cnt" "$nmax" "$over" "$thr"
  else
    printf 'context: no ctx_pct samples (enable bin/ctx-hook.sh — ~/.harness-mini/docs/smart-dumb.md)\n'
  fi

  # evaluation outcomes from the durable records (rework loops = fails)
  local ep ef
  ep=$(grep -l '^verdict: pass' "$pdir"/trace/evals/*.md 2>/dev/null | wc -l | tr -d ' ')
  ef=$(grep -l '^verdict: fail' "$pdir"/trace/evals/*.md 2>/dev/null | wc -l | tr -d ' ')
  printf 'evaluation: %s pass / %s fail (rework loops: %s)\n' "$ep" "$ef" "$ef"

  # checkpoints written (committed institutional memory)
  local ncp
  ncp=$(ls "$pdir"/trace/checkpoints/*.md 2>/dev/null | wc -l | tr -d ' ')
  printf 'checkpoints: %s\n' "$ncp"
  return 0
}

usage() {
  cat >&2 <<'EOF'
usage: harness.sh [--root DIR] <command> [--root DIR]
  version                 show installed version (+ latest, best-effort)
  update [--src DIR] [--force]  refresh runtime + global copies + this project's skills/roles
                          (checksum-guarded; migrates a pre-0.13 layout automatically;
                          refuses to downgrade the runtime unless --force)
  diff <relpath|path>     show how your kept file differs from its upstream <file>.new
                          (e.g. diff bin/harness.sh · diff skills/tdd/SKILL.md)
  agent list|install <host>  list the hosts · install skills + role files for YOUR host
  doctor                  check install health (ok/warn/fail; exit 1 on a fail)
  status                  show work state (plans, workboard, session path, checkpoints)
  report [run]            aggregate trace metrics (stages, context, evals, checkpoints)
  release <x.y.z> [opts]  bump + tag + GitHub release (source repo only)
EOF
}

# --- dispatch ----------------------------------------------------------------
args=()
root_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] && [ -n "$2" ] || die "--root needs a directory" 64
      root_override="$2"
      shift 2
      ;;
    *) args+=("$1"); shift ;;
  esac
done
[ "${#args[@]}" -gt 0 ] || { usage; exit 64; }
set -- "${args[@]}"
if [ -n "$root_override" ]; then HARNESS_ROOT="$root_override"; fi
[ -d "$HARNESS_ROOT" ] || die "project root not found: $HARNESS_ROOT" 64
HARNESS_ROOT="$(cd "$HARNESS_ROOT" && pwd)"
LOCK="$(state_dir "$HARNESS_ROOT")/harness.lock"
sub="$1"; shift
# A 0.13.0 flat state dir moves to projects/<id> before any command reads it:
# `update` reports the move, every other command does it silently.
case "$sub" in
  -h|--help|help) ;;
  update) migrate_state_dir "$HARNESS_ROOT" || die "update: cannot move the old state dir into $(harness_home)/projects" 1 ;;
  *) migrate_state_dir "$HARNESS_ROOT" >/dev/null || true ;;
esac
case "$sub" in
  version) cmd_version "$@" ;;
  update)  cmd_update "$@" ;;
  doctor)  cmd_doctor "$@" ;;
  status)  cmd_status "$@" ;;
  agent)   cmd_agent "$@" ;;
  diff)    cmd_diff "$@" ;;
  report)  cmd_report "$@" ;;
  release) cmd_release "$@" ;;
  -h|--help|help) usage; exit 0 ;;
  *) echo "harness.sh: unknown command: $sub" >&2; usage; exit 64 ;;
esac
