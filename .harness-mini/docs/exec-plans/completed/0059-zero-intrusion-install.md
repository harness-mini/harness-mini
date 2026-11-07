---
plan: zero-intrusion-install
seq: 0059
stage: done
owner: main
mode: full
eval: L2
---
# Zero-intrusion install: split harness-owned vs project-progress files

## Intake
- Delete-first: stop writing harness docs, lock, manifest, `.trace/`, `ARCHITECTURE.md`, whole-file `AGENTS.md`, and `.gitignore` edits into the user's project tree.
- Riskiest assumption: a single marked block in the project's root `AGENTS.md` is enough for agents to find `~/.harness-mini` and obey the routing gate.

## Principle
Two classes of file:
- **Harness-owned, independent of project progress** → `~/.harness-mini/` (global) or `~/.harness-mini/<project-id>/` (per-project bookkeeping).
- **Project-progress, must be recorded** → `<project>/.harness-mini/` (committed, except `trace/runtime/`).

## Decisions (user-confirmed 2026-11-06)
1. **AGENTS.md**: append a `<!-- harness-mini:begin/end -->` block to the project root `AGENTS.md` (create a minimal file containing only the block if none). The full map lives at `~/.harness-mini/AGENTS.md`. Uninstall removes only the block. **No CLAUDE.md, ever.**
2. **ARCHITECTURE.md**: harness lifecycle part → `~/.harness-mini/docs/ARCHITECTURE.md`; project recon output → `<project>/.harness-mini/architecture.md`. The project's own `ARCHITECTURE.md` is never touched.
3. **skills** are installed per host (revised): `harness.sh agent install <host>` picks the skills dir from the host table. Hosts that natively read `.agents/skills` share it (one copy); others get their native dir (e.g. `.claude/skills`, `.qoder/skills`, `.zcode/skills`, `.trae/skills`, `.codebuddy/skills`). `init.sh` itself installs no skills/agents (it does not know the host); the AGENTS.md block tells the agent to run `harness.sh agent list` then `agent install <host>` when skills are missing.
4. **agents** (role descriptions): the running agent states its host; a deterministic script maps host → target dir and installs. Reverses 0058's "no host detection" for skills and agents. Unknown / unsupported host → script prints the source path and instructions and the host agent installs them itself. Supported hosts: Antigravity, Codex, Cursor, Claude Code, Qoder, zcode, Kimi, DeepSeek harness, pi, opencode, Grok, GitHub Copilot, MiMo Code, Trae, Muse, Hermes, CodeBuddy (mapping table verified from official docs before coding; unverifiable → `unknown`).
5. **project-id** = `<project-name>-<8 chars [0-9a-z]>`; name = lowercase-hyphenated basename; 8 chars = base36 of sha256(absolute project path). Moving a project changes its id (documented trade-off).
6. **Per-project** `harness.lock` + `manifest.md` → `~/.harness-mini/<project-id>/`.
7. **Static docs** (principles, smart-dumb, assumptions, templates, walkthrough, examples, getting-started) → `~/.harness-mini/docs/` only; never copied into projects.
8. **Project progress** → `<project>/.harness-mini/{docs/exec-plans/{active,completed}, trace/{checkpoints,evals,garden-backlog.md,runtime}, architecture.md}`. `.harness-mini/.gitignore` ignores `trace/runtime/`; the project `.gitignore` is never edited.
9. **Git hygiene**: installed `.agents/skills/` and per-host agent dirs are added to `.git/info/exclude` (local, no project file change).
10. **docs/references/ and docs/assets/banner.svg** move to source-repo root (`references/`, `assets/`); never installed or locked.
11. **Migration**: automatic on `update`/`init`; moves `docs/exec-plans` and `.trace` into `.harness-mini/`; lock-verified harness docs/AGENTS/ARCHITECTURE/`harness/` files are removed when unchanged; edited files and existing targets are kept and reported.
12. **Source repo dogfoods** the `.harness-mini/` layout; its `docs/` is distribution source only.

## Acceptance criteria
- [ ] `init.sh` writes in the project only `.harness-mini/`, the AGENTS.md marker block, and `.git/info/exclude`; after `agent install <host>` it also writes that host's skills/agents dirs.
- [ ] No project `docs/`, `harness/`, `.trace/`, `CLAUDE.md`, `ARCHITECTURE.md`, `bin/` created; project `.gitignore` byte-identical.
- [ ] Existing project AGENTS.md content outside the marker block is byte-identical after install and after uninstall of the block; re-install is idempotent.
- [ ] project-id algorithm deterministic, 8-char suffix, safe for odd names.
- [ ] trace.sh, ctx-hook.sh, harness.sh (doctor/status/report/update), session.sh, and all skills use the new paths; two projects stay isolated.
- [ ] `harness.sh agent` lists hosts, installs for a named host, and prints self-install instructions for unknown hosts.
- [ ] Legacy layout migrates automatically; edited files preserved; repeat run harmless.
- [ ] `bash tests/run.sh` passes; README/getting-started/walkthrough/changelog updated; VERSION bumped (0.13.0).

