---
plan: versioning
seq: 001
stage: checkpoint
ctx_pct_at_checkpoint: 33
prev: build-harness-001
---
## Done
- `bin/harness.sh` CLI shipped: `version`, `update`, `release` (66/66 tests green).
- `bin/_harness_lib.sh` shared helpers (managed-set, checksums, lockfile).
- `VERSION` (0.1.0) + `CHANGELOG.md` (Keep-a-Changelog) added.
- `init.sh` now writes `harness/harness.lock` (additive); existing behaviour intact.
- `update` is checksum-guarded (ADD/UPDATE/CONFLICT); user space never touched.
- `release` gates on semver + green tests + clean tree; `--dry-run`/`--no-push`/`--no-gh`.
- `release` skill + AGENTS/README/ARCHITECTURE/manifest wired.
## Now
- Feature complete on a branch; about to commit + cut the real `v0.1.0` release.
## Next (resume here)
- Run `bin/harness.sh release 0.1.0` (real: tag v0.1.0 + GitHub release + push),
  then move `docs/exec-plans/active/0002-versioning.md` to `completed/`.
## Decisions
- Managed set defined once in `emit_managed_pairs()` (lib) = the harness/user
  boundary. Lock stores PRISTINE upstream checksums so update can tell user edits
  from upstream changes. Full rationale: `docs/exec-plans/active/0002-versioning.md`.
## Open questions / blockers
- none (release needs `gh` auth + `origin` remote; falls back to local tag if absent).
