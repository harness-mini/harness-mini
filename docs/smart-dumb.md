# The smart/dumb contract

> Requirement #1 of harness-mini. This is the intellectual core: keep every
> agent's context in the **smart zone** at all times.

## Definition — a clean-context budget, with occupancy as the cheap proxy

"Smart" and "dumb" name a **budget for keeping context clean.** 40% occupancy is
the *operating trigger* we measure — but our own benchmark (`bench/cib/`, see
`results/FINDINGS.md`) found that **what fills the window matters more than how full
it is.** Treat 40% as a conservative checkpoint default, not a law.

- **Smart zone — below 40% occupancy (default trigger).** Comfortable headroom to
  reason, follow instructions, and write a clean handoff.
- **Dumb zone — at or above 40%.** Not a measured cliff — a *checkpoint-now* line
  drawn early so quality never gets the chance to slide.

**What the CIB benchmark actually showed (2026-06, Qwen2.5-7B + gpt-4o-mini +
haiku-4.5):**
- Under a controlled design (fixed task, only fill varied), **raw occupancy alone
  showed no 40–50% intelligence cliff** — not even on Qwen2.5-7B, the model from the
  paper that motivated the line. Frontier models held smart on retrieval to ~78–80%.
- The one thing that *did* degrade quality was **interference**: filling the window
  with *irrelevant* text was tolerated, but filling it with *competing, related*
  content dropped real QA-F1. **Signal-to-noise, not token count, is the driver.**

So the line's real job is to bound **interference**, and the load-bearing mechanisms
below — fan-out distillation and progressive disclosure — are what keep the smart
zone smart by keeping competing content *out*. Occupancy is just the proxy we can
cheaply measure. The threshold is configurable (`HARNESS_CTX_THRESHOLD`, default 40);
every agent — main and sub — is responsible for keeping **itself** smart. See
assumption **A1** in `docs/assumptions.md` for the test record.

## Tuning the threshold — a default operating line, not a universal law

40% is a conservative default chosen so quality never gets a chance to slide. It
is **not** sacred. Set `HARNESS_CTX_THRESHOLD` to the number that matches your
risk tolerance and task:

```bash
HARNESS_CTX_THRESHOLD=30 bash bin/ctx.sh 60000 200000   # 30% → 2 (checkpoint)
HARNESS_CTX_THRESHOLD=40 bash bin/ctx.sh 60000 200000   # 40% → 0 (smart) [default]
HARNESS_CTX_THRESHOLD=60 bash bin/ctx.sh 60000 200000   # 60% → 0 (smart)
```

| Threshold | When | Trade-off |
|-----------|------|-----------|
| **30%** | high-stakes / long-horizon / unfamiliar code; you want maximum headroom for reasoning and a pristine handoff | checkpoints more often; more session resets |
| **40% (default)** | normal work | balanced |
| **60%** | a solo dev on a small, well-understood task who values flow over frequent resets, and accepts some quality risk | fewer resets; closer to the degradation cliff |

Rule of thumb for solo devs: lower the line when the **cost of a bad handoff** is
high (architecture, security, data); raise it when the task is small and you'd
rather not break flow. Never push it near the model's real limit — the whole
point is to checkpoint *while still sharp*.

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

Fan-out is not only for *reading*. In the implement stage, once the vertical
skeleton is proven, the main agent fans out **write** work too — one `generator`
per independent issue, in parallel (`parallel-slices`). The safety rule there is
**disjoint file footprints** (no two generators write the same file), and the same
firewall discipline applies in reverse: the orchestrator takes back each
generator's *distillate* (tests green, footprint touched), never the raw diffs —
read the code through the evaluator, not by inflating the orchestrator's window.

### 2. 40% = the checkpoint-and-reset trigger (not a hard wall)
Crossing 40% does not mean "stop blindly." It means: **checkpoint now, while you
are still sharp.** Write `.trace/checkpoints/<plan>-<seq>.md`, update the active
exec-plan, then reset to a fresh session that bootstraps from that artifact.
Waiting until 90% is fatal — the handoff itself would be written by a degraded
agent.

### 3. Measurement — best-effort, to *see* drift
`bin/ctx.sh <used_tokens> [window]` prints `N%` and exits 2 at/over threshold.
You cannot portably read a model's internal token counter, so this is an
estimate. It is good enough to watch trends in `.trace/runtime/`, not a hard
interrupt — and `bin/harness.sh report` charts those trends (max ctx%, how often
the 40% line was crossed) so the threshold is tuned by data, not guesswork.

### 4. Progressive disclosure keeps the baseline low
`AGENTS.md` is a ~100-line map of pointers, never an encyclopedia. Start
near-empty; pull a file only when you need it. This buys the most headroom for
the least effort.

### 5. One bounded task per session
A session scoped to a single feature / plan-step never *needs* to hold
everything, so it naturally stays under budget.

## Enforcement style
**Behavioral + structural**, not a hard runtime kill: agents follow this
protocol and the explorer firewall does the heavy lifting.

### Give the 40% line teeth (opt-in, Claude Code)
The rule only bites if something *watches*. `bin/ctx-hook.sh` is a PostToolUse
adapter that, after every tool call, estimates context from the transcript size,
records a `ctx_pct` sample (so `harness.sh report` has real data), and nudges you
to checkpoint once you cross the line. It's the one Claude-Code-specific file —
**opt-in**, so the harness stays CLI-agnostic. Wire it up in `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "bash bin/ctx-hook.sh" } ] }
    ]
  }
}
```

Honest caveat: `bytes(transcript)/4` is a heuristic proxy for tokens, not a true
count — good enough to see the trend and fire a reminder, which is all this asks.

## Entropy: smart context decays
Smart context is **append-rarely, prune-aggressively.** Over time, once-useful
"always-loaded" facts rot. The **gardener** agent periodically demotes stale
smart context back into dumb (on-demand) docs and flags drift — the garbage
collector that keeps the smart zone smart.
