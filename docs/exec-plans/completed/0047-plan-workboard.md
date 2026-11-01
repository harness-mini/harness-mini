---
plan: plan-workboard
seq: 0047
stage: done
owner: main
mode: full
eval: L1
issue: 52
---
# Dual JSON+MD exec-plans (machine workboard) + status-first routing gate — full mode

> Implements #52. This plan dogfoods the very format it introduces: it keeps a
> JSON twin (`0047-plan-workboard.json`) whose slices are flipped to
> `passes: true` as this work lands.

## Intake
- Existing project → recon done in-session (init.sh / harness.sh / templates /
  skills all read before planning).
- Delete-first pass: nothing to delete — but the OLD gate markers
  (`harness-mini:start/end`) and the old `version`-first session directive are
  *replaced*, not duplicated. One gate, ever.
- Riskiest assumption: agents will actually run `harness.sh status` first —
  mitigated by the gate living in every always-on entry file (CLAUDE.md,
  .cursor rules, AGENTS.md).

## Problem
Plan state lives only in MD frontmatter + prose. A cold-start agent must read
whole MD files to find "what's next", violating progressive exposure; there is
no machine-readable per-slice state, so nothing can point at *the next slice*
mechanically. Meanwhile session-start guidance is scattered across three
wordings (`version` in AGENTS.md gate, gate in CLAUDE.md, cursor rule).

## PRD (run `to-prd`)
- Goal: a cold-start agent (or human) runs one command — `bin/harness.sh status`
  — and sees the workboard: active plans, their JSON status, current slice, and
  the next slice with `passes: false`.
- Out of scope (deliberately deleted): no jq/runtime dependency, no TUI, no
  plan-history migration (completed/ plans stay MD-only), no per-slice evaluator
  ceremony beyond existing tiers.

## Acceptance criteria
- [ ] `docs/templates/` documents the dual-file rule (same basename) + JSON
      schema + `## Session Context Handoff` section; demo plan
      `docs/examples/demo-auth/` shows a paired `.md`/`.json`.
- [ ] `harness.sh status` prints per-plan workboard lines (status, current
      slice, next `passes:false` slice) parsed from JSON with awk only; graceful
      (no breakage) when a JSON twin is absent.
- [ ] `harness.sh doctor` warns — never fails — on missing/unparseable JSON twin.
- [ ] `init.sh` injects the `HARNESS_ROUTING_GATE_BEGIN/END` block idempotently;
      an install carrying the old `harness-mini:start/end` block gets it
      replaced in place (still exactly one gate).
- [ ] AGENTS.md carries exactly one routing-gate section, status-first, with the
      Repository Map additions.
- [ ] `to-issues`, `checkpoint`, `stage-viewer`, `evaluate` skills state the
      dual-file contract (who creates the twin, who refreshes the handoff, who
      flips `passes` — main agent, only after an evaluator verdict).
- [ ] `bash tests/run.sh` green including new tests for all of the above.
- [ ] CHANGELOG `[Unreleased]` entry; README/walkthrough consistent.

## Issues (run `to-issues`)
1. templates+schema — files: `docs/templates/full-plan.md`, `docs/templates/quick-plan.md`, `docs/examples/demo-auth/*` — depends-on: none
2. status workboard — files: `bin/harness.sh`, `tests/run.sh` — depends-on: none
3. installer gate v2 — files: `init.sh`, `tests/run.sh` — depends-on: none
4. agent map — files: `AGENTS.md` — depends-on: none
5. skills contract — files: `skills/to-issues/`, `skills/checkpoint/`, `skills/stage-viewer/`, `skills/evaluate/` — depends-on: none
6. changelog sweep — files: `CHANGELOG.md`, `docs/walkthrough.md` — depends-on: 1–5

## Vertical slices (build order)
1. slice-001 docs/templates → slice-002 bin workboard (parsing proves the schema)
   → slice-003 installer gate → slice-004 AGENTS.md → slice-005 skills →
   slice-006 changelog sweep.

## Evaluation
- Tier: L1 lightweight (separate context). Machine checks: `bash tests/run.sh`;
  grep-level checks for one-gate-only in AGENTS.md/CLAUDE.md fixtures.

## Now (resume here)
- DONE. L1 verdict: pass 8/8 (`.trace/evals/plan-workboard-001.md`); reviewer's
  clean-code findings applied (doctor twin bar unified, migration guarded,
  comment + CHANGELOG fixes) with the suite re-run green. Plan moves to
  `docs/exec-plans/completed/` in PR for #52.

## Next
- (none — completed)

## Session Context Handoff

**Last Updated**: 2026-11-01 (Session #2)
**Completed Work**: all six slices implemented and independently evaluated
(L1, 8/8 PASS); clean-code findings applied post-verdict; 6/6 slices
`passes: true`; final suite green.
**Current Blockers / Risks**: none.

## Decisions log
- 2026-11-01: init.sh stays the additive installer; gate upgraded in place with
  new markers + migration (replaces old block) — user-approved.
- 2026-11-01: AGENTS.md gate sections merged (one gate, status-first) — user-approved.
- 2026-11-01: dual-track state — MD frontmatter `stage:` remains FSM authority
  (eval-gate untouched); JSON `status` mirrors planned|in_progress|done;
  `slices[].passes` flips to true only via main agent after evaluator verdict —
  user-approved.
- 2026-11-01: naming keeps the repo's 4-digit seq (`0047-slug`); the rule that
  matters is same-basename pairing. Completed/ legacy plans stay MD-only.
- 2026-11-01: init.sh now excludes `docs/exec-plans/` when copying docs/ — the
  source repo's own plans must never seed a fresh install (surfaced by the new
  workboard fixture).
- 2026-11-01: mid-flight `passes` policy for THIS dogfood plan: slices 1–5 flip
  on per-slice machine evidence (full suite green after each slice, L0-grade);
  the L1 evaluator audits all six and gates slice-006 (and the plan stage).
