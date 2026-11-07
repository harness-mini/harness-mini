---
plan: host-neutral-install
issue: issue-003
verdict: pass
tier: L2
criteria: 3/3
grader: evaluator
---
## Evidence
- Two project roots update independently through `.agents/skills`; updating the first leaves the second project's lock and content unchanged until its own update.
- Runtime self-update installs the upstream executable and records runtime version/checksums in `harness/runtime.lock`; project locks contain no `bin/` records.
- Edited runtime executables remain intact and upstream content is written to `.new`; project-managed edit conflict behavior is also covered.
- Independent evaluator ran `bash tests/run.sh`: 337 passed, 0 failed. `bash -n` and `git diff --check` passed. No actionable clean-code concerns.
