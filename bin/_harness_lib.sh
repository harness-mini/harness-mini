#!/usr/bin/env bash
# _harness_lib.sh — shared helpers for the harness-mini glue scripts.
# Sourced by bin/harness.sh (the CLI) and by init.sh (the installer); never run
# directly. Holds the single source of truth for WHERE files live (project-id,
# state dir, progress dir), "what files the harness manages in a project" and how
# to checksum them, so `update` and the install-time lockfile agree.

# cksum_file <path> — print a stable checksum of a file (sha256 preferred).
cksum_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else
    cksum "$1" 2>/dev/null | awk '{print $1"-"$2}'
  fi
}

# --- layout resolver ---------------------------------------------------------
# Two classes of file (0059): harness-owned bookkeeping lives under
# $HARNESS_HOME (global) or $HARNESS_HOME/projects/<project-id> (per project); project
# progress lives in <project>/.harness-mini/. These helpers are the single
# source of truth for where each class goes.

# harness_home — the user runtime root (HARNESS_HOME override for tests).
harness_home() { printf '%s' "${HARNESS_HOME:-${HOME:?HOME must be set}/.harness-mini}"; }

# hash_hex <string> — sha256 hex of a string (cksum CRC, hex-encoded, as the
# last-resort fallback so a bare box still gets a deterministic value).
hash_hex() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf '%x' "$(printf '%s' "$1" | cksum | awk '{print $1}')"
  fi
}

# base36_tail8 <hex> — the last 8 base-36 digits of a hex number of any length.
# Long division in awk: r = (r*16 + digit) mod 36^8 keeps every step below 2^53.
base36_tail8() {
  printf '%s' "$1" | awk '
    BEGIN { m = 36 ^ 8; h = "0123456789abcdef"; d = "0123456789abcdefghijklmnopqrstuvwxyz" }
    { for (i = 1; i <= length($0); i++) r = (r * 16 + index(h, substr($0, i, 1)) - 1) % m
      for (i = 0; i < 8; i++) { s = substr(d, r % 36 + 1, 1) s; r = int(r / 36) }
      print s }'
}

# project_name <root> — lowercase-hyphenated basename, "project" if nothing safe remains.
project_name() {
  local name
  name="$(basename "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//' | cut -c1-40)"
  name="${name%-}"
  printf '%s' "${name:-project}"
}

# project_id <root> — <name>-<8 chars [0-9a-z]>, deterministic per ABSOLUTE
# (symlink-resolved) path. Moving a project changes its id (accepted trade-off).
project_id() {
  local abs
  abs="$(cd "$1" 2>/dev/null && pwd -P)" || abs="$1"
  printf '%s-%s' "$(project_name "$abs")" "$(base36_tail8 "$(hash_hex "$abs")")"
}

# state_dir <root> — per-project harness bookkeeping (lock, manifest, targets).
state_dir() { printf '%s/projects/%s' "$(harness_home)" "$(project_id "$1")"; }

# migrate_state_dir <root> — 0.13.0 kept the state dir flat at $HARNESS_HOME/<id>;
# move it to projects/<id>. Only a directory named exactly like this project's id
# that holds a harness.lock moves, and never a runtime dir name. An existing
# projects/<id> is never overwritten (both kept, one `keep` notice). Silent when
# there is nothing to move. The caller defines say().
migrate_state_dir() {
  local id old new n
  id="$(project_id "$1")"
  for n in bin docs skills agents harness projects; do [ "$id" != "$n" ] || return 0; done
  old="$(harness_home)/$id"; new="$(state_dir "$1")"
  [ -d "$old" ] && [ -f "$old/harness.lock" ] || return 0
  if [ -e "$new" ]; then
    say "keep  $old (projects/$id also exists; both kept — delete the old one yourself if unused)"
    return 0
  fi
  mkdir -p "$(dirname "$new")" && mv "$old" "$new" || return 1
  say "migr  moved state dir to projects/$id"
}

# progress_dir <root> — per-project progress that must be committed.
progress_dir() { printf '%s/.harness-mini' "$1"; }

# git_exclude_add <root> <pattern>... — list installed harness dirs in the
# project's LOCAL .git/info/exclude (never the project's .gitignore). Idempotent,
# keeps existing lines, and does nothing when <root> has no .git directory.
git_exclude_add() {
  local root="$1" file pat; shift
  [ -d "$root/.git" ] || return 0
  file="$root/.git/info/exclude"
  mkdir -p "$root/.git/info" || return 0
  [ -f "$file" ] || : > "$file"
  # a final line without a newline would glue onto our first append
  [ -z "$(tail -c1 "$file")" ] || printf '\n' >> "$file"
  for pat in "$@"; do
    grep -qxF -- "$pat" "$file" 2>/dev/null || printf '%s\n' "$pat" >> "$file"
  done
}

# --- AGENTS.md marker block --------------------------------------------------
# The ONLY thing the harness writes into a project's root AGENTS.md: one block
# between these markers. Everything outside it stays byte-identical, so the
# block can be added, re-added (no-op) and removed cleanly.
HM_BEGIN='<!-- harness-mini:begin -->'
HM_END='<!-- harness-mini:end -->'

# agents_block_text <home_ref> — the block; <home_ref> is how the runtime root
# is spelled to the agent ('$HOME/.harness-mini' unless HARNESS_HOME is custom).
agents_block_text() {
  printf '%s\n' "$HM_BEGIN" \
    '## harness-mini' \
    "This project runs on harness-mini; progress is recorded in \`.harness-mini/\`." \
    "1. First run \`\"$1/bin/harness.sh\" status\` and follow its \`path:\` line." \
    "2. Read the global map \`$1/AGENTS.md\` (routing gate, lifecycle, skills)." \
    "3. Skills missing? Run \`\"$1/bin/harness.sh\" agent list\`, then \`agent install <host>\`." \
    "$HM_END"
}

# agents_block_add <file> <home_ref> — create the file with only the block, or
# append it after existing content. The single "\n" written first either ends
# an unterminated last line or makes the blank separator line.
agents_block_add() {
  local f="$1"
  [ -f "$f" ] && grep -qxF "$HM_BEGIN" "$f" && return 0
  if [ -s "$f" ]; then printf '\n' >> "$f" || return 1; fi
  agents_block_text "$2" >> "$f"
}

