<!-- Thanks! Keep PRs small and focused — one logical change, one concern.
     Full expectations: CONTRIBUTING.md → "Pull request expectations".
     The template pre-fills the PR body once merged to the default branch. -->

## What & why

<!-- One short paragraph: what changes, and *why* (the diff already shows what). -->

Closes #N _(or "no issue — trivial one-liner, explained above")_

## Type

<!-- Check exactly one. Maintainers cut releases via the `release` skill;
     you don't bump VERSION in a PR. -->

- [ ] `docs` — Markdown only, no behavior change
- [ ] `fix` — glue fix in `bin/*` or `init.sh` (PATCH)
- [ ] `feat` — new skill / agent / CLI capability (MINOR)
- [ ] `chore` — tooling, tests, repo hygiene
- [ ] breaking — changes the install layout or the lock contract (MAJOR)

## Checklist

- [ ] **Tests green:** `bash tests/run.sh` (zero dependencies)
- [ ] **TDD for shell:** any behavior change to `bin/*.sh` / `init.sh` ships with
      its failing-test-first companion (`skills/tdd/SKILL.md`)
- [ ] **macOS bash 3.2 safe** — no GNU-only flags, no third-party binaries
- [ ] **Managed-set aware:** touching anything `init.sh` installs → updated
      `emit_managed_pairs()` in `bin/_harness_lib.sh`
- [ ] **`AGENTS.md` stays a map** — a one-line pointer at most, no prose
- [ ] **Docs updated** alongside the change (README / ARCHITECTURE / manifest)
- [ ] **`CHANGELOG.md` `[Unreleased]`** has a user-facing line
- [ ] **Mini constraint:** Markdown or POSIX shell only — no runtime, package
      manager, or third-party dependency added

## Harness lifecycle artifacts (skip if docs-only)

<!-- If this change rode the harness loop, link its records so the reviewer
     can verify against the stated acceptance criteria. -->

- Plan: `docs/exec-plans/…` — stage reached:
- Eval verdict: `.trace/evals/…` (L0 / L1 / L2) —
- Checkpoint: `.trace/checkpoints/…` —

## Reviewers

<!-- @mention the person or team whose area this touches. -->

@reviewer
