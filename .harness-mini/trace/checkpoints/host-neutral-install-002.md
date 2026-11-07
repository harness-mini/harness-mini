---
plan: host-neutral-install
seq: 002
stage: implement
ctx_pct_at_checkpoint: unknown
prev: host-neutral-install-001
---
## Done
- issue-001 passed the independent L2 evaluation (3/3).
- Runtime executables install under HARNESS_HOME; fresh project installs no longer create bin/.
- Runtime executable checksums use harness/runtime.lock; project locks exclude executable paths.
- Central harness commands accept --root and isolate workboards between projects.
- Full suite passed: 350 passed, 0 failed.
## Now
- Workboard is at issue-002, passes:false. Issue-001 is the only slice marked passed.
## Next (resume here)
- In a new coding session, complete Getting Bearings and start issue-002 with failing tests for agent selection, native skill paths, and no-mutation behavior on unknown/noninteractive selection.
## Task state
- Acceptance: issue-001 met; issues 002–006 remain open.
- Footprint
  - bin/_harness_lib.sh:18-50::DONE
  - init.sh:142-169::DONE
  - bin/harness.sh:13-37::DONE
  - bin/harness.sh:640-662::DONE
  - tests/run.sh:127-155::DONE
  - tests/run.sh:459-480::DONE
- Last green: none
- Open issues: issue-002, issue-003, issue-004, issue-005, issue-006
## Decisions
- The central runtime and per-project files have separate checksum locks.
- Runtime refresh and agent-adapter mapping are left to later issues.
- The project root can be supplied as --root or HARNESS_ROOT; absent either, the CLI uses the current directory.
## Open questions / blockers
- None for issue-001.
