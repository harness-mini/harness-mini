---
plan: test-selection
seq: 001
stage: checkpoint
ctx_pct_at_checkpoint: 33
prev: none
---
## Done
- All three slices committed on `feat/0063-test-selection`:
  `489be99` (run.sh `@group` tags + selection + `--list`; no-args stdout
  byte-identical to pre-edit pin), `716488c` (`tests/groups.tsv` 76 prefixes +
  `tests/affected.sh` + `test-selection` self-test group), slice-003 docs
  (tdd/checkpoint/evaluate SKILL lines + README Develop block).
- Eval L1 **PASS 6/6** → `.harness-mini/trace/evals/0063-test-selection-001.md`
  (independent re-runs: no-args delta shape exact, selection counts == `--list`
  rows, unknown group exit 2, affected.sh mapping hand-derived cross-check,
  README examples executed literally).
- Suite: **48 groups, 984 asserts**; inner loop 197s → 0.15–17.9s (largest
  group update-polish); full suite 159s (not slower).

## Now
- Plan advancing checkpoint→done; PR to main next.

## Next (resume here)
- Push branch, open PR; after merge the predictor-drift garden item (below) is
  first in the next sweep.

## Task state
- Acceptance: 6/6 criteria met (evidence: evals/0063-test-selection-001.md)
- Footprint: tests/run.sh:1-60::DONE
  - tests/run.sh:2943-3003::DONE
  - tests/affected.sh:1-123::DONE
  - tests/groups.tsv:1-83::DONE
- Last green: `bash tests/run.sh` → Passed: 984 Failed: 0 (evaluator fresh run)
- Open issues: none

## Decisions
- No third-party test framework (Mini constraint); ~150-line POSIX selection on
  the in-house runner. Revisit trigger: runner >~3k lines or TAP/junit need.
- Gates keep the full suite (checkpoint last-green, evaluate, release, CI);
  only the red→green inner loop narrows. Unknown path → `all` fallback.
- `--list` counts are statically predicted executions (loop expansion), not
  grep counts — needed to reach exact totals; drift is currently SILENT →
  garden backlog item (assert `--list` total == dynamic PASS count or warn on
  selected-run mismatch).

## Open questions / blockers
- none
