---
plan: session-runner
seq: 0053
stage: done
owner: main
mode: quick
eval: L0
issue: 61
---
# bin/session.sh — Outer session runner (P2, optional) — quick mode

## Problem
Unattended/scripted long runs need Outer to FORCE the matching session-*
playbook into a fresh context each session — without SessionStart hooks or a
vendor agent API in the Mini kernel (discussion #55 P2 → #61).

## Acceptance criteria
- [ ] Runner selects the skill from `status`'s `path:` line and injects that
      skill's body verbatim (single source: `.claude/skills/` then `skills/`;
      no forked prompt text — only a short generic wrapper)
- [ ] `-- <host-cmd...>` mode passes the message as the host command's final
      argument; default mode prints to stdout (vendor-neutral)
- [ ] Fresh context: the runner persists nothing (no files written to the board)
- [ ] No SessionStart-hook or vendor dependency (script is standalone POSIX sh)
- [ ] README/docs state this is optional P2, not required for Mini core
- [ ] Tests: coding board → session-coding body; init board → session-init
      body; `--` mode == stdout mode; nothing written; vendor-free script
- [ ] `bash tests/run.sh` green

## The change
- `bin/session.sh` (~70 lines POSIX sh): status → path → skill body (frontmatter
  stripped) + 4-line wrapper → stdout or `-- cmd…` exec.
- Walkthrough subsection "Unattended runs" (examples live in docs, script
  stays vendor-free); CHANGELOG entry.

## Evidence (fill on completion)
- Red first: 8 assertions failed pre-implementation.
- Post: `bash tests/run.sh` → Passed: 288 Failed: 0 (path-driven selection
  with both skills present in fixtures · verbatim body · -- mode ==
  stdout mode · no files written · vendor/hook-free script).
- L0 eval record: `.trace/evals/session-runner-001.md` (pass 7/7).
- Live dogfood: run mid-plan in the source repo, the runner selected
  session-coding for plan 0053's own board.
- Two invariant catches during build: wrapper wording leaked "Getting
  Bearings" into init prompts (reworded); CHANGELOG briefly grew a duplicate
  ### Changed heading (caught by the same awk check the evaluator used,
  fixed before commit).

## Session Context Handoff
**Last Updated**: 2026-11-02 (Session #1)
**Completed Work**: slice-001 done — bin/session.sh + walkthrough §9 +
CHANGELOG; 288/288; L0 pass 7/7.
**Current Blockers / Risks**: none. bin/* is in the managed set, so the
  runner ships with installs automatically.

## Decisions
- Script (not doc-only) because it must execute; POSIX sh, no deps, no vendor
  tokens (vendor examples go in docs only).
- Frontmatter stripped (presentation, not forking); body injected verbatim.
- Interactive path (gate+skills) remains authoritative; the runner is a
  convenience wrapper, explicitly P2.
