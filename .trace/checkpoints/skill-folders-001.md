---
plan: skill-folders
seq: 001
stage: done
ctx_pct_at_checkpoint: 38
prev: versioning-001
---
## Done
- All 15 skills migrated to the canonical Agent Skills layout:
  `skills/<name>/SKILL.md` + `.claude/skills/<name>/SKILL.md` (via `git mv`).
- Agents intentionally left flat (`.claude/agents/<name>.md`).
- `emit_managed_pairs()` now recurses `skills/` → lock + `update` track every file
  under a skill folder (incl. future scripts/ references/ …).
- init manifest generator + static `harness/manifest.md` list `<name>/SKILL.md`.
- **Mini constraint** codified: `docs/principles.md` (new top section) + `AGENTS.md`;
  ARCHITECTURE/CONTRIBUTING/README updated.
- tests/run.sh 67→69 (folder-form install/lock/nested-update), all green.
## Now
- Committed/pushed to main; entries sit in CHANGELOG `[Unreleased]`.
## Next (resume here)
- Cut `0.2.0` (`bin/harness.sh release 0.2.0`) when the user wants — MINOR,
  pre-1.0 layout change. Existing installs may keep orphaned flat skill files
  (`update` never deletes); fresh install is cleanest.
## Decisions
- Skills-only folders; agents flat. Full rationale:
  `docs/exec-plans/active/0003-skill-folders.md`.
## Open questions / blockers
- none.