## Issues
1. **project-id + layout resolver** — `bin/_harness_lib.sh`: `project_id`, `project_dir`, `state_dir` helpers; `HARNESS_ROOT`/`HARNESS_HOME` contract. Depends-on: none.
2. **Progress files to `.harness-mini/`** — trace.sh, ctx-hook.sh, harness.sh readers, init seed plans, inner `.gitignore`, `.git/info/exclude`. Depends-on: #1.
3. **AGENTS.md block + global map/docs split** — marker-block writer/remover, global `AGENTS.md`/`docs/ARCHITECTURE.md`, project `architecture.md`, no CLAUDE.md; static docs global. Depends-on: #1.
4. **Lock/manifest per project under `~/.harness-mini/<id>/`**; managed set = skills + agents only. Depends-on: #1, #3.
5. **Host-aware agents install** — deterministic `harness.sh agent list|install <host>`; table verified from official docs; unknown → instructions. Depends-on: #4.
6. **Source repo reshuffle** — move `docs/references`, `docs/assets` to root; remove from managed set; dogfood `.harness-mini/` layout; rewrite skill/doc path references. Depends-on: #2, #3.
7. **Automatic legacy migration** — move plans/trace, remove lock-clean legacy files, report conflicts. Depends-on: #2–#4.
8. **Docs, changelog, version, L2 evaluation**. Depends-on: #5–#7.

## Vertical slices (build order)
1 → 2 → 3 → 4 → 5, then 6 → 7 → 8 (sequential: all share init.sh / harness.sh / lib).

## Host mapping (researched 2026-11-06 from official docs; pending user confirmation)
Format: MD + YAML (`name`, `description`) unless noted. `skills?` = natively reads `.agents/skills`.

| host | agents dir | format | skills? | confidence |
|---|---|---|---|---|
| antigravity | `.agents/agents/` | md | yes | high |
| codex | `.codex/agents/` | **toml** (`name`,`description`,`developer_instructions`) | yes | high |
| cursor | `.cursor/agents/` | md | yes | high |
| claude | `.claude/agents/` | md | **no** (`.claude/skills` only) | high |
| qoder | `.qoder/agents/` | md | unverified | high / low |
| zcode | `.zcode/agents/` | md | yes | medium (project-level not in official docs) |
| kimi | `.kimi-code/agents/` (or `.agents/agents/`) | md (`description` required) | yes | high (Kimi Code 2.x) |
| deepseek (dsh) | `.dsh/agents/` (3rd-party plugin convention, user-confirmed) | md | yes | low |
| pi | `.pi/agents/` | md | yes | medium (extension convention) |
| opencode | `.opencode/agents/` | md (`description` required) | yes | high |
| grok | `.grok/agents/` | md | yes | high / medium |
| copilot | `.github/agents/` | `<name>.agent.md` | yes | high |
| mimo | `.mimocode/agents/` | md (opencode-style) | yes | high |
| trae | `.trae/agents/` | md (beta toggle; skills toggle) | toggle | high |
| muse | none (spawned dynamically) | — | yes | high |
| hermes | none (profiles) | — | **no** | medium |
| codebuddy | `.codebuddy/agents/` | md | **no** | high |

Self-id hints (env): claude `CLAUDECODE=1`, codex `CODEX_THREAD_ID`, cursor `CURSOR_AGENT=1`, opencode `OPENCODE=1`, pi `PI_CODING_AGENT=true`, generic `AI_AGENT`. The agent still states its host explicitly; env vars are only a hint.

Skills dir rule: `.agents/skills` where the host reads it natively, else the host's native skills dir. Claude Code, CodeBuddy, Qoder, Hermes do not read `.agents/skills` → native dir (Hermes: unknown → self-install fallback). zcode `.zcode/*` and pi `.pi/agents/` confirmed by the user.

## Decisions log
- 2026-11-06: skills made host-aware like agents; dsh uses `.dsh/agents/`; zcode/pi dirs confirmed; Muse/Hermes → self-install fallback.
- 2026-11-06: scope and 12 decisions above confirmed by the user. Host mapping research delegated to a sub-agent.

- 2026-11-07 (post-merge-prep): user verified Cursor loads skills from `.cursor/skills`, not `.agents/skills`; host table row for cursor corrected to `.cursor/skills`.

## Evaluation
- L2 round 1 (`zero-intrusion-install-001`): fail — B1 blocker (v0.12.1 upgrade removed project bin without a runtime), M1/M2 major. Fixed.
- L2 round 2 (`zero-intrusion-install-002`): **pass**, 8/8, 4 minor open (N1 .new hint wording, N2 `update` has no downgrade guard, N3 `.mdc` description-only edit reported as unchanged, N4 stale legacy docs left after upgrade).
- Accepted known limitations: no uninstall CLI; `.git/info/exclude` is per-directory; project-id from a subdirectory differs / moved project orphans its state dir; Claude-only `tools:`/`model:` kept in non-Claude role files; `report` misses traces for paths with spaces (pre-existing).
