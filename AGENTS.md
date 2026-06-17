# harness-mini — agent map

> This file is a **map, not an encyclopedia** (~100 lines). It is injected into
> every run. Keep it small: a table of contents pointing at the system of record.
> If everything is "important," nothing is. Prune aggressively.

## Start here — routing gate (precedence)

This project runs on **harness-mini**. Before non-trivial work — a feature, a
multi-step or ambiguous change, anything cross-cutting — **route it through the
`stage-viewer` skill first**, and prefer harness-mini's lifecycle, skills, and
sub-agents over ad-hoc tools or other installed plugins. When a harness skill and
another tool both fit, **the harness skill wins.** Trivial one-line fixes may skip
the ceremony (quick mode). On entering a fresh session, `stage-viewer` first
checks for a newer harness-mini (`bin/harness.sh version`) and prompts you to
update. The rest of this file is the map. The repository is the **system of
record** — anything not in a version-controlled file does not exist to you; read
the pointer you need, when you need it, never preload everything.

## The one rule that governs everything: the 40% line

Context occupancy below **40%** is the *smart zone* (you reason sharply); at or
above 40% is the *dumb zone* (you degrade, lose instructions, get "context
anxiety"). Keep yourself smart:

1. **Delegate heavy work.** Any operation that would read more than ~2k tokens
   (broad searches, large files, log scans) → spawn the **explorer** agent and
   take back only its distilled answer. Sub-agents are context firewalls.
2. **Checkpoint at 40%.** When you cross the line, stop taking new work, write a
   checkpoint (`checkpoint` skill → `.trace/checkpoints/`), update the active
   exec-plan, and reset. Hand off *while you are still smart enough to write a
   good handoff.*
3. **One bounded task per session.** A session scoped to a single plan-step never
   needs to hold everything.

Estimate occupancy any time with `bin/ctx.sh <used_tokens> [window]`.
Full contract: `docs/smart-dumb.md`.

## Core constraint: Mini (when changing the harness itself)

The harness *is the environment, not a program.* Before adding anything to
harness-mini: **shell-or-doc first, no environment dependence, no complex
languages.** A new capability is a Markdown skill/agent/doc by default and only
becomes a small POSIX `bin/*.sh` when it must execute — never a runtime, package
manager, or third-party binary. Apply the Five-Step to the harness itself: try to
**delete** before you add. Full contract: `docs/principles.md` → "The Mini constraint."

## Lifecycle (the state machine you live inside)

```
intake → prd → issues → implement ⇄ evaluate → checkpoint → done
                           ↑___________|   (loop until criteria pass)
       garden ──── runs orthogonally, on triggers ────
```

- Only the **main agent** (via the `stage-viewer` skill) advances the stage.
  **No worker may promote its own work to "done."** (Anti-self-praise firewall.)
- Each requirement is a file in `docs/exec-plans/active/<plan>.md` with a
  `stage:` field. Read it before acting; act only within your role's stage.

## Where things live (progressive disclosure)

| Need | Go to |
|------|-------|
| Core beliefs + Musk's Five-Step core-mind | `docs/principles.md` |
| Load-bearing assumptions + staleness tests | `docs/assumptions.md` |
| The smart/dumb (40%) contract | `docs/smart-dumb.md` |
| Layer stack + lifecycle FSM detail | `ARCHITECTURE.md` |
| Active work + decision logs | `docs/exec-plans/active/` |
| Source-blog distillates | `docs/references/*-llms.txt` |
| Skills (how to do a task) | `.claude/skills/<name>/SKILL.md` (one folder per skill) |
| Sub-agents (who does the work) | `.claude/agents/<name>.md` (flat) |
| Committed checkpoints (institutional memory) | `.trace/checkpoints/` |
| Committed evaluation verdicts (the `done`-gate) | `.trace/evals/<plan>-NNN.md` |
| Ephemeral runtime traces (gitignored) | `.trace/runtime/` |

## Versioning — `bin/harness.sh` (the front door)

`bin/harness.sh help` lists the commands (`version` · `update` · `doctor` ·
`status` · `report` · `release`); installed version + checksums live in
`harness/harness.lock` (canonical source: `VERSION`). Two semantics that aren't
obvious from `--help`: `update` is **checksum-guarded** — your edits are kept,
upstream lands as `<file>.new`, and `docs/exec-plans/` + `.trace/` are never
touched; `doctor` enforces the **eval-gate** — a plan can't be `done` without a
`verdict: pass` record in `.trace/evals/`. `release` is source-repo only (see the
`release` skill).

## Skills by stage

- **orchestrate:** `stage-viewer`, `ralph-loop`, `checkpoint`, `five-step`, `grill-me`, `release`
- **intake (new project only):** `founder-check`
- **plan:** `to-prd`, `to-issues`
- **implement:** `tdd`, `slice-coding`, `parallel-slices`, `clean-code`, `refactor`
- **evaluate:** `evaluate` (tiered by risk: L0 self-check · **L1 lightweight, default** · L2 full Opus evaluator)
- **maintain:** `garden` (triggers: ≥5 checkpoints · plan-done · pre-release · smell backlog; `harness.sh status` shows `garden: DUE|ok`)

## Sub-agents (separate context windows = firewalls)

| Agent | Role | Skills | Model |
|-------|------|--------|-------|
| planner | goal → exec-plan | to-prd, to-issues, five-step | sonnet |
| generator | build one slice via TDD | tdd, slice-coding, clean-code, refactor, checkpoint | sonnet · *opus* |
| evaluator | grade vs criteria (separate window) | evaluate, clean-code | opus |
| explorer | disposable read/search → distillate | (none) | haiku |
| gardener | entropy GC, demote stale context | garden, refactor, clean-code | haiku |

Model = capability **tier** (CLI maps it), not a pinned version. The builder
(generator) auto-upgrades to the top tier (`opus`) when `HARNESS_TOP_MODEL` is
set, else stays sonnet; every other role keeps its static tier. The spawning
agent resolves it with `bin/model.sh builder` and passes it as the worker's model
override (`HARNESS_MODEL_BUILDER=<alias>` pins an exact model).

## Tracing (best-effort, never blocks work)

Log events with `bin/trace.sh <agent> <stage> <event> [k=v ...]` → appends JSONL
to `.trace/runtime/`. Include `ctx_pct=<n>` so the 40% line is observable.
Commit milestones as checkpoints in `.trace/checkpoints/` (the `checkpoint` skill).
