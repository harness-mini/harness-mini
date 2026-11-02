---
plan: session-init
seq: 001
tier: L0
verdict: pass
criteria: 5/5
grader: main
---
## Evidence
L0 self-check — every criterion is a file-content fact, each covered by its own
assertion in tests/run.sh ("source repo — session-init skill" group):
1. PASS — skills/session-init/SKILL.md exists; opens with "Confirm the path"
   (`path: init` via `bin/harness.sh status`); branches compose founder-check /
   to-prd / to-issues (twin, all passes:false), explorer (recon), stage
   finishing, twin repair; done-criteria section present; ends with checkpoint.
2. PASS — "No product code — not even a 'quick fix'" + explicit "plan-stage
   write ban" section (asserted by two greps).
3. PASS — anti-self-praise: grep for flip/set-passes-true instructions = 0;
   skill states stage-viewer owns advancement and the main agent flips passes
   only after an evaluator verdict.
4. PASS — 12 presence/content/catalog assertions, including the AGENTS.md
   skills list mention (the repo's catalog).
5. PASS — `bash tests/run.sh`: Passed: 233 Failed: 0 (group verified red
   before the skill existed: 11 failures).

Skill follows repo conventions: frontmatter name/description, ~55 lines,
map-not-encyclopedia, no always-on dump (progressive disclosure via
AGENTS.md listing only).
