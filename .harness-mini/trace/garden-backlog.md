# Garden backlog — deferred smells (committed debt)
<!-- gardened-at: 21 -->

## Open
- [ ] 2026-11-07 | Layered config overrides (tool defaults → project-level shared config → user-local config) so users never edit the install dir; today edited install files only produce .new + diff notice. | medium | generator (plan 0060)
- [ ] 2026-11-08 | bin/harness.sh:cmd_status/cmd_doctor/cmd_update (~213/148/95 lines) | long-function | med | Extract Function per report section / check group, one command at a time under green tests (plan 0062)
- [ ] 2026-11-13 | tests/run.sh `--list` predictor (static loop expansion) drifts silently: unrecognized helper counts 0, `while read` clamps to 1, no self-test asserts predicted==actual | low | Assert `--list` total == dynamic PASS count, or warn when a selected run's `Passed:` != its `--list` row (eval 0063 minor finding)

## Cleared
- [x] 2026-08-11 | cadence reset after session-ops completion | gardener
- [x] 2026-11-08 | stale docs: cursor-getting-started `.agents/skills` → `.cursor/skills`, walkthrough sample v0.14.0, README/ARCHITECTURE now cover `diff` + downgrade guard | gardener
- [x] 2026-11-08 | duplication: 9 copies of `tr -d ' \t\r\n' < VERSION` → `read_version` | gardener
- [x] 2026-11-08 | dead code: unused `target_agent_dirs`; stale `exec-plans/active/0059` comment → `completed/` | gardener
- [x] 2026-11-13 | bin/harness.sh:cmd_status/cmd_doctor/cmd_update long-function → extracted dispatchers, shipped v0.15.1 via plan 0062 | gardener
