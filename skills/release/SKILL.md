---
name: release
description: Cut a versioned release of harness-mini — bump VERSION, roll the CHANGELOG, tag, and publish a GitHub release. Use when shipping a new version. Wraps `bin/harness.sh release`; covers the human-judgment steps (semver choice, changelog curation) the script can't make.
---

You are shipping a release. `bin/harness.sh release <x.y.z>` does the mechanics;
you own the judgment around it. Releases are a **stage transition** — checkpoint
the plan first.

## Pick the version (SemVer)
- **PATCH** (`x.y.Z`) — glue/bug fixes, doc edits; no behavior change for users.
- **MINOR** (`x.Y.0`) — new skills, agents, or `harness.sh` capabilities;
  backward-compatible.
- **MAJOR** (`X.0.0`) — breaking the install layout or the lockfile/managed-set
  contract (anything that makes `update` behave incompatibly).

## Pre-flight (the script enforces these — don't fight them)
1. Working tree is **clean** — commit the feature first; the release commit must
   contain only the VERSION + CHANGELOG bump.
2. `tests/run.sh` is **green** (the script aborts on red).
3. Curate `CHANGELOG.md`: ensure the `## [Unreleased]` section lists what shipped
   in user-facing terms. `release` rolls Unreleased into `## [<version>] - <date>`
   and uses that section as the GitHub release notes.
4. **Garden if due** (release is a gardening trigger): run `bin/harness.sh status`
   and, if `garden: DUE`, dispatch the gardener and let its fixes land *before*
   the release commit. Ship from a tended tree. See the `garden` skill.

## Cut it
```bash
bin/harness.sh release <x.y.z> --dry-run   # preview: gates + plan, mutates nothing
bin/harness.sh release <x.y.z>             # bump + commit + tag v<x.y.z> + push + gh release
```
Flags: `--no-push` (tag/commit locally only), `--no-gh` (skip the GitHub release).
Needs `gh` authenticated and an `origin` remote for the push + GitHub release;
without them it tags locally and tells you to finish by hand.

## After
- Verify the tag and release: `git tag | tail` and `gh release view v<x.y.z>`.
- Installed projects pick it up via `bin/harness.sh update` (checksum-guarded:
  user-edited files are kept, upstream offered as `<file>.new`).
- Write a checkpoint and move the plan to `docs/exec-plans/completed/`.
