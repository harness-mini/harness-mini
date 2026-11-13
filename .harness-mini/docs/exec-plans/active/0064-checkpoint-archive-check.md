---
plan: checkpoint-archive-check
seq: 0064
stage: implement
owner: main
mode: quick
eval: L1        # lightweight reviewer; small verifier + docs wiring
---
# Archive-integrity verifier for the checkpoint skill — quick mode

> Pain (measured, twice): plan archival via `git mv` stages only the rename —
> the `stage:`/`passes` content edits stayed in the working tree and stale
> metadata landed on main via PR #91 (0062, fixed by amend+force-push) and
> again via PR #94 (0063, needed its own fix PR whose add/add conflict also
> blocked CI). The plan twin's `status`/`passes` on main is the machine truth
> `harness.sh status` reads for cold sessions — stale metadata means the board
> lies. Follows discussion #75: determinism (one shell verifier per fragile
> field) + efficiency (kill the whole post-hoc fix-PR cycle).

## Acceptance criteria
<!-- Machine-checkable. -->
- [ ] `skills/checkpoint/scripts/checkpoint-archive-check.sh [root]` exists:
      POSIX/bash per repo style, zero deps, bash 3.2 compatible, `root`
      defaults to the git toplevel (fallback: `$PWD`).
- [ ] Dirty tracked file under `<root>/.harness-mini/docs/exec-plans/` →
      exit 1, each dirty path named.
- [ ] Invariant: every `completed/*.md` has `stage: done`; its twin `.json`
      has `status: "done"` and no slice with `passes: false` → violations
      exit 1 naming the plan + field. `active/` gets the dirty check only
      (stages legitimately vary there). Missing dirs are skipped, not errors.
- [ ] Clean, consistent tree → exit 0, silent.
- [ ] New `checkpoint-archive-check` group in `tests/run.sh` covers: dirty
      file, bad stage, bad passes, clean fixture (fixture git repos, temp
      dirs; patterns per `test-selection` group from 0063). `--list` totals
      updated; full suite green.
- [ ] Docs wiring: checkpoint SKILL archival step mandates running the check
      (exit 1 ⇒ no checkpoint, fix first); stage-viewer's done-advance
      condition references it; release SKILL gains the "clean gate counts
      untracked scratch — move it out first" line (measured 0.15.1).

## The change
- **slice-001** — the verifier script + `checkpoint-archive-check` test group.
- **slice-002** — docs-only wiring (checkpoint / stage-viewer / release SKILL
  lines). May land in parallel with slice-001: disjoint files, the script
  name and contract are pinned by this plan.

## Evidence (fill on completion)
- <per-slice: probe outputs, test counts, --list totals>

## Session Context Handoff
**Last Updated**: 2026-11-13 (Session #1)
**Completed Work**: plan opened from the twice-measured git-mv archival bug.
**Current Blockers / Risks**: invariant scope — `completed/` only; do NOT
validate `active/` stages (they vary legitimately mid-lifecycle).

## Decisions
- Docs-only would rely on the agent remembering; the verifier makes the
  postcondition machine-checkable ("prefer one shell verifier per fragile
  field" — this field is tree state + twin consistency, not prose).
- No doctor wiring this plan: the check runs at checkpoint time (where the
  skill already invokes lint/guard). Doctor integration can ride a later
  garden item if the failure mode reappears.
