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
- Delete-first: stop copying executable harness scripts into project `bin/`; remove Cursor rule generation and remove clean legacy harness scripts during migration.
- Riskiest assumption: a user-level runtime under `$HOME/.harness-mini` can serve multiple projects while project-specific agent selection, lock checksums, and skill layouts remain isolated and deterministic.

## Problem
`init.sh` currently copies harness executables into each project's `bin/`, fixes installed skills and agents under `.claude/`, and emits Cursor rules that point back to `.claude/skills`. The result is project pollution and tooling-specific coupling. The user wants the shell runtime centralized at `~/.harness-mini`, explicit host adapters (`claude` and `cursor`), Cursor skills at `.cursor/skills`, and lock/update/doctor/status behavior tied to the chosen project layout.

## PRD
- Goal: install the harness runtime once per user at `$HOME/.harness-mini`; leave no harness-owned executables in project `bin/`; install skills using the explicitly selected agent's native project layout; keep update and diagnostics project-aware.
- Out of scope:
  - Automatically identifying every agent product from shell environment variables; unknown or absent identity must never be guessed.
  - Adding support for hosts other than Claude and Cursor in this change.
  - Removing user-authored project files or user-edited legacy harness scripts.
  - Changing the lifecycle, workboard schema, or the content of skills except path references needed for the new layout.
- Chosen behavior: `init.sh --agent claude|cursor`; if omitted, prompt only on an interactive terminal; otherwise fail before project mutation and print valid options. An agent may choose the host and pass it explicitly. `$HOME/.harness-mini` is the default runtime location; `HARNESS_HOME` is an override for tests and nonstandard installations. A project lock records its selected host and per-project managed file checksums. The runtime command receives an explicit project root (with `HARNESS_ROOT` override); project routing examples use the user-level executable.
- Layout: Claude gets `.claude/skills/` and `.claude/agents/`; Cursor gets `.cursor/skills/` and no generated `.cursor/rules/`. Project-level docs, plans, manifest, and trace remain project data. Cursor receives only skills unless an established native agent-file layout is verified separately.

## Acceptance criteria
- [ ] `init.sh --agent claude|cursor` installs/refreshes executable runtime files under `$HOME/.harness-mini` (or `HARNESS_HOME` in tests); no fresh install creates project `bin/` for harness scripts.
- [ ] Missing/unknown agent selection never mutates project files: TTY prompts with supported choices; non-TTY exits with usage naming `--agent claude|cursor`.
- [ ] Claude skills/agents land under `.claude/skills` and `.claude/agents`; Cursor skills land under `.cursor/skills`; Cursor install does not generate `.cursor/rules`.
- [ ] Each project's lock records host/layout and checksums for that project's managed files; update uses that project's selected adapter, preserves edited files as `.new`, and cannot redirect another project's update.
- [ ] `doctor` and `status` work when invoked from the centralized runtime with an explicit project root; skill count/readiness checks use the selected host layout and report missing/invalid selection clearly.
- [ ] Upgrade migration removes only legacy project `bin/` files whose current checksum matches the old lock baseline; modified files are preserved and no longer treated as centrally managed executable files.
- [ ] Regression coverage exercises Claude, Cursor, unknown host, two independent project roots, clean/edited legacy migration, update conflict behavior, doctor, and status; `bash tests/run.sh` passes.
- [ ] README, getting-started docs, routing gates, walkthrough, manifest wording, and changelog no longer instruct users to run `bin/harness.sh` from project `bin/` or describe Cursor skills as rules.

## Issues
1. **Central runtime and project-root contract** — Add a stable `$HOME/.harness-mini` runtime install/update path and make commands operate on an explicit project root. No project `bin/` creation on fresh installs. Files: `init.sh`, `bin/harness.sh`, `bin/_harness_lib.sh`, tests. Depends-on: none. Done = failing tests prove centralized execution and project isolation; tests pass.
2. **Explicit host selection and adapters** — Add `--agent claude|cursor`, interactive-only selection when omitted, and no-mutation failure for unknown/noninteractive ambiguity. Map Claude skills/agents and Cursor skills; remove Cursor rule generation. Files: `init.sh`, `bin/_harness_lib.sh`, tests. Depends-on: #1. Done = adapter layout and selection tests pass.
3. **Per-project lock and update routing** — Record selected host/layout in project metadata/lock and use the matching target map for install/update/checksums; retain guarded conflict semantics. Files: `bin/_harness_lib.sh`, `bin/harness.sh`, tests. Depends-on: #2. Done = separate Claude/Cursor roots update independently and edited files produce `.new`.
4. **Centralized doctor/status behavior** — Resolve project root without relying on the executable's parent directory; use selected adapter for skills readiness, counts, manifest checks, and update-conflict discovery. Files: `bin/harness.sh`, `bin/_harness_lib.sh`, tests. Depends-on: #3. Done = doctor/status pass for both layouts and fail/warn usefully for missing metadata.
5. **Safe migration from project `bin/`** — Read the prior lock, remove only checksum-clean harness-owned scripts, preserve modified files, and migrate lock/layout metadata idempotently. Files: `init.sh`, `bin/harness.sh`, `bin/_harness_lib.sh`, tests. Depends-on: #3. Done = clean legacy scripts removed, edited files retained, repeated migration is harmless.
6. **Docs and release-facing cleanup** — Update host setup, command examples, routing gates, manifest and changelog to reflect centralized runtime and native skill paths; remove stale Cursor-rules advice. Files: `README.md`, `docs/*getting-started.md`, `docs/walkthrough.md`, `init.sh`, `CHANGELOG.md`, tests. Depends-on: #4, #5. Done = focused searches find no active instructions for project `bin/harness.sh` or `.cursor/rules` skills.

## Vertical slices (build order)
1. Establish the central runtime + explicit project-root walking skeleton (#1).
2. Install one agent adapter end-to-end and select it explicitly (#2).
3. Persist host-specific managed-file mapping and update safely (#3).
4. Route diagnostics through the same selected mapping (#4).
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
- Begin slice #1 in a coding session: write regression tests for runtime placement and explicit project-root operation before changing implementation.

## Next
- Implement #1 through #6 in listed order; keep the PRD decisions fixed unless code inspection disproves a stated assumption.

## Session Context Handoff
**Last Updated**: 2026-11-06 (Session #1)
**Completed Work**: Feasibility and impact review completed; six implementation issues and their dependencies are recorded. No product code changed.
**Current Blockers / Risks**: Runtime install/update under `$HOME/.harness-mini` needs careful separation from project locks; legacy edited scripts must remain untouched. Implementation begins only after the plan is coding-ready.

## Decisions log
- 2026-11-06: Advanced intake → PRD → issues → implement after confirming install scope, host selection behavior, and checksum-safe legacy migration; implementation order is captured in issues #1–#6.
- 2026-11-06: Runtime lives at `$HOME/.harness-mini` (`HARNESS_HOME` test/installation override); project-specific host and file checksums stay in project lock metadata.
- 2026-11-06: Host selection is explicit (`--agent`); prompt only on TTY, and fail before mutation in noninteractive unknown cases.
- 2026-11-06: Cursor uses `.cursor/skills` and receives no generated rules; only Claude receives `.claude/agents` until a Cursor-native agent-file layout is established.
- 2026-11-06: Migration removes only legacy harness scripts verified unchanged by the old lock; user-edited files are retained.
