---
plan: host-neutral-install
seq: 005
stage: implement
ctx_pct_at_checkpoint: 24
prev: host-neutral-install-004
---
## Done
- Issue-004 passed L2: central doctor/status use explicit project roots, report runtime/project versions and shared skill inventory, validate manifest entries, name missing skills, and block readiness when listed skills are absent.
- Empty manifests now report unhealthy. Full suite: 356 passed, 0 failed.

## Now
- Workboard has advanced to issue-005, the checksum-safe migration from legacy project files.

## Next (resume here)
- Run `bin/harness.sh status`, complete session-coding Getting Bearings, then start issue-005 migration tests first.

## Task state
- Acceptance: issue-001 through issue-004 met; issue-005 and issue-006 open.
- Footprint:
  - bin/harness.sh:1-800::DONE
  - tests/run.sh:1-1223::DONE
  - docs/exec-plans/active/0058-host-neutral-install.json:1-14::DONE
  - docs/exec-plans/active/0058-host-neutral-install.md:1-84::DONE
- Last green: none
- Open issues: issue-005, issue-006
## Decisions
- Runtime and project versions are reported separately; project version comes from the selected project's lock, runtime version from the runtime lock.
- Manifest skill entries are validated against `.agents/skills`; missing listed skills fail doctor and block status readiness.
- Empty `.agents/skills` manifest sections are unhealthy and are not called complete.
## Open questions / blockers
- None
