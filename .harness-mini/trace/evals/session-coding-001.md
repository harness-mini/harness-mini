---
plan: session-coding
seq: 001
tier: L0
verdict: pass
criteria: 5/5
grader: main
---
## Evidence
L0 self-check — every criterion is a file-content fact with its own assertion
(tests/run.sh "source repo — session-coding skill + Getting Bearings" group):
1. PASS — skills/session-coding/SKILL.md exists; the FIRST `## ` section is
   "Getting Bearings (first turn — before any product code)" (asserted by
   extracting the first section heading); all five locked steps present
   (pwd · status+`git log --oneline -5`+latest checkpoint · twin
   `"passes": false` selection preferring `next:` · baseline with
   stop-on-regression · "selected slice" report to the user).
2. PASS — baseline ≠ harness installer: skill names `init.sh`, calls it the
   harness installer, forbids re-running it, and allows the app's own
   `./init.sh` (three assertions cover the distinction).
3. PASS — one slice per session; `steps` as never-rewritten test conditions;
   flip-passes-to-true grep = 0 with stage-viewer named as the flipping
   authority; `completed/` history ban; bearings never skipped.
4. PASS — 22 presence/content/catalog assertions incl. the AGENTS.md
   orchestrate listing (group verified red first: 21 failures pre-file).
5. PASS — `bash tests/run.sh`: Passed: 243 Failed: 0.

Live dogfood: the repo's own status printed `path: coding · next slice ready`
for plan 0051 while it was in flight — the exact trigger this skill consumes.
