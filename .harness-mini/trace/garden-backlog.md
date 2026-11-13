# Garden backlog — deferred smells (committed debt)
<!-- gardened-at: 23 -->

## Open
- [ ] 2026-11-07 | Layered config overrides (tool defaults → project-level shared config → user-local config) so users never edit the install dir; today edited install files only produce .new + diff notice. | medium

## Cleared
- [x] 2026-11-13 | predictor-drift: footer now compares --list predictions vs actual executions, warning-only (plan 0065, PR #97; eval 5/5 incl. doctored-clone negative probe) | main
- [x] 2026-11-13 | README assertion-count literal → `bash tests/run.sh --list` pointer (plan 0065 slice-002, PR #97) | main
- [x] 2026-08-11 | cadence reset after session-ops completion | gardener
- [x] 2026-11-08 | stale docs: cursor-getting-started `.agents/skills` → `.cursor/skills`, walkthrough sample v0.14.0, README/ARCHITECTURE now cover `diff` + downgrade guard | gardener
- [x] 2026-11-08 | duplication: 9 copies of `tr -d ' \t\r\n' < VERSION` → `read_version` | gardener
- [x] 2026-11-08 | dead code: unused `target_agent_dirs`; stale `exec-plans/active/0059` comment → `completed/` | gardener
- [x] 2026-11-13 | bin/harness.sh:cmd_status/cmd_doctor/cmd_update long-function → extracted dispatchers, shipped v0.15.1 via plan 0062 | gardener
