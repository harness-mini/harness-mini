---
plan: host-neutral-install
seq: 006
stage: implement
ctx_pct_at_checkpoint: 24
prev: host-neutral-install-005
---
## Done
- Issue-005 passed L2: upgrade migration removes only checksum-matching legacy project scripts and skills, moves clean skills into `.agents/skills`, and removes only byte-identical generated Cursor rules.
- Edited, untracked, and symlinked files are preserved. Repeated init is idempotent and removes an empty old `bin/` directory. Full suite: 370 passed, 0 failed.

## Now
- Workboard has advanced to issue-006, the final documentation and manifest cleanup.

## Next (resume here)
- Run `bin/harness.sh status`, complete session-coding Getting Bearings, then search active docs and update stale project-bin/host-specific path instructions.

## Task state
- Acceptance: issue-001 through issue-005 met; issue-006 open.
- Footprint:
  - init.sh:1-363::DONE
  - tests/run.sh:1-1303::DONE
  - docs/exec-plans/active/0058-host-neutral-install.json:1-14::DONE
  - docs/exec-plans/active/0058-host-neutral-install.md:1-85::DONE
- Last green: none
- Open issues: issue-006
## Decisions
- Prior project lock checksums are the authority for removing or migrating old project bin/Claude skill files.
- Generated Cursor rules are removed only on exact content match; all edited, unknown, or symlinked user files remain.
- Empty directories are removed only after tracked harness files are migrated/deleted.
## Open questions / blockers
- Source manifest and getting-started documentation still contain stale paths; issue-006 owns their cleanup.
