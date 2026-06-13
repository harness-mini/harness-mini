# Using harness-mini with OpenAI Codex

harness-mini is **Claude Code-first, but CLI-portable** — it's an environment, not
a program. Claude Code gets native auto-discovery of `.claude/skills/` and
`.claude/agents/`; Codex doesn't, but it can use the exact same harness by
**reading the files directly**. No adapter, no daemon, no dependency.

> **This is a secondary path.** On Codex you load skills by hand and reproduce
> sub-agents with separate sessions — it works, but it isn't at parity with the
> Claude Code experience.

## 1. Install (same as everyone)

```bash
git clone https://github.com/harness-mini/harness-mini.git
bash harness-mini/init.sh /path/to/your/project
```

## 2. Point Codex at the harness

The harness is plain Markdown + shell. `AGENTS.md` — which Codex reads by
convention — opens with a **routing gate**: it tells the agent to route
non-trivial work through `stage-viewer` first and prefer harness skills over
ad-hoc tools (the harness skill wins ties). At the start of a Codex session, have
it read the map and the manifest:

> Read `AGENTS.md`, `ARCHITECTURE.md`, and `harness/manifest.md`. Follow the 40%
> rule and the lifecycle they describe. The repo is the system of record.

- `AGENTS.md` — the ~100-line map (the 40% rule, the lifecycle, where things live).
- `harness/manifest.md` — the neutral pointer list of every skill + agent file.
- A skill is just a file: open `.claude/skills/<name>/SKILL.md` when its
  `description` matches what you're doing. (Same content as `skills/<name>/SKILL.md`.)

## 3. Prompt recipes

**Load a skill on demand** (progressive disclosure):

> Open `.claude/skills/tdd/SKILL.md` and follow it for this change.

**Run the lifecycle** (existing project):

> We have a new requirement: "<X>". Use `stage-viewer` to route it (simple vs
> complex). For complex work, run `to-prd` then `to-issues`, then implement one
> vertical slice with `tdd` + `slice-coding`.

## 4. Fallback when sub-agents aren't available

harness-mini's sub-agents (`explorer`, `evaluator`, …) are **separate context
windows**, not a framework. If your Codex setup can't spawn sub-agents, run the
same role manually — the firewall is the *separate context*, not the tooling:

- **explorer** → do the broad search in a **separate thread / fresh session**,
  paste back only the distillate (a few hundred tokens). Keeps your main thread
  under 40%.
- **evaluator** → open a **fresh session** with no build context, give it only the
  plan's acceptance criteria + the diff, and have it grade (see the tiered
  `evaluate` convention: L0 self-check → L1 lightweight reviewer → L2 deep). The
  point is that the grader didn't build the thing.

## 5. The shell glue works anywhere

`bin/*.sh` are POSIX shell with no dependencies — call them directly:

```bash
bash bin/ctx.sh 50000 200000      # context occupancy vs the 40% line
bash bin/harness.sh version       # installed harness version
bash bin/trace.sh codex implement tool_call ctx_pct=22   # log a runtime event
```

That's the whole integration: read the docs, open the skill files, run the shell.
*Any agent that can run shell can use it* — but on Codex that means **loading
skills by hand**, a manual path that trails the auto-discovered Claude Code
experience.
