---
plan: session-runner
seq: 001
tier: L0
verdict: pass
criteria: 7/7
grader: main
---
## Evidence
L0 self-check — machine-checkable criteria, each with its own assertion group
(tests/run.sh "bin/session.sh — Outer session runner"):
1. PASS — path-aware selection: coding board injects the session-coding body
   (Getting Bearings present, status-first preserved); init board injects
   session-init ("plan session") with ZERO bearings mentions. Both skills
   installed in both fixtures, so selection is path-driven, not
   whichever-file-exists.
2. PASS — single source: bodies are `cat`ed verbatim from the landed SKILL.md
   (frontmatter stripped — presentation only); wrapper is 4 generic lines and
   deliberately does not preview skill content (an earlier wrapper wording
   leaked "Getting Bearings" into init prompts and was caught by the
   invariant).
3. PASS — `-- <cmd>` mode delivers byte-identical message to stdout mode
   (asserted equal), message as final argument.
4. PASS — fresh context: file count on the board unchanged after a run; the
   runner persists nothing.
5. PASS — vendor-neutral: no claude/cursor/codex invocation in the script
   (excluding the harness's own `.claude/skills` install-layout path) and no
   session-start-hook dependency.
6. PASS — docs: walkthrough §9 "Unattended runs" states optional P2, not
   required for core, with host examples living in docs only; script header
   repeats it; CHANGELOG entry recorded.
7. PASS — `bash tests/run.sh`: Passed: 288 Failed: 0 (group verified red
   first: 8 failures pre-implementation).

Live dogfood: run in the source repo mid-plan, the runner selected
session-coding for plan 0053's own coding-ready board — the playbook that
built it.
