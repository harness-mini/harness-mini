---
plan: host-neutral-install
issue: issue-005
verdict: pass
tier: L2
criteria: 2/2
grader: evaluator
---
## Evidence
- Lock-matching legacy bin scripts are removed; clean `.claude/skills` files move under `.agents/skills`. Edited files and legacy files with no lock evidence are preserved.
- Cursor routing and per-skill rule files are removed only when their bytes match the prior generated templates. Edited rules and unrelated rules remain.
- Repeated install is idempotent; an empty legacy project `bin/` is removed. Symlinked executables/rules are preserved.
- Independent evaluator ran `bash tests/run.sh`: 370 passed, 0 failed. Shell syntax and `git diff --check` passed. No actionable clean-code concerns.
