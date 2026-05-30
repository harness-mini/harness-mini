---
plan: skill-folders
seq: 0003
stage: done
owner: main
---
# Skill-folder layout + the Mini constraint

## Problem
Skills are flat files (`skills/<name>.md`, `.claude/skills/<name>.md`). The
canonical Anthropic Agent Skills format — and how Claude Code actually discovers
project skills — is a folder per skill: `<name>/SKILL.md` (required, metadata in
frontmatter) plus optional `scripts/ references/ assets/ examples/ tests/`. Fix
the layout, and codify the core iteration constraint: **Mini — shell-or-doc
first, no complex languages or environment dependencies.**

## Decisions
- Each skill → `skills/<name>/SKILL.md` and `.claude/skills/<name>/SKILL.md`
  (mirror). Frontmatter `name:` already matches the folder name for all 15.
- **Agents stay flat** (`.claude/agents/<name>.md`) — that is the correct Claude
  Code subagent format; the folder form is skills-only.
- Optional subdirs (`scripts/`, `references/`, …) are **not** scaffolded now
  (Mini: don't add empty structure). Shared scripts stay in `bin/`, referenced by
  skills — not duplicated into skill folders.
- `emit_managed_pairs()` must **recurse** `skills/` so the lock + `update` track
  every file under each skill folder (not just top-level `*.md`).
- Layout change is pre-1.0, so a MINOR bump (0.2.0) when released; old flat
  `.claude/skills/*.md` in existing installs become orphans — a fresh install or
  manual cleanup is cleanest (update never deletes).

## Acceptance criteria
- [x] Every skill is `skills/<name>/SKILL.md` (+ `.claude/skills/<name>/SKILL.md`).
- [x] `emit_managed_pairs()` recurses skills; a folder-form skill is installed by
      `init.sh` AND recorded in `harness/harness.lock`.
- [x] `harness.sh update` refreshes a nested `skills/<name>/SKILL.md` correctly.
- [x] init manifest + static `harness/manifest.md` list `<name>/SKILL.md`.
- [x] Mini constraint codified in `docs/principles.md` + surfaced in `AGENTS.md`;
      ARCHITECTURE/CONTRIBUTING/README updated to the folder layout.
- [x] Tests written first; full `tests/run.sh` green (69/69).

## Now (resume here)
- DONE. 15 skills migrated; Mini constraint codified. 69/69 green; dogfood install
  verified (15 folder skills tracked in lock + manifest). Sitting in CHANGELOG
  `[Unreleased]` — bump to 0.2.0 when the user wants to cut a release.

## Next
- Optional: `bin/harness.sh release 0.2.0` (MINOR — layout change, pre-1.0).

## Decisions log
- 2026-05-30: layout is skills-only folders; agents stay flat; Mini constraint
  added as a first-class principle.
- 2026-05-30: TDD — install already recursed (copy_tree); the failing tests were
  lock + nested-update, fixed by recursing `skills/` in `emit_managed_pairs()`.
- 2026-05-30: evaluate gate = `tests/run.sh` 69/69 + dogfood install. Stage=done.
