---
plan: host-neutral-install
seq: 003
stage: implement
ctx_pct_at_checkpoint: 20
prev: host-neutral-install-002
---
## Done
- Issue-002 passed L2 evaluation: shared `.agents/skills` install, neutral `harness/agents` role docs, no host-specific generated skill/routing files, and doctor/status/session runner support.
- Full suite: 324 passed, 0 failed; `git diff --check` clean.

## Now
- Workboard has advanced to issue-003, focusing on runtime/project lock separation during update and `.new` conflict preservation.

## Next (resume here)
- Run `bin/harness.sh status`, then follow session-coding Getting Bearings and start issue-003 test-first.

## Task state
- Acceptance: issue-001 and issue-002 met; issue-003 through issue-006 open.
- Footprint:
  - init.sh:1-247::DONE
  - bin/_harness_lib.sh:1-99::DONE
  - bin/harness.sh:1-670::DONE
  - bin/session.sh:1-70::DONE
  - tests/run.sh:1-1153::DONE
  - AGENTS.md:1-156::DONE
- Last green: none
- Open issues: issue-003, issue-004, issue-005, issue-006
## Decisions
- Every agent uses `.agents/skills`; do not detect, prompt for, or branch on host.
- Central session runner defaults to `$PWD` for the selected project; `HARNESS_ROOT` overrides it.
- Legacy project files are preserved for the dedicated checksum-safe migration issue.
## Open questions / blockers
- None.
