# Cursor proof transcript — `slugify` demo

The text record for [#23](https://github.com/harness-mini/harness-mini/issues/23).
Fill each beat with Cursor's **actual** response (verbatim or lightly trimmed). See
[`README.md`](./README.md) for the prompts and what each beat proves.

| Field | Value |
|-------|-------|
| Date | 2026-06-16 |
| Cursor version | not recorded |
| Model | not recorded |
| Driver | matt |

---

## Beat 1 — Gate routes the work

**Prompt sent:**
> I want to add a `slugify(text)` function that turns a title into a URL slug. Where do we start?

**Rules Cursor attached:** `harness-mini.mdc` (always-applied gate)

**Cursor's response:**
```
You're in the right place. This is **Beat 1** of the `cursor-slugify-demo` — the harness gate should steer before any code lands.

## Start here: route through the lifecycle

This is a **small, well-scoped feature** (one pure function, clear test cases), so we use **quick mode** — skip the full PRD/issues funnel, but still follow the harness rhythm:

```
implement (test-first) → evaluate → done
```

Harness is up to date (0.8.0). No active exec-plan yet — we'd create a lightweight quick plan in `docs/exec-plans/active/` if you want the full paper trail, or keep it informal inside `examples/cursor-slugify-demo/` for the demo.

## What we're building

The acceptance criteria are already in the demo README:

| # | Behavior | Example |
|---|----------|---------|
| 1 | Lowercase, words joined by `-` | `"Hello, World!"` → `"hello-world"` |
| 2 | Non-alphanumerics become separators | `"Café & Bar"` → `"caf-bar"` |
| 3 | Collapse repeated separators | `"a   --  b"` → `"a-b"` |
| 4 | Strip leading/trailing `-` | `"  Hi!  "` → `"hi"` |
| 5 | Empty / all-punctuation → `""` | `"!!!"` → `""` |

Files go in `examples/cursor-slugify-demo/` — e.g. `slugify.py` + `test_slugify.py` (Python + stdlib `unittest` is the simplest path).

## Recommended next step

**Don't write implementation yet.** The harness way is test-first via the `tdd` skill:

1. Write a **failing test** for criterion 1 (`"Hello, World!"` → `"hello-world"`)
2. Run it red
3. Write the minimal `slugify()` to go green
4. Add tests for criteria 2–5, refactor if needed
5. Grade in a **separate chat** with the `evaluate` skill (anti-self-praise firewall)

---

**Your move (Beat 2 prompt):**

> Good. Let's implement the first slice test-first.

That should pull the `tdd` skill and start red→green on criterion 1. Want me to proceed with that?
```

**Verdict:** ☑ **routed through the lifecycle (not raw code)** — chose quick mode, refused to write code yet   ⬜ did not

---

## Beat 2 — Skill pulled on demand

**Prompt sent:**
> Good. Let's implement the first slice test-first.

**Rules Cursor attached:** `harness-mini.mdc` (gate) + **`tdd.mdc`** — confirmed pulled on demand in Cursor's UI

**Cursor's response (note: failing test written before implementation):**
```
**Beat 2 — TDD red→green** (via `tdd` skill)

## 1. RED — failing test first

```1:12:examples/cursor-slugify-demo/test_slugify.py
import unittest

from slugify import slugify


class SlugifyTest(unittest.TestCase):
    def test_lowercases_and_joins_words_with_hyphens(self):
        self.assertEqual(slugify("Hello, World!"), "hello-world")


if __name__ == "__main__":
    unittest.main()
```

```
ModuleNotFoundError: No module named 'slugify'
FAILED (errors=1)
```

## 2. GREEN — minimal implementation

```1:7:examples/cursor-slugify-demo/slugify.py
import re


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower())
    return slug.strip("-")
```

```
test_lowercases_and_joins_words_with_hyphens ... ok

Ran 1 test in 0.000s
OK
```

---

**Slice 1 done:** criterion 1 (`"Hello, World!"` → `"hello-world"`) is green.

**Next slices** (still test-first, one criterion at a time):
- `"Café & Bar"` → `"caf-bar"` (non-ASCII / punctuation)
- `"a   --  b"` → `"a-b"` (collapse separators)
- `"  Hi!  "` → `"hi"` (trim)
- `"!!!"` → `""` (empty input)

Say the word if you want the next failing test added, or jump to **Beat 4** (fresh chat + `evaluate` skill) to grade what we have so far.
```

**Verdict:** ☑ **pulled `tdd.mdc` on demand, test-first** (red → green)   ⬜ did not

---

## Beat 3 — 40% discipline

**Commands run in Cursor's terminal:**
```bash
bash bin/harness.sh version
bash bin/ctx.sh 80000 200000; echo "exit=$?"
```

**Output:**
```
harness-mini 0.8.0 (installed)
up to date.

40%
exit=2
```

