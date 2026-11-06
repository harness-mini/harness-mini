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
#   HARNESS_ROOT   project root (default: current directory; override with --root)
#   HARNESS_REPO   owner/repo for latest-version checks (default harness-mini/harness-mini)
#   HARNESS_NO_NET if set, skip all network (offline; tests)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=bin/_harness_lib.sh
. "$HERE/_harness_lib.sh"

HARNESS_ROOT="${HARNESS_ROOT:-$PWD}"
LOCK="$HARNESS_ROOT/harness/harness.lock"

say()  { printf '  %s\n' "$1"; }
die()  { echo "harness.sh: $1" >&2; exit "${2:-1}"; }

# installed_version — version recorded in the lock, else the root VERSION file.
installed_version() {
  if [ -f "$LOCK" ]; then
    lock_version "$LOCK"
  elif [ -f "$RUNTIME_ROOT/VERSION" ]; then
    tr -d ' \t\r\n' < "$RUNTIME_ROOT/VERSION"
  elif [ -f "$HARNESS_ROOT/VERSION" ]; then
    tr -d ' \t\r\n' < "$HARNESS_ROOT/VERSION"
  else
    echo "unknown"
  fi
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

  local newlock log pairs self deferred_src="" deferred_dst=""
  newlock="$(mktemp)"; log="$(mktemp)"
  printf 'version: %s\n' "$src_ver" > "$newlock"
  # Absolute path of THIS running script. If the update set includes it, its
  # copy is deferred: bash reads scripts lazily, so overwriting the executing
  # file mid-run makes the interpreter resume the NEW file at the OLD byte
  # offset (garbage commands, crash). The swap is the very last action, and the
  # command exits immediately after it — never returning past its own file.
  self="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
  pairs="$(emit_managed_pairs "$src")"
  while IFS="$(printf '\t')" read -r s rel; do
    local dst="$HARNESS_ROOT/$rel" new base cur rec
    new="$(cksum_file "$s")"
    base="$(lock_sha "$LOCK" "$rel")"
    if [ -f "$dst" ]; then cur="$(cksum_file "$dst")"; else cur=""; fi

    if [ "$dst" -ef "$self" ]; then
      if [ "$new" != "$cur" ]; then
        deferred_src="$s"; deferred_dst="$dst"      # record now, copy last
        printf 'update %s\n' "$rel" >> "$log"
      fi
      rec="$new"                                    # unchanged self: no swap
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

  mv "$newlock" "$LOCK"
  if [ -s "$log" ]; then sed 's/^/  /' "$log"; else echo "  already up to date."; fi
  rm -f "$log"
  [ -n "$tmpclone" ] && rm -rf "$tmpclone"
  if [ -n "$deferred_src" ]; then
    cp "$deferred_src" "$deferred_dst"              # self-swap, then die here
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

  # update check (best-effort; never a FAIL) — skip silently when offline/unknown.
  local latest; latest="$(latest_version)"
  if [ -n "$latest" ]; then
    version_newer "$(installed_version)" "$latest" \
      && emit warn "harness-mini $latest available (installed $(installed_version)) — run harness.sh update" \
      || emit ok "harness-mini up to date ($(installed_version))"
  fi

  # Installed projects and the source repo share the .agents/skills path.
  local skill_root="" skill_label=""
  if [ -d "$root/.agents/skills" ]; then
    skill_root="$root/.agents/skills"; skill_label=".agents/skills"
  elif [ -d "$root/skills" ]; then
    skill_root="$root/skills"; skill_label="skills"
  fi
  if [ -n "$skill_root" ]; then
    local nfolders nflat
    nfolders=$(find "$skill_root" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
    nflat=$(find "$skill_root" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    [ "$nfolders" -gt 0 ] && emit ok "$nfolders skills in <name>/SKILL.md shape" \
                          || emit fail "$skill_label has no <name>/SKILL.md"
    [ "$nflat" -gt 0 ] && emit warn "$nflat flat .md skill(s) in $skill_label (old shape)"
  else
    emit fail ".agents/skills missing"
  fi

  if [ -f "$root/harness/manifest.md" ]; then
    grep -q '\.md' "$root/harness/manifest.md" && emit ok "manifest lists skills" \
                                               || emit warn "harness/manifest.md lists no skills"
  else
    emit warn "harness/manifest.md missing"
  fi

  ls "$root"/docs/exec-plans/active/*.md >/dev/null 2>&1 \
    && emit ok "active exec-plan present" || emit warn "no active exec-plan"

  # dual-file twins: each active MD plan should carry a same-basename .json
  # workboard (WARN only, never FAIL — the MD stays the lifecycle authority and
  # status degrades gracefully to MD-only without the twin).
  local pf2 twin2 wb2 wpid2 wst2
  for pf2 in "$root"/docs/exec-plans/active/*.md; do
    [ -f "$pf2" ] || continue
    twin2="${pf2%.md}.json"
    if [ ! -f "$twin2" ]; then
      emit warn "$(basename "$pf2" .md): no JSON twin — workboard blind (docs/templates/full-plan.md)"
    else
      # "Readable" = same bar status applies: plan_id seen AND a status value.
      wb2="$(json_wb "$twin2")"
      wpid2="$(printf '%s' "$wb2" | awk -F'|' '{print $6}')"
      wst2="$(printf '%s' "$wb2" | awk -F'|' '{print $1}')"
      { [ "$wpid2" = "1" ] && [ -n "$wst2" ]; } \
        || emit warn "$(basename "$pf2" .md): JSON twin unparseable — fix fields or delete it"
    fi
  done

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
  if [ -d "$root/skills" ] && [ -d "$root/.agents/skills" ]; then
    diff -r "$root/skills" "$root/.agents/skills" >/dev/null 2>&1 \
      && emit ok "skills source == .agents mirror" \
      || emit warn "skills/ and .agents/skills/ diverge — regen: cp -R skills/. .agents/skills/"
  fi
  if [ -d "$root/agents" ] && [ -d "$root/harness/agents" ]; then
    diff -r "$root/agents" "$root/harness/agents" >/dev/null 2>&1 \
      && emit ok "role descriptions source == harness mirror" \
      || emit warn "agents/ and harness/agents/ diverge — regen: cp -R agents/. harness/agents/"
  fi

  # eval-gate (anti-self-praise teeth): an active plan that reached `done` must
  # have a passing evaluation on record (.trace/evals/<plan>-*.md, verdict: pass).
  # Scoped to active/ so legacy completed/ plans are never retroactively failed.
  local pf stg plan r rec
  for pf in "$root"/docs/exec-plans/active/*.md; do
    [ -f "$pf" ] || continue
    stg="$(awk -F': *' '/^stage:/{print $2; exit}' "$pf")"
    [ "$stg" = "done" ] || continue
    plan="$(awk -F': *' '/^plan:/{print $2; exit}' "$pf")"
    [ -z "$plan" ] && plan="$(basename "$pf" .md)"
    rec=""
    for r in "$root"/.trace/evals/"$plan"-*.md; do
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
  local root="$HARNESS_ROOT"
  echo "harness-mini $(installed_version)"

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
  if ls "$root"/docs/exec-plans/active/*.md >/dev/null 2>&1; then
    echo "active plans:"
    for f in "$root"/docs/exec-plans/active/*.md; do
      [ -f "$f" ] || continue
      plan="$(awk -F': *' '/^plan:/{print $2; exit}' "$f")"
      stage="$(awk -F': *' '/^stage:/{print $2; exit}' "$f")"
      [ -z "$plan" ] && plan="$(basename "$f" .md)"
      printf '  %-24s stage: %s\n' "$plan" "${stage:-?}"
      cp="$(ls "$root"/.trace/checkpoints/"$plan"-*.md 2>/dev/null | sort | tail -n1)"
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

  local nnew; nnew="$(count_dotnew "$root")"
  echo "update conflicts: $nnew .new file(s)"

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
  local level=ready next="" nskills done_plan="" r
  nskills=$(find "$root/.agents/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  [ -z "$nskills" ] && nskills=0
  if [ "$nskills" -eq 0 ] && [ -d "$root/skills" ]; then
    nskills=$(find "$root/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
    [ -z "$nskills" ] && nskills=0
  fi

  if [ ! -f "$root/AGENTS.md" ]; then
    level=blocked; next="restore AGENTS.md (re-run init.sh)"
  elif [ "$nskills" -eq 0 ]; then
    level=blocked; next="install skills (re-run init.sh)"
  else
    for f in "$root"/docs/exec-plans/active/*.md; do
      [ -f "$f" ] || continue
      stage="$(awk -F': *' '/^stage:/{print $2; exit}' "$f")"
      [ "$stage" = "done" ] || continue
      plan="$(awk -F': *' '/^plan:/{print $2; exit}' "$f")"
      [ -z "$plan" ] && plan="$(basename "$f" .md)"
      local evf has_pass=no
      for evf in "$root"/.trace/evals/"$plan"-*.md; do
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
      level=warning; next="open a plan (docs/templates/quick-plan.md or full-plan.md)"
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

# cmd_report [run] — aggregate .trace into a metrics summary so thresholds are
# tuned by data, not vibes. grep/awk/sed/ls only; always exits 0. No arg = all
# runs; <run> scopes the runtime trace to one run id.
cmd_report() {
  local root="$HARNESS_ROOT" run="${1:-}" thr="${HARNESS_CTX_THRESHOLD:-40}"
  local rt="$root/.trace/runtime" glob files="" f
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
    printf 'context: no ctx_pct samples (enable bin/ctx-hook.sh — docs/smart-dumb.md)\n'
  fi

  # evaluation outcomes from the durable records (rework loops = fails)
  local ep ef
  ep=$(grep -l '^verdict: pass' "$root"/.trace/evals/*.md 2>/dev/null | wc -l | tr -d ' ')
  ef=$(grep -l '^verdict: fail' "$root"/.trace/evals/*.md 2>/dev/null | wc -l | tr -d ' ')
  printf 'evaluation: %s pass / %s fail (rework loops: %s)\n' "$ep" "$ef" "$ef"

  # checkpoints written (committed institutional memory)
  local ncp
  ncp=$(ls "$root"/.trace/checkpoints/*.md 2>/dev/null | wc -l | tr -d ' ')
  printf 'checkpoints: %s\n' "$ncp"
  return 0
}

usage() {
  cat >&2 <<'EOF'
usage: harness.sh [--root DIR] <command> [--root DIR]
  version                 show installed version (+ latest, best-effort)
  update [--src DIR]      sync this project's managed assets (checksum-guarded)
  doctor                  check install health (ok/warn/fail; exit 1 on a fail)
  status                  show work state (plans, workboard, session path, checkpoints)
  report [run]            aggregate .trace metrics (stages, context, evals, checkpoints)
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
LOCK="$HARNESS_ROOT/harness/harness.lock"
sub="$1"; shift
case "$sub" in
  version) cmd_version "$@" ;;
  update)  cmd_update "$@" ;;
  doctor)  cmd_doctor "$@" ;;
  status)  cmd_status "$@" ;;
  report)  cmd_report "$@" ;;
  release) cmd_release "$@" ;;
  -h|--help|help) usage; exit 0 ;;
  *) echo "harness.sh: unknown command: $sub" >&2; usage; exit 64 ;;
esac
