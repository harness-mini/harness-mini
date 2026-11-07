---
plan: host-neutral-install
seq: 007
stage: checkpoint
ctx_pct_at_checkpoint: 24
prev: host-neutral-install-006
---
## Done
- Issue-006 passed independent L2 evaluation. README, AGENTS.md, architecture, getting-started guides, walkthrough, smart/dumb guidance, skills, roles, manifest, and changelog now describe shared `.agents/skills/` and `harness/agents/` paths with executables in the user runtime.
- Active documentation search found no project-local runtime command examples or host-specific skill paths/rules guidance. Full suite: 372 passed, 0 failed; `git diff --check` passed.

## Now
- All six slices passed L2. The exec plan is ready to archive after this checkpoint.

## Next (resume here)
- Move `0058-host-neutral-install.md` and `.json` from `active/` to `completed/`, set stage/status to done, and run status/doctor.

## Task state
- Acceptance: issue-001 through issue-006 met.
- Footprint:
  - README.md:1-265::DONE
  - AGENTS.md:1-160::DONE
  - docs/exec-plans/active/0058-host-neutral-install.md:1-96::DONE
  - docs/exec-plans/active/0058-host-neutral-install.json:1-14::DONE
- Last green: none
- Open issues: none
## Decisions
- All agent hosts use the same `.agents/skills/` directory; no detection, selection, or host adapter is part of installation.
- Harness executables stay in `~/.harness-mini/bin/`; runtime and project locks remain separate.
- User-edited legacy project scripts remain preserved during migration, as recorded in issue-005.
## Open questions / blockers
- This checkout's ignored `.agents/skills/` mirror is stale and lacks `parallel-slices`; local status remains readiness-blocked until the mirror is refreshed. Clean-install manifest and regression coverage are correct.