# agents_block_remove <file> — remove the block (and the separator that
# agents_block_add put before it). A file left empty is deleted. A block with no
# end marker is left untouched (returns 1).
agents_block_remove() {
  local f="$1" b e total pre tmp strip=no
  [ -f "$f" ] || return 0
  set -- $(awk -v b="$HM_BEGIN" -v e="$HM_END" '
    !bl && $0 == b { bl = NR; next }
    bl && !el && $0 == e { el = NR }
    END { if (bl) print bl, el + 0 }' "$f")
  b="${1:-}"; e="${2:-0}"
  [ -n "$b" ] || return 0
  [ "$e" -gt 0 ] || return 1
  total="$(awk 'END { print NR }' "$f")"
  pre=$((b - 1))
  if [ "$pre" -ge 1 ]; then
    if [ -z "$(sed -n "${pre}p" "$f")" ]; then pre=$((pre - 1))        # blank separator
    elif [ "$e" -eq "$total" ]; then strip=yes; fi                      # unterminated original
  fi
  tmp="$(mktemp)" || return 1
  { [ "$pre" -ge 1 ] && head -n "$pre" "$f"; [ "$e" -lt "$total" ] && tail -n +"$((e + 1))" "$f"; true; } > "$tmp"
  [ "$strip" = yes ] && printf '%s' "$(cat "$tmp")" > "$tmp.s" && mv "$tmp.s" "$tmp"
  if [ -s "$tmp" ]; then cat "$tmp" > "$f"; else rm -f "$f"; fi
  rm -f "$tmp"
}

# --- host table ---------------------------------------------------------------
# The ONE place that knows where each coding-agent host reads skills and role
# files (researched from official docs, see .harness-mini/docs/exec-plans/active/0059-*.md).

HOST_IDS="antigravity codex cursor claude qoder zcode kimi deepseek pi opencode grok copilot mimo trae codebuddy muse hermes"

# host_row <id-or-alias> — print "<id>|<skills dir>|<agents dir>|<format>|<note>"
# as one TAB-separated row, or return 1 for an unrecognised host. format is
# md | toml | agent.md | none (none = unsupported: the host installs itself).
host_row() {
  local id r
  id="$(printf '%s' "$1" | LC_ALL=C tr 'A-Z_ ' 'a-z--')"
  case "$id" in
    antigravity)                    r='antigravity|.agents/skills|.agents/agents|md|high' ;;
    codex|codex-cli)                r='codex|.agents/skills|.codex/agents|toml|high' ;;
    cursor)                         r='cursor|.cursor/skills|.cursor/agents|md|high' ;;
    claude|claude-code)             r='claude|.claude/skills|.claude/agents|md|high' ;;
    qoder)                          r='qoder|.qoder/skills|.qoder/agents|md|high agents; skills dir low' ;;
    zcode|z-code)                   r='zcode|.zcode/skills|.zcode/agents|md|medium (project dirs not in official docs)' ;;
    kimi)                           r='kimi|.agents/skills|.agents/agents|md|high' ;;
    deepseek|deepseek-harness|dsh)  r='deepseek|.agents/skills|.dsh/agents|md|low (third-party plugin convention)' ;;
    pi)                             r='pi|.agents/skills|.pi/agents|md|medium (extension convention)' ;;
    opencode)                       r='opencode|.agents/skills|.opencode/agents|md|high' ;;
    grok)                           r='grok|.agents/skills|.grok/agents|md|high' ;;
    copilot|github-copilot)         r='copilot|.agents/skills|.github/agents|agent.md|high' ;;
    mimo|mimo-code|mimocode)        r='mimo|.agents/skills|.mimocode/agents|md|high' ;;
    trae)                           r='trae|.trae/skills|.trae/agents|md|high (beta toggles)' ;;
    codebuddy)                      r='codebuddy|.codebuddy/skills|.codebuddy/agents|md|high' ;;
    muse)                           r='muse|-|-|none|unsupported: agents are spawned dynamically; self-install' ;;
    hermes)                         r='hermes|-|-|none|unsupported: profiles, no project dirs; self-install' ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$r" | tr '|' '\t'
}

# --- install targets ---------------------------------------------------------
# A project's targets are rows "<host>\t<skills dir>\t<agents dir>\t<format>",
# persisted one per installed host in <state_dir>/targets. Without that file the
# default row applies; its format `copy` installs role files verbatim.
DEFAULT_TARGET_ROW="$(printf 'default\t.agents/skills\t.agents/agents\tcopy')"

# targets_text <root> — the project's target rows (persisted, else the default).
targets_text() {
  local f; f="$(state_dir "$1")/targets"
  if [ -s "$f" ]; then cat "$f"; else printf '%s\n' "$DEFAULT_TARGET_ROW"; fi
}

# target_skill_dirs / target_agent_dirs <root> — unique relative target dirs.
target_skill_dirs() { targets_text "$1" | awk -F'\t' '!s[$2]++ { print $2 }'; }
target_agent_dirs() { targets_text "$1" | awk -F'\t' '!s[$3]++ { print $3 }'; }

# existing_skill_dirs <root> — the skill targets that exist on disk.
existing_skill_dirs() {
  local d
  for d in $(target_skill_dirs "$1"); do [ -d "$1/$d" ] && printf '%s\n' "$d"; done
  return 0
}

# find_installed_skill <root> <name> — path of the first installed
# <name>/SKILL.md at a persisted target, else the source checkout's skills/.
find_installed_skill() {
  local d
  for d in $(target_skill_dirs "$1") skills; do
    [ -f "$1/$d/$2/SKILL.md" ] && { printf '%s' "$1/$d/$2/SKILL.md"; return 0; }
  done
  return 1
}

# targets_add <state_dir> <row> — record a host row, replacing an earlier row of
# the same host (idempotent; other hosts keep their rows).
targets_add() {
  local f="$1/targets" row="$2" host tmp
  host="${row%%$(printf '\t')*}"
  mkdir -p "$1" || return 1
  tmp="$(mktemp)" || return 1
  { [ -f "$f" ] && awk -F'\t' -v h="$host" '$1 != h' "$f"; printf '%s\n' "$row"; } > "$tmp"
  cat "$tmp" > "$f"; rm -f "$tmp"
}

# --- role files ---------------------------------------------------------------
# Role (agent) files are installed per host format: md as-is, `<name>.agent.md`
# for Copilot, TOML for Codex. Pure shell + awk.

# fm_value <md> <key> — a YAML frontmatter value (surrounding quotes dropped).
fm_value() {
  awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, k ":") == 1 {
      sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t\r]+$/, "")
      q = substr($0, 1, 1)
      if (length($0) > 1 && (q == "\"" || q == sq) && q == substr($0, length($0)))
        $0 = substr($0, 2, length($0) - 2)
      print; exit
    }' sq="'" "$1"
}

# role_body <md> — everything after the frontmatter, leading blank lines dropped.
role_body() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }
    !started && $0 == "" { next }
    { started = 1; print }' "$1"
}

# quote_escape <string> — escape backslash and double quote for a "..." string.
quote_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# role_target_name <format> <basename.md> — the installed file name.
role_target_name() {
  case "$1" in
    toml)     printf '%s.toml' "${2%.md}" ;;
    agent.md) printf '%s.agent.md' "${2%.md}" ;;
    *)        printf '%s' "$2" ;;
  esac
}

# role_needs_render <format> <md> — does the installed copy differ from the source?
role_needs_render() {
  case "$1" in
    copy) return 1 ;;
    toml) return 0 ;;
  esac
  [ -n "$(fm_value "$2" name)" ] && [ -n "$(fm_value "$2" description)" ] && return 1
  return 0
}

