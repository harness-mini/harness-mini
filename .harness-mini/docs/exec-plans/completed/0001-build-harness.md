---
plan: build-harness
seq: 0001
stage: done
owner: main
---
# Build harness-mini (worked example)

A real exec-plan, kept as a worked example of the format. This plan tracked the
initial build of harness-mini itself.

## Problem
Need a minimal, CLI-agnostic agent harness encoding the best practices from the
Anthropic, OpenAI, and Founder's Playbook references — convention + skills +
sub-agents + thin shell glue, not a program.

## Acceptance criteria
- [x] `bin/*` scripts implemented test-first; `tests/run.sh` green.
- [x] `init.sh` additive + idempotent, new-vs-existing asymmetry.
- [x] Smart/dumb = 40% occupancy contract documented + enforced (ctx.sh).
- [x] 13 skills + 5 tiered sub-agents with per-agent skill scoping.
- [x] 4 references distilled to `docs/references/*-llms.txt`.
- [x] Self-install (dogfood) succeeds and re-runs idempotently.

## Out of scope (deleted via five-step)
- Published npm/global CLI (violates "mini"; install is an agent action).
- Perfect token counting (best-effort estimate is enough).
- Full OpenAI docs/ scale (product-specs/, generated/) until a project needs it.

## Vertical slices (build order, all done)
1. scaffold → 2. bin TDD → 3. init.sh → 4. core docs → 5. skills+agents →
6. references → 7. dogfood.

## Decisions
- Native `.claude/` install + neutral `harness/manifest.md` mirror.
- `.trace/` split: `checkpoints/` committed, `runtime/` gitignored.
- Model tiers: explorer/gardener=haiku, planner/generator=sonnet, evaluator=opus.
- FSM transition authority mode C: only main agent advances stages.
