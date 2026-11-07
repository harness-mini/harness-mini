---
plan: zero-intrusion-install
seq: 001
tier: L2
verdict: fail
criteria: 7/8
grader: evaluator
---
## Evidence

All evidence below was produced by the evaluator, running outside the sandbox.
Every run used a temporary `HARNESS_HOME` (`/tmp/hm-*`) plus `HARNESS_NO_NET=1`;
the real `~/.harness-mini` was never touched. Old layouts were rebuilt from git:
`git archive HEAD` gives the 0058 layout (unreleased; `main` is 8 commits ahead
of `origin/main`), and `git archive v0.12.1` gives the pre-0058 layout, which is
the only released one.

### Acceptance criteria
- **`init.sh` writes only `.harness-mini/`, the AGENTS.md block and `.git/info/exclude`; `agent install` adds the host dirs** — PASS.
  Fresh project `/tmp/hm-e2e-proj.*/my app` (git init, package.json, custom AGENTS.md with no trailing newline, .gitignore).
  After `init.sh`, `find` shows only `.harness-mini/{.gitignore,architecture.md,docs/exec-plans/{active/0001-recon.{md,json},completed},trace/{checkpoints,evals,runtime}}` plus AGENTS.md.
  After `agent install claude|codex|copilot`, the project also has `.claude/{skills,agents}`, `.agents/skills`, `.codex/agents/*.toml` and `.github/agents/*.agent.md`.
  `.git/info/exclude` gains exactly `.claude/skills/ .claude/agents/ .agents/skills/ .codex/agents/ .github/agents/`.
- **No project `docs/`, `harness/`, `.trace/`, `CLAUDE.md`, `ARCHITECTURE.md` or `bin/`; `.gitignore` byte-identical** — PASS (`cmp .gitignore orig` → identical; the `find` inventory has none of these).
- **AGENTS.md outside the block is byte-identical after install and removal; re-install is idempotent** — PASS.
  On the e2e file, `agents_block_remove` gives `cmp` identical to the original (unterminated last line).
  Six more shapes also round-trip byte-identically through add, add again and remove: empty/absent, trailing blank line, CRLF, a single `\n`, and normal text.
  A full re-run of `init.sh` plus the three `agent install` calls gives an identical snapshot (sha of every file, the exclude file and the state dir). Caveat: removal exists only as a library function; there is no user-facing uninstall (see m4).
- **project-id is deterministic, has an 8-char suffix and is safe for odd names** — PASS.
  `My Cool App`→`my-cool-app-4xw9abo9`, `日本語プロジェクト`→`project-am3opxr1`, `---`→`project-…`, `/`→`project-cknb81kh`, a 60-char name is truncated to 40.
  A symlink and its target give the same id (`real-2pjsw8iq`, including via `cd link; project_id .`). Every id matches `^[a-z0-9-]+-[0-9a-z]{8}$` and is stable across calls.
  The suffix matches a Python reference (`sha256 mod 36^8`) for 3 paths. The `shasum` and `sha256sum` digests agree. awk precision is safe (r·16 < 2^53).
- **trace.sh, ctx-hook.sh, harness.sh (doctor/status/report/update), session.sh and all skills use the new paths; two projects stay isolated** — PASS.
  In the e2e project, `trace.sh` and `ctx-hook.sh` write to `.harness-mini/trace/runtime/`.
  `report` counts them in a project path without spaces. (In "my app" it shows 0 because of a word-splitting bug that already existed in v0.12.1; not a regression.)
  `session.sh` picks `session-init`. `status` and `doctor` are healthy.
  A second project `my-app` gets its own state dir `my-app-hrjsoo4x` next to `my-app-dk67h999`. Editing a skill in A then running `update` in both gives a `.new` only in A ("1 .new" in A, "0" in B).
- **`harness.sh agent` lists hosts, installs for a named host, and prints self-install instructions for unknown hosts** — PASS.
  `agent list` prints 17 rows that match the plan's host table.
  The 5 codex `.toml` files parse as valid TOML (checked with Python tomllib, by the evaluator only) and contain exactly `name`, `description` and `developer_instructions`.
  Copilot files are named `<name>.agent.md`.
  `muse`, `hermes` and `frobnicate` print the instructions, exit 0, and leave the project and state dir unchanged (snapshot diff empty).
