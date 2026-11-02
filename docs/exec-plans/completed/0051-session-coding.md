---
plan: session-coding
seq: 0051
stage: done
owner: main
mode: quick
eval: L0
issue: 59
---
# session-coding skill + full Getting Bearings — quick mode

## Problem
Coding agents resume with no prior-session memory and: edit the wrong slice,
re-run harness-mini's installer `init.sh` as an "app baseline", or leave half-
open second slices on the board. Need the locked five-step **Getting Bearings**
first-turn recipe inside an on-demand `session-coding` skill for boards where
`status` prints `path: coding` (discussion #55 → #59).

## Acceptance criteria
- [ ] `skills/session-coding/SKILL.md` exists; FIRST section is the mandatory
      Getting Bearings with the five locked steps (pwd · status+git log+
      checkpoint · twin+next slice · app baseline green, ≠ harness `init.sh`,
      stop-on-fail · tell the user the selected slice)
- [ ] Explicit: app check command ≠ harness-mini `init.sh`
- [ ] One slice only · never rewrite JSON `steps` · builder never flips
      `passes` · no `completed/` history loads · bearings never skipped
- [ ] Tests assert skill presence + content + AGENTS.md listing
- [ ] `bash tests/run.sh` green

## The change
- One skill file (English, per the #55 locked text), AGENTS.md orchestrate
  line, CHANGELOG entry, presence/content test group, mirror to `.agents/`.

## Evidence (fill on completion)
- Red first: 21 assertions failed before the skill existed.
- Post: `bash tests/run.sh` → Passed: 243 Failed: 0 (22-assertion group:
  first-section-is-bearings, five steps, init.sh ≠ app baseline, one-slice +
  bans + no-passes-flip, stage-viewer authority, completed/ ban, tdd/
  evaluate/checkpoint composition, path: coding confirm, AGENTS.md catalog).
- L0 eval record: `.trace/evals/session-coding-001.md` (pass 5/5).
- Live dogfood: this repo's status printed `path: coding · next slice ready`
  for plan 0051 while in flight — the exact trigger the skill consumes.

## Session Context Handoff
**Last Updated**: 2026-11-02 (Session #1)
**Completed Work**: slice-001 done — skill written + wired (AGENTS.md
orchestrate line) + CHANGELOG; mirrored to .agents/skills/; 243/243; L0 pass.
**Current Blockers / Risks**: AGENTS.md orchestrate line edited identically-
located by PR #67 — one-line textual conflict expected; #67 merges first,
this branch rebases trivially.

## Decisions
- Full five-step bearings by default (Quick mode deferred per #55 lock).
- Bearings live inside this skill only; gate pointer is #60.
