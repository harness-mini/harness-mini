# harness-mini — agent map

<!-- AGENT-MAP v1 · sections carry ANCHOR: marks — jump by trigger, read one target, never preload -->

> **⌖ Context navigation map** — injected every run. A **map, not an encyclopedia**:
> read the pointer your trigger names, not the whole territory. Prune aggressively.

| Anchor | Jump when… |
|--------|------------|
| **`gate`** | any non-trivial task starts here — routing + precedence |
| **`forty`** | context feels heavy, or it's time to checkpoint/reset |
| **`mini`** · **`versioning`** | adding to / updating the harness itself |
| **`fsm`** | you need stage rules or want to advance a plan |
| **`map`** | you need to find where something lives |
| **`skills`** · **`agents`** | picking the tool or worker for a stage |
| **`trace`** | logging an event or committing a checkpoint |

## Start here — routing gate (mandatory, precedence)

<!-- ANCHOR: gate -->

When a new session starts, **MUST FIRST** run
`"$HOME/.harness-mini/bin/harness.sh" status` from the project root to check
the active workboard and its session `path:` line, then open the matching
session skill and follow it. Harness executables live in the user's runtime,
not in the project:

- `path: init` → **`session-init`** — plan-layer work only (founder funnel,
  PRD, issues, JSON twin). **No product code on this path.**
- `path: coding` → **`session-coding`** — complete its **Getting Bearings** first turn before any product edit; then implement exactly one slice: the highest-priority `passes: false` slice the workboard's `next:` points at.

Then, before non-trivial work — a feature, a
multi-step or ambiguous change, anything cross-cutting — **route it through the
`stage-viewer` skill first**; when a harness skill and another tool both fit,
**the harness skill wins.** Trivial one-line fixes may skip the ceremony (quick
mode). The repository is the **system of record** — anything not in a
version-controlled file does not exist to you.

Quick repository map (details in the `map` anchor below):

- **Architecture definition**: `ARCHITECTURE.md`
- **Execution plans**: active plans live under `docs/exec-plans/active/`
  (same-basename `.md` + `.json` twins). Do NOT load the full historical
  records — read only the plan you are working, and only your slice.
- **Quality & constraints**: `docs/smart-dumb.md` (maintain the 40% guardrail).

## The one rule that governs everything: the 40% line

<!-- ANCHOR: forty -->

