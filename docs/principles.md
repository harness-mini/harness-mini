# Principles & core-mind

> The "golden principles": opinionated, mechanical rules that keep an
> agent-generated codebase readable and coherent for the *next* agent run.
> Taste, encoded once, applied to every line.

## The Mini constraint (how this harness may grow)

**This is the first gate on every change to harness-mini itself.** The harness
*is the environment, not a program* — it must stay droppable into any project,
runnable by any agent CLI that can read Markdown and run shell, with nothing to
install. The contract is files + shell — see the README.

1. **Shell-or-doc first.** A capability is a Markdown skill/agent/doc by default.
   Only when it genuinely needs to *execute* does it become a small POSIX
   `sh`/`bash` script in `bin/`. Reach for shell **after** you've tried to express
   it as a convention.
2. **No environment dependence.** No runtime, no package manager, no language
   toolchain (Python/Node/Go/…), no third-party binaries. If a contribution needs
   `pip install` or `npm i`, it does not belong in the harness. Tests are
   zero-dependency (`tests/run.sh`); glue uses only POSIX utilities present on a
   bare macOS/Linux box.
3. **No complex languages.** Keep glue boringly simple — readable by an agent at a
   glance, debuggable with `set -x`. Cleverness is a smell; a 30-line script that
   one obvious thing beats a framework.
4. **Mini beats featureful.** Question each harness requirement and try to
   **delete** it before adding code. Most
   new "features" should be a new skill or a paragraph in a doc, not new code.

> If a change can't be done in shell or a doc without adding a dependency, the
> answer is usually "make it a convention" or "don't." Carve-outs must be argued
> in the PR and recorded in the decision log.

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
5. **Type the boundary; never guess the shape.** Get types from the source —
   depend on a **typed SDK/client** for any external system so the compiler models
   the data for you. Where none exists (raw HTTP, a CLI's stdout, a file format),
   **parse and validate the shape where it enters** the system and pass typed
   values inward. Either way, nothing downstream may build on a guessed or untyped
   structure. Enforce mechanically at the seam where the project allows (per #4).
6. **Prefer shared utilities over hand-rolled helpers**, so invariants live in
   one place.
7. **Pay technical debt in small, continuous installments** — the garbage
   collector (`garden`), not a once-a-quarter cleanup. Gardening fires on
   concrete triggers (≥5 checkpoints, plan-completion, pre-release, or the smell
   backlog crossing its threshold), surfaced by `harness.sh status`.
8. **Correct, maintainable, readable beats stylistically human.** Agent-written
   code need not match human style; it must be right and clear for the next run.
9. **Spend emphasis from a budget.** Emphasis is signal only when rare. Reserve
   **ALL-CAPS** for a small set of load-bearing imperatives — `MUST` / `NEVER` /
   `ALWAYS` — on safety- or invariant-critical lines; default to bold + structure
   (headers, ordered priority) for everything else. If every line shouts, nothing
   does. (Whether the model needs caps at all is itself a stale-able assumption —
   see below; it's registered in `docs/assumptions.md`.)

## Question stale assumptions (the harness is not the model)

> From Anthropic's *Scaling managed agents* (`docs/references/anthropic-managed-agents-llms.txt`):
> a harness encodes assumptions about what the model **can't do on its own**, and
> those assumptions **go stale as models improve**. The post's own example —
> context-anxiety workarounds needed in Sonnet 4.5 became unnecessary in Opus 4.5.

Almost every mechanism in harness-mini is a **patch for a presumed model gap**:
the 40% smart/dumb line, the anti-self-praise eval firewall, the explorer
fan-out, progressive disclosure, even caps-for-emphasis (#9). Each was true when
written. Each may quietly stop being true.

So we hold them as **hypotheses, not law**:

1. **Register the assumption.** Every load-bearing constraint is logged in
   `docs/assumptions.md` with the model-gap it patches and *how to test if it's
   stale* — a concrete experiment, ideally read off `harness.sh report`.
2. **Re-test on a trigger, don't trust forever.** The `garden` sweep audits the
   register (cadence: **pre-release**, when the model tier moves). A constraint
   that no longer earns its keep gets **deleted** — the Mini constraint's
   delete-first discipline applied to the harness's own beliefs, not just its features.
3. **Decoupling validated, not copied.** The post's brain/hands/session split is
   already ours (main agent / sub-agent firewalls / `.trace/`); we *interrogate*
   the session (`status`/`report`/checkpoints) instead of reloading it. The infra
   half — sandboxes, vaults, TTFT, provisioning — stays out (the Mini constraint).

## Clean Code & Refactoring (the quality spine)

- **`clean-code`** is the *forward* constraint (write it right the first time):
  intention-revealing names, small single-responsibility functions, no
  duplication, comments that explain *why* not *what*.
- **`refactor`** is the *recovery* constraint (smell → named refactoring, always
  under green tests): never refactor on red; one named move at a time.

Together they are principle #7 in action — taste applied to every line, every
run, so entropy never compounds.
