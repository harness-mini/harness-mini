#!/usr/bin/env bash
# harness.sh — the front-door CLI for harness-mini. Thin glue over the
# convention: report the installed version, pull a newer version into this
# project without clobbering your edits, and (in the source repo) cut releases.
#
# Usage:
#   harness.sh version                 show installed version (+ latest, best-effort)
#   harness.sh update [--src DIR]      sync managed files from upstream (checksum-guarded)
#   harness.sh release <x.y.z> [opts]  bump + tag + GitHub release (source repo only)
#
# Env:
#   HARNESS_ROOT   the installed project root (default: parent of bin/)
#   HARNESS_REPO   owner/repo for latest-version checks (default harness-mini/harness-mini)
#   HARNESS_NO_NET if set, skip all network (offline; tests)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=bin/_harness_lib.sh
. "$HERE/_harness_lib.sh"

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$HERE/.." && pwd)}"
LOCK="$HARNESS_ROOT/harness/harness.lock"

say()  { printf '  %s\n' "$1"; }
die()  { echo "harness.sh: $1" >&2; exit "${2:-1}"; }

# installed_version — version recorded in the lock, else the root VERSION file.
installed_version() {
  if [ -f "$LOCK" ]; then
    lock_version "$LOCK"
  elif [ -f "$HARNESS_ROOT/VERSION" ]; then
    tr -d ' \t\r\n' < "$HARNESS_ROOT/VERSION"
  else
    echo "unknown"
  fi
}

# latest_version — best-effort newest published tag for HARNESS_REPO (no "v").
# Never hangs the caller offline-on-purpose: HARNESS_NO_NET short-circuits it.
latest_version() {
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
  if [ "$latest" != "$v" ]; then
    echo "latest: $latest — run \`harness.sh update\`"
  else
    echo "up to date."
  fi
}

# cmd_update [--src DIR] — refresh managed files from upstream, checksum-guarded.
# Per file (base = lock baseline, cur = on disk, new = upstream):
#   absent          -> ADD       missing managed file
#   new == cur      -> UNCHANGED  already matches upstream
#   cur == base     -> UPDATE     upstream changed, user untouched -> overwrite
#   otherwise       -> CONFLICT   user-edited & diverged -> keep, write <file>.new
# User space (docs/exec-plans/, .trace/, project code) is never iterated.
cmd_update() {
  local src=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --src) src="$2"; shift 2 ;;
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
  [ -f "$src/VERSION" ] && src_ver="$(tr -d ' \t\r\n' < "$src/VERSION")"
  echo "updating harness-mini $(installed_version) -> $src_ver"

  local newlock log; newlock="$(mktemp)"; log="$(mktemp)"
  printf 'version: %s\n' "$src_ver" > "$newlock"

  emit_managed_pairs "$src" | while IFS="$(printf '\t')" read -r s rel; do
    local dst="$HARNESS_ROOT/$rel" new base cur rec
    new="$(cksum_file "$s")"
    base="$(lock_sha "$LOCK" "$rel")"
    if [ -f "$dst" ]; then cur="$(cksum_file "$dst")"; else cur=""; fi

    if [ ! -f "$dst" ]; then
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
  done

  mv "$newlock" "$LOCK"
  if [ -s "$log" ]; then sed 's/^/  /' "$log"; else echo "  already up to date."; fi
  rm -f "$log"
  [ -n "$tmpclone" ] && rm -rf "$tmpclone"
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

