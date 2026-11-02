---
plan: update-self-replace
seq: 0048
stage: done
owner: main
mode: quick
eval: L0
issue: 62
---
# harness.sh update: self-replacement crash — quick mode

## Problem
`harness.sh update` overwrites the running `bin/harness.sh` mid-execution; bash
resumes reading the new file at the old byte offset → `run: unbound variable`,
unclean exit. Blocks the documented upgrade path (#56 soak; filed as #62).

## Acceptance criteria
- [ ] update over a changed `bin/harness.sh` exits 0 with no diagnostics
- [ ] installed `bin/harness.sh` matches the new upstream checksum; lock updated
- [ ] regression test in `tests/run.sh` with fixtures that include `bin/`
- [ ] `bash tests/run.sh` green

## The change
- `cmd_update`: capture pairs into a variable (`while … <<< "$pairs"`, no pipe
  subshell); when the target is the running script (`-ef`), skip the copy and
  remember it; after the lockfile move + log/cleanup, copy it last and
  `exit 0` immediately — the interpreter never reads past the swap.

## Evidence (fill on completion)
- Red first: regression test failed pre-fix (`actual: [2]`, desync diagnostic).
- Post-fix: `bash tests/run.sh` → Passed: 207 Failed: 0, including the new
  group "harness.sh update — replacing the RUNNING script is deferred to exit
  (#62)" (exit 0 · no desync diagnostic · log line · installed == new upstream
  · lock advanced · replaced script still executes).
- End-to-end soak re-run (pre-#53 install → fixed tree): update applies
  correctly, doctor exit 0 — but the *transition* itself still prints the
  error, because the executing (old) script predates the fix. Unfixable from
  our side; recorded in #62. All upgrades from the fixed version onward are
  clean and regression-tested.

## Session Context Handoff
**Last Updated**: 2026-11-02 (Session #1)
**Completed Work**: slice-001 implemented TDD (red→green), 207/207; L0
self-check done; awaiting nothing — plan closes with the PR.
**Current Blockers / Risks**: transition-from-v0.11.0 crash is out of scope
(old running code; harmless, applies cleanly) — noted in #62.

## Decisions
- Fix now rather than defer: #56's "upgraded install behaves as documented" is
  false until the updater stops crashing on its own file.
