# Cursor proof demo — `slugify` via the harness lifecycle

This folder is a **runnable proof** for [#23](https://github.com/harness-mini/harness-mini/issues/23):
evidence that Cursor doesn't just *contain* the harness files but actually **routes
real work through them** — gate steers → a skill is pulled on demand → the 40%
discipline fires → an evaluator grades in a separate chat.

The deliverable is a **text transcript** (no screenshots): you drive Cursor through
the four beats below and paste its responses into [`TRANSCRIPT.md`](./TRANSCRIPT.md).
When that file is filled in, #23's last open item is satisfied.

> **Why a throwaway `slugify`?** The point isn't to build something impressive — it's
> to show Cursor *behaving like the harness* on the smallest legible task. `slugify`
> is one pure function with obvious test cases, so the whole lifecycle fits in one
> short session and an evaluator can grade it in seconds. It's also harness-mini's
> first real end-to-end dogfood on a greenfield, not on itself.

---

## How the rules activate

This folder has its own nested [`.cursor/rules/`](./.cursor/rules/) — the **gate**
(`harness-mini.mdc`, `alwaysApply: true`) plus one **agent-requested** rule per skill
(`<name>.mdc`, `alwaysApply: false` + the skill's `description`), generated in the
exact format `init.sh` produces. Each rule is a thin pointer to the canonical
`.claude/skills/<name>/SKILL.md` at the repo root — single source of truth, no copy.

**Setup:** open the **harness-mini repo root** in Cursor (so `.claude/skills/` resolves),
then work on files **inside this folder**. The nested rules apply to this subtree.

---

## The feature being built — acceptance criteria

`slugify(text)` turns a title into a URL slug:

| # | Criterion | Example |
|---|-----------|---------|
| 1 | Lowercases, words joined by single `-` | `"Hello, World!"` → `"hello-world"` |
| 2 | Non-alphanumerics become separators | `"Café & Bar"` → `"caf-bar"` |
| 3 | Collapses repeated separators | `"a   --  b"` → `"a-b"` |
| 4 | Strips leading/trailing `-` | `"  Hi!  "` → `"hi"` |
| 5 | Empty / all-punctuation input → `""` | `"!!!"` → `""` |

Cursor will create the implementation + tests right here in this folder (e.g.
`slugify.py` + `test_slugify.py`). Use whatever language Cursor proposes; Python is
simplest (stdlib `unittest`, zero install).

---

## The four beats — what to type, what proves it

Paste each prompt into Cursor verbatim and record the response in `TRANSCRIPT.md`.

### Beat 1 — Gate routes the work (always-applied)
**Type:**
> I want to add a `slugify(text)` function that turns a title into a URL slug. Where do we start?

**What proves it:** Cursor does **not** just dump code. Because the gate is loaded, it
calls the work non-trivial, offers to route through `stage-viewer`, and proposes the
lifecycle (prd → issues → tdd) — referencing `.claude/skills/stage-viewer/SKILL.md`.
**The tell:** it mentions harness-mini / stage-viewer / the lifecycle *unprompted*.

### Beat 2 — Skill pulled on demand (agent-requested rule)
**Type:**
> Good. Let's implement the first slice test-first.

**What proves it:** Cursor pulls `tdd.mdc` (matched by its description) and does
red→green — writes a **failing test first** (e.g. `slugify("Hello, World!") == "hello-world"`),
runs it red, then minimal code to green. **The tell:** Cursor names/attaches the `tdd`
rule, and the test appears *before* the implementation. In the transcript, note that
`tdd` was the rule it pulled (Cursor shows referenced rules per message).

### Beat 3 — 40% discipline
Can't happen "naturally" in a short demo, and Cursor has no auto-hook — so show the
convention. In Cursor's integrated terminal, **run:**
```bash
bash bin/harness.sh version                    # gate's fresh-session check
bash bin/ctx.sh 80000 200000; echo "exit=$?"   # prints "40%", exit=2
```
**What proves it:** `ctx.sh` prints the occupancy (`40%`) and signals via **exit code** —
`2` means at/over the 40% line ("checkpoint now"), `0` means still in the smart zone
(see `docs/smart-dumb.md`). That's the discipline the Claude Code hook automates, here
run by hand. Paste both the `40%` line and `exit=2`.

### Beat 4 — Evaluator firewall (separate chat)
Open a **brand-new Cursor chat** (it must never have seen the build). **Type:**
> You are grading, not building. Read `.claude/skills/evaluate/SKILL.md`. Here are the
> acceptance criteria and the diff — pass/fail each with evidence, and run the tests.

…then paste the 5 criteria above + the output of `git diff`.

**What proves it:** a chat that didn't write the code grades it, runs the tests, returns
pass/fail per criterion. **The tell:** two visibly separate chats — one built, a
different one graded. That's the anti-self-praise firewall.

---

## Done when

[`TRANSCRIPT.md`](./TRANSCRIPT.md) has all four beats filled with Cursor's real
responses, and `slugify` passes its tests. Then update #23 and the README positioning
can move from "parity pending" to "proven."
