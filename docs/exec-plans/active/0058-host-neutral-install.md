---
plan: host-neutral-install
seq: 0058
stage: implement
owner: main
mode: full
eval: L2
---
# Host-neutral install and project-isolated runtime

## Intake
- Delete-first: stop copying executable harness scripts into project bin/; remove host-specific skill/rule generation; remove clean legacy host-specific artifacts during migration.
- Riskiest assumption: a user-level runtime under `$HOME/.harness-mini` can serve multiple projects while the global runtime lock and project-specific host/layout locks remain isolated and deterministic.

## Problem
init.sh currently copies harness executables into each project's bin/, fixes skills under .claude/, and emits Cursor rules that point back to .claude/skills. The result is project pollution and host-specific coupling. The user wants the runtime centralized at ~/.harness-mini and all skills managed at the shared, open-compatible .agents/skills path without detecting or selecting an agent host.

## PRD
- Goal: install the harness runtime once per user at $HOME/.harness-mini; leave no harness-owned executables in project bin/; install all skills into one shared .agents/skills directory for every agent; keep update and diagnostics project-aware.
- Out of scope:
  - Detecting, prompting for, or branching on the current agent host.
  - Generating host-specific skill mirrors or rules such as .claude/skills, .cursor/skills, or .cursor/rules.
  - Removing user-authored project files or user-edited legacy harness scripts.
  - Changing the lifecycle, workboard schema, or the content of skills except path references needed for the new layout.
- Chosen behavior: init.sh has no agent argument and performs no host detection or prompt. Every skill installs recursively to .agents/skills/. Sub-agent role descriptions install as neutral project data under harness/agents/. The installer does not generate CLAUDE.md or .cursor/rules; shared instructions come from AGENTS.md. $HOME/.harness-mini is the default runtime location; HARNESS_HOME is an override for tests and nonstandard installations. The global runtime lock records executable/source files and version. Each project lock records checksums for the shared project layout; no host field is needed. update --root <project> refreshes the central runtime and syncs that project's common files; two lock scopes must not overwrite each other. The runtime command receives an explicit project root (with HARNESS_ROOT override).
- Layout: source skills map to .agents/skills/; role descriptions map to harness/agents/. No generated host-specific skill or routing files are written. Project-level docs, plans, manifest, and trace remain project data.

## Acceptance criteria
- [ ] init.sh installs/refreshes executable runtime files under $HOME/.harness-mini (or HARNESS_HOME in tests); no fresh install creates project bin/ for harness scripts.
- [ ] All skills and nested resources install under .agents/skills for every invocation, without host arguments, prompts, or detection.
- [ ] Fresh installs do not generate .claude/skills, .cursor/skills, .cursor/rules, or CLAUDE.md; role descriptions are available under harness/agents.
- [ ] Each project's lock records checksums for the common managed files and no host identity; update preserves edited files as .new and cannot redirect another project's update.
- [ ] The global runtime lock and each project lock have distinct ownership; runtime self-update does not write runtime checksums into a project lock, and project update cannot overwrite another project's adapter state.
- [ ] doctor and status work when invoked from the centralized runtime with an explicit project root; skill count/readiness checks use .agents/skills and report missing skills clearly.
- [ ] Upgrade migration removes only legacy project `bin/` files whose current checksum matches the old lock baseline; modified files are preserved and no longer treated as centrally managed executable files.
- [ ] Regression coverage exercises the common layout, two independent project roots, clean/edited legacy migration, update conflict behavior, doctor, and status; bash tests/run.sh passes.
- [ ] README, getting-started docs, routing instructions, walkthrough, manifest wording, and changelog no longer instruct users to run bin/harness.sh from project bin/ or describe skills as host-specific.

