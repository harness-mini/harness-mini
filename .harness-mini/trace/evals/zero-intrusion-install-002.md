---
plan: zero-intrusion-install
seq: 002
tier: L2
verdict: pass
criteria: 8/8
grader: evaluator
---
## Evidence

This is round 2. Every run below was done by the evaluator, outside the sandbox,
with a temporary `HARNESS_HOME` (`/tmp/hm-r2b1.*`) and `HARNESS_NO_NET=1`. The
system bash is `/bin/bash` 3.2.57, so every run is also a bash 3.2 check. The
old layouts come from `git archive v0.12.1` (pre-0058) and `git archive HEAD`
(0058). `bash tests/run.sh` reports `Passed: 833 Failed: 0`.

### Round-1 defects re-checked
- **B1 (upgrading v0.12.1 left no working harness) — FIXED.**
  - **`update` run twice.** The second run installs the runtime and globals into
    `$HARNESS_HOME` (`runtime add bin/harness.sh` …). It then moves the plans
    and trace, replaces AGENTS.md with the block, and removes `bin/`, `.claude/`
    and `.cursor/rules`. `agent list` works, and `doctor` reports healthy.
  - **One `update` with the new code** (`bash <new>/bin/harness.sh update --src <new>`
    on a v0.12.1 project) exits 0, `agent list` works, and only `.harness-mini/`,
    AGENTS.md, the leftover `docs/` and the user's own files remain.
  - **`init.sh`** gives the same result, and a second run prints only `skip` lines.
  - **Refusal path.** With a source that has no `bin/harness.sh` and an empty
    home, `update` exits 1 and `init.sh` exits 1. Both print "legacy files …
    were NOT migrated — nothing was moved or removed". A sha snapshot of the
    whole project is identical before and after both commands.
- **M2 (`init.sh` never refreshed an older runtime) — FIXED.**
  - A real 0058 home (0.12.1) with a user-edited `bin/ctx.sh`, followed by the
    new `init.sh`, prints `update user runtime (v0.12.1 -> v0.13.0)` and
    `keep bin/ctx.sh (edited) -> wrote bin/ctx.sh.new`. VERSION and runtime.lock
    become 0.13.0, the edit is preserved, `agent list` works, and status shows
    the migrated board (`recon`, `path: init`).
  - **No downgrade.** A home marked 0.14.0 gets `skip user runtime (v0.14.0 … already current)`, and the bin checksums are unchanged.
- **M1 (real 0058 manifest misread as edited) — FIXED.**
  - The real 0058-generated manifest gives `migr removed generated harness/manifest.md`, and `harness/` is gone.
  - A hand-edited manifest gives `keep harness/manifest.md (edited; not removed)`.
  - Later runs: run 2 prints one line; run 3 prints one summary line (`keep 1 legacy path(s) left as before`).
- **Leftover cleanup — FIXED.**
  - `docs/assets/banner.svg` and `docs/references/*` are removed when they are byte-identical to the shipped copy.
  - Harness docs from an older version that no longer match the shipped copy are kept and summarised once (`keep 7 leftover legacy harness file(s) …`). After that the project no longer looks legacy, so later runs are silent.
  - Generated `.cursor/rules/*.mdc` whose descriptions changed under an old update are now removed (scenario A has no `.cursor/` left).
  - Safety: a rule with an extra body line (`tdd.mdc`, byte-identical afterwards), `alwaysApply: true` (`refactor.mdc`), a custom body under a harness skill name (`evaluate.mdc`), and an unrelated `mine.mdc` are all kept.
- **Global `.new` files — FIXED.** `status` shows `update conflicts: 1 .new file(s) (1 under <home>)`, and `doctor` warns with the same count.
- **CONTRIBUTING — FIXED.** Line 64 now reads `bash init.sh <your project>` … `~/.harness-mini/bin/harness.sh update`.

