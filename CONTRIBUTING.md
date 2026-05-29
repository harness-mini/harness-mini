# Contributing to harness-mini

First off — thank you. harness-mini is a small, opinionated harness, and it gets
better every time someone uses it on a real project and tells us what broke.

This guide assumes you've skimmed [`README.md`](README.md). The harness "is the
environment, not a program," so most contributions are Markdown (skills, agents,
docs) plus the occasional ~30 lines of POSIX shell glue. You do **not** need to
be a shell wizard to help.

By participating you agree to keep things kind and constructive — assume good
faith, critique ideas not people, and help newcomers land their first PR.

## Before you start

- **Questions / "how do I…"** → open a [Discussion] or a `question` issue, not a PR.
- **Anything non-trivial** → open an issue first so we can agree on the shape
  before you spend time. Tiny fixes (typos, broken links, an obviously-missing
  guard) can go straight to a PR.
- **Read the conventions once.** They're short and they're the whole point:
  - [`AGENTS.md`](AGENTS.md) — the map, and the **40% rule** that governs everything.
  - [`ARCHITECTURE.md`](ARCHITECTURE.md) — layout, lifecycle FSM, the managed set.
  - [`docs/principles.md`](docs/principles.md) — golden principles + Musk's Five-Step.
  - [`docs/smart-dumb.md`](docs/smart-dumb.md) — the smart/dumb context contract.

## 1. Ways to contribute

You don't have to write code to make a real difference:

- **New skills** (`skills/*.md`) — a reusable "how to do a task" play. Keep it
  one job, ~1 screen, with frontmatter `name:` + `description:` (the description
  is how an agent decides to load it). Mirror it into `.claude/skills/` and add
  it to `harness/manifest.md`.
- **New sub-agents** (`agents/*.md`) — a role with its own context window. Set
  `tools:`, `model:` (haiku/sonnet/opus per the tier table), and `skills:`.
- **Shell glue** (`bin/*.sh`) — must be POSIX-friendly, dependency-free, and
  test-first (see below). Glue stays *thin*: if it wants a framework, it doesn't
  belong here.
- **Reference distillates** (`docs/references/*-llms.txt`) — condense a source
  blog/paper into the harness's own idiom. Cite the source.
- **Real-world reports** — install it (`bin/harness.sh update`), use it on a real
  project, and open an issue describing what was confusing or what you wished
  existed. This is the single most valuable contribution.
- **Triage & review** — reproduce bugs, refine proposals, review open PRs.

Look for issues labelled **`good first issue`** and **`help wanted`** to start.

## 2. Pull request expectations

Keep PRs **small and focused** — one logical change, one concern. A 40-line PR
gets reviewed today; a 1,000-line PR waits.

Checklist before you open a PR:

- [ ] **Tests are green:** `bash tests/run.sh` (zero dependencies, runs anywhere).
- [ ] **You added tests *first*.** This repo is TDD — a behavioral change to
      `bin/*.sh` or `init.sh` lands with a failing test that your change turns
      green. See [`skills/tdd.md`](skills/tdd.md).
- [ ] **You followed `slice-coding`** for anything multi-step: a thin vertical
      slice end-to-end before breadth. See [`skills/slice-coding.md`](skills/slice-coding.md).
- [ ] **`AGENTS.md` stays a map** (~100 lines). If your change adds a pointer,
      add one line — don't turn the map into an encyclopedia.
- [ ] **Docs updated** alongside the code (README / ARCHITECTURE / manifest as relevant).
- [ ] **`CHANGELOG.md` `[Unreleased]`** has a user-facing line for your change.
- [ ] **Managed-set awareness:** if you touch what `init.sh` installs, update
      `emit_managed_pairs()` in [`bin/_harness_lib.sh`](bin/_harness_lib.sh) — it's
      the single source of truth for what `harness.sh update` owns.
- [ ] **SemVer note** in the PR description: is this a PATCH (glue fix), MINOR
      (new skill/agent/CLI), or MAJOR (breaks the install layout or lock contract)?
      Maintainers cut releases via the [`release` skill](skills/release.md); you
      don't bump `VERSION` in a PR.

**Commit style:** short, imperative, Conventional-Commits-flavoured subjects —
`feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`. Link the issue
(`Closes #123`). Keep the body to *why*, not *what*.

**The review loop is the `implement ⇄ evaluate` loop:** a maintainer (the
anti-self-praise gate) verifies against the change's stated acceptance criteria.
Expect requests for changes — that's the system working, not a rejection.

## 3. Documentation and community contributions

Docs are a first-class contribution here, not an afterthought — a harness that
isn't legible is a harness nobody trusts.

- **Match the voice:** terse, concrete, example-driven. Prefer a 6-line example
  over two paragraphs of prose.
- **Respect the disclosure ladder:** `AGENTS.md` points; the deep docs explain.
  Put detail where it lives, link to it from the map — never duplicate it.
- **Skills are docs too.** A good skill reads like a checklist a tired agent can
  follow at 39% context.
- **Distillates** should be faithful and attributed; we're standing on the
  shoulders of the linked sources.
- **Community help counts:** answering Discussions, improving error messages,
  writing a "how I used harness-mini" walkthrough, fixing a confusing sentence —
  all welcome, all creditable.
- Fix a typo the moment you see it. No issue required.

## 4. Reporting bugs and proposing features

Use **GitHub Issues**. Search first — it may already be filed.

**Bug reports** should let a maintainer reproduce in one read. Include:

- **Version:** output of `bin/harness.sh version`.
- **Environment:** OS + shell (e.g. macOS / zsh, Ubuntu / bash), and which agent
  CLI you're driving it with (claude / codex / cursor) if relevant.
- **Steps to reproduce:** the exact commands.
- **Expected vs. actual:** what you thought would happen, what did.
- **Evidence:** the relevant slice of output, or a `.trace/runtime/*.jsonl` line.

A failing case added to `tests/run.sh` *is* the ideal bug report.

**Feature proposals** are run through the harness's own front door — Musk's
[Five-Step](skills/five-step.md), starting with step 1: **question the
requirement.** In the issue, tell us:

- **The problem**, not the solution — what can't you do today, and why does it matter?
- **The smallest valuable slice** that would help (we ship thin and iterate).
- **What it should *not* do** — scope you're deliberately deleting.
- **Fit:** how it stays inside "convention + thin glue" rather than growing a
  program. Proposals that add dependencies or a runtime face a high bar.

Maintainers will label (`bug`, `enhancement`, `docs`, `good first issue`, …) and,
for accepted non-trivial work, an exec-plan in `docs/exec-plans/` may track it.

---

Thanks again. Ship thin, keep it smart. 🌱

[Discussion]: https://github.com/harness-mini/harness-mini/discussions