---

## Beat 4 — Evaluator firewall (separate chat)

**New chat?** ☑ yes (fresh context, never saw the build)

**Prompt sent:** (criteria + `git diff` pasted in)
> You are grading, not building. Read `.claude/skills/evaluate/SKILL.md` ...

**Rules the evaluator chat attached:** `harness-mini.mdc` (gate) + **`evaluate.mdc`** — confirmed pulled on demand in Cursor's UI

**Evaluator's response (pass/fail per criterion + test run):**
```
## Evaluation — `slugify` (Beat 4, L1)

**Tier:** L1 (lightweight reviewer)  
**Role:** Grading only — did not build or modify code.

---

### Test run

```
python3 -m unittest test_slugify -v
```

```
test_lowercases_and_joins_words_with_hyphens ... ok

Ran 1 test in 0.000s
OK
```

**Note:** The suite only asserts criterion 1. I exercised criteria 2–5 directly against `slugify()` (see below).

---

### Acceptance criteria

| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| 1 | Lowercases, words joined by single `-` | **PASS** | `slugify("Hello, World!")` → `"hello-world"`; unit test passes |
| 2 | Non-alphanumerics become separators | **PASS** | `slugify("Café & Bar")` → `"caf-bar"` (`é` stripped; `&` → `-`) |
| 3 | Collapses repeated separators | **PASS** | `slugify("a   --  b")` → `"a-b"` |
| 4 | Strips leading/trailing `-` | **PASS** | `slugify("  Hi!  ")` → `"hi"` |
| 5 | Empty / all-punctuation → `""` | **PASS** | `slugify("!!!")` → `""` |

**Criteria: 5/5 PASS**

---

### Implementation reviewed

```1:7:examples/cursor-slugify-demo/slugify.py
import re


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower())
    return slug.strip("-")
```

Behavior matches all five examples. `re.sub(r"[^a-z0-9]+", "-", ...)` replaces each non-alphanumeric run with a single `-`; `.strip("-")` handles leading/trailing hyphens and all-punctuation input.

---

### Secondary lens (clean-code)

- **PASS** — Small, intention-revealing function; no duplication.
- **Gap (non-blocking):** Tests cover only criterion 1. Behavior for 2–5 is correct but not locked in by tests; a regression would not be caught until manual checks or Beat 4-style verification.

---

### Verdict

**PASS** — Implementation satisfies all acceptance criteria. Recommend adding four more unit tests (one per remaining criterion) before calling the slice fully done.

---

For `TRANSCRIPT.md` Beat 4, you can paste this block and check: **graded in a separate chat, ran tests**.
```

**Verdict:** ☑ **graded in a separate chat, ran tests** — and caught a real gap (only criterion 1 is locked in by a test)   ⬜ did not

---

## Final slugify result

```python
# slugify.py
import re


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower())
    return slug.strip("-")
```

Independent re-run (not Cursor's say-so — `python3` in this folder):

```
$ python3 -m unittest test_slugify -v
test_lowercases_and_joins_words_with_hyphens ... ok
Ran 1 test in 0.000s
OK

$ # all 5 criteria, checked directly against slugify()
1. slugify('Hello, World!') -> 'hello-world'  PASS
2. slugify('Café & Bar')    -> 'caf-bar'      PASS
3. slugify('a   --  b')     -> 'a-b'          PASS
4. slugify('  Hi!  ')       -> 'hi'           PASS
5. slugify('!!!')           -> ''             PASS
```

## Summary

**Yes — Cursor genuinely routed this work through the harness.** The gate
(`harness-mini.mdc`, always-applied) steered Beat 1: instead of dumping code Cursor
chose quick mode and refused to implement before a failing test. The two
agent-requested rules were **actually pulled on demand, confirmed in Cursor's UI** —
`tdd.mdc` on Beat 2 (drove a real red→green) and `evaluate.mdc` in a separate Beat 4
chat that had never seen the build. That separate chat is the firewall working: it
graded 5/5 **and caught a real gap** — the TDD beat locked in only criterion 1 with a
test; criteria 2–5 are correct (independently re-verified above) but untested, so a
regression wouldn't be caught.

**Where it needed nudging / limits:** (1) Cursor stopped TDD after one slice instead of
continuing to criteria 2–5 unprompted — the spec→tests coverage is on the human to
push. (2) The 40% discipline has no auto-hook in Cursor; `bin/ctx.sh` fires the signal
(`40%` / exit 2) but only when run by hand. Both are honest caveats, not blockers.

**Net for [#23](https://github.com/harness-mini/harness-mini/issues/23):** the
file-level mechanism doesn't just exist — Cursor observably loads the gate and pulls
skills on demand by description, and the separate-chat evaluator firewall reproduces.
First real end-to-end dogfood on a greenfield (not the harness on itself).