### Acceptance criteria (regression sweep)
- **`init.sh` footprint** — PASS. In the fresh project `reg proj/my app` (git, package.json, AGENTS.md without a trailing newline, .gitignore), `find` shows only `.harness-mini/{.gitignore,architecture.md,docs/exec-plans/…,trace/…}`, AGENTS.md and package.json. After the claude, codex and copilot installs, `.git/info/exclude` contains `.claude/skills/ .claude/agents/ .agents/skills/ .codex/agents/ .github/agents/`.
- **No docs/, harness/, .trace/, CLAUDE.md, ARCHITECTURE.md or bin/; .gitignore byte-identical** — PASS.
- **AGENTS.md byte-identity and idempotency** — PASS. Removing the block leaves a file `cmp`-identical to the original. Re-running `init.sh` plus the three installs leaves the full snapshot unchanged (files, exclude, state dir).
- **project-id** — PASS. `My Cool App`→`my-cool-app-ghquum5f`, `日本`→`project-8ir11csg`, `/`→`project-cknb81kh`. A symlink and its target give the same id. Ids are stable across calls, and the base36 value matches the round-1 Python reference (`qa7m5cl8`).
- **New paths everywhere; two projects isolated** — PASS. The two projects get separate state dirs (`my-app-9vbtjrmz`, `my-app-a33dgvh1`). Updating one leaves the other's skills untouched, and the other picks up the change only on its own `update`. The prose sweep is clean, and `bash -n` passes on all scripts.
- **`agent list` / `install` / unknown hosts** — PASS. All 5 codex `.toml` files are valid TOML (checked with Python tomllib, evaluator side only). Copilot files are named `<name>.agent.md`. `muse`, `hermes` and `bogus` leave the snapshot unchanged.
- **Legacy migration** — PASS (see B1, M1, M2 and the leftover cleanup above).
- **Tests, docs, VERSION** — PASS. 833 tests pass. VERSION is 0.13.0. The CHANGELOG bootstrap note now describes the working paths and the refusal gate.
- **`update` refreshes globals and project targets** — PASS. A clean global is updated, an edited global gets a `.new`, the change propagates to `.claude`, `.agents`, `.codex` (toml re-rendered) and `.github`, an edited project skill gets a `.new`, and a second run reports "already flagged".
- **Edge cases** — PASS. A `HARNESS_HOME` path with spaces, and a minimal environment (`env -i`, PATH=/usr/bin:/bin), both upgrade v0.12.1 and run `agent install`, `doctor` and `status`.

## Remaining defects (all minor — no blocker or major)
- **N1** — If the runtime's `bin/harness.sh` was edited in an old home, `init.sh` writes `harness.sh.new` but keeps the old script. The migration then refuses (exit 1, project untouched) on every run. The refusal says "get the new harness-mini and run init.sh", which the user just did; it should say to resolve `bin/harness.sh.new`.
  Repro: 0058 home, `echo '# local' >> $HARNESS_HOME/bin/harness.sh`, then run the new `init.sh`.
- **N2** — `update` has no downgrade guard, unlike `init.sh`.
  - `update --src <older>` replaces a 0.13.1 runtime with 0.12.1. That runtime has no `agent` command and reads the old paths.
  - Running `update` with no `--src` clones GitHub main, so it downgrades the same way whenever upstream is older than the local install. That is the case today: origin is at v0.12.1.
  - Repro: `HARNESS_HOME=<0.13 home> harness.sh update --src <git archive HEAD>` (VERSION 0.12.1) prints `runtime update bin/harness.sh`, and VERSION becomes 0.12.1.
- **N3** — The relaxed Cursor-rule match deletes a generated `.mdc` whose only edit is the `description:` line, and reports it as `removed unchanged`. Body edits are safe. Edited rules that are kept are not reported.
- **N4** — Harness docs that were pristine in an older version, but changed upstream since, can never be removed automatically; they are kept and summarised once. This is safe, but leaves 7 to 10 files in `docs/` after a typical upgrade.

## Accepted known limitations (not graded as defects)
- No uninstall CLI; the AGENTS.md block is removed with the library function `agents_block_remove` only.
- `.git/info/exclude` lists whole host dirs (`.claude/skills/`, `.github/agents/` …), so user-authored files there are hidden from `git status`.
- The project-id comes from the working directory, so running from a subdirectory resolves another id or state dir; moving a project orphans its state dir.
- Non-Claude role files (Copilot `.agent.md`, Cursor) keep Claude-only `tools:` and `model:` frontmatter verbatim.
- `harness.sh report` misses traces when the project path contains a space (`for f in $glob`; already present in v0.12.1).
