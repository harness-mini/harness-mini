---
plan: checkpoint-archive-check
seq: 001
stage: checkpoint
ctx_pct_at_checkpoint: 36
prev: none
---
## Done
- All slices committed on `feat/0064-archive-check`: `8be429b` (docs wiring ×3
  skills), `57940c3` (verifier + 15-assert test group), `de95434` (9 stale
  completed twins 0047–0055 flipped to status done — each pre-verified:
  single in_progress line, zero passes:false), `9bc01b2` (legacy twin
  exemption, seq < 47 / non-numeric, +4 asserts, red→green).
- Eval L1 **PASS 6/6** → `.harness-mini/trace/evals/0064-checkpoint-archive-check-001.md`
  (evaluator-built fixtures; data-repair audited numstat 1/1 × 9; boundary
  proven on real bash 3.2).
- Suite: **1003 asserts / 0 fail** (`--list` total 1003, partition gap-free).
- **Archive check dogfooded at this plan's own archival: exit 0, tree clean.**

## Now
- Plan advancing checkpoint→done; PR to main next.

## Next (resume here)
- Push branch, open PR; evaluator minors (porcelain dir-level naming for
  wholly-untracked dirs; docs could name the twin checks) left as-is — safe
  direction, no backlog item needed.

## Task state
- Acceptance: 6/6 criteria met (evidence: evals/0064-checkpoint-archive-check-001.md)
- Footprint: skills/checkpoint/scripts/checkpoint-archive-check.sh:1-119::DONE
  - tests/run.sh:3005-3110::DONE
  - skills/checkpoint/SKILL.md:61-79::DONE
  - tests/groups.tsv:77-77::DONE
- Last green: `bash tests/run.sh` → Passed: 1003  Failed: 0 (builder + evaluator independent runs)
- Open issues: none

## Decisions
- Hybrid rescope on the generator's course-correct: repair 9 stale twins (real
  board-lies class) + exempt pre-contract plans from the twin requirement
  (check_eval_gate precedent, bin/harness.sh:646) — no fabricated history.
- No doctor wiring this plan; check runs at checkpoint time. Revisit if the
  failure mode reappears.

## Open questions / blockers
- none
