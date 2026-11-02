---
plan: session-init
seq: 0050
stage: done
owner: main
mode: quick
eval: L0
issue: 58
---
# session-init skill (plan-layer playbook) — quick mode

## Problem
Cold starts on an empty or still-planning board get the same "pick
`passes: false` and code" pressure as implement sessions — skipping
founder/PRD/issues work, inventing product edits early, breaking the
plan-stage write ban. Need an on-demand skill that advances ONLY the plan
layer until `path: coding` is provable (discussion #55 → #58).

## Acceptance criteria
- [ ] `skills/session-init/SKILL.md` exists and states: confirm `path: init`
      from `status`, plan-only writes, compose existing skills
      (founder-check/to-prd/to-issues/explorer/checkpoint), done criteria
- [ ] Explicit ban on product-code edits while on this path
- [ ] Does NOT instruct the builder to flip `passes`
- [ ] Tests assert skill presence + content + AGENTS.md listing
- [ ] `bash tests/run.sh` green

## The change
- One new skill file (English skeleton per #58), AGENTS.md orchestrate line,
  CHANGELOG entry, presence/content test group. Mirror to `.agents/skills/`.

## Evidence (fill on completion)
- Red first: 11 assertions failed before the skill existed.
- Post: `bash tests/run.sh` → Passed: 233 Failed: 0 (12-assertion group:
  presence, path-confirm, product-code ban, composition, write-ban reference,
  no-passes-flip, stage-viewer authority, AGENTS.md catalog).
- L0 eval record: `.trace/evals/session-init-001.md` (pass 5/5).

## Session Context Handoff
**Last Updated**: 2026-11-02 (Session #1)
**Completed Work**: slice-001 done — skill written + wired (AGENTS.md
orchestrate line) + CHANGELOG; mirrored to .agents/skills/; 233/233; L0 pass.
**Current Blockers / Risks**: none. session-coding (#59) and the gate rewrite
(#60) follow; nothing here constrains them.

## Decisions
- Orchestrate-stage skill (a session playbook like stage-viewer/ralph-loop);
  listed in AGENTS.md skills-by-stage — that file is the repo's catalog.
