# Using harness-mini with Cursor

harness-mini is an **environment, not a program** — Markdown skills/agents +
distilled docs + thin POSIX shell. Claude Code auto-discovers `.claude/skills/`
and `.claude/agents/`; Cursor doesn't, but it can use the same harness by reading
the files. No adapter, no extension, no dependency.

> **Heads up — this is a secondary path.** harness-mini is Claude Code-first.
> `init.sh` now mirrors each skill into `.cursor/rules/` as an **agent-requested**
> rule (`alwaysApply: false` + the skill's `description`), so Cursor's agent can
> surface a skill on demand — but you still reproduce sub-agents with separate
> chats, and there's no equivalent of the 40%-line hook. The file-level mechanism
> is tested **and now demonstrated once end-to-end**: a worked run
> ([`examples/cursor-slugify-demo/`](../examples/cursor-slugify-demo/),
> [#23](https://github.com/harness-mini/harness-mini/issues/23)) shows Cursor
> observably loading the gate and pulling skill rules on demand. That's one model
> session, not a cross-version guarantee — so this stays a **secondary path**, not
> claimed parity.

## 1. Install

```bash
git clone https://github.com/harness-mini/harness-mini.git
bash harness-mini/init.sh /path/to/your/project
```

## 2. Make the harness visible to Cursor

`init.sh` does this for you, two ways:

- **The routing gate** — an **always-applied** rule at
  `.cursor/rules/harness-mini.mdc` (`alwaysApply: true`) that tells Cursor to
  prefer the harness lifecycle and skills over ad-hoc tools, and points at
  `AGENTS.md`.
- **One rule per skill** — `.cursor/rules/<name>.mdc` (`alwaysApply: false` + the
  skill's `description`), an **agent-requested** rule Cursor can pull on demand by
  matching the description. Each points at the canonical
  `.claude/skills/<name>/SKILL.md` (single source of truth — the rule is a thin
  pointer, not a copy of the body).

Both are harness-owned and created only if absent, so re-running `init.sh` won't
clobber your edits. You can still open `.claude/skills/<name>/SKILL.md` directly
any time (identical to `skills/<name>/SKILL.md`).

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

Read the docs, let Cursor pull the skill rules (or open the files directly), run
the shell — that's the integration. The file-level mechanism is tested, and one
end-to-end run ([#23](https://github.com/harness-mini/harness-mini/issues/23)) has
shown Cursor actually routing a task through the harness.

**See / repeat it:** [`examples/cursor-slugify-demo/`](../examples/cursor-slugify-demo/)
is a runnable storyboard with a **completed transcript** ([`TRANSCRIPT.md`](../examples/cursor-slugify-demo/TRANSCRIPT.md))
from a real Cursor session — gate → skill-on-demand → 40% line → evaluator in a
separate chat. Open this repo in Cursor and re-run the four beats to reproduce it.
