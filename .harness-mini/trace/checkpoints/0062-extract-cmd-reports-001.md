---
plan: extract-cmd-reports
seq: 001
stage: checkpoint
ctx_pct_at_checkpoint: 23
prev: none
---
## Done
- All three slices committed on `refactor/0062-extract-cmd-reports`:
  `5f34384` (cmd_status → 19-line dispatcher + 10 section fns),
  `69f9ee0` (cmd_doctor → 29-line dispatcher + 10 check fns),
  `b1098b7` (cmd_update → 22-line dispatcher + 6 step fns)
- `bash tests/run.sh` 975/0 green before, after each extraction, and final (independently re-run by evaluator)
- status/doctor/version/update outputs byte-identical to frozen pins (recipe: `.harness-mini/trace/runtime/0062-baseline/fixture.sh`)
- Eval L1 **PASS 4/4** → `.harness-mini/trace/evals/0062-extract-cmd-reports-001.md`

## Now
- Plan advancing checkpoint→done; MD+JSON moving to `completed/`; PR to main next.

## Next (resume here)
- Push branch `refactor/0062-extract-cmd-reports`, open PR; after merge the next garden sweep clears the backlog item (annotated `plan 0062`).

## Task state
- Acceptance: 4/4 criteria met (evidence: evals/0062-extract-cmd-reports-001.md)
- Footprint: bin/harness.sh:289-310::DONE
  - bin/harness.sh:672-700::DONE
  - bin/harness.sh:954-972::DONE
- Last green: `bash tests/run.sh` → Passed: 975  Failed: 0 (evaluator independent run on the branch)
- Open issues: none

## Decisions
- Cross-section values write back via shell dynamic scoping, documented in each dispatcher (slice-001); `emit()` kept nested verbatim, `fails`/`warns` write-back native (slice-002)
- Downgrade guard + version banner stayed inline in `cmd_update` (plan rule: no guard logic moves); `.new`/checksum flow moved whole as `update_apply_pairs`; deferred self-swap write-backs left bare so the swap still fires (slice-003)
- `update.txt` pin required freezing the update `--src` input via `git archive` snapshot — naive pinning was caught by the double-capture determinism check

## Open questions / blockers
- none
