---
plan: <slug>
seq: <NNNN>
stage: implement
owner: main
mode: quick
eval: L0        # L0 self-check (tiny) or L1 lightweight reviewer; see evaluate skill
---
# <Title> — quick mode

> **Quick mode** = one obvious change, no ambiguity, ≤ ~1 vertical slice. Skip the
> PRD/issues ceremony. Use `docs/templates/full-plan.md` instead if the change is
> ambiguous, cross-cutting, touches architecture, or risks data/security.
> (When unsure, the README first-screen table decides for you.)

## Problem
<One or two sentences: what's broken or missing, and why it matters now.>

## Acceptance criteria
<!-- Keep these machine-checkable so L0 (tests-as-firewall) is honest. Each
     criterion gets its OWN test, gone red→green (see the tdd skill): behavior
     that "happens to pass" without a test of its own is not done. -->
- [ ] <e.g. `bash tests/run.sh` green with a new test for X>
- [ ] <observable behaviour: command/output that proves it>

## The change
- <The single slice / edit. Test-first: write the failing test, then the code.>

## Evidence (fill on completion)
- <test output, observed behaviour — the proof the criteria passed>

## Decisions
- <anything non-obvious; or "none">
