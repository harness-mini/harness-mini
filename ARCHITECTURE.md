# Architecture

Top-level map of how harness-mini is laid out and how work flows through it.

## Lifecycle at a glance

Every requirement is a plan file riding this state machine — **only the main
agent (via `stage-viewer`) advances a state; sub-agents never do.**

```
  start ── init.sh seeds the first plan: 0001-intake (new) · 0001-recon (existing)
         │
         ▼
   ┌────────────┐  exit: founder-check done (new) · recon done (existing)
   │   intake   │
   └────────────┘
         │  to-prd → stress-test it with grill-me
         ▼
   ┌────────────┐  exit: PRD written and grilled
   │    prd     │
   └────────────┘
         │  to-issues → atomic, testable work units
         ▼
   ┌────────────┐  exit: atomic, testable issues exist
   │   issues   │  (the plan-stage write ban lifts here)
   └────────────┘
         │  implement → one vertical slice (tdd · slice-coding)
         ▼
   ┌────────────┐  exit: slice green → hand to the evaluator
   │ implement  │◀┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┐
   └────────────┘                               ┆
         │  evaluate (separate window)          ┆ criteria fail
         ▼                                      ┆ → rework loop
   ┌────────────┐  verdict: pass                ┆
   │  evaluate  │┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┘
   └────────────┘
         │  checkpoint → committed handoff
         ▼
   ┌────────────┐
   │ checkpoint │  gate: verdict: pass in .harness-mini/trace/evals/ (doctor enforces)
   └────────────┘
         │  archive → .harness-mini/docs/exec-plans/completed/
         ▼
   ┌────────────┐
   │    done    │
   └────────────┘

  garden ⟳ runs orthogonal to every state — fires on triggers (≥5 checkpoints ·
  a plan completing · pre-release · smell backlog) and never blocks the loop
```

- **quick mode:** a trivial, unambiguous fix (≤ ~1 slice) may jump straight to
  `implement` — the ceremony scales with risk, not habit.
- **solid arrows** advance only when the exit condition holds; the **dashed**
  loop is the implement ⇄ evaluate rework cycle until criteria pass.

## Two file classes

Zero-intrusion install: harness-mini never spreads its own files through a
project. Every file belongs to exactly one class.

| Class | Lives in | Examples |
|-------|----------|----------|
| **Harness-owned**, independent of project progress | `$HARNESS_HOME` (default `~/.harness-mini/`), per project under `$HARNESS_HOME/projects/<project-id>/` | executables, the map, static docs, skill/agent sources, lock, manifest |
| **Project progress**, must be recorded with the project | `<project>/.harness-mini/` (committed, except `trace/runtime/`) | plans, checkpoints, evals, garden backlog, project architecture |

Besides `.harness-mini/`, an install writes only a `<!-- harness-mini:begin/end -->`
block in the project's root `AGENTS.md`, local `.git/info/exclude` lines, and —
after `harness.sh agent install <host>` — that host's skills/agents dirs. The
project's own `.gitignore`, `ARCHITECTURE.md` and `CLAUDE.md` are never touched.

### Project layout (`<project>/.harness-mini/`)

```
.harness-mini/
  .gitignore           # ignores trace/runtime/ (the project .gitignore stays untouched)
  architecture.md      # this project's recon output (the explorer fills it)
  docs/
    exec-plans/
      active/          # in-flight plans: <NNN-slug>.md + .json twin (committed)
      completed/       # archived plans (committed)
  trace/
    checkpoints/       # COMMITTED — decisions, milestones, handoffs
    evals/             # COMMITTED — <plan>-NNN.md verdicts (the done-gate)
    garden-backlog.md  # COMMITTED — smell backlog
    runtime/           # GITIGNORED — ephemeral per-run JSONL (report reads these)
```

### Runtime layout (`$HARNESS_HOME`, default `~/.harness-mini/`)

