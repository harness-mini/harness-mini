---
plan: upgrade-polish
seq: 001
tier: L1
verdict: pass
criteria: 7/7
grader: evaluator
---
## Evidence
All probes ran with a temp `HARNESS_HOME` and temp `HOME` under `/tmp/evalp`. The real `~/.harness-mini` does not exist and was not created. Two source trees were used: A = repo copy at 0.13.0, B = copy at 0.13.1 with changed `bin/ctx.sh`, `bin/model.sh` and `skills/tdd/SKILL.md`. Legacy projects came from `git archive v0.12.1` plus its own `init.sh`.

- **1. `diff` subcommand: PASS.**
  - After `update --src B` with edited runtime, global and project files, `diff bin/ctx.sh` (runtime), `diff skills/tdd/SKILL.md` (global) and `diff .claude/skills/tdd/SKILL.md --root P1` (project) each exit 0 with a labelled `diff -u` (yours vs upstream).
  - It also works with an absolute path, with a `.new` suffix, from another cwd, and with a space in the path.
  - A `.new` identical to the kept file prints "no differences".
  - Errors: no `.new` → exit 1 with a clear message; not found → exit 1; no args or an extra arg → exit 64.
  - `help` documents it.
- **2. `!!` banner: PASS.**
  - `update` and `init.sh` each print exactly one `!!` block when a `.new` exists. It lists every `.new` path (runtime, global, project) and a diff line.
  - A re-run with `.new` files still waiting prints the banner again.
  - The banner is absent on a clean `init.sh`, a re-run, a same-version `update`, and an `update` after the `.new` files were resolved.
  - The printed diff commands were run verbatim and worked: the `HARNESS_HOME=… harness.sh diff …` form, the `--root` form, the `"$HOME/.harness-mini/bin/harness.sh" diff …` form (default home), and the plain `diff -u` form (when `harness.sh.new` exists).
  - With more than 5 files it prints one example line plus a "same form" hint.
- **3. Migration refusal: PASS.**
  - Setup: a v0.12.1 legacy project, plus a temp home holding the v0.12.1 runtime with an edited `bin/harness.sh`. `init.sh` from B exits 1 and names `…/bin/harness.sh.new` as the blocker.
  - The message gives the working command `diff -u "<home>/bin/harness.sh" "<home>/bin/harness.sh.new"` and says "Resolve each .new first … then run the same command again".
  - It no longer says "run init.sh again" as the fix.
  - Project checksums are identical before and after (nothing moved or removed).
  - `update` refuses the same way.
  - After `mv harness.sh.new harness.sh` and a re-run, the migration succeeds.
  - Control: with an edited `harness.sh` that still answers `agent list`, the migration correctly proceeds and the banner prints at the end.
- **4. Downgrade guard: PASS.**
  - `update --src A` (0.13.0) against an installed 0.13.1 exits 1 with "refusing to downgrade … nothing was changed". A checksum of home + project is identical afterwards.
  - `--force` (in either argument order) installs it.
  - Upgrade, same-version and 0.13.1→0.13.10 are unaffected. 0.13.10→0.9.9 is refused, so the version compare is numeric.
  - An empty home bootstraps fine.
  - The default clone path (a fake `git clone` shim on PATH) is also refused without `--force` and allowed with it.
- **5. N3 `.cursor/rules`: PASS.**
  - Setup: a v0.12.1 project with the generated rules, then these edits: `evaluate.mdc` description only, `checkpoint.mdc` body only, `tdd.mdc` trailing whitespace on the description line, plus the user rules `my-own.mdc` and `tdd-extra.mdc`.
  - The edited rules were kept byte-intact and each got a `keep …` notice naming its path. The 15 clean rules and `harness-mini.mdc` were removed. The user rules were untouched.
  - The "removed unchanged" message is not printed for any edited rule.
  - There is no repeat notice on a later run (migration no longer runs once the legacy markers are gone). That is acceptable.
- **6. Leftover docs: PASS.**
  - A 0.12.1 project with 7 leftover docs printed 7 `keep <path> (leftover legacy harness file …)` lines.
  - The listed set equals the files remaining under `docs/` exactly (diffed).
- **7. Tests, changelog, backlog, regressions: PASS.**
  - `bash tests/run.sh` (outside the sandbox, temp home): Passed 919, Failed 0, exit 0.
  - `bash -n` is clean on `bin/*.sh`, `init.sh` and `tests/run.sh`. No `python` in the product scripts.
  - CHANGELOG `[0.13.0]` has entries for the notice, `diff`, the downgrade guard, N3 and the full leftover list. `[Unreleased]` is empty.
  - The backlog has an open item for layered config overrides.
  - A fresh install footprint is unchanged: `.harness-mini/{.gitignore,architecture.md,docs/exec-plans/active/0001-*}` plus `AGENTS.md` in the project, and 54 files in the home.
  - `doctor` and `status` report healthy and 0 `.new` files.

## Defects
- None at blocker or major level.
- Nit: a `.new` file that is not listed in `runtime.lock`, `global.lock` or the project lock is invisible to the banner and to `doctor`. This is by design and not a regression.
- Nit: `update --force --src B` over an installed 0.13.10 prints "already up to date" while `VERSION` changes. This is cosmetic.
