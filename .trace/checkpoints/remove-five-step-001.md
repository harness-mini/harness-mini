---
plan: remove-five-step
seq: 001
stage: checkpoint
ctx_pct_at_checkpoint: 30
prev: none
---
## Done
- The Five-Step skill, Cursor mirror, managed manifest entry, core-mind section, and all live funnel/installer/template/planner references were removed.
- Founder-check (new) and recon (existing) now lead directly to to-prd → to-issues.
- One plain delete-first sentence remains under the Mini constraint.
- Historical completed plans and illustrative demo records were preserved.
- Red-to-green test evidence: the new installer regression initially failed, then the full suite passed 168/168.
- Independent L1 evaluation passed: `.trace/evals/remove-five-step-001.md`.

## Now
- Implementation and evaluation are complete; commit the branch and open the issue-only PR.

## Next (resume here)
- Stage the issue #46 changes, run `git diff --cached` for a final review, commit with `Closes #46`, push `chore/remove-five-step`, and open a pull request rather than merging directly to main.

## Decisions
- 2026-10-30: Preserve historical archaeology; edit only the stale live checkpoint instruction because it appeared under “Next (resume here)”.
- 2026-10-30: Rename managed-skill test fixtures to the neutral name `sample.md` and add a negative regression assertion guarding the seeded funnel.

## Task state
- Acceptance: all issue #46 criteria passed by the independent evaluator.
- Footprint: source skill, Cursor mirror, managed manifest, live docs/agents/installer, tests, changelog, and evaluation records.
- Last green: `bash tests/run.sh` → 168 passed, 0 failed.
- Open issues: none.

## Open questions / blockers
- none
