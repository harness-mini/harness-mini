# Changelog

All notable changes to harness-mini are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/): MINOR adds skills/agents/CLI
capabilities, PATCH fixes glue, MAJOR breaks the install layout or lock contract.

## [Unreleased]

### Added
- **`harness.sh doctor`** — install health check (3 severities: ok/warn/fail;
  exit 1 only on a fail). Checks AGENTS.md, the lock (or source repo), skill
  folder-shape, manifest, an active exec-plan, `.trace/runtime` ignored,
  unresolved `.new` files, VERSION↔lock, and **source↔`.claude` mirror divergence**.
- **`harness.sh status`** — current work state for cold resume: installed version,
  active plans + stages, latest checkpoint per plan, `.new` conflict count, last
  `ctx_pct` from the trace tail, and resumability. grep/awk/tail only — no parser.

### Changed
- **Tiered evaluation** (`skills/evaluate/SKILL.md`): evaluation now scales with
  risk instead of always spawning an Opus evaluator — **L0** self-check + evidence
  (tiny/low-risk) · **L1** independent lightweight reviewer (**default**) · **L2**
  full Opus evaluator (cross-slice/architecture/security/data-loss/public-API/
  release). The tier is recorded in the plan's `eval:` field; the firewall is the
  *separate context*, not the model. Wired into `stage-viewer`, `evaluator`,
  `AGENTS.md`, and the README. A convention, not a runtime.

### Added
- **Walkthrough:** `docs/walkthrough.md` shows one complete loop end-to-end
  (install → recon → route → plan → TDD slice → evaluate → checkpoint → cold
  resume), backed by a committed illustrative example under
  `docs/examples/demo-auth/` (a plan + 3 checkpoints). Linked from the README.
- **First-run guidance docs:** `docs/codex-getting-started.md` and
  `docs/cursor-getting-started.md` (use the harness from non-Claude agents — read
  the files, run the shell, reproduce sub-agents as separate threads); a README
  **quick-vs-full** decision table; `docs/templates/{quick,full}-plan.md`.
- **Threshold tuning docs:** `docs/smart-dumb.md` now presents 40% as a tunable
  default with 30/40/60 examples + when a solo dev should move it; `bin/ctx.sh -h`
  prints worked examples.
- **Recon schema:** the seeded `0001-recon.md` and `agents/explorer.md` now carry
  a concrete output schema (entry points, test/build/lint commands, domains,
  layers, risky + generated dirs, where behaviour/tests live, first slice).
- **Shell-compatibility notes** in `CONTRIBUTING.md` (bash 3.2/macOS, Linux bash,
  zsh-callable, no deps, GNU/BSD pitfalls) + a brief README line.

### Changed
- **Source vs installed tree made explicit** (README + CONTRIBUTING): edit
  `skills/<name>/SKILL.md` / `agents/<name>.md`; `.claude/` is a committed
  generated mirror — regenerate with `cp -R`. Fixed stale `skills/*.md` doc links.

## [0.2.0] - 2026-05-30

### Added
- **`LICENSE`** — MIT.
- **`CONTRIBUTING.md`** — ways to contribute, PR expectations, docs/community
  guidance, and how to report bugs / propose features.
- **The Mini constraint** — codified as a first-class principle
  (`docs/principles.md`) and surfaced in `AGENTS.md`: shell-or-doc first, no
  environment dependence, no complex languages; delete before you add.

### Changed
- **Skill layout → canonical Agent Skills format.** Each skill is now a folder
  `skills/<name>/SKILL.md` (mirrored to `.claude/skills/<name>/SKILL.md`) instead
  of a flat `<name>.md` — matching how Claude Code discovers project skills, with
  room for optional `scripts/ references/ assets/ examples/ tests/`. Agents stay
  flat (`.claude/agents/<name>.md`). `emit_managed_pairs()` now recurses `skills/`
  so the lock + `update` track every file under a skill folder.

### Note
- Pre-1.0 layout change: existing installs may keep orphaned flat
  `.claude/skills/*.md` after `update` (it never deletes) — a fresh install or
  manual cleanup is cleanest.

## [0.1.0] - 2026-05-29

### Added
- **`bin/harness.sh`** — the front-door CLI with three subcommands:
  - `version` — report the installed version (from `harness/harness.lock`, else
    `VERSION`) plus a best-effort latest published tag.
  - `update [--src DIR]` — checksum-guarded sync of the managed file set from
    upstream: refresh untouched files, **keep** user-edited ones and write the
    upstream copy beside them as `<file>.new`, add new files; never touches
    `docs/exec-plans/` or `.trace/`.
  - `release <x.y.z> [--dry-run] [--no-push] [--no-gh]` — gated bump + tag +
    GitHub release (semver + green-tests + clean-tree gates).
- **`VERSION`** file — canonical version, starting at `0.1.0`.
- **`harness/harness.lock`** — version + pristine upstream checksums of every
  managed file, written by `init.sh` (additive) and maintained by `update`.
- **`bin/_harness_lib.sh`** — shared helpers (managed-set enumeration, checksums,
  lockfile) used by both `harness.sh` and `init.sh`.
- **`release` skill** documenting the human-judgment side of cutting a release.
- TDD coverage for version/lock/update/release (`tests/run.sh`).