## Issues
1. **Central runtime and project-root contract** — Add a stable `$HOME/.harness-mini` runtime install/update path, a user-level runtime lock, and make commands operate on an explicit project root. No project `bin/` creation on fresh installs. Files: `init.sh`, `bin/harness.sh`, `bin/_harness_lib.sh`, tests. Depends-on: none. Done = failing tests prove centralized execution and project isolation; tests pass.
2. **Shared skill installation path** — Install source skills at .agents/skills without host selection or detection; put role descriptions at harness/agents; remove host-specific skill/routing generation. Make doctor/status and the optional session runner recognize the shared skill directory. Files: init.sh, bin/_harness_lib.sh, bin/harness.sh, bin/session.sh, AGENTS.md, tests. Depends-on: #1. Done = tests prove common paths and no host-specific generated files.
3. **Separate lock scopes and common-path update routing** — Keep runtime version/checksums in the user-level lock; track common project files in each project lock. Retain guarded conflict semantics. Files: bin/_harness_lib.sh, bin/harness.sh, tests. Depends-on: #2. Done = two roots update independently, runtime self-update does not alter project lock ownership, and edited files produce .new.
4. **Diagnostic hardening** — Resolve project root consistently and report shared skills readiness, manifest health, and runtime/project versions without host metadata. Files: bin/harness.sh, bin/_harness_lib.sh, tests. Depends-on: #3. Done = doctor/status report the same common layout and handle missing skills clearly.
5. **Safe migration from legacy project files** — Read the prior lock; remove only checksum-clean harness-owned bin scripts, skills under .claude/skills, and generated .cursor/rules; preserve modified files; migrate to the common layout idempotently. Files: init.sh, bin/harness.sh, bin/_harness_lib.sh, tests. Depends-on: #3. Done = clean legacy files removed, edited files retained, repeated migration harmless.
6. **Docs and release-facing cleanup** — Update command examples, routing instructions, manifest, and changelog for centralized runtime and common .agents/skills; remove stale host-specific skill guidance. Files: README.md, docs/*getting-started.md, docs/walkthrough.md, init.sh, CHANGELOG.md, tests. Depends-on: #4, #5. Done = focused searches find no active project-bin commands or host-specific skills/rules instructions.

## Vertical slices (build order)
1. Establish the central runtime + explicit project-root walking skeleton (#1).
2. Install the common .agents/skills layout end-to-end without host selection (#2).
3. Persist common managed-file mapping and update safely (#3).
4. Harden diagnostics around the common project layout (#4).
5. Migrate legacy installs without deleting edited user files (#5).
6. Update all user-facing docs and run integration evaluation (#6).

## Parallel groups
- Sequential: #1 → #2 → #3 → #4.
- Sequential after #3: #5 (shares installer, lock, and update behavior).
- Final integration: #6 after #4 and #5; docs and acceptance search are coupled to final behavior.

## Evaluation
- Tier: L2 — install layout, migration behavior, and managed-file/update contract span multiple subsystems and carry data-loss risk.
- Separate evaluator checks all acceptance criteria after implementation.

## Now (resume here)
- Begin issue-005: safely migrate lock-clean legacy project bin scripts, host-specific skill folders, and generated Cursor rules; preserve edits.

## Next
- Implement #5 and #6 in listed order; keep the PRD decisions fixed unless code inspection disproves a stated assumption.

## Session Context Handoff
**Last Updated**: 2026-11-06 (Session #5)
**Completed Work**: Issues 001–004 passed L2. Runtime/project locks are separate; skills use .agents/skills; doctor/status accept explicit project roots and report runtime/project versions, shared skill count, manifest health, and named missing skills. Missing listed skills block readiness; empty manifests are reported as unhealthy. Full suite: 356 passed, 0 failed.
**Current Blockers / Risks**: Checksum-safe migration of legacy project bin scripts and host-specific files remains for issue-005.

## Decisions log
- 2026-11-06: Advanced intake → PRD → issues → implement after confirming install scope, host selection behavior, and checksum-safe legacy migration; implementation order is captured in issues #1–#6.
- 2026-11-06: Runtime lives at `$HOME/.harness-mini` (`HARNESS_HOME` test/installation override); global runtime version/checksums and project-specific host/file checksums use separate lock scopes.
- 2026-11-06: User replaced the unstarted host-adapter issue with one shared .agents/skills layout; no host detection, prompt, or adapter argument.
- 2026-11-06: All skills use .agents/skills; role descriptions are ordinary harness project data at harness/agents; no host-specific routing or skill files are generated.
- 2026-11-06: Migration removes only legacy harness scripts verified unchanged by the old lock; user-edited files are retained.
- 2026-11-06: issue-001 passed L2; runtime refresh remains in the later update slice so this slice only establishes the central install and root/lock boundaries.
- 2026-11-06: issue-002 passed L2; the central session runner defaults project root to the invoking working directory, and shared skill discovery uses .agents/skills.
- 2026-11-06: issue-003 passed L2; project locks track only managed project data, runtime lock owns executable checksums/version, and self-update defers replacing the running script until the final step.
- 2026-11-06: issue-004 passed L2; doctor/status use the selected project root and report shared skill inventory, manifest completeness, and separate runtime/project versions. Missing manifest-listed files block status readiness.
