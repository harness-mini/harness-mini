---
plan: host-neutral-install
seq: 001
stage: implement
ctx_pct_at_checkpoint: unknown
prev: none
---
## Done
- Feasibility and impact review recorded in the active plan.
- Six issues are ordered; plan is coding-ready and points to issue-001.
- No product code changed.
## Now
- Workboard is at issue-001 with `passes: false`; coding session must begin with its required bearings before editing.
## Next (resume here)
- Start issue-001 by writing tests for `$HOME/.harness-mini` runtime placement, absence of project `bin/`, and explicit project-root operation.
## Task state
- Acceptance: planning complete; implementation issues 001–006 open.
- Footprint: none
- Last green: none
- Open issues: issue-001, issue-002, issue-003, issue-004, issue-005, issue-006
## Decisions
- Runtime lives at `$HOME/.harness-mini`, with `HARNESS_HOME` as an override.
- Global runtime checksums/version and each project's selected adapter/file checksums use separate lock scopes.
- Host selection is explicit (`claude` or `cursor`); interactive prompt only on TTY; fail before mutation otherwise.
- Cursor gets `.cursor/skills` and no generated rules; Claude gets `.claude/skills` and `.claude/agents`.
- Migration removes only old harness executables that match the legacy lock checksum; preserve edited files.
## Open questions / blockers
- The repository instructions require committed checkpoints, but the current sandbox denies writing `.git/index`; the plan/checkpoint files remain in the workspace pending an approved commit.
