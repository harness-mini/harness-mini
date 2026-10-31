# Accessibility Statement

harness-mini ships two kinds of surfaces: **terminal output** (POSIX shell in
`bin/` and `init.sh`) and **Markdown** (this repo's docs, skills, and agent
files, which are also rendered as web pages by GitHub). We want both usable by
people with disabilities and by assistive-technology (AT) users — screen-reader
users, low-vision users, and anyone for whom a wall of unstructured text is a
barrier. This statement is adapted from
[W3C/WAI guidance](https://www.w3.org/WAI/planning/statements/) and the
[open-source accessibility toolkit](https://github.com/open-source-accessibility/accessibility-toolkit),
scoped honestly to what this project actually is: no web UI, no mobile app —
a CLI and a corpus of Markdown.

These are **goals and commitments, not a claim of verified conformance.**

## Priorities

**Terminal / CLI**

- **Plain text by construction.** Our scripts emit plain text only — no ANSI
  color, no cursor tricks. Meaning is never carried by color or styling alone.
- **If color is ever introduced**, it must be gated on an interactive TTY
  (`[ -t 1 ]`), honor [`NO_COLOR`](https://no-color.org/), degrade to plain
  text when piped or redirected, and never be the only signal of status.
- **Output is line-oriented and predictable** — parseable by AT and by scripts
  alike (the same property that makes it agent-friendly).

**Markdown / docs**

- **Logical heading hierarchy** — no skipped levels; headings double as the
  navigation anchors both AT users and coding agents jump by.
- **Descriptive link text** — "the `evaluate` skill", never "click here".
- **Tables carry header rows**; images carry alt text (decorative SVGs get
  `role="img"` + `aria-label` rather than being left voiceless).
- **ASCII diagrams** (like the lifecycle FSM in `ARCHITECTURE.md`) must be
  accompanied by a prose equivalent — the diagram is a visual aid, the bullets
  beside it are the source of truth a screen reader can linearize.
- **Plain language and stable terminology** throughout.

## For contributors

- New CLI output: keep it plain; if you must add color, follow the gating rules
  above.
- New or edited Markdown: keep heading order, give links and images real text,
  put a prose equivalent next to any new diagram.
- If something can't conform, say so in the PR and add it under
  [Known limitations](#known-limitations) rather than leaving it undocumented.

## Supported environments

- Common terminal emulators (macOS Terminal/iTerm2, the Linux VTE family) with
  common screen readers (VoiceOver, NVDA) running over them.
- GitHub's web rendering of this repository's Markdown.
- Caveat: we cannot test every terminal/AT combination; reports from
  configurations we missed are especially welcome.

## Known limitations

- **ASCII diagrams linearize poorly** in a screen reader — box-drawing
  characters are read as glyphs. Every diagram ships next to prose carrying the
  same information; treat the art as optional.
- **No automated accessibility CI** — conformance is by convention and review,
  not by tooling.
- This statement is new; gaps may exist that we haven't found yet. Tell us.

## Reporting an accessibility problem

Open a **public GitHub issue** with the `accessibility` label (accessibility
reports are not security reports — [SECURITY.md](SECURITY.md) covers those).
Please include:

- What you were trying to do, and what blocked you (expected vs. actual)
- The surface: which script/command, or which document
- Reproduction steps, and your environment: OS, terminal, and AT (name +
  version) — or "none" if the barrier is cognitive/linguistic
- Severity: **Critical** (fully blocks a task) · Serious · Moderate · Minor

You never need to disclose a diagnosis. Reports are treated as expertise, not
complaints. We aim to acknowledge within **7 days**, propose a workaround when
one exists, and link the tracking issue here once filed.

## Ownership

The maintainers triage `accessibility`-labeled issues, keep this statement
current, and record unresolved barriers above instead of letting them go dark.

## Feedback on this statement

Accessibility is an ongoing practice, not a one-time fix. Issues and PRs that
improve this document — or point at what it missed — are welcome.
