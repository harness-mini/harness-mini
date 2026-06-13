# harness-mini

Run an agent like Claude Code on a long task and it **drifts** — wandering off
the goal, re-deciding settled questions, and polishing the wrong thing. Push the
session further and its **context explodes**, as heavy reads and dead-end
transcripts crowd out working memory until the agent goes dumb. Close the window
and **session amnesia** wipes every hard-won decision, constraint, and in-flight
plan you had built up.

harness-mini is a minimal, CLI-agnostic agent harness — convention, skills,
sub-agents, and distilled best-practice docs over thin shell glue — that keeps a
long-running agent on-task, context-light, and resumable across sessions.

## Quick Demo

<!-- TODO: replace with asciicast recording -->

> _Placeholder for an asciicast recording._ The clip should show, end-to-end:
> `init.sh` grafting the harness into a project, the agent routing a real task
> through `stage-viewer` (intake → prd → issues → implement), a disposable
> `explorer` absorbing a heavy read so the main context stays under the 40% line,
> an `evaluator` grading the slice in a separate window, and a committed
> checkpoint that a brand-new session resumes from with zero context loss.

## Install

It installs like a skill — tell your agent *"install harness-mini here"*, or run:

```bash
git clone https://github.com/harness-mini/harness-mini.git
bash harness-mini/init.sh /path/to/your/project
```

`init.sh` is **additive** (never overwrites your files) and **idempotent** (safe
to re-run). It behaves asymmetrically:

- **New/empty project** → generative bootstrap: seeds an intake plan and runs the
  founder funnel (`founder-check → five-step → to-prd → to-issues`).
- **Existing project** → recon graft: installs additively and seeds a recon plan
  (the `explorer` maps your codebase into `ARCHITECTURE.md`); skips the founder
  funnel.

Skills install to `.claude/skills/` and agents to `.claude/agents/` (auto-loaded
by Claude Code); `harness/manifest.md` is a neutral pointer list for other CLIs.

So the agent **prefers the harness by default** (rather than waiting to be told),
`init.sh` also seeds a short **routing gate** into each CLI's native always-on
file — `CLAUDE.md` (Claude Code), `.cursor/rules/harness-mini.mdc` (Cursor), and
the top of `AGENTS.md` (Codex). The gate says: route non-trivial work through
`stage-viewer` first and, when a harness skill and another tool both fit, *the
harness skill wins*. Seeding is additive + idempotent — an existing `CLAUDE.md`
keeps its content (the gate is appended once, marker-guarded).

**Other agents (Codex, Cursor, …):** the harness is plain Markdown + shell, so any
agent can use it by reading the files — see
[`docs/codex-getting-started.md`](docs/codex-getting-started.md) and
[`docs/cursor-getting-started.md`](docs/cursor-getting-started.md).

## Your first task: quick or full?

harness-mini does **not** force ceremony onto every change. Route first:

| If the task is… | Use | Path |
|---|---|---|
| a small bug fix · one obvious change · no ambiguity (≤ ~1 slice) | **Quick mode** | copy [`docs/templates/quick-plan.md`](docs/templates/quick-plan.md) → implement (`tdd`) → L0/L1 eval → checkpoint |
| ambiguous · cross-cutting · architecture/security/data-loss impact | **Full mode** | copy [`docs/templates/full-plan.md`](docs/templates/full-plan.md) → PRD → issues → implement → L1/L2 evaluate → checkpoint |

The `stage-viewer` skill makes this call; the templates are its two shapes. **New
to the loop? Watch one run end-to-end: [`docs/walkthrough.md`](docs/walkthrough.md).**

## Versioning & updates

The install is versioned. `bin/harness.sh` is the front door:

```bash
bin/harness.sh version              # installed version (+ latest, best-effort)
bin/harness.sh update               # pull a newer harness into this project
bin/harness.sh doctor               # install health: ok/warn/fail (exit 1 on fail)
bin/harness.sh status               # current work state (plans, checkpoints, resumable)
bin/harness.sh report               # aggregate .trace metrics (stages, context, evals)
bin/harness.sh release <x.y.z>      # (source repo) bump + tag + GitHub release
```

The firewall has **teeth**: a plan can't reach `done` without a committed
`verdict: pass` record in `.trace/evals/` — `doctor` FAILs otherwise. `report`
turns the runtime traces into a metrics summary (context trend vs the 40% line,
eval pass-rate + rework loops) so the thresholds are tuned by data, not vibes.
Claude Code users can give the 40% rule teeth too with the opt-in
`bin/ctx-hook.sh` (see `docs/smart-dumb.md`).

On entering a fresh session the agent checks for a newer release first (the
routing gate + `stage-viewer` run `harness.sh version`); `version`, `status`, and
`doctor` all surface an **update reminder** when one is available, so you're
prompted to `update` rather than drifting behind. The check is best-effort and
silent offline (`HARNESS_NO_NET`); `HARNESS_LATEST` pins it.

