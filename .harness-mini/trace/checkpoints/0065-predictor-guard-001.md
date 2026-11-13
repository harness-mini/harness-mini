---
plan: predictor-guard
seq: 001
stage: checkpoint
ctx_pct_at_checkpoint: 34
prev: none
---
## Done
- Both slices committed on `feat/0065-predictor-guard`: slice-001
  (`predictor_warning` + unconditional group-index init + `PREDICTED_TOTAL`
  footer comparison + `predictor-guard` group, 7 asserts; TDD red 5/7 →
  green 7/7; the red run itself exposed the lazy-init placement bug),
  slice-002 (README counts → `--list` pointer).
- Eval L1 **PASS 5/5** → `.harness-mini/trace/evals/0065-predictor-guard-001.md`
  (negative probe on a doctored temp clone: real run warned AND stayed exit 0).
- Suite: **1010 asserts / 0 fail**, `--list` total 1010, 50 groups; full-run
  stdout delta = new banner + 7 ok lines + summary only; zero drift warnings
  on the real tree.
- **Archive check dogfooded at archival: exit 0** (0064's verifier, second use).

## Now
- Plan advancing checkpoint→done; PR to main next.

## Next (resume here)
- Push branch, open PR; after merge (with garden PR #96), the next garden
  sweep clears two backlog items: README-pointer (0065 slice-002 landed it)
  and predictor-drift (0065 slice-001 landed the eval's suggested hardening).

## Task state
- Acceptance: 5/5 criteria met (evidence: evals/0065-predictor-guard-001.md)
- Footprint: tests/run.sh:449-463::DONE
  - tests/run.sh:482-502::DONE
  - tests/run.sh:3123-3141::DONE
  - tests/groups.tsv:83-84::DONE
- Last green: `bash tests/run.sh` → Passed: 1010  Failed: 0 (builder + evaluator independent runs)
- Open issues: none

## Decisions
- Warning-only, non-blocking: exit contract stays "exit = tests"; drift is an
  observability bug, not a test failure.
- Group index now built on every path (was lazy: only args/--list) — required
  for the footer comparison on full runs; no output change (byte-delta proven).
- Backlog clearances deferred to next sweep (PR #96 conflict avoidance).

## Open questions / blockers
- none
