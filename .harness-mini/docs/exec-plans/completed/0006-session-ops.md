---
plan: session-ops
seq: 0006
stage: done
owner: main
mode: full
eval: L1
---
# Session ops (OpenHarness-inspired, Mini-shaped) — full mode

> Borrow three *ideas* from OpenHarness (dry-run readiness, plan-mode write
> discipline, compact-with-state) and express them as **docs + thin shell** only.
> Do not grow a second agent runtime.

## Intake (existing project — recon + five-step; no founder-check)

**Source of the ask:** compare HKUDS/OpenHarness vs harness-mini; take the top
three Mini-compatible borrows that improve cold resume and stage discipline
without violating the Mini constraint (`docs/principles.md`).

**Riskiest assumption:** a one-line `ready|warning|blocked` verdict on `status`
meaningfully changes agent behavior (agents act on next-action) — not just
cosmetics. If agents ignore it, the feature is dead weight (Five-Step delete).

### Five-Step pass

1. **Less dumb (named):** Matt wants colder sessions to *know what to do next*
   and to stop agents writing product code during plan stages — without Mini
   becoming OpenHarness.
2. **Deleted (over-delete on purpose):**
   - Separate `harness.sh dry-run` / `oh`-style preview CLI
   - Permission engine, path deny lists, Pre/Post tool hook VM
   - `MEMORY.md` / `~/.ohmo`-style out-of-repo personal memory
   - Team coordinator / background task daemon (already have `ralph-loop` +
     `parallel-slices`)
   - Standalone `harness.sh skills` command (inventory folds into `status`)
   - Mechanical git-diff “write ban” in `doctor` (project-specific, brittle;
     predict ≤10% add-back as a *soft WARN heuristic* only if grill says yes)
   - New `mode:` frontmatter if `stage:` already encodes plan vs build
3. **Simplified survivors:**
   - `status` gains a single **readiness** line (`ready|warning|blocked` + next)
   - `checkpoint` skill gains a **Task state** block (compact-with-state payload)
   - `stage-viewer` (+ planner pointer) gains a **plan-stage write ban** convention
4. **Accelerate:** TDD on `status` readiness first (walking skeleton); docs/skills
   follow the proven shape.
5. **Automate last:** only the readiness classifier in `cmd_status` (pure shell
   heuristics over files already read by status). No network, no JSON parser.

**Predict add-back (~10%):** a soft doctor WARN for “stage pre-implement but
working tree dirty outside docs/.trace” — only if grill confirms value.

Trace intent: `five_step deleted=7 survivors=3`.

## Problem

Cold agents (and humans) open a grafted project and see `status` facts but not a
**verdict** — so they re-decide “what’s broken / what’s next.” Separately, agents
in intake/prd/issues sometimes “helpfully” edit product code before the walking
skeleton is authorized. Separately again, checkpoints capture Done/Now/Next but
omit a compact **task state** payload that OpenHarness preserves across compact —
so resume loses acceptance progress, last green test, and file footprint.

## PRD

### Goal (smallest valuable outcome)

A cold session can run `bin/harness.sh status`, read one readiness verdict + next
action, resume from a checkpoint that carries Task state, and is constrained by
an explicit plan-stage write ban — all without new dependencies or a new binary
surface.

### Out of scope (stay deleted)

- Agent loop, tools, MCP, TUI, providers, plugins, personal-agent gateway
- New top-level CLI verb (`dry-run`, `skills`, `ready`)
- Out-of-repo memory files
- Hard permission enforcement / sandboxing
- Changing the 40% contract or eval-gate semantics

### Acceptance criteria

- [x] **AC1 — Readiness line:** `harness.sh status` prints exactly one line of the
      form `ready: <ready|warning|blocked> — <one next action>` derived from
      existing signals (active plan, checkpoint, garden, `.new`, update-behind,
      eval-gate-relevant state). Exit code stays 0. POSIX file utils only
      (grep/awk/sed/ls/find — same family as existing `cmd_status`/`doctor`).
