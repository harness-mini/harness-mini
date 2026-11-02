---
plan: seed-twin
seq: 0055
stage: done
owner: main
mode: quick
eval: L0
issue: 64
---
# init.sh seeds carry their JSON twin — quick mode

## Problem
Fresh installs seed `0001-intake.md` / `0001-recon.md` with no JSON twin, so
`doctor` WARNs "no JSON twin" on day one — the installer violates its own
dual-file contract out of the box (#64, #56 soak). Option (a) per the issue:
seed the twin.

## Acceptance criteria
- [ ] fresh install (new mode): `0001-intake.json` seeded; doctor has NO twin
      warning; `status` shows a workboard line for the seed plan
- [ ] fresh install (existing mode): same for `0001-recon.json`
- [ ] tests cover both modes; `bash tests/run.sh` green

## The change
- Beside each seeded MD, write its twin (`status: planned`, empty `slices`) —
  `json_wb` already renders `no slices yet`; walkthrough transcript updated.

## Evidence (fill on completion)
- Red first (shared with 0054's group). Post: 287/287; both install modes
  seed twins; doctor day-one clean; status shows `planned · no slices yet`.
- L0 eval record: `.trace/evals/seed-twin-001.md` (pass 3/3).
- Ripple: older twin-workboard tests now fabricate the legacy no-twin state
  explicitly (fresh installs always have twins) — missing-twin degradation
  coverage preserved.

## Session Context Handoff
**Last Updated**: 2026-11-02 (Session #1)
**Completed Work**: slice-001 done — intake/recon seeds carry twins; walkthrough
  transcript + CHANGELOG updated; L0 pass.
**Current Blockers / Risks**: none.

## Decisions
- `current_slice_id` left empty in seed twins (no slices yet — status prints
  the `no slices yet` line and never reads current for 0-slice boards).
