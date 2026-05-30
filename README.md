# harness-mini

A **minimal, CLI-agnostic agent harness** — convention + skills + sub-agents +
distilled best-practice docs, with only thin shell glue as code. It encodes the
patterns from Anthropic's long-running-agent engineering, OpenAI's harness
engineering, and Anthropic's Founder's Playbook into a structure you can drop
into any project.

The harness *is the environment*, not a program. Any agent that can run shell
(`claude`, `codex`, `cursor`, …) can use it.

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
bin/harness.sh release <x.y.z>      # (source repo) bump + tag + GitHub release
```

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
       garden ──── runs orthogonally, periodically ────
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
| `bin/harness.sh` | front-door CLI: `version`·`update`·`doctor`·`status`·`release` |
| `bin/{ctx,trace,ralph}.sh` | context gauge · JSONL tracer · ralph loop |
| `harness/harness.lock` | installed version + managed-file checksums |
| `skills/<name>/SKILL.md` → `.claude/skills/` | 15 skills (one folder each) |
| `agents/` → `.claude/agents/` | 5 sub-agents (who does the work) |
| `docs/principles.md` | golden principles + Musk's Five-Step core-mind |
| `docs/smart-dumb.md` | the 40% contract |
| `docs/exec-plans/{active,completed}/` | plans + decision logs (committed) |
| `docs/references/*-llms.txt` | the 4 source distillates |
| `.trace/checkpoints/` | committed handoffs (institutional memory) |
| `.trace/runtime/` | gitignored ephemeral JSONL traces |
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
| generator | build one slice via TDD | sonnet |
| evaluator | grade vs criteria (separate window) | opus |
| explorer | disposable read/search → distillate | haiku |
| gardener | entropy GC / doc-gardening | haiku |

## Develop

```bash
bash tests/run.sh   # 69 assertions, zero dependencies
```

Pure POSIX shell, no dependencies — tested on macOS `bash` 3.2 and Linux `bash`,
and safe to call from `zsh`. See the compatibility notes in
[`CONTRIBUTING.md`](CONTRIBUTING.md) before contributing shell.

## References distilled in `docs/references/`
- Anthropic — Effective harnesses for long-running agents
- Anthropic — Harness design for long-running apps
- OpenAI — Harness engineering (leveraging Codex)
- Anthropic — The Founder's Playbook

## Contributing

Issues and PRs welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). It's a small,
opinionated harness: most contributions are Markdown (skills, agents, docs) plus
the occasional ~30 lines of test-first shell. Ship thin, keep it smart.

## License

[MIT](LICENSE) © 2026 harness-mini contributors.
