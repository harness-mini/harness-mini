# The smart/dumb contract

> Requirement #1 of harness-mini. This is the intellectual core: keep every
> agent's context in the **smart zone** at all times.

## Definition — occupancy, not content

"Smart" and "dumb" describe **how full the context window is**, not which
content is in it.

- **Smart zone — below 40% occupancy.** The model reasons sharply, follows
  instructions, holds the whole task in view.
- **Dumb zone — at or above 40% occupancy.** The model degrades: it drops
  instructions, optimizes the wrong constraint, exhibits "context anxiety,"
  and writes worse handoffs. Empirically, quality falls long before the nominal
  context limit — so we draw the line early, at **40%**.

The threshold is configurable (`HARNESS_CTX_THRESHOLD`, default 40) but 40 is
the deliberate default. Every agent — main and sub — is responsible for keeping
**itself** smart.

## How the line is held (in priority order)

### 1. Sub-agent fan-out — the load-bearing mechanism
The only mechanism that does not depend on an agent honestly measuring itself.
The main agent stays smart by *delegating* every heavy or dirty operation —
broad searches, large-file reads, log scans — to a disposable **explorer**.
The explorer is *allowed* to fill its own window to ~90%, then returns a
**distillate** (a few hundred tokens) and dies. The caller absorbs only the
distillate. Structural, therefore reliable.

> Rule of thumb: any operation that would pull in more than ~2k tokens →
> delegate it.

### 2. 40% = the checkpoint-and-reset trigger (not a hard wall)
Crossing 40% does not mean "stop blindly." It means: **checkpoint now, while you
are still sharp.** Write `.trace/checkpoints/<plan>-<seq>.md`, update the active
exec-plan, then reset to a fresh session that bootstraps from that artifact.
Waiting until 90% is fatal — the handoff itself would be written by a degraded
agent.

### 3. Measurement — best-effort, to *see* drift
`bin/ctx.sh <used_tokens> [window]` prints `N%` and exits 2 at/over threshold.
You cannot portably read a model's internal token counter, so this is an
estimate (Claude Code can do better via a PostToolUse hook). It is good enough
to watch trends in `.trace/runtime/`, not a hard interrupt.

### 4. Progressive disclosure keeps the baseline low
`AGENTS.md` is a ~100-line map of pointers, never an encyclopedia. Start
near-empty; pull a file only when you need it. This buys the most headroom for
the least effort.

### 5. One bounded task per session
A session scoped to a single feature / plan-step never *needs* to hold
everything, so it naturally stays under budget.

## Enforcement style
**Behavioral + structural**, not a hard runtime kill: agents follow this
protocol and the explorer firewall does the heavy lifting. On Claude Code a
PostToolUse hook may log real usage as a bonus tripwire.

## Entropy: smart context decays
Smart context is **append-rarely, prune-aggressively.** Over time, once-useful
"always-loaded" facts rot. The **gardener** agent periodically demotes stale
smart context back into dumb (on-demand) docs and flags drift — the garbage
collector that keeps the smart zone smart.
