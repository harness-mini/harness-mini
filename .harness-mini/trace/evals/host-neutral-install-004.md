---
plan: host-neutral-install
issue: issue-004
verdict: pass
tier: L2
criteria: 2/2
grader: evaluator
---
## Evidence
- Doctor and status invoked through the centralized runtime with `--root` report the selected project's workboard and do not rely on the runtime install directory for project state.
- Both commands report runtime/project versions, shared skill count, and manifest health. Missing manifest-listed skills are named; doctor fails and status readiness becomes blocked. Empty skill manifests are reported as unhealthy rather than healthy.
- Independent evaluator ran `bash tests/run.sh`: 356 passed, 0 failed. Shell syntax and `git diff --check` passed.
