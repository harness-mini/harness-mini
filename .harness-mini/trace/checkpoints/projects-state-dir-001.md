---
plan: projects-state-dir
seq: 001
stage: done
ctx_pct_at_checkpoint: 0
prev: none
---
## Done
- v0.13.0 released: zero-intrusion install (plans 0059/0060, PRs #79/#81, issues #78/#80). The project holds only `.harness-mini/`, one marked `AGENTS.md` block and the host's skills/agents dirs (listed in `.git/info/exclude`).
- v0.14.0 released: per-project state moved to `$HARNESS_HOME/projects/<project-id>/` (plan 0061, PR #83, issue #82), migrated automatically and idempotently from the 0.13.0 flat layout.
- Cursor skills now install to `.cursor/skills` (host-aware `agent install`).
- Garden sweep (14 checkpoints since the last sweep) on `chore/garden-v0.14.0`:
  - Docs: `docs/cursor-getting-started.md` points at `.cursor/skills`; `docs/walkthrough.md` sample output shows v0.14.0; README and ARCHITECTURE now mention `harness.sh diff` and the runtime downgrade guard (`update --force`).
  - Code: `read_version` helper replaces nine copies of `tr -d ' \t\r\n' < VERSION`; dead `target_agent_dirs` removed; a stale plan path comment in `_harness_lib.sh` fixed.
  - AGENTS.md reviewed: still a map, nothing to demote.
  - Backlog: new open items for the long `cmd_status` / `cmd_doctor` functions; `gardened-at:` re-stamped.
- CHANGELOG `[0.14.0]` has an `### Upgrading` note (run the 0.14.0 `init.sh` first).
## Now
- Nothing in flight. The sweep edits are uncommitted on `chore/garden-v0.14.0`, pending review and commit.
## Next (resume here)
- Review and commit the garden sweep, then pick the next plan from the open items below.
- Layered config overrides (tool defaults, then project-level shared config, then user-local config), still open in `.harness-mini/trace/garden-backlog.md`.
- The three minor L1 items in `.harness-mini/trace/evals/projects-state-dir-001.md`: doctor gives no hint at the old flat dir when migration fails; a TOCTOU race between the `-e` check and `mv`; the runtime-name guard can never trigger.
- The four known limitations from the 0059 plan: no uninstall CLI; `.git/info/exclude` is per-directory; a subdir project-id or a moved project orphans its state dir; Claude-only `tools:`/`model:` frontmatter in non-Claude role files; `report` misses traces for paths with spaces.
- Manually verify that hosts reading `.agents/skills` really do (unverified).
## Task state
- Acceptance: plan 0061 ACs 4/4 met (L1 pass, projects-state-dir-001 eval); the sweep adds no new acceptance work.
- Footprint: none
- Last green: `bash tests/run.sh` with a temp `HARNESS_HOME`; the pre-sweep baseline was 961 pass / 0 fail.
- Open issues: none
## Decisions
- The sweep is behavior-preserving only; anything bigger is recorded in the garden backlog instead of fixed inline.
- Released history (past CHANGELOG sections, completed plans, evals) was not edited; the only CHANGELOG edit is the 0.14.0 `### Upgrading` note.
## Open questions / blockers
- none
