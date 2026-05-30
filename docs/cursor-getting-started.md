# Using harness-mini with Cursor

harness-mini is an **environment, not a program** — Markdown skills/agents +
distilled docs + thin POSIX shell. Claude Code auto-discovers `.claude/skills/`
and `.claude/agents/`; Cursor doesn't, but it can use the same harness by reading
the files. No adapter, no extension, no dependency.

## 1. Install

```bash
git clone https://github.com/harness-mini/harness-mini.git
bash harness-mini/init.sh /path/to/your/project
```

## 2. Make the harness visible to Cursor

Cursor reads your repo. Two good options:

- **Point its rules at the map.** Add a short Cursor rule (or `.cursorrules` line):
  *"Follow `AGENTS.md` and `harness/manifest.md`. Honor the 40% context rule and
  the lifecycle. The repo is the system of record; read a skill file before doing
  its task."*
- **Open files on demand.** When a task starts, open
  `.claude/skills/<name>/SKILL.md` whose `description` matches — e.g.
  `tdd`, `slice-coding`, `to-issues`. (Identical to `skills/<name>/SKILL.md`.)

## 3. Prompt recipes

**Route a new requirement:**

> Read `.claude/skills/stage-viewer/SKILL.md`. Decide if "<X>" is simple or
> complex. If complex, run the funnel (`to-prd` → `to-issues`); then implement one
> vertical slice with `tdd` + `slice-coding`.

**Stay smart (40%):**

> Before a broad search or large read, do it in a separate chat and bring back
> only a short distillate — don't fill this thread (see `docs/smart-dumb.md`).

## 4. Fallback when sub-agents aren't available

The harness's sub-agents are **separate context windows**, not a runtime. In
Cursor, reproduce them with separate chats:

- **explorer** → a throwaway chat does the heavy search/read; paste back only the
  conclusion + `file:line` pointers.
- **evaluator** → a fresh chat with *only* the acceptance criteria + the diff
  grades the work (it didn't build it — that's the anti-self-praise firewall).
  Scale rigor with the tiered `evaluate` convention (L0/L1/L2).

## 5. Run the shell directly

```bash
bash bin/harness.sh version       # installed harness version
bash bin/ctx.sh 80000 200000      # 40% → checkpoint now
bash bin/trace.sh cursor implement test result=green   # log a runtime event
```

Read the docs, open the skill files, run the shell — that's the entire
integration. The CLI-agnostic promise holds for Cursor too.