- **Legacy layout migrates automatically; edited files preserved; repeat run harmless** — FAIL. See B1, M1, M2 and m1. Plans, trace and edited files are preserved and conflicts keep both copies (p58i: `0002-feat.md` exists in both places). But the documented upgrade path for released v0.12.1 installs strips the install, and the real 0058 manifest is misread as edited.
- **`bash tests/run.sh` passes; README/getting-started/walkthrough/changelog updated; VERSION is 0.13.0** — PASS. `Passed: 710 Failed: 0`. VERSION is 0.13.0. The README Install commands and walkthrough §0 output reproduce verbatim in a temp home. The CHANGELOG bootstrap note is inaccurate (M2).

### Slice steps
- issue-001 — PASS (project-id probes above; `state_dir` → `$HARNESS_HOME/<id>`, `progress_dir` → `<root>/.harness-mini`).
- issue-002 — PASS (paths, `.harness-mini/.gitignore` = `trace/runtime/`, project .gitignore identical, exclude stays idempotent across re-installs).
- issue-003 — PASS (block round-trip; fresh project gets only the block; no CLAUDE.md/ARCHITECTURE.md; map and docs under `$HARNESS_HOME`; `architecture.md` under `.harness-mini/`).
- issue-004 — PASS (`harness.lock` and `manifest.md` only in the state dir; lock lists only skills and roles; an edited `.claude/skills/tdd/SKILL.md` gives `.new` on update).
- issue-005 — PASS (see the agent criterion).
- issue-006 — PASS (`references/` and `assets/` are at the root, with 0 entries in global.lock, runtime.lock or the project lock and none under the install home. The sweep for `docs/exec-plans`, `.trace/`, `harness/manifest.md`, `harness/harness.lock`, `.claude/skills`, `CLAUDE.md`, `docs/references` and `docs/assets` is clean outside history, migration code and the host table. `status` and `doctor` in the source repo with a temp home are healthy, with 1 warning about the missing manifest).
- issue-007 — FAIL (B1, M1, M2, m1).
- issue-008 — FAIL (this L2 evaluation fails; the CHANGELOG bootstrap note points at broken paths).

### update refreshes globals and project targets — PASS
With a modified source (0.13.1), `update` in the e2e project:
- overwrites the clean globals (`skills/garden`, `docs/smart-dumb.md`, `agents/planner.md`);
- keeps the locally edited global `docs/principles.md` and writes `principles.md.new`;
- propagates the changes to `.claude/skills`, `.agents/skills`, `.claude/agents`, `.codex/agents/planner.toml` (re-rendered) and `.github/agents/planner.agent.md`;
- bumps runtime.lock, global.lock and the project lock to 0.13.1.

A second run is a no-op ("already flagged").

## Defects

### B1 — blocker: upgrading v0.12.1 with `update` twice (the CHANGELOG's advice) leaves no working harness
Repro:
```
git archive v0.12.1 | tar -x -C /tmp/src12
mkdir /tmp/p && cd /tmp/p && git init -q && echo '{}' > package.json
bash /tmp/src12/init.sh                                     # released layout, bin/ in the project
export HARNESS_HOME=$(mktemp -d) HARNESS_NO_NET=1
bash bin/harness.sh update --src <0.13.0 checkout>          # old runtime: copies the 0.13 bin/ into the project
bash bin/harness.sh update --src <0.13.0 checkout>          # new code, RUNTIME_ROOT = the project
ls $HARNESS_HOME          # -> only <project-id>/harness.lock (no bin/, docs/, skills/, agents/, AGENTS.md)
ls bin                    # -> No such file or directory (migration removed the lock-clean bin/)
grep harness.sh AGENTS.md # block points at $HARNESS_HOME/bin/harness.sh, which does not exist
```
What happens:
1. `update_runtime` returns early when there is no runtime.lock.
2. `sync_globals` only runs when `$HARNESS_HOME/harness/runtime.lock` exists, so neither installs anything.
3. `migrate_legacy_layout` then deletes the project's `bin/`, `.claude/skills` and `.claude/agents` because they match the lock.

The note also tells the user to run a `harness.sh agent list` that does not exist. The only copy of the new code was in the temporary clone (`update` without `--src` deletes it). Plans survive, but the install is gone.

Fix direction: `cmd_update` (and the migration) must install the runtime and globals into `$HARNESS_HOME` before deleting any legacy executable, or refuse to migrate while running from a project-local runtime.

