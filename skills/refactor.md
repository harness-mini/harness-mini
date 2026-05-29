---
name: refactor
description: The recovery code-quality constraint (Refactoring). Use to improve code structure without changing behavior — smell → named refactoring, always under green tests, one move at a time. Used by the generator (in the tdd refactor step) and the gardener (entropy cleanup).
---

Refactoring = changing structure **without changing behavior**. The tests are
the proof behavior didn't change.

## Iron rules
1. **Green only.** Never refactor while any test is red. If there's no test
   covering the code, write one first (it should pass), *then* refactor.
2. **One named move at a time.** Apply a single catalog refactoring, re-run
   tests, commit. Don't blend refactoring with feature changes.

## Smell → move (common catalog)
| Smell | Refactoring |
|-------|-------------|
| Long function | Extract Function |
| Unclear name | Rename |
| Duplicated code | Extract Function / Pull Up |
| Long parameter list | Introduce Parameter Object |
| Feature envy | Move Function |
| Primitive obsession | Replace Primitive with Object |
| Conditional complexity | Decompose Conditional / Replace with Polymorphism |
| Comments explaining bad code | Extract + Rename until the comment is redundant |

## In the harness
- Generator: the REFACTOR step of every `tdd` cycle.
- Gardener: continuous small installments (golden principle #7) — scan for
  smells, open targeted, green, one-move PRs. Pay debt before it compounds.

Trace: `bin/trace.sh <agent> <stage> refactor move=<name>`.
