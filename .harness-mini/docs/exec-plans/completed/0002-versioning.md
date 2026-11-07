---
plan: versioning
seq: 0002
stage: done
owner: main
---
# Versioning, update & GitHub releases

Give harness-mini a CLI to report its version, pull a newer version into an
installed project without destroying user edits, and cut GitHub tags/releases.

## Problem
harness-mini installs by copying files into a project — there is no package
manager, so an install is a frozen snapshot. Users can't tell which version they
have, can't pull fixes/new skills, and the repo has no release tags. We need
versioning that fits the "convention + thin shell glue" model (no daemon, no
registry).

## Decisions (from grill-me, 2026-05-29)
- **Single dispatcher**: `bin/harness.sh <version|update|release>` is the front
  door; ctx/trace/ralph stay as internal primitives.
- **Checksum-guarded update**: a lockfile records the pristine upstream checksum
  of every managed file. On update, unchanged files are overwritten silently;
  user-edited files are kept and the new version is written beside them as
  `<file>.new`. User space (`docs/exec-plans/`, `.trace/`, project code) is never
  touched.
- **Guarded full release + `release` skill**: `release <v>` gates on green tests
  + clean tree, bumps `VERSION`, updates `CHANGELOG.md`, commits, tags `v<v>`,
  pushes, and `gh release create`s. A `release` skill documents the judgment.
- **Start at 0.1.0.** SemVer: MINOR = new skills/agents, PATCH = glue fixes,
  MAJOR = breaking the install layout.

## Source of truth & artifacts
- Source repo: `VERSION` (canonical), `CHANGELOG.md` (Keep-a-Changelog-lite).
- Installed target: `harness/harness.lock` — `version:` line + `<sha>  <relpath>`
  baseline checksums of every managed file. Written by `init.sh` (additive:
  only if absent); maintained thereafter by `harness.sh update`.
- **Managed set** (single source of truth = `emit_managed_pairs()` in harness.sh,
  also used by init for the lock): `.claude/skills/*`, `.claude/agents/*`,
  `bin/*`, `docs/principles.md`, `docs/smart-dumb.md`, `docs/references/*`,
  `AGENTS.md`, `ARCHITECTURE.md`. Explicitly NOT `docs/exec-plans/**` or `.trace/**`.

## Lock baseline semantics (correctness core)
Per managed file, lock stores `base` = checksum of the pristine upstream content
last synced. On update, compare `base`, `cur` (on disk), `new` (incoming source):
- target absent → **ADD** (write, record `new`).
- `new == base` → **UNCHANGED** (skip).
- `new != base` && `cur == base` → **UPDATE** (overwrite, record `new`).
- `new != base` && `cur != base` → **CONFLICT** (keep user file, write `.new`,
  leave `base` so we keep surfacing the freshest `.new`).

## Acceptance criteria
- [x] `harness.sh version` prints installed version (from lock, else source
      VERSION) + best-effort latest; exits 0 with/without network.
- [x] `init.sh` writes `harness/harness.lock` (version + checksums) when absent;
      stays additive + idempotent; existing tests still green.
- [x] `harness.sh update` performs ADD/UPDATE/CONFLICT correctly; never touches
      `docs/exec-plans/` or `.trace/`; rewrites lock version after.
- [x] `harness.sh release <v>` refuses on bad semver / dirty tree / red tests;
      `--dry-run` mutates nothing; happy path bumps VERSION + CHANGELOG, commits,
      tags `v<v>` (push/gh gated by `--no-push`/`--no-gh` and availability).
- [x] `release` skill added; AGENTS.md / README / manifest / ARCHITECTURE wired.
- [x] All test sections written test-first; full `tests/run.sh` green (66/66).

## Vertical slices (build order)
1. **Skeleton**: `VERSION`=0.1.0 + `bin/harness.sh version` reading source VERSION.
2. **Lock**: `init.sh` emits `harness/harness.lock`; `version` reads from lock;
   `emit_managed_pairs()` + `cksum_file()` shared helpers.
3. **Update**: checksum-guarded ADD/UPDATE/CONFLICT sync.
4. **Release**: guarded `release` (+`--dry-run`/`--no-push`/`--no-gh`) + skill.
5. **Wire + ship**: docs, CHANGELOG, memory; cut the real v0.1.0 release.

## Out of scope (deleted via five-step)
- Package registry / dependency resolution / semver range solving.
- Auto-update daemon or background checks.
- 3-way merge of conflicts (we hand the user `.new`; they merge).

## Now (resume here)
- DONE. Shipped as **v0.1.0**: tag pushed + GitHub release published
  (github.com/harness-mini/harness-mini/releases/tag/v0.1.0). 66/66 green.

## Next
- Future bumps: `bin/harness.sh release <x.y.z>` (MINOR for new skills/agents/CLI).
- Installed projects upgrade via `bin/harness.sh update`.

## Decisions log
- 2026-05-29: grill-me resolved 4 forks (above). Plan authored; stage=issues.
- 2026-05-29: issues are atomic + testable → advanced stage to `implement`.
- 2026-05-29: extracted `bin/_harness_lib.sh` (managed-set + lock) so update &
  init share one source of truth (clean-code).
- 2026-05-29: `release` runs the suite as its gate; release-tests use throwaway
  repos with trivial tests → no recursion against the real suite.
- 2026-05-29: evaluate gate = deterministic `tests/run.sh` (66/66 green), not a
  self-grade. In a full multi-session run the evaluator agent would grade here.
  → advanced stage to `checkpoint`.
