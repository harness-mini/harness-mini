# Changelog

All notable changes to harness-mini are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/): MINOR adds skills/agents/CLI
capabilities, PATCH fixes glue, MAJOR breaks the install layout or lock contract.

## [Unreleased]

### Changed
- **Refactor: `bin/harness.sh` report commands are thin dispatchers.**
  `status`, `doctor` and `update` — the three longest functions (214/149/96
  lines) — are extracted into named per-section functions, the largest
  extracted function 67 lines (plan 0062). No behavior change: outputs are
  byte-identical to frozen snapshot pins and `tests/run.sh` stayed 975/0
  through every extraction. Two write-only locals surfaced by the shellcheck
  gate (`agent_list`'s `tab`, the ready verdict's `done_plan`) are gone.

## [0.15.0] - 2026-11-11

### Added
- **`session-coding` Getting Bearings reads a file-truth report.**
  `skills/session-coding/scripts/session-bearings.sh` prints the plan, the
  selected slice, the workboard, the checkpoint resume line, and last-green
  from disk. Quote that report; do not restate it from memory. Exit 2 means
  the board is still `path: init`.

### Fixed
- Workboard parsing pairs each `passes` value with the slice `id` that
  precedes it. A one-line twin no longer drops the failing slice, so
  `harness.sh status` and the bearings report name the real `next:` slice.

### Changed
- Pull requests and pushes to `main` run `bash tests/run.sh` on Ubuntu and
  macOS. Changed `.sh` files are shellchecked at warning level and above.

## [0.14.1] - 2026-11-08

### Changed
- **Garden sweep.** Docs now match the code: the Cursor getting-started uses
  `.cursor/skills`, and README/ARCHITECTURE document `harness.sh diff <file>` and
  the `update` downgrade guard (`--force`). Internals: a single `read_version`
  helper replaces nine duplicated `VERSION` reads and an unused helper is gone
  (no behavior change). A user who hand-edited `bin/_harness_lib.sh` keeps their
  copy on `update` (upstream lands as `.new`) and must merge it, because
  `harness.sh` now needs `read_version` from the lib.
- The 0.14.0 section gained an `### Upgrading` note: run the new checkout's
  `init.sh` first, because an installed 0.13.0 runtime reports `lock missing`
  once the state dir has moved.

## [0.14.0] - 2026-11-07

### Changed
- **Per-project state dirs now live under `$HARNESS_HOME/projects/<project-id>/`**
  (was `$HARNESS_HOME/<project-id>/`), so the top of `~/.harness-mini/` holds only
  the runtime (`bin`, `docs`, `skills`, `agents`, `harness`, `projects`, `AGENTS.md`,
  `VERSION`). Existing 0.13.0 state dirs are moved automatically and idempotently by
  `init.sh` and by `harness.sh` (`update`, `doctor`, `status`, `agent install`, ...);
  runtime dirs are never touched and an existing `projects/<project-id>/` is never
  overwritten (the old dir is kept with a `keep` notice). Issue #82.

### Upgrading
Run the 0.14.0 checkout's `init.sh` first. An installed 0.13.0 runtime is old
code: it reports `lock missing` once the state dir has moved to `projects/`.
`init.sh` refreshes the runtime (checksum-guarded, never a downgrade) and then
migrates the state dir.

## [0.13.0] - 2026-11-07

### Changed
- **BREAKING — zero-intrusion install layout (plan 0059).** Files now fall in
  two classes. *Harness-owned* files that don't depend on project progress
  live under `$HARNESS_HOME` (default `~/.harness-mini/`); *project-progress*
  files that must be recorded live in the project's `.harness-mini/`. A
  project now receives only: `.harness-mini/` (plans, trace, `architecture.md`,
  an inner `.gitignore` for `trace/runtime/`), one `<!-- harness-mini:begin/end -->`
  block in the root `AGENTS.md` (the file is created holding only the block if
  absent; text outside the block is never touched), the host's skills/agents
  dirs placed by `agent install`, and lines for those dirs in the local
  `.git/info/exclude`. It no longer receives `docs/`, `harness/`, `.trace/`,
  `ARCHITECTURE.md`, `CLAUDE.md`, a harness `bin/`, or any edit of the project
  `.gitignore`.
- **Per-project bookkeeping moves to `$HARNESS_HOME/<project-id>/`**
  (`harness.lock`, `manifest.md`, `targets`). `project-id` is
  `<name>-<8 chars [0-9a-z]>`: the lowercase-hyphenated basename plus the last
  8 base-36 digits of sha256(absolute, symlink-resolved path). Caveat: **moving
  or renaming a project changes its id**, so its old lock/targets are orphaned;
  re-run `init.sh` and `agent install <host>` there.
