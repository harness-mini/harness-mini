# Using harness-mini with Cursor

Zero intrusion: the project gets only `.harness-mini/` (plans, trace, project
architecture) and one marked block in its root `AGENTS.md`; everything else
harness-owned lives under `$HOME/.harness-mini/`. `harness.sh agent install cursor`
adds skills in `.cursor/skills/` and role
descriptions in `.cursor/agents/` as Markdown; both dirs are listed in
`.git/info/exclude`.

## 1. Install

```bash
git clone https://github.com/harness-mini/harness-mini.git
bash harness-mini/init.sh /path/to/your/project
cd /path/to/your/project
"$HOME/.harness-mini/bin/harness.sh" agent list            # confirm your host id: cursor
"$HOME/.harness-mini/bin/harness.sh" agent install cursor
```

Executables, map and static docs are installed once under `$HOME/.harness-mini/`;
projects get no `bin/` or `docs/`. Re-running the new `init.sh` (or `update`)
installs the runtime first, then migrates an older install automatically.

## 2. Open the shared instructions

Read the project's `AGENTS.md` (it carries the harness-mini block), then the
global map `$HOME/.harness-mini/AGENTS.md`. Open a skill from
`.agents/skills/<name>/SKILL.md` when its description matches your task. The
source checkout keeps canonical skill files at `skills/<name>/SKILL.md`.

For a new requirement, use `stage-viewer` to choose quick or full planning.
For implementation, the session path in `status` selects `session-init` or
`session-coding`. Sub-agent roles are installed in `.cursor/agents/` and can
be run as separate chats if the editor does not provide independent agents.

## 3. Use the runtime from the project root

```bash
"$HOME/.harness-mini/bin/harness.sh" --root "$PWD" status
"$HOME/.harness-mini/bin/harness.sh" --root "$PWD" doctor
"$HOME/.harness-mini/bin/ctx.sh" 80000 200000
"$HOME/.harness-mini/bin/trace.sh" main implement tool_call ctx_pct=22
```

When called from the project directory, `--root "$PWD"` may be omitted. The
same commands and project layout apply in any coding agent that can read files
and run shell commands.
