# Architecture

Top-level map of how harness-mini is laid out and how work flows through it.

## Repository layout

```
AGENTS.md              # ~100-line map injected every run (table of contents)
ARCHITECTURE.md        # this file
init.sh                # additive, idempotent installer (new vs existing)
bin/
  ctx.sh               # context % estimate vs the 40% threshold
  trace.sh             # append runtime JSONL (best-effort, never blocks)
  ralph.sh             # ralph-loop driver (work → check → repeat)
skills/                # source skills → installed to .claude/skills/
agents/                # source sub-agents → installed to .claude/agents/
docs/
  principles.md        # golden principles + Five-Step core-mind
  smart-dumb.md        # the 40% occupancy contract
  exec-plans/
    active/            # in-flight plans + decision logs (committed)
    completed/         # archived plans (committed)
  references/          # *-llms.txt distillates of the source blogs
tests/run.sh           # zero-dep TDD suite for bin/* and init.sh
harness/manifest.md    # neutral pointer list for non-Claude CLIs
.trace/
  checkpoints/         # COMMITTED — decisions, milestones, handoffs
  runtime/             # GITIGNORED — ephemeral per-run JSONL
```

## Lifecycle FSM

```
intake → prd → issues → implement ⇄ evaluate → checkpoint → done
                           ↑___________|   (loop until criteria pass)
       garden ──── runs orthogonally, periodically ────
```

- State lives in each `docs/exec-plans/active/<plan>.md` frontmatter (`stage:`).
- **Transition authority (mode C):** agents work freely *within* a stage, but
  only the **main agent** (via `stage-viewer`) advances the FSM. No sub-agent
  may mark its own output "done" — the evaluator gate plus main-agent control
  is the anti-self-praise firewall extended across the whole lifecycle.

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

## New vs existing project (set by `init.sh`)

- **new** → generative bootstrap: seed `0001-intake.md`, run the founder funnel
  (founder-check → five-step → to-prd → to-issues).
- **existing** → recon graft: seed `0001-recon.md`, the explorer maps the
  codebase into this file's "Domains & layers" section below; skip the founder
  funnel; install additively without overwriting anything.

## Domains & layers
<!-- The explorer fills this in during recon of an existing project. -->
_(empty until a project is mapped)_
