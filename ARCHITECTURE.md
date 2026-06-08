# Architecture

Top-level map of how harness-mini is laid out and how work flows through it.

## Repository layout

```
AGENTS.md              # ~100-line map injected every run (table of contents)
ARCHITECTURE.md        # this file
VERSION                # canonical version (SemVer); bumped by `harness.sh release`
CHANGELOG.md           # Keep-a-Changelog; rolled on release
init.sh                # additive, idempotent installer (new vs existing)
bin/
  harness.sh           # front-door CLI: version·update·doctor·status·release
  _harness_lib.sh      # shared helpers: managed-set, checksums, lockfile
  ctx.sh               # context % estimate vs the 40% threshold
  trace.sh             # append runtime JSONL (best-effort, never blocks)
  ralph.sh             # ralph-loop driver (work → check → repeat)
skills/                # one folder per skill: <name>/SKILL.md (required;
                       #   metadata in frontmatter) + optional scripts/
                       #   references/ assets/ examples/ tests/.
                       #   Installed (recursively) to .claude/skills/<name>/
agents/                # sub-agents, flat <name>.md → installed to .claude/agents/
docs/
  principles.md        # golden principles + Five-Step core-mind
  smart-dumb.md        # the 40% occupancy contract
  exec-plans/
    active/            # in-flight plans + decision logs (committed)
    completed/         # archived plans (committed)
  references/          # *-llms.txt distillates of the source blogs
tests/run.sh           # zero-dep TDD suite for bin/* and init.sh
harness/
  manifest.md          # neutral pointer list for non-Claude CLIs
  harness.lock         # installed version + pristine checksums of managed files
.trace/
  checkpoints/         # COMMITTED — decisions, milestones, handoffs
  evals/               # COMMITTED — <plan>-NNN.md verdicts (the done-gate)
  runtime/             # GITIGNORED — ephemeral per-run JSONL (report reads these)
```

## Versioning & update model

An install is a snapshot of the **managed set** — the files harness-mini owns
(`bin/*`, `.claude/skills/**` recursively, `.claude/agents/*`,
`docs/principles.md`, `docs/smart-dumb.md`, `docs/references/*`, `AGENTS.md`,
`ARCHITECTURE.md`). The set is defined once, in `emit_managed_pairs()`
(`bin/_harness_lib.sh`) — which recurses `skills/` so every file under a skill
folder is tracked — and is the
single boundary between "harness territory" and "user territory" (your
exec-plans, `.trace/`, and project code are never in it).

`init.sh` writes `harness/harness.lock` recording the version and the **pristine
upstream checksum** of each managed file. `harness.sh update` diffs three states
per file — `base` (lock baseline), `cur` (on disk), `new` (upstream) — to decide
ADD / UNCHANGED / UPDATE / CONFLICT, so a newer harness can be pulled in without
ever clobbering a file you edited. `harness.sh release` is the inverse end: it
stamps a new `VERSION`, rolls `CHANGELOG.md`, tags `v<x.y.z>`, and publishes a
GitHub release (gated on green tests + a clean tree).

## Lifecycle FSM

```
intake → prd → issues → implement ⇄ evaluate → checkpoint → done
                           ↑___________|   (loop until criteria pass)
       garden ──── runs orthogonally, on triggers ────
```

- State lives in each `docs/exec-plans/active/<plan>.md` frontmatter (`stage:`).
- **Transition authority (mode C):** agents work freely *within* a stage, but
  only the **main agent** (via `stage-viewer`) advances the FSM. No sub-agent
  may mark its own output "done" — the evaluator gate plus main-agent control
  is the anti-self-praise firewall extended across the whole lifecycle.
- **The firewall has teeth:** promoting a plan to `done` requires a committed
  `verdict: pass` record at `.trace/evals/<plan>-NNN.md`; `harness.sh doctor`
  FAILs a done plan that lacks one. `harness.sh report` aggregates these verdicts
  (+ the runtime ctx trend) so the loop is measured, not asserted.
- **Garden triggers (orthogonal):** gardening fires on concrete signals, not
  "periodically" — **≥5 checkpoints** since the last sweep, a plan completing, a
  pending release, or the **smell backlog** (`.trace/garden-backlog.md`) crossing
  its threshold (any `high` / ≥3 open). `harness.sh status` prints `garden:
  DUE|ok`; the main agent dispatches the gardener. See the `garden` skill.

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
  (founder-check → five-step → to-prd → to-issues).
- **existing** → recon graft: seed `0001-recon.md`, the explorer maps the
  codebase into this file's "Domains & layers" section below; skip the founder
  funnel; install additively without overwriting anything.

## Domains & layers
<!-- The explorer fills this in during recon of an existing project. -->
_(empty until a project is mapped)_
