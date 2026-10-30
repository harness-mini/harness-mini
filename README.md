# harness-mini

**A minimal outer harness for developers' long coding tasks.**

Run a coding agent on a multi-session feature and it **drifts** — wandering off
the goal, re-deciding settled questions, polishing the wrong thing. Push further
and **context explodes** as heavy reads and dead ends crowd out working memory.
Close the window and **session amnesia** wipes decisions, constraints, and
in-flight plans.

harness-mini keeps that work **on-task, context-light, and resumable**: repo
conventions + thin shell glue (skills, sub-agents, distilled docs). It is an
**outer harness for coding** — not a generic agent shell, not a sandbox
platform. The contract is **files + shell**: any coding agent that can read the
repo and run commands can drive it.

### Who it's for / not for

| For | Not for |
|---|---|
| Developers doing cross-session feature work who will commit plans & traces | One-shot Q&A, chat-only agents, or anyone who won't write plans to git |
| Bootstrap → one feature at a time → independent eval → mergeable main | Generic non-coding long-running orchestration as the primary story |
| Outer harness (guides + sensors) around your coding agent | IDE replacement, multi-agent SaaS, or "sandbox as the product" |

### How it compares (one glance)

| | harness-mini | Generic agent harness | Bare coding agent | Host CI only |
|---|---|---|---|---|
| Focus | **Coding** long tasks | Often domain-general | Single-session by default | Gates after the fact |
| Cross-session bridge | Plans, checkpoints, evals in-repo | Varies / platform state | You reinvent it | No agent loop |
| Done gate | Independent evaluate + `doctor` | Often self-report | Easy to self-praise | Pass/fail without agent education |

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

Skills install to `.claude/skills/` and agents to `.claude/agents/`.
`harness/manifest.md` lists those paths. Any coding agent that can read the
repo and run shell can drive the same files.

So the agent **prefers the harness by default** (rather than waiting to be told),
`init.sh` also seeds a short **routing gate** into each host's always-on file —
`CLAUDE.md`, `.cursor/rules/harness-mini.mdc` (Cursor), and the top of
`AGENTS.md` (Codex). The gate says: route non-trivial work through
`stage-viewer` first and, when a harness skill and another tool both fit, *the
harness skill wins*. Seeding is additive + idempotent — an existing `CLAUDE.md`
keeps its content (the gate is appended once, marker-guarded).

### How a host picks it up

Same files everywhere. Nothing here is a primary agent; each host reads the
install layout in its own way:

| | On disk | How a host uses it |
|---|---|---|
| Skills (16) | `.claude/skills/<name>/SKILL.md` | Read the file. **Cursor** also gets an agent-requested `.cursor/rules/<skill>.mdc` (written by `init.sh`). **Codex** reads the file on demand. |
| Sub-agents (5) | `.claude/agents/<name>.md` | A separate context window where the host can spawn one; otherwise a separate chat or session. |
| Routing gate | `CLAUDE.md`, `.cursor/rules/harness-mini.mdc`, top of `AGENTS.md` | Seeded once, additive. |
| 40%-line teeth | `bin/ctx-hook.sh` | Optional PostToolUse hook, wired from `.claude/settings.json`. Hosts without that hook use `bin/ctx.sh` by hand. |

The harness is plain Markdown + shell, so any agent can use it by reading the
files — `init.sh` seeds the routing gate for each host (and, for Cursor, one
agent-requested rule per skill), and the getting-started guides show the prompt
recipes: [`docs/cursor-getting-started.md`](docs/cursor-getting-started.md) and
[`docs/codex-getting-started.md`](docs/codex-getting-started.md). The Cursor
skill mirror is file-level tested **and demonstrated end-to-end**: a worked
run ([`examples/cursor-slugify-demo/`](examples/cursor-slugify-demo/),
[#23](https://github.com/harness-mini/harness-mini/issues/23)) shows Cursor
observably loading the gate and **pulling skill rules on demand by description**,
with a separate-chat evaluator reproducing the firewall. That's one model
session, not a guarantee for every host — and Cursor still has no 40%-line hook,
so that reminder stays manual there.

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
Hosts that speak a PostToolUse hook can give the 40% rule teeth with the
opt-in `bin/ctx-hook.sh` (see `docs/smart-dumb.md`). Wire it from
`.claude/settings.json`.

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

> **What we measured** ([`bench/cib/results/FINDINGS.md`](bench/cib/results/FINDINGS.md)).
> We built a benchmark (`bench/cib/`) and ran it live on gpt-4o-mini, haiku-4.5, and
> Qwen2.5-7B. Under a controlled design (fixed task, only context fill varied), **raw
> occupancy showed no 40% "intelligence cliff"** — even on the small model from the paper
> that motivated the line. What degraded real QA-F1 was **interference** (competing,
> related content), not how *full* the window was. So **40% is a conservative checkpoint
> default, not a law** — and the firewall + progressive-disclosure mechanisms earn their
> keep by holding *competing content out*, which is the effect that actually matters.
> (Caveat: gradual/modest effect, frontier-model contrast still pending.)

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
| `bin/ctx-hook.sh` | opt-in PostToolUse hook (auto ctx_pct + 40% nudge) |
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
| `bench/cib/` | context-intelligence benchmark + live results ([`FINDINGS.md`](bench/cib/results/FINDINGS.md)) |

> **Editing skills?** `skills/<name>/SKILL.md` (and `agents/<name>.md`) are the
> **canonical source** — edit there. `.claude/skills/` and `.claude/agents/` are a
> committed **generated mirror** of that install layout;
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
