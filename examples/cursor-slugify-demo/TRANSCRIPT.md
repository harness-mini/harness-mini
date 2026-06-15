# Cursor proof transcript — `slugify` demo

The text record for [#23](https://github.com/harness-mini/harness-mini/issues/23).
Fill each beat with Cursor's **actual** response (verbatim or lightly trimmed). See
[`README.md`](./README.md) for the prompts and what each beat proves.

| Field | Value |
|-------|-------|
| Date | _YYYY-MM-DD_ |
| Cursor version | _e.g. 0.4x_ |
| Model | _e.g. claude-opus-4-8_ |
| Driver | _your name_ |

---

## Beat 1 — Gate routes the work

**Prompt sent:**
> I want to add a `slugify(text)` function that turns a title into a URL slug. Where do we start?

**Rules Cursor attached:** _e.g. harness-mini.mdc (always)_

**Cursor's response:**
```
<paste here>
```

**Verdict:** ⬜ routed through stage-viewer / lifecycle (not raw code)   ⬜ did not

---

## Beat 2 — Skill pulled on demand

**Prompt sent:**
> Good. Let's implement the first slice test-first.

**Rules Cursor attached:** _expected: tdd.mdc_

**Cursor's response (note: failing test written before implementation):**
```
<paste here — include the test it wrote first and the red→green steps>
```

**Verdict:** ⬜ pulled `tdd`, test-first   ⬜ did not

---

## Beat 3 — 40% discipline

**Commands run in Cursor's terminal:**
```bash
bash bin/harness.sh version
bash bin/ctx.sh 80000 200000; echo "exit=$?"
```

**Output:**
```
<paste here — expect "40%" then "exit=2" (2 = at/over the line = checkpoint now)>
```

---

## Beat 4 — Evaluator firewall (separate chat)

**New chat?** ⬜ yes (fresh context, never saw the build)

**Prompt sent:** (criteria + `git diff` pasted in)
> You are grading, not building. Read `.claude/skills/evaluate/SKILL.md` ...

**Rules the evaluator chat attached:** _expected: evaluate.mdc_

**Evaluator's response (pass/fail per criterion + test run):**
```
<paste here>
```

**Verdict:** ⬜ graded in a separate chat, ran tests   ⬜ did not

---

## Final slugify result

```
<paste the final slugify implementation + passing test output>
```

## Summary

_One paragraph: did Cursor genuinely route work through the harness? Where did it
follow the rules, where did it need nudging? This is the honest finding for #23._
