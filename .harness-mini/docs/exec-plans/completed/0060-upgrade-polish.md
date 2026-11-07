---
plan: upgrade-polish
seq: 0060
stage: done
owner: main
mode: quick
eval: L1
---
# Upgrade polish: fixes N1-N4 from the 0059 L2 evaluation

Source: `.harness-mini/trace/evals/zero-intrusion-install-002.md` (minor defects).

## Decisions (user-confirmed 2026-11-07)
- **N1** Users must not edit files under `$HARNESS_HOME`; edited runtime files are still preserved and the upstream copy lands as `<file>.new`. After an upgrade/init/update that leaves any `.new` under `$HARNESS_HOME` (or the project), print a prominent terminal notice and, right below it, a ready-to-run command: `harness.sh diff <relpath>` (shows the difference between the kept file and its `.new`). Add that `diff` subcommand. The migration-refusal message must say "resolve `bin/harness.sh.new`" (with the diff command), not "run init.sh again".
- **N2** `update` refuses to downgrade the runtime (same version comparison as `init.sh`), unless `--force`. Applies to `--src <dir>` and to the default clone path.
- **N3** Generated `.cursor/rules/*.mdc` cleanup: delete only if the `description:` line equals a known generated value for that skill (the installed skill's current description or the legacy fallback); otherwise keep and report. Never report "removed unchanged" for a rule whose description differs; kept rules get a notice.
- **N4** Unchanged behaviour (stale legacy docs are kept), but the leftover notice must list EVERY leftover path, not a count.
- Out of scope, recorded in `.harness-mini/trace/garden-backlog.md` as an open item: layered config overrides (tool defaults → project-level shared config → user-local config) so users never need to edit the install dir.

## Acceptance criteria
- [ ] `harness.sh diff <path>` exists, works for runtime and global files with a `.new`, errors clearly otherwise; `help` documents it.
- [ ] Any run that leaves `.new` files prints a prominent notice + the diff command line; quiet when none.
- [ ] Migration refusal caused by an edited runtime file names the `.new` file and the diff command.
- [ ] `update` downgrade refused (exit non-zero, nothing changed) without `--force`; works with `--force`; upgrade and same-version unchanged.
- [ ] N3 behaviours as above, with tests for description-only-edited rule (kept + notice) and clean rule (removed).
- [ ] Leftover docs notice lists all paths.
- [ ] `bash tests/run.sh` passes; CHANGELOG updated under 0.13.0 (or [Unreleased]); backlog item added.

## Evaluation
- L1 (`upgrade-polish-001`): **pass**, 7/7, no blocker/major. Nits: a `.new` not recorded in any lock is invisible to the banner/doctor (by design); `update --force` with no file change prints "already up to date" though VERSION moved (cosmetic); kept-`.mdc` notice only on the migration run.
