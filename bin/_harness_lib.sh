#!/usr/bin/env bash
# _harness_lib.sh — shared helpers for the harness-mini glue scripts.
# Sourced by bin/harness.sh (the CLI) and by init.sh (the installer); never run
# directly. Holds the single source of truth for "what files the harness owns"
# and how to checksum them, so `update` and the install-time lockfile agree.

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

# emit_managed_pairs <src_root> — print "<src_abs><TAB><target_relpath>" for
# every file harness-mini manages. The source layout (skills/, agents/) maps to
# the installed layout (.claude/skills/, .claude/agents/). This is THE managed
# set: user space (docs/exec-plans/, .trace/, project code) is deliberately
# absent, so update/lock never touch it.
emit_managed_pairs() {
  local s="$1" f rel tab; tab="$(printf '\t')"
  # Skills are folders (<name>/SKILL.md plus optional scripts/ references/ …), so
  # recurse and mirror the whole tree into .claude/skills/. (Flat <name>.md is
  # still handled — it just maps to .claude/skills/<name>.md.)
  if [ -d "$s/skills" ]; then
    find "$s/skills" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      rel="${f#"$s"/skills/}"
      printf '%s%s.claude/skills/%s\n' "$f" "$tab" "$rel"
    done
  fi
  for f in "$s"/agents/*.md;            do [ -e "$f" ] && printf '%s%s.claude/agents/%s\n'  "$f" "$tab" "$(basename "$f")"; done
  for f in "$s"/bin/*;                  do [ -e "$f" ] && printf '%s%sbin/%s\n'             "$f" "$tab" "$(basename "$f")"; done
  for f in "$s"/docs/references/*;      do [ -e "$f" ] && printf '%s%sdocs/references/%s\n' "$f" "$tab" "$(basename "$f")"; done
  for f in principles.md smart-dumb.md; do [ -e "$s/docs/$f" ] && printf '%s%sdocs/%s\n'    "$s/docs/$f" "$tab" "$f"; done
  for f in AGENTS.md ARCHITECTURE.md;   do [ -e "$s/$f" ]       && printf '%s%s%s\n'         "$s/$f" "$tab" "$f"; done
}

# write_lock <src_root> <dest_root> <version> — (re)write dest/harness/harness.lock
# recording the version plus the PRISTINE upstream checksum of each managed file
# (keyed by target relpath). Pristine, not on-disk: that is what lets update tell
# "user edited this" from "upstream changed this".
write_lock() {
  local src="$1" dest="$2" ver="$3" out="$2/harness/harness.lock" s rel
  mkdir -p "$dest/harness" || return 1
  {
    printf 'version: %s\n' "$ver"
    emit_managed_pairs "$src" | while IFS="$(printf '\t')" read -r s rel; do
      printf '%s  %s\n' "$(cksum_file "$s")" "$rel"
    done
  } > "$out"
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

# count_dotnew <root> — number of unresolved <file>.new files left by `update`,
# searched only in managed areas (not the whole tree). grep/find only, no parsing.
count_dotnew() {
  local root="$1" n
  n=$(find "$root/.claude" "$root/bin" "$root/docs" "$root/harness" -name '*.new' 2>/dev/null | wc -l | tr -d ' ')
  [ -f "$root/AGENTS.md.new" ] && n=$((n + 1))
  [ -f "$root/ARCHITECTURE.md.new" ] && n=$((n + 1))
  printf '%s' "$n"
}
