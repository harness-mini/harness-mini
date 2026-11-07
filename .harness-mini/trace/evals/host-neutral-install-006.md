---
plan: host-neutral-install
issue: issue-006
verdict: pass
tier: L2
criteria: 2/2
grader: evaluator
---
## Evidence
- Focused searches across active instructions, README, getting-started guides, walkthrough, manifest, skills, and agent roles found no project-local runtime commands or host-specific skill paths/rules. Historical CHANGELOG entries remain as release history.
- Documentation consistently describes `.agents/skills/`, `harness/agents/`, the per-user `~/.harness-mini/bin/` runtime, and separate project/runtime locks.
- The manifest lists 17 skills and 5 role descriptions, matching source directories. Checkpoint helper root discovery is covered by regression tests.
- Independent L2 evaluator ran `bash tests/run.sh`: 372 passed, 0 failed. `git diff --check` passed.
