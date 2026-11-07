---
plan: projects-state-dir
seq: 0061
stage: done
owner: main
mode: quick
eval: L1
---
# Move per-project state to ~/.harness-mini/projects/<project-id>

Issue: #82.

## Decisions
- `state_dir <root>` = `$HARNESS_HOME/projects/<project-id>`. Contents unchanged (`harness.lock`, `manifest.md`, `targets`, `legacy-kept`).
- Every reader/writer uses `state_dir` (no hard-coded `$HARNESS_HOME/<id>` anywhere): init.sh, bin/harness.sh, bin/session.sh, bin/_harness_lib.sh, tests, docs.
- Automatic, idempotent migration of existing `$HARNESS_HOME/<project-id>/` into `projects/<project-id>/` on `init.sh` and `update` (for the project being handled): move only when the old dir is that project's state dir (name equals its project-id and it contains a `harness.lock`), never touch runtime dirs (`bin`, `docs`, `skills`, `agents`, `harness`) or other files, never overwrite an existing target (if target exists keep the old dir and print a `keep` notice). The migration runs BEFORE anything reads the state dir.
- `doctor`/`status` for a project whose state is still in the old location must not report a missing lock (they read through the migration helper or report a clear hint).

## Acceptance criteria
- [ ] Fresh install writes lock/manifest/targets under `$HARNESS_HOME/projects/<project-id>/` and nothing else new at the top level of `$HARNESS_HOME`.
- [ ] A 0.13.0-layout home (`$HARNESS_HOME/<id>/`) migrates on `init.sh` and on `update --root`, idempotently; runtime dirs untouched; existing target never overwritten.
- [ ] Two projects migrate independently; a project whose id equals a runtime dir name cannot clobber it.
- [ ] `bash tests/run.sh` passes; README/ARCHITECTURE/walkthrough/CHANGELOG `[Unreleased]` updated.

## Evaluation
- L1 (`projects-state-dir-001`): **pass**, 4/4, no blocker/major. Minor, left open: doctor output on a failed migration (read-only home) does not hint at the old flat dir; a race between the `-e` check and `mv` could nest the old dir under `projects/<id>/`; the runtime-name guard cannot trigger for real ids (harmless).
