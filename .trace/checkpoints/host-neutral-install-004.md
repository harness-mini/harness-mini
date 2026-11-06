---
plan: host-neutral-install
seq: 004
stage: implement
ctx_pct_at_checkpoint: 22
prev: host-neutral-install-003
---
## Done
- Issue-003 passed L2: project locks and global runtime lock advance independently; runtime scripts update checksum-guarded, edited runtime scripts get `.new`, and the running harness script is replaced last.
- Regression tests verify two project roots update independently and installed runtime checksums match upstream. Full suite: 337 passed, 0 failed.

## Now
- Workboard has advanced to issue-004, focused on doctor/status root selection, shared skill health, and runtime/project version reporting.

## Next (resume here)
- Run `bin/harness.sh status`, complete session-coding Getting Bearings, then start issue-004 test-first.

## Task state
- Acceptance: issue-001, issue-002, and issue-003 met; issue-004 through issue-006 open.
- Footprint:
  - bin/harness.sh:1-715::DONE
  - tests/run.sh:1-1188::DONE
  - docs/exec-plans/active/0058-host-neutral-install.json:1-14::DONE
  - docs/exec-plans/active/0058-host-neutral-install.md:1-83::DONE
- Last green: none
- Open issues: issue-004, issue-005, issue-006
## Decisions
- Runtime checksums/version belong to `$HARNESS_HOME/harness/runtime.lock`; project lock files list only project-managed data.
- Runtime update uses checksum guards and writes conflicts to `.new`; the running runtime CLI is replaced only after lock writes and output complete.
- Each project update advances only that project's project lock, while shared runtime update is centralized.
## Open questions / blockers
- None