# render_role <format> <md> — print the installed form of a role file.
render_role() {
  local fmt="$1" src="$2" name desc hn=0 hd=0
  name="$(fm_value "$src" name)"; [ -n "$name" ] && hn=1 || name="$(basename "$src" .md)"
  desc="$(fm_value "$src" description)"; [ -n "$desc" ] && hd=1 || desc="harness-mini role: $name"
  if [ "$fmt" = toml ]; then
    printf 'name = "%s"\ndescription = "%s"\n' "$(quote_escape "$name")" "$(quote_escape "$desc")"
    if role_body "$src" | grep -qF "'''"; then       # a literal string cannot hold '''
      printf 'developer_instructions = """\n'
      role_body "$src" | sed 's/\\/\\\\/g; s/"""/""\\"/g'
      printf '"""\n'
    else
      printf "developer_instructions = '''\n"
      role_body "$src"
      printf "'''\n"
    fi
  elif [ "$(head -n1 "$src")" = "---" ]; then        # inject only what is missing
    awk -v n="$name" -v d="$(quote_escape "$desc")" -v hn="$hn" -v hd="$hd" '
      NR == 1 { print; if (hn != 1) print "name: " n; if (hd != 1) print "description: \"" d "\""; next }
      { print }' "$src"
  else
    printf -- '---\nname: %s\ndescription: "%s"\n---\n' "$name" "$(quote_escape "$desc")"
    cat "$src"
  fi
}

# --- managed set --------------------------------------------------------------

# emit_skill_pairs <src_root> <skills_target> — "<src><TAB><rel>" per skill file.
emit_skill_pairs() {
  local s="$1" st="$2" f tab; tab="$(printf '\t')"
  [ -d "$s/skills" ] || return 0
  find "$s/skills" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s%s%s/%s\n' "$f" "$tab" "$st" "${f#"$s"/skills/}"
  done
}

# emit_role_pairs <src_root> <agents_target> <format> — same for role files.
# A role whose installed form differs from the source is rendered into
# $HM_STAGE (caller-owned scratch dir) and the pair points at the rendered file,
# so lock, update and install all checksum and copy the INSTALLED bytes.
emit_role_pairs() {
  local f rel tab; tab="$(printf '\t')"
  for f in "$1"/agents/*.md; do
    [ -e "$f" ] || continue
    rel="$2/$(role_target_name "$3" "$(basename "$f")")"
    if role_needs_render "$3" "$f"; then
      : "${HM_STAGE:?emit_managed_pairs needs HM_STAGE (a scratch dir) to render role files}"
      mkdir -p "$(dirname "$HM_STAGE/$rel")" && render_role "$3" "$f" > "$HM_STAGE/$rel" || return 1
      printf '%s%s%s\n' "$HM_STAGE/$rel" "$tab" "$rel"
    else
      printf '%s%s%s\n' "$f" "$tab" "$rel"
    fi
  done
}

# emit_managed_pairs <src_root> [target_rows] — print what an agent install
# places in a project as "<src_abs><TAB><target_relpath>" for every target row
# (default row when omitted). Skills recurse (nested resources share the managed
# path). Nothing else is managed: docs, map and executables live in $HARNESS_HOME.
emit_managed_pairs() {
  local s="$1" rows="${2:-$DEFAULT_TARGET_ROW}" tab; tab="$(printf '\t')"
  printf '%s\n' "$rows" | while IFS="$tab" read -r _ st at fmt; do
    emit_skill_pairs "$s" "$st"
    emit_role_pairs "$s" "$at" "$fmt"
  done | awk -F'\t' '!seen[$2]++'
}

# managed_root_of <relpath> [target_rows] — which install root (a skills or
# agents target dir) a managed relpath belongs to.
managed_root_of() {
  local rel="$1" rows="${2:-$DEFAULT_TARGET_ROW}" d
  for d in $(printf '%s\n' "$rows" | awk -F'\t' '{ print $2; print $3 }'); do
    case "$rel" in "$d"/*) printf '%s' "$d"; return 0 ;; esac
  done
}

# installed_drift <root> — in a source checkout, list the managed target files
# (per the persisted targets) that exist but differ from what an install would
# write, or are missing from an existing target dir. Silent otherwise.
installed_drift() {
  local root="$1" rows stage s rel
  [ -s "$(state_dir "$root")/targets" ] || return 0
  rows="$(targets_text "$root")"
  stage="$(mktemp -d)" || return 0
  HM_STAGE="$stage" emit_managed_pairs "$root" "$rows" | while IFS="$(printf '\t')" read -r s rel; do
    [ -d "$root/$(managed_root_of "$rel" "$rows")" ] || continue
    cmp -s "$s" "$root/$rel" 2>/dev/null || printf '%s\n' "$rel"
  done
  rm -rf "$stage"
}

# write_manifest <src_root> <state_dir> [target_rows] — (re)write
# <state_dir>/manifest.md: the skills/roles an agent install places, listed
# relative to the real target dirs.
write_manifest() {
  local src="$1" state="$2" rows="${3:-$DEFAULT_TARGET_ROW}" sd ad home
  home="$(harness_home)"
  # (the `d`/`m` loop variables below live in subshells)
  sd="$(printf '%s\n' "$rows" | awk -F'\t' '!s[$2]++ { printf "%s%s/", sep, $2; sep = " " }')"
  ad="$(printf '%s\n' "$rows" | awk -F'\t' '!s[$3]++ { printf "%s%s/", sep, $3; sep = " " }')"
  mkdir -p "$state" || return 1
  {
    echo "# harness-mini manifest"
    echo
    echo "Skills and role descriptions are installed per host by \`harness.sh agent install <host>\`"
    echo "(default shared dirs: .agents/skills/ and .agents/agents/; sources: $home/skills, $home/agents)."
    echo "Any coding agent that can read the repo should open the paths below."
    echo
    echo "## Skills ($sd)"
    ( cd "$src/skills" 2>/dev/null && {
        for d in */; do [ -f "${d}SKILL.md" ] && printf -- '- %sSKILL.md\n' "$d"; done
        for m in *.md; do [ -f "$m" ] && printf -- '- %s\n' "$m"; done
      } )
    echo
    echo "## Role descriptions ($ad)"
    ( cd "$src/agents" 2>/dev/null && ls *.md 2>/dev/null ) | sed 's/^/- /'
    echo
    echo "## Map: $home/AGENTS.md   Architecture: .harness-mini/architecture.md"
  } > "$state/manifest.md"
}

