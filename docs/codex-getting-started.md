# Using harness-mini with OpenAI Codex

The install layout is shared across coding agents. Skills and nested resources
live under `.agents/skills/`, role descriptions live under `harness/agents/`, and
project instructions live in `AGENTS.md`. The installer does not detect the
agent or create host-specific skill paths or routing files.

## 1. Install

```bash
git clone https://github.com/harness-mini/harness-mini.git
bash harness-mini/init.sh /path/to/your/project
```

The harness executables are installed once under `$HOME/.harness-mini/bin/`.
Projects do not need a harness-owned `bin/` directory.

## 2. Open the shared instructions

Read `AGENTS.md`, `ARCHITECTURE.md`, and `harness/manifest.md`. Open a skill
from `.agents/skills/<name>/SKILL.md` when its description matches your task.
The source checkout keeps canonical skill files at `skills/<name>/SKILL.md`.

For a new requirement, ask the agent to use `stage-viewer` to choose quick or
full planning. For implementation, the session path in `status` selects
`session-init` or `session-coding`.

## 3. Use the runtime from the project root

```bash
"$HOME/.harness-mini/bin/harness.sh" --root "$PWD" status
"$HOME/.harness-mini/bin/harness.sh" --root "$PWD" doctor
"$HOME/.harness-mini/bin/ctx.sh" 50000 200000
"$HOME/.harness-mini/bin/trace.sh" main implement tool_call ctx_pct=22
```

When called from the project directory, `--root "$PWD"` may be omitted. The
same commands and project layout apply in any coding agent that can read files
and run shell commands.