Context occupancy below **40%** is the *smart zone* (you reason sharply); at or
above 40% is the *dumb zone* (you degrade, lose instructions, get "context
anxiety"). Keep yourself smart:

1. **Delegate heavy work.** Any operation that would read more than ~2k tokens
   (broad searches, large files, log scans) → spawn the **explorer** agent and
   take back only its distilled answer. Sub-agents are context firewalls.
2. **Checkpoint at 40%.** When you cross the line, stop taking new work, write a
   checkpoint (`checkpoint` skill → `.trace/checkpoints/`), update the active
   exec-plan, and reset — while still smart enough to write a good handoff.
3. **One bounded task per session.** A session scoped to a single plan-step never
   needs to hold everything.

Estimate occupancy any time with
`"$HOME/.harness-mini/bin/ctx.sh" <used_tokens> [window]`.
Full contract: `docs/smart-dumb.md`.

## Core constraint: Mini (when changing the harness itself)

<!-- ANCHOR: mini -->

The harness *is the environment, not a program.* Before adding anything to
harness-mini: **shell-or-doc first, no environment dependence, no complex
languages.** A new capability is a Markdown skill/agent/doc by default and only
becomes a small POSIX `bin/*.sh` when it must execute — never a runtime, package
manager, or third-party binary. Question harness requirements and try to
**delete** before adding. Full contract: `docs/principles.md` → "The Mini constraint."

## Lifecycle (the state machine you live inside)

<!-- ANCHOR: fsm -->

`intake → prd → issues → implement ⇄ evaluate → checkpoint → done`, with `garden`
running orthogonally on triggers — full diagram + per-state exit conditions:
`ARCHITECTURE.md#lifecycle-at-a-glance`.

- Only the **main agent** (via the `stage-viewer` skill) advances the stage.
  **No worker may promote its own work to "done."** (Anti-self-praise firewall.)
- Each requirement is a **dual-file plan** in `docs/exec-plans/active/`:
  `<NNN-slug>.md` (narrative, frontmatter `stage:` = the lifecycle authority)
  + `<NNN-slug>.json` (machine workboard: `status`, `current_slice_id`,
  `slices[].passes`). Read it before acting; act only within your role's stage.
  Never alter `steps` in the JSON — they are the slice's test conditions.

## Where things live (progressive disclosure)

<!-- ANCHOR: map -->

| Need | Go to |
|------|-------|
| Core beliefs + delete-first discipline | `docs/principles.md` |
| Load-bearing assumptions + staleness tests | `docs/assumptions.md` |
| The smart/dumb (40%) contract | `docs/smart-dumb.md` |
| Lifecycle FSM diagram + layer stack | `ARCHITECTURE.md#lifecycle-at-a-glance` |
| Active work + decision logs | `docs/exec-plans/active/` |
| Source-blog distillates | `docs/references/*-llms.txt` |
| Skills (how to do a task) | `skills/<name>/SKILL.md` here; `.agents/skills/<name>/SKILL.md` after install |
| Sub-agents (who does the work) | `agents/<name>.md` here; `harness/agents/<name>.md` after install |
| Committed checkpoints (institutional memory) | `.trace/checkpoints/` |
| Committed evaluation verdicts (the `done`-gate) | `.trace/evals/<plan>-NNN.md` |
| Ephemeral runtime traces (gitignored) | `.trace/runtime/` |

## Versioning — `~/.harness-mini/bin/harness.sh` (the front door)

<!-- ANCHOR: versioning -->

`"$HOME/.harness-mini/bin/harness.sh" help` lists the commands (`version` ·
`update` · `doctor` · `status` · `report` · `release`); runtime checksums live
in `~/.harness-mini/harness/runtime.lock`, and project checksums live in
`harness/harness.lock` (canonical version source: `VERSION`). Non-obvious
semantics:
`update` is **checksum-guarded** (your edits kept, upstream lands as `<file>.new`;
`docs/exec-plans/` + `.trace/` never touched); `doctor` enforces the **eval-gate**
(`done` needs a `verdict: pass` in `.trace/evals/`); `status` ends with a
**`ready:`** verdict; `release` is source-repo only (the `release` skill).

## Skills by stage

<!-- ANCHOR: skills -->

- **orchestrate:** `stage-viewer`, `session-init` (`path: init` boards — plan-layer only), `session-coding` (`path: coding` boards — bearings first), `ralph-loop`, `checkpoint`, `grill-me`, `release`
- **intake (new project only):** `founder-check`
- **plan:** `to-prd`, `to-issues`
- **implement:** `tdd`, `slice-coding`, `parallel-slices`, `clean-code`, `refactor`
- **evaluate:** `evaluate` (tiered by risk: L0 self-check · **L1 lightweight, default** · L2 full Opus evaluator)
- **maintain:** `garden` (triggers: ≥5 checkpoints · plan-done · pre-release · smell backlog; `harness.sh status` shows `garden: DUE|ok`)

## Sub-agents (separate context windows = firewalls)

<!-- ANCHOR: agents -->

| Agent | Role | Skills | Model |
|-------|------|--------|-------|
| planner | goal → exec-plan | to-prd, to-issues | sonnet |
| generator | build one slice via TDD | tdd, slice-coding, clean-code, refactor, checkpoint | sonnet · *opus* |
| evaluator | grade vs criteria (separate window) | evaluate, clean-code | opus |
| explorer | disposable read/search → distillate | (none) | haiku |
| gardener | entropy GC, demote stale context | garden, refactor, clean-code | haiku |

Model = capability **tier** (CLI maps it), not a pinned version. The generator
auto-upgrades to the top tier (`opus`) when `HARNESS_TOP_MODEL` is set; every
other role keeps its static tier. Resolve at spawn time with
`"$HOME/.harness-mini/bin/model.sh" builder` (`HARNESS_MODEL_BUILDER=<alias>` pins an exact model).

## Tracing (best-effort, never blocks work)

<!-- ANCHOR: trace -->

Log events with `"$HOME/.harness-mini/bin/trace.sh" <agent> <stage> <event> [k=v ...]` → appends JSONL
to `.trace/runtime/`. Include `ctx_pct=<n>` so the 40% line is observable.
Commit milestones as checkpoints in `.trace/checkpoints/` (the `checkpoint` skill).