# write_runtime_lock <src_root> <runtime_root> <version> — checksum the
# centralized executable set independently from each project's file lock.
write_runtime_lock() {
  local src="$1" runtime="$2" ver="$3" f out="$2/harness/runtime.lock"
  mkdir -p "$runtime/harness" || return 1
  {
    printf 'version: %s\n' "$ver"
    for f in "$src"/bin/*; do
      [ -f "$f" ] || continue
      printf '%s  bin/%s\n' "$(cksum_file "$f")" "$(basename "$f")"
    done
  } > "$out"
}

# sync_runtime <src_root> <runtime_root> <version> <log_file> [running_script]
# Install or refresh <runtime_root>/{bin/*, VERSION, harness/runtime.lock} from a
# source tree, checksum-guarded (base = runtime.lock baseline, cur = on disk,
# new = source). With no lock at all it is a bootstrap: missing files are added and
# any existing differing file is kept with a .new sibling. One "runtime <verb> ..."
# line per action goes to <log_file>. A file that IS the running script is not
# swapped (bash reads scripts lazily): its pair is left in RUNTIME_DEFER_SRC/DST for
# the caller to copy last. Returns 2 (writing nothing) when the source has no
# bin/harness.sh, i.e. it cannot yield a working runtime.
RUNTIME_DEFER_SRC=""; RUNTIME_DEFER_DST=""
sync_runtime() {
  local src="$1" rt="$2" version="$3" log="$4" self="${5:-}" lock="$2/harness/runtime.lock"
  local s name target new base current
  RUNTIME_DEFER_SRC=""; RUNTIME_DEFER_DST=""
  [ -f "$src/bin/harness.sh" ] || return 2
  for s in "$src"/bin/*; do
    [ -f "$s" ] || continue
    name="$(basename "$s")"; target="$rt/bin/$name"
    new="$(cksum_file "$s")"; base="$(lock_sha "$lock" "bin/$name")"
    if [ -f "$target" ]; then current="$(cksum_file "$target")"; else current=""; fi
    if [ "$new" = "$current" ]; then
      continue
    elif [ ! -e "$target" ]; then
      { mkdir -p "$rt/bin" && cp "$s" "$target"; } || return 1
      chmod +x "$target" 2>/dev/null || true
      printf 'runtime add bin/%s\n' "$name" >> "$log"
    elif [ -n "$base" ] && [ "$current" = "$base" ]; then
      if [ -n "$self" ] && [ "$target" -ef "$self" ]; then
        RUNTIME_DEFER_SRC="$s"; RUNTIME_DEFER_DST="$target"
      else
        cp "$s" "$target" || return 1
      fi
      printf 'runtime update bin/%s\n' "$name" >> "$log"
    elif [ "$new" != "$base" ] || [ ! -f "$target.new" ]; then
      cp "$s" "$target.new" || return 1
      printf 'runtime keep bin/%s (edited) -> wrote bin/%s.new\n' "$name" "$name" >> "$log"
    else
      printf 'runtime keep bin/%s (already flagged)\n' "$name" >> "$log"
    fi
  done
  [ ! -f "$src/VERSION" ] || cp "$src/VERSION" "$rt/VERSION" || return 1
  write_runtime_lock "$src" "$rt" "$version" || return 1
}

# runtime_usable <runtime_root> — can the installed runtime do what the AGENTS.md
# block tells an agent to run? It needs its lock, its lib and a harness.sh that
# answers `agent list` (a pre-0.13 runtime does not). Sets RUNTIME_WHY on failure.
RUNTIME_WHY=""
runtime_usable() {
  local rt="$1"
  RUNTIME_WHY=""
  if [ ! -f "$rt/harness/runtime.lock" ]; then RUNTIME_WHY="no harness/runtime.lock (the runtime is not installed)"
  elif [ ! -f "$rt/bin/harness.sh" ] || [ ! -f "$rt/bin/_harness_lib.sh" ]; then RUNTIME_WHY="bin/harness.sh or bin/_harness_lib.sh is missing"
  elif ! ( cd "$rt" && HARNESS_HOME="$rt" bash "$rt/bin/harness.sh" agent list ) >/dev/null 2>&1; then
    RUNTIME_WHY="bin/harness.sh does not answer \`agent list\` (an older runtime?)"
  fi
  [ -z "$RUNTIME_WHY" ]
}

# write_lock <src_root> <state_dir> <version> [target_rows] — (re)write
# <state_dir>/harness.lock: the version plus the PRISTINE upstream checksum of
# each managed file (keyed by target relpath). Pristine, not on-disk: that is
# what lets update tell "user edited this" from "upstream changed this".
write_lock() {
  local src="$1" state="$2" ver="$3" s rel stage
  mkdir -p "$state" && stage="$(mktemp -d)" || return 1
  {
    printf 'version: %s\n' "$ver"
    HM_STAGE="$stage" emit_managed_pairs "$src" "${4:-}" | while IFS="$(printf '\t')" read -r s rel; do
      printf '%s  %s\n' "$(cksum_file "$s")" "$rel"
    done
  } > "$state/harness.lock"
  rm -rf "$stage"
}

# lock_version <lockfile> — print the version recorded in a lockfile.
lock_version() { awk -F': *' '/^version:/{print $2; exit}' "$1" 2>/dev/null; }

# lock_sha <lockfile> <relpath> — print the recorded baseline checksum for a path.
lock_sha() { awk -v p="$2" '$2==p{print $1; exit}' "$1" 2>/dev/null; }

# version_newer <a> <b> — exit 0 iff semver <b> is strictly newer than <a>.
# Dependency-free numeric compare on dot-separated fields (no `sort -V`), so it
# stays portable on a bare macOS/Linux box. Tolerates a leading "v" and any
# pre-release suffix on a field. Empty operands are never "newer".
version_newer() {
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  local a="${1#v}" b="${2#v}" ai bi
  while [ -n "$a" ] || [ -n "$b" ]; do
    ai="${a%%.*}"; bi="${b%%.*}"
    ai="${ai%%[!0-9]*}"; bi="${bi%%[!0-9]*}"   # drop any non-numeric suffix
    [ -n "$ai" ] || ai=0
    [ -n "$bi" ] || bi=0
    [ "$bi" -gt "$ai" ] && return 0
    [ "$bi" -lt "$ai" ] && return 1
    case "$a" in *.*) a="${a#*.}" ;; *) a="" ;; esac
    case "$b" in *.*) b="${b#*.}" ;; *) b="" ;; esac
  done
  return 1
}

# dotnew_list_project <root> — relpaths (without the .new suffix) of the managed
# project files that have an unresolved <file>.new left by `update`, sorted. Only
# managed targets (the paths recorded in the project lock) can have one, so the
# lock is the whole search space — no tree walk, host-independent.
dotnew_list_project() {
  local root="$1" lock rel
  lock="$(state_dir "$root")/harness.lock"
  [ -f "$lock" ] || return 0
  while read -r _ rel; do
    [ -n "$rel" ] && [ -f "$root/$rel.new" ] && printf '%s\n' "$rel"
  done < <(awk '$1 != "version:"' "$lock") | LC_ALL=C sort
}

# dotnew_list_home — the same for the runtime executables and the global copies
# under $HARNESS_HOME (the paths in runtime.lock and global.lock), sorted.
dotnew_list_home() {
  local home rel f; home="$(harness_home)"
  while read -r _ rel; do
    [ -n "$rel" ] && [ -f "$home/$rel.new" ] && printf '%s\n' "$rel"
  done < <(for f in "$home/harness/runtime.lock" "$home/harness/global.lock"; do
             [ -f "$f" ] && awk '$1 != "version:"' "$f"; done) | LC_ALL=C sort
}

# count_dotnew <root> / count_dotnew_home — how many of those there are.
count_dotnew() { printf '%s' "$(dotnew_list_project "$1" | wc -l | tr -d ' ')"; }
count_dotnew_home() { printf '%s' "$(dotnew_list_home | wc -l | tr -d ' ')"; }

# dotnew_shq <word> — the word, double-quoted only when it needs quoting.
dotnew_shq() {
  case "$1" in ""|*[!A-Za-z0-9_./-]*) printf '"%s"' "$1" ;; *) printf '%s' "$1" ;; esac
}

# dotnew_diff_cmd <H|P> <relpath> <root> — the runnable line that shows how the kept
# file differs from its .new (H = under $HARNESS_HOME, P = in the project). When the
# installed harness.sh itself has a .new it may be older than the `diff` subcommand,
# so the line then uses plain diff(1), which always works.
dotnew_diff_cmd() {
  local kind="$1" rel="$2" root="$3" home ref pre="" f
  home="$(harness_home)"; ref="$(home_ref)"
  if [ -f "$home/bin/harness.sh.new" ]; then
    if [ "$kind" = H ]; then f="$home/$rel"; else f="$root/$rel"; fi
    printf 'diff -u "%s" "%s.new"' "$f" "$f"
    return 0
  fi
  [ "$ref" = '$HOME/.harness-mini' ] || pre="HARNESS_HOME=\"$home\" "
  printf '%s"%s/bin/harness.sh" diff %s' "$pre" "$ref" "$(dotnew_shq "$rel")"
  [ "$kind" != P ] || printf ' --root "%s"' "$root"
  return 0
}

# dotnew_notice <root> — ONE prominent block when any <file>.new is waiting under
# $HARNESS_HOME or in the project: which files, why, and the exact command that shows
# each difference (one line per file; one example line when there are more than 5).
# Prints nothing when there are none.
dotnew_notice() {
  local root="$1" home items tab kind rel n
  tab="$(printf '\t')"; home="$(harness_home)"
  items="$(dotnew_list_home | sed "s/^/H$tab/"; dotnew_list_project "$root" | sed "s/^/P$tab/")"
  n="$(printf '%s\n' "$items" | awk 'NF { c++ } END { print c + 0 }')"
  [ "$n" -gt 0 ] || return 0
  printf '\n!! harness-mini: %s file(s) were NOT upgraded because you edited them\n' "$n"
  printf '   Files under %s\n' "$home"
  printf '   are managed by harness-mini and should not be edited (put local needs in your\n'
  printf '   project instead). Your edited copy was kept; the new upstream version waits\n'
  printf '   next to it as <file>.new:\n'
  printf '%s\n' "$items" | while IFS="$tab" read -r kind rel; do
    [ -n "$rel" ] || continue
    if [ "$kind" = H ]; then printf '     - %s/%s.new\n' "$home" "$rel"; else printf '     - %s/%s.new\n' "$root" "$rel"; fi
  done
  printf '%s\n' "$items" | while IFS="$tab" read -r kind rel; do
    [ -n "$rel" ] || continue
    printf '   see the difference:  %s\n' "$(dotnew_diff_cmd "$kind" "$rel" "$root")"
    [ "$n" -le 5 ] || break
  done
  [ "$n" -le 5 ] || printf '   (same form for every file above: replace the path after "diff")\n'
  printf '   To take the upstream version: mv <file>.new <file>   (then nothing is left to resolve)\n\n'
}

# --- global copies under $HARNESS_HOME ----------------------------------------
# The map, static docs, lifecycle ARCHITECTURE.md, skills and agents the runtime
# serves to every project (`agent install` copies FROM these). Their pristine
# checksums are recorded in $HARNESS_HOME/harness/global.lock so `update` can
# refresh untouched copies and protect local edits.

# emit_global_pairs <src_root> — "<src_abs><TAB><relpath under $HARNESS_HOME>".
emit_global_pairs() {
  local s="$1" d f tab; tab="$(printf '\t')"
  {
    [ -f "$s/AGENTS.md" ] && printf '%s%sAGENTS.md\n' "$s/AGENTS.md" "$tab"
    [ -f "$s/ARCHITECTURE.md" ] && printf '%s%sdocs/ARCHITECTURE.md\n' "$s/ARCHITECTURE.md" "$tab"
    for d in docs skills agents; do
      [ -d "$s/$d" ] || continue
      find "$s/$d" -type f | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s%s%s/%s\n' "$f" "$tab" "$d" "${f#"$s/$d/"}"
      done
    done
  } | awk -F'\t' '!seen[$2]++'
}

# sync_globals <src_root> <add|refresh> — place the global copies, printing one
# "<verb> <relpath…>" line per action (add | update | keep).
#   add     (init)   only creates missing files; never touches an existing one.
#   refresh (update) base = recorded baseline, cur = on disk, new = upstream:
#                    cur == new -> unchanged;  cur == base -> overwrite;
#                    otherwise  -> keep the local edit, write <file>.new.
sync_globals() {
  local src="$1" mode="$2" home lock upd tmp ver tab; tab="$(printf '\t')"
  home="$(harness_home)"; lock="$home/harness/global.lock"
  ver="$(tr -d ' \t\r\n' < "$src/VERSION" 2>/dev/null)"; : "${ver:=unknown}"
  [ "$mode" = refresh ] || [ ! -f "$lock" ] || ver="$(lock_version "$lock")"
  mkdir -p "$home/harness" && upd="$(mktemp)" || return 1
  emit_global_pairs "$src" | while IFS="$tab" read -r s rel; do
    dst="$home/$rel"; new="$(cksum_file "$s")"; base="$(lock_sha "$lock" "$rel")"
    if [ ! -e "$dst" ]; then
      mkdir -p "$(dirname "$dst")" && cp "$s" "$dst" || continue
      printf 'add %s\n' "$rel"
    else
      cur="$(cksum_file "$dst")"
      if [ "$new" = "$cur" ]; then :
      elif [ "$mode" != refresh ]; then continue
      elif [ -n "$base" ] && [ "$cur" = "$base" ]; then
        cp "$s" "$dst"; printf 'update %s\n' "$rel"
      elif [ "$new" != "$base" ] || [ ! -f "$dst.new" ]; then
        cp "$s" "$dst.new"; printf 'keep %s (edited) -> wrote %s.new\n' "$rel" "$rel"
      else
        printf 'keep %s (already flagged)\n' "$rel"
      fi
    fi
    printf '%s  %s\n' "$new" "$rel" >> "$upd"
  done
  if [ -s "$upd" ] || [ ! -f "$lock" ] || [ "$ver" != "$(lock_version "$lock")" ]; then
    tmp="$(mktemp)" || { rm -f "$upd"; return 1; }
    { printf 'version: %s\n' "$ver"
      { [ -f "$lock" ] && awk -v u="$upd" '
          BEGIN { while ((getline l < u) > 0) { split(l, a); seen[a[2]] = 1 } }
          $1 != "version:" && !($2 in seen)' "$lock"
        cat "$upd"; } | LC_ALL=C sort -k2
    } > "$tmp" && mv "$tmp" "$lock"
  fi
  rm -f "$upd"
}

# lock_override <lockfile> <relpath> <sha> — replace the baseline of a path that
# is already listed (never adds a line).
lock_override() {
  local tmp; tmp="$(mktemp)" || return 1
  awk -v p="$2" -v s="$3" '$2 == p { print s "  " p; next } { print }' "$1" > "$tmp" && cat "$tmp" > "$1"
  rm -f "$tmp"
}

# progress_gitignore_ensure <root> — create .harness-mini/.gitignore (ignores the
# ephemeral traces from INSIDE; the project's own .gitignore is never edited).
# Returns 0 when it created the file, 1 when it already existed.
progress_gitignore_ensure() {
  local f; f="$(progress_dir "$1")/.gitignore"
  [ ! -f "$f" ] || return 1
  mkdir -p "$(dirname "$f")" && printf 'trace/runtime/\n' > "$f"
}

# home_ref — how the runtime root is spelled to an agent in the AGENTS.md block.
home_ref() {
  local h; h="$(harness_home)"
  if [ "$h" = "${HOME:-}/.harness-mini" ]; then printf '%s' '$HOME/.harness-mini'; else printf '%s' "$h"; fi
}

# --- legacy layout migration --------------------------------------------------
# Pre-0059 installs (the 0058 shared layout and the older .claude/ layout) put
# harness docs, executables, locks and progress files into the project tree.
# migrate_legacy_layout <root> moves the user's progress into .harness-mini/ and
# removes harness-owned files ONLY when their checksum equals the old lock
# baseline (<root>/harness/harness.lock); everything else is kept and reported.
# Callers define say(); output lines start with `migr`, `keep` or `note`.
# Idempotent; never rm -rf (directories go with rmdir, so only when empty).

LEGACY_MOVED=0; LEGACY_KEPT=0; LEGACY_SKILLS_GONE=0; LEGACY_SEEDS=""
LEGACY_NOTES=""   # "<key><TAB><text>" lines: the kept-path notices of this run

# legacy_keep <key> <text> — queue a "keep" notice (key = what was kept). Notices
# are printed once by legacy_flush_notes, and only when the kept set changed since
# the previous run, so a re-run that has nothing new to say stays quiet.
legacy_keep() {
  LEGACY_NOTES="$LEGACY_NOTES$1$(printf '\t')$2
"
}

legacy_noted() { printf '%s' "$LEGACY_NOTES" | cut -f1 | grep -qxF -- "$1"; }

# legacy_flush_notes <root> — print the queued notices (same kept set as last time:
# one summary line instead). The last printed set is remembered in the state dir.
legacy_flush_notes() {
  local f keys
  [ -n "$LEGACY_NOTES" ] || return 0
  f="$(state_dir "$1")/legacy-kept"
  keys="$(printf '%s' "$LEGACY_NOTES" | cut -f1 | LC_ALL=C sort)"
  if [ "$keys" = "$(cat "$f" 2>/dev/null)" ]; then
    say "keep  still kept, as in the earlier run: $(printf '%s' "$keys" | tr '\n' ',' | sed 's/,/, /g')"
  else
    printf '%s' "$LEGACY_NOTES" | while IFS="$(printf '\t')" read -r _ text; do say "keep  $text"; done
    mkdir -p "$(dirname "$f")" && printf '%s\n' "$keys" > "$f"
  fi
  return 0
}

# legacy_present <root> — is there any pre-0059 harness trace worth migrating?
legacy_present() {
  [ -d "$1/harness" ] || [ -d "$1/docs/exec-plans" ] || [ -d "$1/.trace" ] \
    || [ -f "$1/.cursor/rules/harness-mini.mdc" ] \
    || { [ -f "$1/CLAUDE.md" ] && grep -qE 'HARNESS_ROUTING_GATE_BEGIN|harness-mini:start' "$1/CLAUDE.md"; }
}

# legacy_refuse <root> <why> — the migration is the ONLY thing that deletes project
# files, and it must never run unless the new runtime is installed and usable: the
# AGENTS.md block would otherwise point at a harness.sh that does not exist.
legacy_refuse() {
  local home blocking rel; home="$(harness_home)"
  blocking="$(dotnew_list_home | grep '^bin/')"
  {
    echo "harness-mini: legacy files in $1 were NOT migrated — nothing was moved or removed."
    echo "  The new runtime at $home is not usable: $2."
    if [ -n "$blocking" ]; then
      echo "  Cause: you edited runtime file(s) under $home, so the upgrade kept them and wrote the upstream copy beside them:"
      printf '%s\n' "$blocking" | while IFS= read -r rel; do
        echo "    - $home/$rel.new  (blocks the upgrade of $rel)"
        echo "      see the difference:  $(dotnew_diff_cmd H "$rel" "$1")"
      done
      echo "  Resolve each .new first: mv <file>.new <file> takes the upstream version (keep local needs in your project)."
      echo "  Then run the same command again and the migration goes ahead."
    else
      echo "  Next step: get the new harness-mini (git clone https://github.com/harness-mini/harness-mini)"
      echo "  and run  bash harness-mini/init.sh \"$1\"  — it installs the runtime first, then migrates."
    fi
  } >&2
}

legacy_prune_parents() { # <root> <rel> — rmdir the now-empty parents of a removed file
  local d; d="$(dirname "$2")"
  while [ "$d" != . ] && [ "$d" != / ]; do
    rmdir "$1/$d" 2>/dev/null || break
    d="$(dirname "$d")"
  done
  return 0
}

# legacy_move_file <root> <old_rel> <new_rel> — move; an existing destination
# keeps BOTH copies (the source stays in place).
legacy_move_file() {
  local src="$1/$2" dst="$1/$3"
  { [ -f "$src" ] || [ -L "$src" ]; } || return 0
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    legacy_keep "$2" "$2 (a different copy exists at $3; both kept)"; return 0
  fi
  mkdir -p "$(dirname "$dst")" && mv "$src" "$dst" || return 1
  LEGACY_MOVED=$((LEGACY_MOVED + 1)); say "migr  moved $2 -> $3"
}

legacy_move_tree() { # <root> <old_rel> <new_rel> — file-by-file merge
  local rel
  [ -d "$1/$2" ] || return 0
  while IFS= read -r rel; do
    legacy_move_file "$1" "$2/$rel" "$3/$rel" || return 1
  done < <(cd "$1/$2" && find . \( -type f -o -type l \) | sed 's#^\./##' | LC_ALL=C sort)
  find "$1/$2" -depth -type d -empty -exec rmdir {} \; 2>/dev/null
  return 0
}

legacy_migrate_user_data() { # <root>
  local r="$1" p=.harness-mini
  legacy_move_tree "$r" docs/exec-plans/active    $p/docs/exec-plans/active    || return 1
  legacy_move_tree "$r" docs/exec-plans/completed $p/docs/exec-plans/completed || return 1
  legacy_move_tree "$r" .trace/checkpoints $p/trace/checkpoints || return 1
  legacy_move_tree "$r" .trace/evals       $p/trace/evals       || return 1
  legacy_move_tree "$r" .trace/runtime     $p/trace/runtime     || return 1
  legacy_move_file "$r" .trace/garden-backlog.md $p/trace/garden-backlog.md || return 1
  rmdir "$r/docs/exec-plans" "$r/docs" "$r/.trace" 2>/dev/null
  if [ "$LEGACY_MOVED" -gt 0 ] && progress_gitignore_ensure "$r"; then say "add   .harness-mini/.gitignore"; fi
  return 0
}

# The byte-exact files the old installers GENERATED (historical match content:
# the old paths below are intentional — they are what is compared against).
legacy_cursor_rule() {
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

legacy_claude_gate() { # a CLAUDE.md that holds only the v3 routing gate
  printf '%s\n' '<!-- HARNESS_ROUTING_GATE_BEGIN -->'
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
  printf '%s\n' '<!-- HARNESS_ROUTING_GATE_END -->'
}

# legacy_skill_description <skill_md> — the `description:` value exactly as the old
# installers copied it into a generated rule (raw: quotes kept).
legacy_skill_description() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---"      { exit }
    fm && /^description:/  { sub(/^description:[ \t]*/, ""); print; exit }
  ' "$1"
}