```
bin/                   # executables (harness.sh, trace.sh, ctx.sh, ...)
VERSION
harness/runtime.lock   # version + checksums of bin/*
AGENTS.md              # the full agent map (the project block points here)
docs/                  # static docs: principles, smart-dumb, assumptions, ARCHITECTURE.md,
                       #   templates/, walkthrough, getting-started, examples/
skills/  agents/       # sources that `agent install <host>` copies from
projects/<project-id>/ # per-project bookkeeping
  harness.lock         # version + pristine checksums of installed skills/agents
  manifest.md          # pointer list of what an agent install placed
  targets              # one row per installed host (skills dir, agents dir, format)
```

**project-id** = `<project-name>-<8 chars [0-9a-z]>`: the name is the lowercase,
hyphenated basename of the project; the 8 chars are base-36 of
`sha256(absolute symlink-resolved path)`. Moving a project changes its id
(documented trade-off). Implemented by `project_id` in `bin/_harness_lib.sh`.
A 0.13.0 state dir sitting flat at the top of `$HARNESS_HOME` is moved into `projects/` automatically
(`migrate_state_dir`: `init.sh` and every `harness.sh` command; never a runtime
dir, never over an existing `projects/<project-id>/`).

**Hosts.** Which skills/agents dir each coding-agent host reads is a single table,
`host_row` in `bin/_harness_lib.sh`; `harness.sh agent list` prints it and
`agent install <host>` acts on it (unknown hosts get self-install instructions).
Hosts that read `.agents/skills` natively share one copy.

## Repository layout (the source repo)

The source repo dogfoods the project layout above: its own plans and trace live
in `.harness-mini/`, while `docs/` is distribution source only.

```
AGENTS.md              # the agent map (installed to $HARNESS_HOME/AGENTS.md)
ARCHITECTURE.md        # this file (installed to $HARNESS_HOME/docs/ARCHITECTURE.md)
VERSION                # canonical version (SemVer); bumped by the release command
CHANGELOG.md           # Keep-a-Changelog; rolled on release
init.sh                # additive, idempotent installer (new vs existing)
bin/                   # runtime script sources; installed under $HARNESS_HOME/bin/
  harness.sh           # front-door CLI: version·update·doctor·status·agent·release
  _harness_lib.sh      # shared helpers: layout resolver, host table, managed-set, lock
  ctx.sh               # context % estimate vs the 40% threshold
  ctx-hook.sh          # opt-in PostToolUse hook (ctx estimate + auto last-green)
  trace.sh             # append runtime JSONL (best-effort, never blocks)
  ralph.sh             # ralph-loop driver (work → check → repeat)
  model.sh             # resolve role model tiers
  session.sh           # fresh-context session playbook runner
skills/                # one folder per skill: <name>/SKILL.md (required;
                       #   metadata in frontmatter) + optional scripts/
                       #   references/ assets/ examples/ tests/.
                       #   Installed (recursively) to the host's skills dir
  checkpoint/scripts/  # checkpoint-only lint, snapshot, and guard helpers
  session-coding/scripts/  # session-coding first-turn bearings report
agents/                # role descriptions → installed to the host's agents dir
docs/                  # DISTRIBUTION SOURCE → $HARNESS_HOME/docs/ (never into a project)
  principles.md  smart-dumb.md  assumptions.md  walkthrough.md  *-getting-started.md
  templates/  examples/
references/            # *-llms.txt distillates of the source blogs (source repo only)
assets/                # README banner etc. (source repo only)
  # references/ and assets/ are never installed, locked, or listed in a manifest
.harness-mini/         # this repo's own plans + trace (dogfood)
tests/run.sh           # zero-dep TDD suite for bin/*, skill scripts, and init.sh
```

## Versioning & update model

An install has two independent managed sets. The **project set** is only the
skills and role files an `agent install` placed in the host's dirs; the
**runtime set** is the executable `bin/*` sources under `$HARNESS_HOME/bin/`. The
project set is defined in `emit_managed_pairs()` (`bin/_harness_lib.sh`) and
recorded in `$HARNESS_HOME/projects/<project-id>/harness.lock`; runtime checksums are in
`$HARNESS_HOME/harness/runtime.lock`. The global copies (map, docs, skill/agent
sources) have their own `harness/global.lock`. Project plans, `.harness-mini/`,
and application files are not managed.

