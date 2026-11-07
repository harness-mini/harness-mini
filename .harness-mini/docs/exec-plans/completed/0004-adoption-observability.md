---
plan: adoption-observability
seq: 0004
stage: done
owner: main
---
# Adoption & observability (the 10 directions)

Make the harness easier to **adopt, observe, and trust** without making it
heavier to install or harder to reason about. Resolved via a grill-me session
(2026-05-30). Delivered as **4 grouped PRs** in priority order:
*understandable → resumable → observable → (only then) automate.*

## Resolved decisions (truth table)
- **#1/#3 walkthrough** — `docs/walkthrough.md` narrates one full loop; authored
  illustrative bundle in `docs/examples/demo-auth/` (`0001-demo-auth.md` + 2–3
  checkpoints). NOT under `exec-plans/` (never mistaken for active work).
- **#2 codex/cursor** — `docs/codex-getting-started.md`, `docs/cursor-getting-started.md`;
  manifest stays neutral; explicit "no sub-agents → run the role as a fresh
  prompt/thread" fallback. Docs only, no adapters.
- **#8 tiered eval** — convention in `skills/evaluate/SKILL.md`: L0 self-check +
  evidence (tiny) · **L1 independent lightweight = DEFAULT** (haiku/fresh ctx) ·
  L2 opus (cross-slice/arch/security/data-loss/public-API/release). Not a runtime.
- **#10 quick/full** — `docs/templates/{quick,full}-plan.md` + README first-screen
  decision table. Surfaces the `stage-viewer` simple/complex routing.
- **#3 doctor** — `harness.sh doctor`; 3-severity soft exit (FAIL→exit 1). Checks:
  AGENTS.md, harness.lock, skill folder-shape, manifest lists skills, active
  exec-plan, .trace/runtime ignored, unresolved .new (WARN), version==lock (WARN),
  + #9 source↔mirror divergence (WARN). `check` reserved for stricter CI later.
- **#4 status** — `harness.sh status`: version · active plans+stages · latest
  checkpoint/plan · .new count · last ctx_pct+event (tail -n1) · resumable bool.
  grep/awk/tail only — NO JSONL parsing engine.
- **#5 ctx** — already configurable (`HARNESS_CTX_THRESHOLD`). Work = docs
  (`smart-dumb.md` 30/40/60 examples + when to adjust), `ctx.sh` help examples,
  `status` surfaces last ctx_pct.
- **#6 shell-compat** — CONTRIBUTING section (bash 3.2/macOS, linux bash,
  zsh-callable, no deps, GNU/BSD diffs) + brief README line.
- **#7 recon** — concrete output schema (entry points; test/build/lint cmd;
  domains; layers; risky + generated/vendor dirs; where behaviour + tests live;
  one recommended first slice) into the `0001-recon.md` seed (`init.sh`) +
  `agents/explorer.md`.
- **#9 double tree** — canonical `skills/`; committed **generated** `.claude/`
  mirror; `doctor` divergence WARN + documented `cp -R skills/. .claude/skills/`
  regen; README/CONTRIBUTING state it loudly.

## PR breakdown
- **PR A — first-run docs** (this branch): #2, #10, #6, #9-docs, #5-docs, #7.
- **PR B — walkthrough + demo-auth example**: #1/#3.
- **PR C — tiered evaluation convention**: #8.
- **PR D — health commands (TDD)**: #3 doctor, #4 status, #9 divergence check,
  #5 ctx_pct surfacing.

## Mini guardrails (apply to every PR)
- Docs/conventions/templates + thin POSIX shell only; no runtime/deps.
- `status`/`doctor` use grep/awk/tail — no JSON parser.
- Each PR: branch → green `tests/run.sh` → PR (per [[git-flow-preference]]).

## Now (resume here)
- **DONE.** All 4 PRs merged (#2–#5); all 10 directions delivered. Shipped as
  **v0.3.0** (tag + GitHub release). 84/84 green.

## Next
- Nothing for 0004. Future work starts a fresh plan (`stage-viewer` routes
  quick vs full).

## Decisions log
- 2026-05-30: grill-me converged all 10 + 4-PR delivery. Stage=implement.
- 2026-05-30: PR A built (docs only; also fixed stale skills/*.md links left by
  the folder migration). Forward-refs to unbuilt status/doctor/walkthrough avoided.
- 2026-05-30: PR A merged (#2). PR B built — walkthrough uses an authored
  demo-auth bundle (illustrative; not a live run) per the grill decision.
