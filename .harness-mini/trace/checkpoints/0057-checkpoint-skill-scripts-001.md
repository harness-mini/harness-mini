---
plan: 0057-checkpoint-skill-scripts
seq: 001
stage: issues
ctx_pct_at_checkpoint: 8
prev: none
---
## Done
- Confirmed the checkpoint helpers are consumed by the checkpoint skill and located current documentation and test references.
- Defined the migration slice and acceptance criteria in the active plan.
## Now
- Plan is ready to enter implementation; the session path gate still needs to be advanced to coding.
## Next (resume here)
- Move the three helpers into skills/checkpoint/scripts/, update callers/docs/tests, and run bash tests/run.sh.
## Task state
- Acceptance: all open; implementation not started
- Footprint: none
- Last green: none
- Open issues: slice-001
## Decisions
- Keep the helper behavior unchanged and make the scripts skill-owned.
## Open questions / blockers
- none
