---
plan: projects-state-dir
seq: 001
tier: L1
verdict: pass
criteria: 4/4
grader: evaluator
---
## Evidence
All probes ran with a temp `HARNESS_HOME` and temp projects (the real `~/.harness-mini` was never touched). Product code, tests and plan files were not modified.

- Fresh install writes lock/manifest/targets under `$H/projects/<id>/` and adds nothing else at the top level — PASS — `init.sh` + `agent install claude` left `$H` holding `AGENTS.md VERSION agents bin docs harness projects skills`. `projects/<id>/` holds `harness.lock manifest.md targets`. The project-side footprint matches `main` (31 files); the only checksum diff is the `AGENTS.md` block (path text).
- 0.13.0-layout home migrates on `init.sh` and on `update --root`, idempotently; runtime dirs untouched; existing target never overwritten — PASS
  - Built the home from `git archive v0.13.0`. The new `init.sh` printed `migr moved state dir to projects/<id>`. The state files are checksum-identical, the old dir is gone, and project files are unchanged. A second run printed no `migr` and the snapshot diff was empty.
  - `update --src R --root P` migrated the same way, and a second update printed "already up to date" with an empty diff. Only runtime files that update normally refreshes changed; skills and agents were untouched.
  - `doctor`, `status` and `version` after migration have no "lock missing", and `doctor` reports healthy.
  - Real upgrade path: the old 0.13.0 runtime ran `update --src <0.14.0 copy>`, then the new `doctor` migrated and reported `harness.lock present (v0.14.0)`. The new `init.sh` over an old home (0.13.0 to 0.14.0) migrated, with state and project files identical.
  - Existing target present: `init` and `update` each printed one `keep` notice. `doctor`, `status` and `version` changed nothing (empty snapshot diff). Both dirs were kept, with the target's `extra` file and marker intact.
- Two projects migrate independently; a runtime-named dir is never clobbered — PASS
  - p1 and p2 in one home: touching p1 left p2's flat dir alone, and p2 migrated only when touched.
  - A decoy `$H/docs/harness.lock` was never moved. A plain file named like p3's id stayed as a file, with its content intact.
  - The tests also cover ids equal to `bin`, `docs`, `skills`, `agents`, `harness` and `projects`.
- `bash tests/run.sh` passes; README/ARCHITECTURE/walkthrough/CHANGELOG `[Unreleased]` updated — PASS
  - `tests/run.sh`: `Passed: 961  Failed: 0`. `bash -n` is clean on `init.sh`, `bin/*.sh` and `tests/run.sh`. No `python` in `bin/` or `init.sh`.
  - `rg` finds no active doc naming the flat `<project-id>` layout; the only hits are the migration comment and the guard test.
  - README, ARCHITECTURE, AGENTS, SECURITY, walkthrough and CHANGELOG all name the new path. The walkthrough output matches the real output (41 global files, `projects/<id>`).
  - `help` does not touch disk (snapshot diff empty). `doctor`, `status`, `version`, `agent` and `report` migrate silently. `update` and `init` announce the move.
- Data-loss paths — PASS (no blocker or major)
  - Read-only `$H`: `update` and `init` abort with a clear error and exit 1, and the old dir stays intact.
  - `mv` is a same-filesystem rename of a sibling dir, so a cross-device copy is not a practical path.

## Defects (all minor, non-blocking)
1. **minor — misleading doctor output when migration fails.**
   - Repro: `chmod a-w $H`, then `harness.sh doctor` on an unmigrated project.
   - Result: stderr shows `mkdir: .../projects: Permission denied`, and `doctor` then reports `fail harness.lock missing in .../projects/<id>` although the lock exists in the old flat dir.
   - Cause: `migrate_state_dir ... || true` swallows the failure. The `fail` is arguably right, but there is no hint pointing at the old location.
   - No data loss.
2. **minor/nit — TOCTOU between `[ -e "$new" ]` and `mv "$old" "$new"`.**
   - If `projects/<id>` appears as a directory in that window, `mv` nests the old dir as `projects/<id>/<id>`.
   - Reproduced by simulating `mkdir projects/<id>; mv old projects/<id>`.
   - No data is lost, but the state is not where readers look. `mv -T` is not portable, so this is acceptable for a single-user CLI.
3. **nit — the runtime-name guard is vacuous.**
   - `project_id` always ends in `-<8 chars>`, so it can never equal `bin`, `docs` and so on.
   - Harmless defence in depth, and the test covers it via a decoy.

## Notes
- The installed runtime is only refreshed when `VERSION` changes. Running a home's own old `harness.sh` after a same-version `init.sh` therefore shows the old flat-layout code and reports "lock missing". This is a dev-only artifact. It resolves once the release bumps `VERSION`, as the 0.14.0 simulation showed.
