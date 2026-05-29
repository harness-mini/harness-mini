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
its own work to "done" — the `evaluator` (separate window, opus) is the
anti-self-praise gate.

## Layout

| Path | Purpose |
|------|---------|
| `AGENTS.md` | ~100-line map injected every run |
| `ARCHITECTURE.md` | layer stack + lifecycle FSM |
| `init.sh` | additive/idempotent installer |
| `bin/{ctx,trace,ralph}.sh` | context gauge · JSONL tracer · ralph loop |
| `skills/` → `.claude/skills/` | 13 skills (how to do a task) |
| `agents/` → `.claude/agents/` | 5 sub-agents (who does the work) |
| `docs/principles.md` | golden principles + Musk's Five-Step core-mind |
| `docs/smart-dumb.md` | the 40% contract |
| `docs/exec-plans/{active,completed}/` | plans + decision logs (committed) |
| `docs/references/*-llms.txt` | the 4 source distillates |
| `.trace/checkpoints/` | committed handoffs (institutional memory) |
| `.trace/runtime/` | gitignored ephemeral JSONL traces |
| `tests/run.sh` | zero-dep TDD suite |

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
bash tests/run.sh   # 35 assertions, zero dependencies
```

## References distilled in `docs/references/`
- Anthropic — Effective harnesses for long-running agents
- Anthropic — Harness design for long-running apps
- OpenAI — Harness engineering (leveraging Codex)
- Anthropic — The Founder's Playbook