`init.sh` records the version and a checksum of every harness-owned file in
`harness/harness.lock`. `update` is **checksum-guarded**: files you never touched
are refreshed silently, files **you edited are kept** (the upstream copy is
written next to them as `<file>.new`), and brand-new files are added — your
exec-plans, `.trace/`, and project code are never touched. `release` stamps
`VERSION`, rolls `CHANGELOG.md`, tags `v<x.y.z>`, and cuts a GitHub release,
gated on green tests + a clean tree (see the `release` skill).

## The one rule: the 40% line

Context occupancy **below 40% = smart zone**; **at/above 40% = dumb zone**. Every
agent keeps itself smart by (1) delegating heavy reads to a disposable `explorer`
(context firewall), (2) checkpointing + resetting at 40%, (3) progressive
disclosure. See `docs/smart-dumb.md`. Estimate with `bin/ctx.sh <used> [window]`.

## Lifecycle

```
intake → prd → issues → implement ⇄ evaluate → checkpoint → done
                           ↑___________|   (loop until criteria pass)
       garden ──── runs orthogonally, on triggers ────
```

Only the main agent advances the stage (via `stage-viewer`). No worker promotes
its own work to "done" — evaluation happens in a **separate context** (the
anti-self-praise gate), **tiered by risk**: L0 self-check · **L1 lightweight
reviewer (default)** · L2 full Opus evaluator. See the `evaluate` skill.

## Layout

| Path | Purpose |
|------|---------|
| `AGENTS.md` | ~100-line map injected every run |
| `ARCHITECTURE.md` | layer stack + lifecycle FSM |
| `init.sh` | additive/idempotent installer |
| `VERSION` · `CHANGELOG.md` | canonical version (SemVer) · release log |
| `bin/harness.sh` | front-door CLI: `version`·`update`·`doctor`·`status`·`report`·`release` |
| `bin/{ctx,trace,ralph}.sh` | context gauge · JSONL tracer · ralph loop |
| `bin/model.sh` | resolve a role's model alias (builder → the highest-available frontier model tier when enabled) |
| `bin/ctx-hook.sh` | opt-in Claude Code PostToolUse hook (auto ctx_pct + 40% nudge) |
| `harness/harness.lock` | installed version + managed-file checksums |
| `skills/<name>/SKILL.md` → `.claude/skills/` | 16 skills (one folder each) |
| `agents/` → `.claude/agents/` | 5 sub-agents (who does the work) |
| `docs/principles.md` | golden principles + Musk's Five-Step core-mind |
| `docs/smart-dumb.md` | the 40% contract |
| `docs/exec-plans/{active,completed}/` | plans + decision logs (committed) |
| `docs/references/*-llms.txt` | the 5 source distillates |
| `.trace/checkpoints/` | committed handoffs (institutional memory) |
| `.trace/evals/` | committed evaluation verdicts (the `done`-gate `doctor` enforces) |
| `.trace/runtime/` | gitignored ephemeral JSONL traces (`harness.sh report` reads these) |
| `tests/run.sh` | zero-dep TDD suite |

> **Editing skills?** `skills/<name>/SKILL.md` (and `agents/<name>.md`) are the
> **canonical source** — edit there. `.claude/skills/` and `.claude/agents/` are a
> committed **generated mirror** so Claude Code discovers the harness in this repo;
> regenerate with `cp -R skills/. .claude/skills/` (and `agents/`). Don't hand-edit
> the mirror.

## Sub-agents

| Agent | Role | Model |
|-------|------|-------|
| planner | goal → exec-plan + issues | sonnet |
| generator | build one slice via TDD | sonnet · **opus** when enabled |
| evaluator | grade vs criteria (separate window) | opus |
| explorer | disposable read/search → distillate | haiku |
| gardener | entropy GC / doc-gardening | haiku |

Model is a capability **tier**, not a pinned version. The **builder** (generator)
auto-upgrades to **the highest-available frontier model tier** (`opus`, the top
tier the harness names) when `HARNESS_TOP_MODEL` is set, falling back to sonnet
otherwise; every other role keeps its static tier. The spawning agent resolves it
at spawn time via `bin/model.sh builder` and passes the result as the worker's
model override. Set `HARNESS_TOP_MODEL=1` to force the upgrade;
`HARNESS_MODEL_BUILDER=<alias>` pins the builder to an exact model.

## Develop

```bash
bash tests/run.sh   # 148 assertions, zero dependencies
```

Pure POSIX shell, no dependencies — tested on macOS `bash` 3.2 and Linux `bash`,
and safe to call from `zsh`. See the compatibility notes in
[`CONTRIBUTING.md`](CONTRIBUTING.md) before contributing shell.

## References distilled in `docs/references/`
- Anthropic — Effective harnesses for long-running agents
- Anthropic — Harness design for long-running apps
- Anthropic — Scaling managed agents (decoupling brain/hands/session; stale assumptions)
- OpenAI — Harness engineering (leveraging Codex)
- Anthropic — The Founder's Playbook

## Contributing

Issues and PRs welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). It's a small,
opinionated harness: most contributions are Markdown (skills, agents, docs) plus
the occasional ~30 lines of test-first shell. Ship thin, keep it smart.

## Community

[GitHub Discussions](https://github.com/harness-mini/harness-mini/discussions) —
questions, show-and-tell, and feedback welcome.

## License

[MIT](LICENSE) © 2026 harness-mini contributors.
