# Changelog

All notable changes to harness-mini are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/): MINOR adds skills/agents/CLI
capabilities, PATCH fixes glue, MAJOR breaks the install layout or lock contract.

## [Unreleased]

### Added
- **CIB — a context-intelligence benchmark, and the first real test of the 40% line (#34, #35).**
  New `bench/cib/` (stdlib-only; 62 unit tests + an offline smoke test; L2-evaluated):
  builds a prompt to a target context occupancy, runs an agent probe (D1 retrieval,
  D2 multi-hop reasoning, and real HotpotQA QA-F1), detects degradation changepoints
  (zero-dep, vs a linear null, with a bootstrap CI), and renders a **self-contained HTML
  report**. Live backend over OpenRouter (any model), occupancy measured from real
  `usage.prompt_tokens`. Ran live on gpt-4o-mini, haiku-4.5, and Qwen2.5-7B: under a
  controlled design (fixed task, only fill varied) **raw occupancy showed no 40%
  "intelligence cliff"** — even on the paper's own model — and what degraded real QA-F1
  was **interference** (competing related content), not how full the window is. Findings,
  data, and reports: `bench/cib/results/FINDINGS.md`.
- **Cursor skill mirror — skills are now agent-requestable in Cursor (#23).**
  `init.sh` emits one `.cursor/rules/<name>.mdc` per skill (`alwaysApply: false` +
  the skill's `description`), so Cursor's agent can pull a skill on demand by its
  description instead of being told to open files by hand. Each rule is a thin
  pointer at the canonical `.claude/skills/<name>/SKILL.md` (single source of
  truth, no duplicated body); generation is additive + idempotent + harness-owned
  (created only if absent, never in the checksum-managed set). The file-level
  mechanism is covered by `tests/run.sh`, and a worked Cursor run later
  demonstrated it end-to-end — Cursor observably pulls the rule on demand
  (#23, closed; transcript in `examples/cursor-slugify-demo/`). First concrete
  step toward Cursor support.

### Changed
- **The 40% line is now documented as a conservative default, not a law (#34, #36).**
  Per the CIB results, `docs/smart-dumb.md` and assumption **A1** (`docs/assumptions.md`)
  are reframed around **interference, not occupancy**: occupancy is the cheap proxy we
  measure, but the firewall + progressive-disclosure mechanisms earn their keep by holding
  *competing content* out. A1 went from zero empirical signal to a tested verdict; the
  README surfaces the result from the front door (#37).
- **Honest CLI positioning — "Claude Code-first", not blanket "CLI-agnostic".**
  README, `docs/cursor-getting-started.md`, `docs/codex-getting-started.md`, and
  `docs/principles.md` now state plainly what's first-class on Claude Code
  (auto-discovered skills/agents, the 40%-line hook) versus the secondary,
  not-yet-at-parity path on Cursor/Codex (you load skills by hand). Dropped the
  unproven "the CLI-agnostic promise holds" / "stays honest" claims. A first
  end-to-end run later demonstrated Cursor loading the gate and pulling skill
  rules on demand (#23, closed) — but it stays portable/secondary, not parity
  (one model session; no 40%-line hook in Cursor).
- **Model upgrade is now model-agnostic.** The builder (generator) upgrades to
  **the highest-available frontier model tier** (`opus`, the top tier the harness
  names) when `HARNESS_TOP_MODEL` is set, replacing the Fable-5-specific behavior.
  `bin/model.sh` drops the now-dead Models-API probe (it grepped for a specific
  model id) in favor of an explicit opt-in flag; the `HARNESS_FABLE` env var is
  **renamed to `HARNESS_TOP_MODEL`**. `README.md` / `AGENTS.md` reworded to
  model-agnostic language.

### Fixed
- **`tdd` now requires one red→green cycle per acceptance criterion (#29).**
  The first real Cursor dogfood (slugify) exposed test-first silently degrading to
  "one test, then code that happens to generalize" — five criteria, one test, four
  untested behaviors passing by luck. The `tdd` skill now states each enumerated
  criterion gets its **own** failing test (with an "it generalized" anti-pattern),
  and `docs/templates/quick-plan.md` echoes it where quick-mode specs are written.
  Locked in by `tests/run.sh`.

## [0.8.0] - 2026-06-12

### Added
- **Claude Fable 5 support — the builder runs on it when available.** New
  `bin/model.sh <role>` resolves a sub-agent's model **tier**. Static tiers are
  unchanged (planner/generator → sonnet, evaluator → opus, explorer/gardener →
  haiku); the one new behavior is that the **builder (generator) auto-upgrades to
  `fable`** (Fable 5, the top tier above Opus) **when Fable 5 is available to the
  account**, falling back to sonnet otherwise. The spawning agent passes the
  resolved alias as the worker's model override (`AGENTS.md` / `README.md`).
  Availability is plan- and time-gated, so it's **detected** best-effort (Models
  API, offline-safe like the version check) — never hardcoded; overridable via
  `HARNESS_FABLE` / `HARNESS_MODEL_BUILDER`, skipped under `HARNESS_NO_NET`.
  Closes #13.
- **Assumption register + audit — question stale assumptions.** New
  `docs/assumptions.md` logs each load-bearing mechanism (the 40% line, the eval
  firewall, the explorer fan-out, progressive disclosure, caps-for-emphasis) with
  the model-gap it patches and a concrete *test if stale*. A "Question stale
  assumptions" meta-principle (`docs/principles.md`) frames every constraint as a
  hypothesis, and the `garden` sweep + gardener now **audit the register
  pre-release** (and when the builder model tier moves), deleting patches the
  model has outgrown. Distilled from Anthropic's *Scaling managed agents*
  (`docs/references/anthropic-managed-agents-llms.txt`). Closes #17.

### Changed
- **`ralph-loop` reframed as a contract, not a tool.** Adds the loop invariants
  (bounded · externally checked · checkpointed), a decision rule (loop only when
  the work is objectively checkable *and* may exceed one session — else a one-shot
  prompt is leaner), and an adapter table mapping the abstraction to each CLI's
  native mechanism (`bin/ralph.sh` fallback · Claude Code `/loop`/`ScheduleWakeup`/
  `schedule`). One contract + one fallback + thin adapters — no per-CLI forks.
- **Emphasis budget (principle #9).** Reserve ALL-CAPS for `MUST`/`NEVER`/`ALWAYS`
  on safety- or invariant-critical lines; default to bold + structure elsewhere.

## [0.7.1] - 2026-06-09

### Changed
- **Contributing workflow is now issue-first.** `CONTRIBUTING.md` requires opening
  a GitHub issue before implementing **any** change (previously only non-trivial
  ones) and linking it from the PR (`Closes #N`); added a PR-checklist item. Repo
  workflow only — deliberately not codified into the CLI-agnostic framework.

## [0.7.0] - 2026-06-08

### Added
- **`harness.sh report [run]` — measure the loop instead of asserting it.** A
  pure-shell aggregator over `.trace/`: stage advances (+ last stage), the context
  trend vs the 40% line (sample count, max %, crossings), evaluation pass/fail +
  rework loops, and checkpoint count. So the thresholds (40%, garden cadence, eval
  tier) can be tuned by data, not vibes.
- **The anti-self-praise firewall now has teeth.** Evaluations write a committed
  verdict to **`.trace/evals/<plan>-NNN.md`** (tier · verdict · criteria), and
  `harness.sh doctor` **FAILs** any active plan marked `done` without a
  `verdict: pass` record. `stage-viewer` won't promote to `done` without it. So
  "done" is earned, not self-declared. (Scoped to active plans; legacy completed
  plans are never retroactively failed.)
- **`bin/ctx-hook.sh` — give the 40% rule teeth (opt-in, Claude Code).** A
  PostToolUse adapter that estimates context after each tool call, records a
  `ctx_pct` sample (feeding `report`), and nudges to checkpoint when over the
  line. Opt-in via `.claude/settings.json` (documented in `docs/smart-dumb.md`);
  `init.sh` never touches your settings. Heuristic (`bytes/4`), honestly framed —
  the one Claude-Code-specific file; the harness stays CLI-agnostic.

## [0.6.0] - 2026-06-03

### Added
- **Update reminder on entry — check for a newer harness-mini first.** On a fresh
  session the agent now checks for a newer release before routing work (the
  routing gate + `stage-viewer`'s on-entry step run `harness.sh version`); if one
  exists it tells the user and offers `harness.sh update`. The reminder is
  surfaced by **`version`** (semver-aware verdict), **`status`** (an `update:`
  line), and **`doctor`** (a WARN — never a FAIL). Best-effort: silent offline
  (`HARNESS_NO_NET`); `HARNESS_LATEST` pins/overrides the latest version.
- New dependency-free `version_newer()` semver compare in `bin/_harness_lib.sh`
  (no `sort -V`), so the "is a newer version available?" check is accurate
  (`0.10.0 > 0.9.0`) and portable. The test suite is now hermetic (network off by
  default; update-checks inject `HARNESS_LATEST`).

## [0.5.0] - 2026-06-03

### Added
- **Gardening trigger policy — gardening now fires on concrete signals instead of
  vague "periodically."** Two agreed triggers: a **cadence** (a *visit* = one
  committed checkpoint; due after **≥5 checkpoints** since the last sweep,
  overridable via `HARNESS_GARDEN_EVERY`, plus at plan-completion and before a
  release) and a **smell backlog** — out-of-scope smells are recorded to a
  committed **`.trace/garden-backlog.md`** (never fixed inline / dropped), and
  garden is due on any `high`-severity item or **≥3 open items**.
- **`harness.sh status` surfaces it:** a new `garden: DUE|ok (<n> checkpoint(s)
  since last; <k> backlog item(s))` line (grep/ls/sed only; always exits 0). The
  gardener stamps `gardened-at:` after a sweep to reset the cadence counter.
- Wired into the flow: `garden` (the policy + backlog format), `gardener`
  (work the backlog, stamp the marker), `checkpoint` (log out-of-scope smells),
  `stage-viewer` (dispatch the gardener when DUE at a plan boundary), `release`
  (garden-if-due pre-flight), and the FSM notes in `AGENTS.md`/`ARCHITECTURE.md`/
  `README.md`/`docs/principles.md`. The backlog is project data — created on
  demand, never in the managed set, so `update` can't clobber it.

## [0.4.1] - 2026-06-02

### Changed
- **Golden principle #5 sharpened** (`docs/principles.md`): "Parse at the boundary"
  → "**Type the boundary; never guess the shape**" — now leads with *depend on a
  typed SDK/client* (acquire types from the source) and falls back to parse +
  validate at the seam where no typed SDK exists; nothing downstream may build on a
  guessed/untyped structure. `slice-coding`'s dependency note aligned to match.
  Wording-only; no behavior change.

## [0.4.0] - 2026-06-01

### Added
- **Routing gate — the harness is preferred by default after install.** `init.sh`
  now seeds a short precedence gate into each CLI's native always-on file so an
  agent reaches for the harness without being told: **`CLAUDE.md`** (Claude Code;
  marker-guarded block, created or appended-once — an existing `CLAUDE.md` is never
  clobbered), **`.cursor/rules/harness-mini.mdc`** (`alwaysApply: true`, Cursor),
  and a precedence preamble atop **`AGENTS.md`** (Codex). The gate: route
  non-trivial work through `stage-viewer` first; when a harness skill and another
  tool both fit, *the harness skill wins*. Additive + idempotent; seeded once, like
  `manifest.md` (not in the checksum-managed set). Getting-started docs + README
  updated.
- **`parallel-slices` skill — write fan-out for the implement stage.** After the
  vertical walking skeleton passes evaluate, the main agent may build the remaining
  **independent** issues in parallel — one `generator` per issue — gated on
  **disjoint file footprints** (no two generators write the same file), then a
  single **integration evaluate**. Vertical-first still holds; the generator is
  unchanged (one issue per session). Wired into `to-issues` (file footprint +
  `depends-on` annotations, parallel groups), `slice-coding`, `stage-viewer`,
  the `generator` (stay-in-footprint, report-on-breach), `docs/smart-dumb.md`
  (fan-out covers writes too), `ARCHITECTURE.md`, and the full-plan template.

## [0.3.0] - 2026-05-30

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