- **`init.sh` is host-blind and installs no skills or agents.** The AGENTS.md
  block tells the agent to run `harness.sh agent list`, then
  `agent install <host>`. Static docs, templates, the map (`AGENTS.md`) and
  `docs/ARCHITECTURE.md` exist once under `$HARNESS_HOME`, never in projects.
- **0058 correction: `.agents/skills` is no longer treated as universal.**
  Install targets are host-aware; hosts that read `.agents/skills` natively
  share it, others (Claude Code, Cursor, Qoder, zcode, Trae, CodeBuddy) get their own
  dir.
- **`references/` and `assets/` moved to the repo root** (from `docs/`); they
  are source-repo only and never installed or locked. The source repo now
  dogfoods the `.harness-mini/` layout (plans, checkpoints, evals); its
  `docs/` is distribution source only.
- `update` also refreshes the global copies (map, docs, skill/agent sources)
  under `$HARNESS_HOME`, checksum-guarded like project files, with a separate
  `harness/global.lock` (next to `runtime.lock`).
- `doctor` gains an installed-drift check: skills at persisted install targets
  that differ from source are reported as a warning.

### Added
- **Host-aware `harness.sh agent list|install <host>`.** `agent list` prints the
  host table (id, skills dir, agents dir, role format, confidence) for
  Antigravity, Codex, Cursor, Claude Code, Qoder, zcode, Kimi, DeepSeek harness,
  pi, opencode, Grok, GitHub Copilot, MiMo Code, Trae and CodeBuddy
  (`host_row` in `bin/_harness_lib.sh` is the single source). Roles are written
  as Markdown, `<name>.agent.md` (Copilot) or TOML (Codex). Unknown hosts, Muse
  and Hermes install nothing: the command prints the source paths and
  instructions so the agent installs itself. Each install appends a row to
  `<state dir>/targets` (`host<TAB>skills<TAB>agents<TAB>fmt`) and rewrites the
  project lock and manifest.
- **Automatic legacy migration** on `init.sh` re-run and `update`: plans move
  from `docs/exec-plans/` and `.trace/` into `.harness-mini/` (file-by-file
  merge); harness-owned files from the old `harness/harness.lock` (docs,
  `ARCHITECTURE.md`, `bin/`, `.claude/`, generated Cursor rules/`CLAUDE.md`)
  are removed only when their checksum still matches; edited files are kept
  and reported. A whole-file harness `AGENTS.md` is replaced by the block when
  unchanged; an edited one keeps your text and gets the block appended;
  leftover harness copies (`docs/references`, `docs/assets`, static docs,
  generated Cursor rules) go only when byte-identical to the shipped copy and
  the rest is listed, one path per line. Repeat runs are harmless and quiet.
  *Bootstrap note (upgrading from ≤ 0.12.x):* run the new checkout's `init.sh`
  in the project (`bash <checkout>/init.sh .`) — it installs the runtime under
  `$HARNESS_HOME` (or refreshes an older one, checksum-guarded; never a
  downgrade) and only then migrates. `bin/harness.sh update --src <checkout>`
  run twice also works: the first run (old code) only copies the new `bin/`
  into the project; the second (new code) installs the runtime from the source
  tree, then migrates. **The migration is refused — nothing moved or removed —
  unless the runtime at `$HARNESS_HOME` is installed and answers `agent list`;**
  the message names the next step.
- `init.sh` refreshes an existing runtime like `update` does (pristine files
  upgraded, edited ones kept with `.new`, `VERSION` + `runtime.lock` advanced).
- `doctor` and `status` also count unresolved `.new` files under
  `$HARNESS_HOME` (runtime executables and global copies).
- **A prominent notice when files were not upgraded (plan 0060).** After
  `init.sh` or `update`, if any `<file>.new` is waiting under `$HARNESS_HOME`
  (runtime or global copies) or in the project, one plain-ASCII banner says how
  many files were NOT upgraded because you edited them (files under the install
  dir are managed by harness-mini and should not be edited; put local needs in
  the project), lists each `.new`, and prints the runnable line that shows the
  difference. Nothing is printed when there are none. A migration refused
  because an edited runtime file blocks the upgrade now names that `.new` and
  the diff command instead of "run init.sh again".
- **`harness.sh diff <relpath|path> [--root DIR]`.** Prints `diff -u` of your
  kept file against its upstream `<file>.new` (labelled yours / upstream) for a
  runtime, global or project file (`bin/harness.sh`, `skills/tdd/SKILL.md`, …);
  exit 1 with a clear message when there is no `.new`.
- **`update` refuses to downgrade the runtime** (same version test as
  `init.sh`, for `--src DIR` and the default clone): exit 1, nothing changed,
  unless `--force`.