# cmd_doctor — install health. 3 severities (ok/warn/fail); exit 1 iff any FAIL.
cmd_doctor() {
  local root="$HARNESS_ROOT" fails=0 warns=0
  emit() { # <sev> <msg>
    case "$1" in
      ok)   printf '  ok   %s\n' "$2" ;;
      warn) printf '  warn %s\n' "$2"; warns=$((warns + 1)) ;;
      fail) printf '  fail %s\n' "$2"; fails=$((fails + 1)) ;;
    esac
  }

  [ -f "$root/AGENTS.md" ] && emit ok "AGENTS.md present" || emit fail "AGENTS.md missing"
  if [ -f "$LOCK" ]; then
    emit ok "harness.lock present (v$(installed_version))"
  elif [ -f "$root/VERSION" ] && [ -d "$root/skills" ]; then
    emit ok "source repo (VERSION $(installed_version); no lock needed)"
  else
    emit fail "harness/harness.lock missing (run init.sh)"
  fi

  if [ -d "$root/.claude/skills" ]; then
    local nfolders nflat
    nfolders=$(find "$root/.claude/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
    nflat=$(find "$root/.claude/skills" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    [ "$nfolders" -gt 0 ] && emit ok "$nfolders skills in <name>/SKILL.md shape" \
                          || emit fail ".claude/skills has no <name>/SKILL.md"
    [ "$nflat" -gt 0 ] && emit warn "$nflat flat .md skill(s) in .claude/skills (old shape)"
  else
    emit fail ".claude/skills missing"
  fi

  if [ -f "$root/harness/manifest.md" ]; then
    grep -q '\.md' "$root/harness/manifest.md" && emit ok "manifest lists skills" \
                                               || emit warn "harness/manifest.md lists no skills"
  else
    emit warn "harness/manifest.md missing"
  fi

  ls "$root"/docs/exec-plans/active/*.md >/dev/null 2>&1 \
    && emit ok "active exec-plan present" || emit warn "no active exec-plan"

  { [ -f "$root/.gitignore" ] && grep -q '\.trace/runtime' "$root/.gitignore"; } \
    && emit ok ".trace/runtime gitignored" || emit warn ".trace/runtime not in .gitignore"

  local nnew; nnew="$(count_dotnew "$root")"
  [ "$nnew" -eq 0 ] && emit ok "no unresolved .new files" \
                    || emit warn "$nnew unresolved .new file(s) from update — resolve & delete"

  if [ -f "$root/VERSION" ] && [ -f "$LOCK" ]; then
    local fv lv; fv="$(tr -d ' \t\r\n' < "$root/VERSION")"; lv="$(installed_version)"
    [ "$fv" = "$lv" ] && emit ok "VERSION matches lock ($lv)" \
                      || emit warn "VERSION ($fv) != lock ($lv)"
  fi

  # #9 source<->mirror divergence (only meaningful when the source trees exist)
  if [ -d "$root/skills" ] && [ -d "$root/.claude/skills" ]; then
    diff -r "$root/skills" "$root/.claude/skills" >/dev/null 2>&1 \
      && emit ok "skills source == .claude mirror" \
      || emit warn "skills/ and .claude/skills/ diverge — regen: cp -R skills/. .claude/skills/"
  fi
  if [ -d "$root/agents" ] && [ -d "$root/.claude/agents" ]; then
    diff -r "$root/agents" "$root/.claude/agents" >/dev/null 2>&1 \
      && emit ok "agents source == .claude mirror" \
      || emit warn "agents/ and .claude/agents/ diverge — regen: cp -R agents/. .claude/agents/"
  fi

  if [ "$fails" -eq 0 ]; then
    printf 'doctor: healthy (%s warning(s))\n' "$warns"
  else
    printf 'doctor: %s problem(s), %s warning(s)\n' "$fails" "$warns"
  fi
  [ "$fails" -eq 0 ]
}

# cmd_status — current work state for cold resume. grep/awk/tail only; always 0.
cmd_status() {
  local root="$HARNESS_ROOT"
  echo "harness-mini $(installed_version)"

  if ls "$root"/docs/exec-plans/active/*.md >/dev/null 2>&1; then
    echo "active plans:"
    local f plan stage cp
    for f in "$root"/docs/exec-plans/active/*.md; do
      plan="$(awk -F': *' '/^plan:/{print $2; exit}' "$f")"
      stage="$(awk -F': *' '/^stage:/{print $2; exit}' "$f")"
      [ -z "$plan" ] && plan="$(basename "$f" .md)"
      printf '  %-24s stage: %s\n' "$plan" "${stage:-?}"
      cp="$(ls "$root"/.trace/checkpoints/"$plan"-*.md 2>/dev/null | sort | tail -n1)"
      [ -n "$cp" ] && printf '     last checkpoint: %s\n' "$(basename "$cp" .md)"
    done
  else
    echo "active plans: none"
  fi

  echo "update conflicts: $(count_dotnew "$root") .new file(s)"

  local newest last cpct ev run
  newest="$(ls -t "$root"/.trace/runtime/*.jsonl 2>/dev/null | head -n1)"
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
  # high-severity open item, OR >= 3 open items in .trace/garden-backlog.md.
  local bl="$root/.trace/garden-backlog.md" total gat since open high gdue
  total=$(ls "$root"/.trace/checkpoints/*.md 2>/dev/null | wc -l | tr -d ' ')
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

  local hasplan=no hascp=no
  ls "$root"/docs/exec-plans/active/*.md >/dev/null 2>&1 && hasplan=yes
  ls "$root"/.trace/checkpoints/*.md >/dev/null 2>&1 && hascp=yes
  if [ "$hasplan" = yes ] && [ "$hascp" = yes ]; then
    echo "resumable: yes (active plan + checkpoint)"
  elif [ "$hasplan" = yes ]; then
    echo "resumable: partial (plan, no checkpoint yet)"
  else
    echo "resumable: no (no active plan)"
  fi
  return 0
}

usage() {
  cat >&2 <<'EOF'
usage: harness.sh <command>
  version                 show installed version (+ latest, best-effort)
  update [--src DIR]      pull a newer version into this project (checksum-guarded)
  doctor                  check install health (ok/warn/fail; exit 1 on a fail)
  status                  show current work state (plans, checkpoints, resumability)
  release <x.y.z> [opts]  bump + tag + GitHub release (source repo only)
EOF
}

# --- dispatch ----------------------------------------------------------------
[ $# -ge 1 ] || { usage; exit 64; }
sub="$1"; shift
case "$sub" in
  version) cmd_version "$@" ;;
  update)  cmd_update "$@" ;;
  doctor)  cmd_doctor "$@" ;;
  status)  cmd_status "$@" ;;
  release) cmd_release "$@" ;;
  -h|--help|help) usage; exit 0 ;;
  *) echo "harness.sh: unknown command: $sub" >&2; usage; exit 64 ;;
esac