- [x] **AC2 — Classifier contract (documented + tested):** *(grill #1 → A)*
      - `blocked` **only** when cold session cannot usefully proceed: install
        broken (e.g. missing AGENTS.md / no skills — doctor FAIL-class signals)
        **or** an active plan is `stage: done` with no `verdict: pass` record
      - `warning` when work can proceed but needs attention: **no active plan**,
        garden DUE, unresolved `.new`, behind latest, resumable partial
      - `ready` otherwise; next action → plan’s Now / first stage action
- [x] **AC3 — Task state in checkpoints:** `skills/checkpoint/SKILL.md` template
      includes a `## Task state` section with: acceptance-criteria status,
      file footprint in flight, last green test command, open issue IDs (or
      `none`). Mirror synced to `.claude/skills/`. Existing checkpoints remain
      valid (additive section).
- [x] **AC4 — Plan-stage write ban:** `skills/stage-viewer/SKILL.md` (and a
      one-line pointer from `agents/planner.md` if needed) states: while
      `stage` ∈ {intake, prd, issues}, agents **MUST NOT** modify product code;
      only `docs/`, `docs/exec-plans/`, `.trace/`, and harness skill/agent docs
      under edit for the *plan itself*. Mirror synced.
- [x] **AC5 — Mini constraint:** no new runtime, package, or non-POSIX tool;
      managed-set files stay shell-or-doc; `tests/run.sh` covers AC1/AC2.
- [x] **AC6 — Assumptions:** new mechanisms registered in `docs/assumptions.md`
      with a staleness test (readiness acted-upon; write-ban compliance).
- [x] **AC7 — Map touch:** `AGENTS.md` and/or `ARCHITECTURE.md` gain at most a
      short pointer (status readiness; plan-stage write ban) — map stays ~100
      lines; no encyclopedia.

### Vertical slices (build order)

1. **Skeleton:** readiness line in `cmd_status` + tests (AC1/AC2 core).
2. Checkpoint Task state template + mirror (AC3).
3. Plan-stage write ban in stage-viewer (+ planner pointer) + AC6/AC7 docs.

## Evaluation

- Tier: **L1** (default). Cross-cutting but low data-loss risk; public CLI
  surface is additive one line. Bump to L2 only if classifier grows beyond
  status’s existing signals.

## Now (resume here)

- **DONE.** Integration L1 pass (`session-ops-002`, 7/7). Archived to completed/.

## Next

- Nothing for 0006. Future work starts a fresh plan.

## Grill branches (resolved — remaining auto-locked to recommendations)

1. **blocked semantics:** → A (install-broken / done-without-eval only;
   no active plan = warning, not blocked)
2. **Write-ban teeth:** → A (convention-only in stage-viewer + planner pointer;
   no doctor/status git dirty-tree check)
3. **Skill inventory:** → skip (stays deleted; not in this plan)
4. **Readiness vs resumable:** → keep both lines; `ready:` next-action must not
   contradict `resumable:`; fix resumable to be **plan-scoped** (active plan’s
   own checkpoint), since today’s any-checkpoint heuristic is a cold-resume lie

## Issues (locked)

1. **Status readiness + plan-scoped resumable** — files: `bin/harness.sh`,
   `tests/run.sh` — depends-on: none — done = `ready:` line + classifier cases
   (blocked/warning/ready) green; resumable uses that plan’s checkpoints
2. **Checkpoint Task state** — files: `skills/checkpoint/SKILL.md`,
   `.claude/skills/checkpoint/SKILL.md` — depends-on: none (after #1 eval) —
   done = `## Task state` in template; mirror in sync
3. **Plan-stage write ban** — files: `skills/stage-viewer/SKILL.md`,
   `.claude/skills/stage-viewer/SKILL.md`, `agents/planner.md`,
   `.claude/agents/planner.md` — depends-on: none (after #1 eval) — done =
   MUST rule present; planner one-line pointer; mirrors in sync
4. **Assumptions + map pointers** — files: `docs/assumptions.md`,
   `AGENTS.md` and/or `ARCHITECTURE.md` — depends-on: #1,#2,#3 — done = A6/A7
   registered; map still ~100 lines

## Parallel groups (after #1 evaluates)

- Group A (parallel): #2 ∥ #3 — disjoint footprints
- Sequential: #1 → (#2 ∥ #3) → #4

## Decisions log

- 2026-08-11: Routed full mode (cross-cutting harness change). Existing project
  → five-step, no founder-check. Borrow scope locked to three Mini-shaped
  items; OpenHarness runtime explicitly out of scope.
- 2026-08-11: Five-step deleted 7 items; survivors = status readiness,
  checkpoint Task state, plan-stage write ban. Stage → prd.
- 2026-08-11: Grill #1 → **A**. `blocked` only for install-broken or active
  `done` without `verdict: pass`; no active plan → `warning` + next action.
- 2026-08-11: User: auto-lock remaining grill to recommendations; only escalate
  when highly uncertain. #2→A convention-only; #3→skip inventory; #4→keep both
  lines + plan-scoped resumable fix. Stage → issues → implement.
- 2026-08-11: Issues locked; stage → implement. Building #1 first.
- 2026-08-11: #1 L1 pass (session-ops-001); #2–#4 landed; integration L1 pass
  (session-ops-002, 7/7). Stage → done; plan archived.
