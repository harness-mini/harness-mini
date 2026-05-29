# Principles & core-mind

> The "golden principles": opinionated, mechanical rules that keep an
> agent-generated codebase readable and coherent for the *next* agent run.
> Taste, encoded once, applied to every line.

## Core-mind: Musk's Five-Step Algorithm

Apply **in order** before building anything. The order matters more than any
single step. (See the `five-step` skill for the operational checklist.)

1. **Make the requirement less dumb.** Question every requirement. Attach a
   *person's name* to it, never a department — requirements from "the system"
   are guesses in disguise. The smartest people's requirements are still partly
   wrong.
2. **Delete the part or process.** If you are not later forced to add back at
   least 10% of what you deleted, you did not delete enough. The best part is no
   part; the best process is no process.
3. **Simplify or optimize — only what survived step 2.** The most common error
   of a smart engineer is to optimize a thing that should not exist.
4. **Accelerate cycle time.** Speed up — but never before steps 1–3. Never
   accelerate a process that should be deleted.
5. **Automate — last.** Automating a flawed or unnecessary process locks the
   flaw in. Automate only what has survived all four prior steps.

> The two named failure modes this prevents: **optimizing** and **automating**
> something that should have been deleted. In an agent harness these are the
> expensive mistakes — they get encoded and replicated across every future run.

## Golden principles (mechanical, enforce-able)

1. **The repo is the system of record.** If knowledge isn't in a
   version-controlled file, it doesn't exist to the agent. Push context *into*
   the repo (decisions, conventions, the "why").
2. **A map, not a 1,000-page manual.** `AGENTS.md` is a table of contents.
   Progressive disclosure beats a wall of instructions every time.
3. **Optimize for agent readability.** The next reader is an agent with no
   memory. Make the repo navigable cold.
4. **Constrain boundaries, free the interior.** Enforce invariants (layers,
   schemas, naming) mechanically; allow freedom in *how* a solution is
   expressed inside those boundaries.
5. **Parse at the boundary.** Validate data shapes where they enter the system;
   don't probe untyped blobs by guessing structure.
6. **Prefer shared utilities over hand-rolled helpers**, so invariants live in
   one place.
7. **Pay technical debt in small, continuous installments** — the garbage
   collector (`garden`), not a once-a-quarter cleanup.
8. **Correct, maintainable, readable beats stylistically human.** Agent-written
   code need not match human style; it must be right and clear for the next run.

## Clean Code & Refactoring (the quality spine)

- **`clean-code`** is the *forward* constraint (write it right the first time):
  intention-revealing names, small single-responsibility functions, no
  duplication, comments that explain *why* not *what*.
- **`refactor`** is the *recovery* constraint (smell → named refactoring, always
  under green tests): never refactor on red; one named move at a time.

Together they are principle #7 in action — taste applied to every line, every
run, so entropy never compounds.