- **Safer cleanup of generated `.cursor/rules/*.mdc`.** A rule is deleted only
  when it is byte-exact AND its `description:` line equals the one the old
  installer wrote (the skill's description, or its fallback text). A look-alike
  with an edited description or body is kept and named in the kept notice; it is
  never reported as "removed unchanged".
- **Leftover docs are listed in full.** Every kept legacy path is printed on its
  own line (sorted); a repeat run never collapses them into a bare count.

## [0.12.1] - 2026-11-06

### Added
- **Checkpoint hardening (#76, #77; Discussion #75).** Checkpoints can record
  structured Footprint entries, validate them with the checkpoint skill's
  linter, capture exact source-line snapshots with boundary checks, and skip
  redundant writes when no tracked files changed. The helpers ship inside
  `skills/checkpoint/scripts/` with their owning skill.
- **Last-green test evidence.** When `HARNESS_TEST_SCRIPT` is configured, the
  context hook records the timestamp and revision of its latest passing run;
  the checkpoint skill can use that record instead of relying on agent memory.

## [0.12.0] - 2026-11-02

### Added
- **Outer session runner — `bin/session.sh` (#61, optional P2).** Forces the
  matching session playbook into a fresh context for unattended/scripted runs:
  reads `path:` from `harness.sh status`, picks `session-init` or
  `session-coding`, and emits that skill's body **verbatim** (frontmatter
  stripped) under a short generic wrapper — skill files stay the single
  source of truth. Default prints the first user message to stdout;
  `-- <cmd…>` execs a host CLI with the message as its final argument. Each
  invocation is a new process (fresh context, nothing persisted), the script
  is vendor-neutral POSIX sh with no session-start-hook dependency, and it is
  explicitly optional — not required for Mini core.

- **Path-aware routing gate v3 (#60).** The always-on gate now branches on the
  `path:` line from `bin/harness.sh status`: `path: init` → open
  `session-init` (plan-layer only, no product code); `path: coding` → open
  `session-coding`, complete its **Getting Bearings** first, then exactly one
  slice (the highest-priority `passes: false`, prefer `next:`). Planning
  boards are no longer pushed into product slices; one-slice / never-alter-
  `steps` / progressive-exposure rules carried over from v2. `init.sh`
  migrates v1 **and** v2 (path-blind) gates in place — still exactly one
  marker-guarded block — and regenerates the Cursor rule; `AGENTS.md`'s gate
  section agrees with the injected copy.
- **`session-coding` skill with the full Getting Bearings recipe (#59).**
  On-demand playbook for boards where `status` prints `path: coding`: the
  first turn MUST report the five locked bearings before any product code —
  `pwd` · `status` + `git log --oneline -5` + latest checkpoint · open the
  twin and select the highest-priority `"passes": false` slice (prefer
  `next:`) · app baseline green (lint/types/tests or the app's own boot
  script — **never harness-mini's installer `init.sh`**; on regression, stop
  new slices and fix first) · tell the user the selected `[slice-id]`. Then
  exactly one slice via `tdd`, verified against the JSON `steps` (never
  rewritten), routed through `evaluate` — the builder never flips `passes`
  (main agent / `stage-viewer` only) — ending with handoff + checkpoint +
  commit, no half-open second slice, no `completed/` history loads.
- **`session-init` skill (#58).** On-demand plan-layer playbook for boards where
  `status` prints `path: init`: confirms the path first, branches on the board
  (greenfield funnel via founder-check → to-prd → to-issues with the JSON twin ·
  recon seed → explorer · stuck prd/issues → finish the stage · broken twin →
  repair first), enforces the plan-stage write ban (**no product code**), never
  flips `passes` (stage-viewer authority), and ends with a checkpoint. Listed
  under orchestrate in AGENTS.md; no always-on prompt dump.
- **Session path in `harness.sh status` (#57).** Two new machine lines —
  `path: init|coding` + `path_reason:` — derived only from file truth (MD
  `stage:` + the JSON twin): empty board or planning stage → `init`
  (`empty board` / `still planning`); a coding stage with a `passes: false`
  slice → `coding` (`next slice ready`); all-green plan not closed → `coding`
  (`wrap-up`). Missing/unparseable twin degrades conservatively to `init`
  (`twin missing` / `twin unparseable`). Across plans, a coding-provable plan
  wins. This is the line the session-path skills (#58/#59) and the path-aware
  gate (#60) branch on.
- **Dual-file exec-plans — machine workboard (#52).** Every active plan keeps a
  same-basename `<NNN-slug>.json` twin beside its MD (`plan_id`, `title`,
  `status`, `current_slice_id`, `slices[]` with `id/category/description/steps/
  passes`). MD frontmatter `stage:` stays the lifecycle authority; JSON mirrors
  progress. `harness.sh status` now prints a per-plan **workboard line**
  (`status · n/m pass · current · next passes:false` slice) parsed with awk only
  (no jq); `doctor` warns — never fails — on a missing or unparseable twin.
  Templates document the schema (`docs/templates/full-plan.md`,
  `full-plan-twin.json`), plans gain a `## Session Context Handoff` section the
  `checkpoint` skill refreshes, and `to-issues` emits the twin. `passes` flips
  to `true` only via the main agent **after an evaluator verdict** (anti-self-praise);
  `steps` are test conditions and are never altered.
- **Accessibility statement** — root `ACCESSIBILITY.md` + a README Community
  link: plain-text/`NO_COLOR` commitments for the CLI, Markdown a11y rules
  (heading order, descriptive links, prose beside diagrams), supported
  environments, known limitations, and a public issue reporting path with an
  `accessibility` label.

### Fixed
- **Fresh installs no longer start with a doctor warning (#64).** The seeded
  `0001-intake`/`0001-recon` plans now ship with their JSON twins
  (`status: planned`, empty `slices`) — `doctor` is clean on day one and
  `status` shows the seed plan's workboard line (`planned · no slices yet`)
  from minute one. Legacy installs with twin-less plans still degrade
  gracefully (WARN, never FAIL).
- **`init.sh` no longer seeds a spurious bootstrap plan into upgraded installs
  (#63).** The seed guard was "no `0001-*.md` present"; an install whose plans
  are numbered differently (e.g. `0009-…`) gained an unrequested
  `0001-intake.md` on upgrade. The guard is now "no active `*.md` at all".
- **`harness.sh update` no longer crashes when the update includes its own
  script (#62).** Overwriting the executing `bin/harness.sh` mid-run desynced
  bash's lazy script reads (resumed the new file at the old byte offset →
  `unbound variable`, nonzero exit). The self-copy is now deferred to the very
  last action, followed by an immediate exit; the pair loop also runs in-shell
  (herestring) so the deferral flag survives. Regression-tested with bin/-
  bearing fixtures. Note: a one-time transition upgrade from v0.11.0 may still
  print the error (the old running script predates the fix) — it is harmless:
  the update applies and the next command runs the new script.

### Changed
- **Routing gate v2 — status-first (#52).** `init.sh` injects a
  `HARNESS_ROUTING_GATE_BEGIN/END`-marked block ([CRITICAL AGENT INSTRUCTION]:
  run `bin/harness.sh status` first, pick the highest-priority `passes: false`
  slice, one slice per session, progressive exposure, never alter JSON `steps`)
  into `CLAUDE.md`, and **upgrades v1 installs** (the old
  `harness-mini:start/end` block is stripped and the v2 gate appended — exactly
  one gate, ever). The `.cursor/rules/harness-mini.mdc` gate is regenerated
  status-first. `AGENTS.md` carries a single merged routing-gate section
  (mandatory `status` first, quick repository map, no full-history loads) and
  documents the twin contract.
- **First-screen & navigation upgrade (docs-nav-001).** README leads with a
  committed SVG banner (`docs/assets/banner.svg`) + shields.io badges and states
  the five-invariant **Core Architecture Contract**; `ARCHITECTURE.md` opens with
  a full ASCII lifecycle FSM (per-state exit conditions, rework loop, quick mode,
  garden orthogonality); `AGENTS.md` becomes an anchor-marked context navigation
  map (`ANCHOR:` marks + a trigger jump table; prose pruned to fund the budget).

## [0.11.0] - 2026-10-30

### Removed
- **Five-Step as a skill, core-mind, and mandatory intake gate (#46).** The harness
  keeps only a plain delete-first discipline under the Mini constraint.

## [0.10.0] - 2026-08-11

### Added
- **Session ops — cold-resume readiness without a second runtime (#38).**
  `harness.sh status` now ends with a single `ready: <ready|warning|blocked> — <next>`
  verdict (OpenHarness dry-run idea, Mini-shaped): blocked only for install-broken
  or an active `done` plan without `verdict: pass`; warnings cover no plan, garden
  DUE, `.new` conflicts, behind-latest, and partial resume. Resumable is
  **plan-scoped** (foreign checkpoints no longer lie). Checkpoint skill gains an
  additive `## Task state` block (acceptance / footprint / last green / open
  issues). `stage-viewer` + planner document a plan-stage write ban (convention
  only — no permission engine) for `intake`/`prd`/`issues`. Assumptions **A6** /
  **A7** registered; short pointers in `AGENTS.md` / `ARCHITECTURE.md`. Plan:
  `docs/exec-plans/completed/0006-session-ops.md`.

## [0.9.0] - 2026-06-24

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