### M1 — major: a real 0058 `harness/manifest.md` is reported as "edited" and never removed
Repro: run the 0058 `init.sh` (`git archive HEAD`) into a fresh project, then the 0059 `init.sh` with a fresh home.
- The output says `keep  harness/manifest.md (edited; not removed)`, but the file was never touched.
- Every later `init.sh`/`update` prints `keep  legacy harness files (bin/, docs/, ARCHITECTURE.md, .claude/, AGENTS.md) not removed: no harness/harness.lock baseline`. That is misleading: those paths are gone, and the warning fires only because `harness/manifest.md` exists.

Cause: the generated 0058 manifest contains `Skills are under .agents/skills/; role descriptions are under harness/agents/.`, which `legacy_generated_manifest` does not accept. Its whitelist covers only `^Skills and ` and `^Any coding agent `.

The tests in `tests/run.sh:606` use a hand-written manifest without that line, so they stay green.

### M2 — major: `init.sh` never refreshes an existing older runtime, but the CHANGELOG tells users to upgrade by re-running it
Repro: keep a 0058-era `$HARNESS_HOME` (it has a `harness/runtime.lock`), then run the 0.13.0 `init.sh` in a 0058 project.
- The output says `skip  user runtime (already initialized …)`, and `$HARNESS_HOME/VERSION` stays 0.12.1.
- `harness.sh agent list` fails with `unknown command: agent`, although the new AGENTS.md block tells the agent to run it.
- `status` still reads `docs/exec-plans/`, which the migration has already moved, so it shows a wrong board (only the leftover conflict copy, `path_reason: twin missing`).

CHANGELOG 0.13.0 says *"the first run after upgrading must be the new runtime's `init.sh`, or run `update` twice."* With an existing runtime the first path breaks as described; for v0.12.1 the second path is B1.

Only re-running `init.sh` from a v0.12.1 project with no home runtime works. 0058 never shipped, which limits the reach, but the documented instructions are wrong.

### m1 — minor: some legacy leftovers are never reported
- `docs/assets/banner.svg` stays after every migration and no line mentions it, because the hint loop only walks `$HARNESS_HOME/docs` and assets were moved out of it.
- After the old runtime's first `update`, its rewritten lock no longer lists `docs/references/*` (6 files, including a PDF). They stay without a word.
- After that same first `update`, 3 generated `.cursor/rules/{checkpoint,ralph-loop,release}.mdc` stay silently: their skill descriptions changed, so they no longer match byte-for-byte.

### m2 — minor: repeated noise
About 13 `keep docs/… (harness doc without a lock baseline…)` lines are printed on every `init.sh` and `update`, with no end. `docs/principles.md` is reported twice: once as edited and once as having no baseline, even though it has one.

### m3 — minor: whole user-shared directories are hidden from git
`.git/info/exclude` lists entire dirs such as `.claude/skills/`, `.claude/agents/` and `.github/agents/`. Skills or agents the user writes there later become invisible to `git status`. This follows decision 9, but it is risky for the Claude and Copilot directories.

### m4 — minor: no user-facing uninstall
Decision 1 says uninstall removes only the block, but there is no CLI for it; `agents_block_remove` is only a library function.

### m5 — minor: global `.new` files are invisible to `doctor` and `status`
`count_dotnew` only scans the project lock, so a `$HARNESS_HOME/docs/principles.md.new` is never surfaced.

### m6 — minor: misleading status line after a project move
`status` prints `manifest: missing .agents/skills section` when the state dir or manifest does not exist at all. The orphaned state dir also stays behind; this trade-off is documented.

### m7 — minor (already existed)
- Running `harness.sh` or `trace.sh` from a subdirectory resolves another project-id and creates a stray `.harness-mini/trace/runtime` there.
- `report` misses traces when the project path contains a space (`for f in $glob`).

### m8 — minor: Claude-only role fields copied to other hosts
Copilot `.agent.md` and Cursor role files keep `tools: Read, Grep, Glob, Bash` and `model: haiku` verbatim. These values may be invalid for those hosts.

### m9 — minor: stale CONTRIBUTING line
`CONTRIBUTING.md:64` still says "install it (`bin/harness.sh update`)".

### Checked and fine
- Mini constraint: no python, node, jq or other third-party binaries in `bin/`, `init.sh` or `skills/*/scripts`.
- `bash -n` is clean on all scripts. shellcheck is not installed.
- An end-to-end install, `agent install codex` and `doctor` run under macOS `/bin/bash` 3.2.
- The host table matches the plan: `.agents/skills` for antigravity, codex, cursor, kimi, deepseek, pi, opencode, grok, copilot and mimo; native skill dirs for claude, qoder, zcode, trae and codebuddy; muse and hermes are self-install.