`init.sh` writes both locks with the **pristine upstream checksum** of each
managed file. `"$HOME/.harness-mini/bin/harness.sh" update` diffs `base` (lock
baseline), `cur` (on disk), and `new` (upstream) independently for runtime and
project files. It preserves edited files and writes upstream conflicts to
`.new` (`harness.sh diff <file>` compares your copy with it). `update` never
downgrades the runtime unless `--force`. `update` also refreshes the global copies and first migrates a pre-0.13
project layout (data moves into `.harness-mini/`; legacy harness files are removed
only when their old-lock checksum matches). From this source repository, the release command stamps `VERSION`, rolls
`CHANGELOG.md`, tags `v<x.y.z>`, and publishes a GitHub release (gated on green
tests + a clean tree).

## Lifecycle FSM

_(The full diagram with per-state exit conditions is at the top:
[Lifecycle at a glance](#lifecycle-at-a-glance).)_

- State lives in each `.harness-mini/docs/exec-plans/active/<plan>.md` frontmatter (`stage:`).
- **Plan-stage write ban:** while `stage` ∈ {intake, prd, issues}, no product-code
  edits (convention in `stage-viewer`; Mini has no permission engine).
- **Transition authority (mode C):** agents work freely *within* a stage, but
  only the **main agent** (via `stage-viewer`) advances the FSM. No sub-agent
  may mark its own output "done" — the evaluator gate plus main-agent control
  is the anti-self-praise firewall extended across the whole lifecycle.
- **The firewall has teeth:** promoting a plan to `done` requires a committed
  `verdict: pass` record at `.harness-mini/trace/evals/<plan>-NNN.md`; `harness.sh doctor`
  FAILs a done plan that lacks one. `harness.sh report` aggregates these verdicts
  (+ the runtime ctx trend) so the loop is measured, not asserted.
- **Garden triggers (orthogonal):** gardening fires on concrete signals, not
  "periodically" — **≥5 checkpoints** since the last sweep, a plan completing, a
  pending release, or the **smell backlog** (`.harness-mini/trace/garden-backlog.md`) crossing
  its threshold (any `high` / ≥3 open). `harness.sh status` prints `garden:
  DUE|ok` and a final `ready: <ready|warning|blocked> — <next>` verdict; the
  main agent dispatches the gardener. See the `garden` skill.

## Coding contract: horizontal + vertical (`slice-coding`)

- **Vertical** — build one feature as a thin walking skeleton end-to-end
  (it runs, it's tested) *before* starting the next feature. Depth-first,
  value-first.
- **Horizontal** — respect a fixed layer stack with **forward-only**
  dependencies. The reference stack (adapt per project):

  ```
  Types → Config → Repo → Service → Runtime → UI
  ```

  Cross-cutting concerns (auth, telemetry, feature flags, connectors) enter
  through a single explicit **Providers** seam. Nothing depends "backward."

- The rule: *a vertical slice proves the path; then expand horizontally across
  features within the same layered contract.* Enforce mechanically where the
  project allows (lint / structure tests); the generator reads this before
  writing code.
- **Parallel horizontal expansion:** once the vertical skeleton passes evaluate,
  the main agent may fan the remaining independent issues out to parallel
  generators — gated on **disjoint file footprints** so no two collide — then run
  a single integration evaluate (`parallel-slices`). Vertical-first, then widen in
  parallel.

## New vs existing project (set by `init.sh`)

- **new** → generative bootstrap: seed `0001-intake.md`, run the founder funnel
  (founder-check → to-prd → to-issues).
- **existing** → recon graft: seed `0001-recon.md`, the explorer maps the
  codebase into `.harness-mini/architecture.md` ("Domains & layers"); skip the founder
  funnel; install additively without overwriting anything.