# legacy_rule_description_known <root> <name> <description line> — is the rule's
# `description: …` line one the old installers wrote for skill <name>: the skill's
# description (the project's copy or the runtime's) or their fallback text?
legacy_rule_description_known() {
  local s d
  for s in "$1/.claude/skills/$2/SKILL.md" "$(harness_home)/skills/$2/SKILL.md"; do
    [ -f "$s" ] || continue
    d="$(legacy_skill_description "$s")"; [ -n "$d" ] || d="harness-mini skill: $2"
    [ "$3" = "description: $d" ] && return 0
  done
  return 1
}

# legacy_cursor_rules <root> — remove generated .cursor/rules/*.mdc, but only a rule that
# is byte-exact AND carries a known generated description. A rule for a harness skill
# that looks generated yet differs (an edited description or body) is kept and reported.
legacy_cursor_rules() {
  local rules="$1/.cursor/rules" expected rule name desc
  [ -d "$rules" ] || return 0
  expected="$(mktemp)" || return 1
  legacy_cursor_rule > "$expected"
  if [ -f "$rules/harness-mini.mdc" ] && [ ! -L "$rules/harness-mini.mdc" ] \
     && cmp -s "$expected" "$rules/harness-mini.mdc"; then
    rm -f "$rules/harness-mini.mdc"; say "migr  removed unchanged generated .cursor/rules/harness-mini.mdc"
  fi
  for rule in "$rules"/*.mdc; do
    [ -f "$rule" ] && [ ! -L "$rule" ] || continue
    name="$(basename "$rule" .mdc)"
    # only a rule for a harness skill: one that is installed here or shipped in the runtime
    [ -f "$1/.claude/skills/$name/SKILL.md" ] || [ -f "$(harness_home)/skills/$name/SKILL.md" ] || continue
    desc="$(sed -n '2p' "$rule")"
    case "$desc" in "description: "*) ;; *) continue ;; esac     # not shaped like a generated rule
    {
      printf '%s\n' '---'
      printf '%s\n' "$desc"
      printf '%s\n' 'alwaysApply: false'
      printf '%s\n\n' '---'
      printf 'harness-mini skill **%s**. Read `.claude/skills/%s/SKILL.md` and follow it for this task.\n' "$name" "$name"
    } > "$expected"
    if legacy_rule_description_known "$1" "$name" "$desc" && cmp -s "$expected" "$rule"; then
      rm -f "$rule"; say "migr  removed unchanged generated .cursor/rules/$name.mdc"
    else
      legacy_keep ".cursor/rules/$name.mdc" ".cursor/rules/$name.mdc (looks generated by an old harness-mini but its description or text differs from what it wrote; kept — delete it yourself if unused)"
    fi
  done
  rm -f "$expected"
  rmdir "$rules" "$1/.cursor" 2>/dev/null
  return 0
}

legacy_claude_md() { # <root> — CLAUDE.md: removed only when it is exactly the generated gate
  local f="$1/CLAUDE.md" expected
  [ -f "$f" ] && [ ! -L "$f" ] || return 0
  expected="$(mktemp)" || return 1
  legacy_claude_gate > "$expected"
  if cmp -s "$expected" "$f"; then
    rm -f "$f"; say "migr  removed unchanged generated CLAUDE.md"
  elif grep -qE 'HARNESS_ROUTING_GATE_BEGIN|harness-mini:start' "$f"; then
    legacy_keep CLAUDE.md "CLAUDE.md (holds a legacy harness gate beside your content; delete that block yourself)"
  fi
  rm -f "$expected"
}

# legacy_agents_md <root> <old_lock> — whole-file harness AGENTS.md copy.
legacy_agents_md() {
  local f="$1/AGENTS.md" base
  [ -f "$f" ] && [ ! -L "$f" ] || return 0
  grep -qxF "$HM_BEGIN" "$f" && return 0           # already migrated
  base="$(lock_sha "$2" AGENTS.md)"
  [ -n "$base" ] || return 0                       # not a legacy harness copy
  if [ "$(cksum_file "$f")" = "$base" ]; then
    rm -f "$f"; agents_block_add "$f" "$(home_ref)" || return 1
    say "migr  replaced the whole-file harness AGENTS.md with the harness-mini block"
  else
    agents_block_add "$f" "$(home_ref)" || return 1
    say "keep  AGENTS.md (edited; your text untouched, harness-mini block appended — delete the stale harness map text yourself)"
  fi
}

# legacy_remove_owned <root> <old_lock> — checksum-verified removal of every
# other path the old lock lists. .agents/{skills,agents} are the CURRENT shared
# install targets: left in place, clean files remembered in LEGACY_SEEDS so the
# new lock can adopt their baseline.
legacy_remove_owned() {
  local root="$1" base rel f shared=0 nl; nl="$(printf '\n.')"; nl="${nl%.}"
  while read -r base rel; do
    [ "$base" = "version:" ] && continue
    case "$rel" in ""|/*|../*|*/../*|*/..|AGENTS.md) continue ;; esac
    f="$root/$rel"
    case "$rel" in .agents/skills/*|.agents/agents/*)
      shared=1
      if [ -f "$f" ] && [ ! -L "$f" ] && [ "$(cksum_file "$f")" = "$base" ]; then
        LEGACY_SEEDS="$LEGACY_SEEDS$rel $base$nl"
      fi
      continue ;;
    esac
    [ -e "$f" ] || [ -L "$f" ] || continue
    if [ -L "$f" ] || [ ! -f "$f" ]; then
      legacy_keep "$rel" "$rel (not a regular file)"; LEGACY_KEPT=$((LEGACY_KEPT + 1))
    elif [ "$(cksum_file "$f")" = "$base" ]; then
      rm -f "$f"; say "migr  removed unchanged $rel"; legacy_prune_parents "$root" "$rel"
      case "$rel" in .claude/skills/*|.claude/agents/*|harness/agents/*) LEGACY_SKILLS_GONE=1 ;; esac
    else
      legacy_keep "$rel" "$rel (edited; not removed)"; LEGACY_KEPT=$((LEGACY_KEPT + 1))
    fi
  done < "$2"
  [ "$shared" -eq 0 ] || legacy_keep .agents/skills ".agents/skills and .agents/agents (the current shared install targets; untouched)"
  return 0
}

# legacy_generated_manifest <file> — true iff every line is one the old installers
# generated: the heading, one of the three intro texts (<=0.10, 0.11/0.12, 0058), the
# `## Skills|Agents|Role descriptions (dir/)` headings, "- path" entries, the Map line,
# or blank. Any other line (user prose) fails.
legacy_generated_manifest() {
  awk '
    $0 == "" || /^- [^ ]+$/ { next }
    /^# harness-mini manifest( \(CLI-neutral pointer list\))?$/ { next }
    /^## (Skills|Agents|Role descriptions) \([^ ]+\)$/ { next }
    /^## Map: AGENTS\.md   Architecture: ARCHITECTURE\.md$/ { next }
    /^Skills and agents are files under [^ ]+ and [^ ]+\.$/ { next }
    /^Skills are under [^ ]+; role descriptions are under [^ ]+\.$/ { next }
    /^Any coding agent that can read the repo should open the paths below\.$/ { next }
    /^Claude Code auto-loads skills\/agents from \.claude\/\. Other CLIs \(codex,$/ { next }
    /^cursor\) should read the files below directly\.$/ { next }
    { bad = 1 }
    END { exit bad }' "$1"
}

# legacy_remove_leftovers <root> <src_root> — harness copies the old lock cannot vouch
# for (an old runtime's `update` rewrote it without them, or init copied them unlocked):
#   docs/references/*, docs/assets/*  vs the source's references/ and assets/
#   docs/<static doc>                 vs the runtime's shared docs/
# Removed only when BYTE-IDENTICAL to the shipped copy (nothing is lost); anything else
# is reported, every path on its own line, sorted. Runs only when the old lock proved a harness install.
legacy_remove_leftovers() {
  local root="$1" src="$2" home rel from canon left="" n=0
  home="$(harness_home)"
  for from in "docs/references:references" "docs/assets:assets" "docs:$home/docs"; do
    case "${from#*:}" in /*) canon="${from#*:}" ;; *) canon="$src/${from#*:}" ;; esac
    [ -d "$root/${from%%:*}" ] && [ -d "$canon" ] || continue
    while IFS= read -r rel; do
      rel="${from%%:*}/$rel"; legacy_noted "$rel" && continue
      [ -f "$canon/${rel#${from%%:*}/}" ] || continue            # not a file the harness ships
      if cmp -s "$root/$rel" "$canon/${rel#${from%%:*}/}"; then
        rm -f "$root/$rel"; say "migr  removed unchanged $rel (identical to the shipped copy)"
        legacy_prune_parents "$root" "$rel"
      else
        left="$left$rel
"; n=$((n + 1))
      fi
    done < <(cd "$root/${from%%:*}" && find . -type f -not -path './exec-plans/*' | sed 's#^\./##' | LC_ALL=C sort)
  done
  [ "$n" -gt 0 ] || return 0
  while IFS= read -r rel; do        # not a pipe: legacy_keep must run in this shell
    legacy_keep "$rel" "$rel (leftover legacy harness file: differs from the shipped copy, not removed; delete it if unused)"
  done < <(printf '%s' "$left" | LC_ALL=C sort)
}

legacy_finish() { # <root> <old_lock> <src_root> — manifest, the consumed lock, leftovers
  local root="$1" mf="$1/harness/manifest.md"
  if [ -f "$mf" ] && [ ! -L "$mf" ]; then
    if legacy_generated_manifest "$mf"; then
      rm -f "$mf"; say "migr  removed generated harness/manifest.md"; legacy_prune_parents "$root" harness/manifest.md
    else
      legacy_keep harness/manifest.md "harness/manifest.md (edited; not removed)"
    fi
  fi
  legacy_remove_leftovers "$root" "$3"
  if [ "$LEGACY_KEPT" -eq 0 ]; then
    rm -f "$2"; say "migr  removed harness/harness.lock (baseline consumed; the new lock lives in $(state_dir "$root"))"
    legacy_prune_parents "$root" harness/harness.lock
  else
    legacy_keep harness/harness.lock "harness/harness.lock ($LEGACY_KEPT kept file(s) still need its baseline)"
  fi
  return 0
}

# legacy_no_baseline <root> — a harness install whose old lock is gone: nothing can be
# verified, so nothing is removed; name what is left (each path once, see legacy_keep).
legacy_no_baseline() {
  local root="$1" rel
  for rel in bin/harness.sh harness/manifest.md harness/agents; do
    [ -e "$root/$rel" ] && legacy_keep "$rel" "$rel (not removed: no harness/harness.lock baseline to verify it against)"
  done
  if [ -f "$root/harness/manifest.md" ] || [ -d "$root/harness/agents" ]; then
    for rel in .claude/skills .claude/agents ARCHITECTURE.md; do
      [ -e "$root/$rel" ] && legacy_keep "$rel" "$rel (not removed: no harness/harness.lock baseline to verify it against)"
    done
  fi
  return 0
}

# migrate_legacy_layout <root> [src_root] — src_root (the source tree being installed)
# lets leftovers in docs/references and docs/assets be verified; optional.
migrate_legacy_layout() {
  local root="$1" src="${2:-}" old="$1/harness/harness.lock" had_trace=no
  LEGACY_MOVED=0; LEGACY_KEPT=0; LEGACY_SKILLS_GONE=0; LEGACY_SEEDS=""; LEGACY_NOTES=""
  legacy_present "$root" || return 0
  # Gate: no project file is moved or deleted unless the runtime the AGENTS.md block
  # will point at is installed and answers `agent list`.
  if ! runtime_usable "$(harness_home)"; then legacy_refuse "$root" "$RUNTIME_WHY"; return 1; fi
  [ -d "$root/.trace" ] && had_trace=yes
  legacy_migrate_user_data "$root" || return 1
  legacy_cursor_rules "$root" || return 1          # before skills go: the rule text embeds them
  legacy_claude_md "$root" || return 1
  if [ -f "$old" ]; then
    legacy_agents_md "$root" "$old" || return 1
    legacy_remove_owned "$root" "$old" || return 1
    legacy_finish "$root" "$old" "$src" || return 1
    [ "$LEGACY_SKILLS_GONE" -eq 0 ] || say "note  skills/role files were removed from the project; run \"$(home_ref)/bin/harness.sh\" agent list, then agent install <host>"
  elif [ -f "$root/harness/manifest.md" ] || [ -d "$root/harness/agents" ] || [ "$LEGACY_MOVED" -gt 0 ]; then
    legacy_no_baseline "$root"
  fi
  legacy_flush_notes "$root"
  if { [ "$had_trace" = yes ] || [ "$LEGACY_MOVED" -gt 0 ]; } && grep -qxF '.trace/runtime/' "$root/.gitignore" 2>/dev/null; then
    say "keep  .gitignore still lists .trace/runtime/ (stale and harmless; the harness never edits your .gitignore)"
  fi
  return 0
}

# legacy_seed_sha <relpath> — the old-lock baseline remembered for a retained file.
legacy_seed_sha() { printf '%s' "$LEGACY_SEEDS" | awk -v p="$1" '$1 == p { print $2; exit }'; }

# legacy_seeds_adopt <lockfile> — make the new lock adopt the old baseline of
# retained .agents/ files that are still pristine, so `update` upgrades them
# instead of flagging a conflict.
legacy_seeds_adopt() {
  local rel sha
  while read -r rel sha; do
    [ -n "$rel" ] && [ "$(lock_sha "$1" "$rel")" != "$sha" ] && lock_override "$1" "$rel" "$sha"
  done <<< "$LEGACY_SEEDS"
  return 0
}
