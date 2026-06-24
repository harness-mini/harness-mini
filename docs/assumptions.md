# Assumption register

> Every load-bearing harness mechanism is a **patch for a presumed model gap**.
> Gaps close as models improve, leaving the patch behind as dead weight (see
> `docs/principles.md` → "Question stale assumptions" and the managed-agents
> distillate). This file holds those assumptions as **hypotheses with a test**.
>
> The `garden` sweep audits this register on a trigger (cadence: **pre-release**,
> and whenever the builder model tier moves). An assumption that no longer earns
> its keep is **deleted** — Five-Step step 2 applied to the harness's own beliefs.

Each entry: the assumption · the model-gap it patches · the experiment that would
show it's gone stale · status. `registered` = first logged; `audited` = last
re-tested against the current model.

> **Audit 2026-06-16** (triggered: builder tier moved to model-agnostic `opus`).
> **Judgment-only — nothing retired.** `harness.sh report` has no experimental
> signal yet (0 eval pass/fail; context never crossed 40%, max 33%), so no patch
> can be honestly deleted on this pass — that would need the A/B each entry names.
> Each `Status` below now carries a current-model judgment + what would settle it.
> The Cursor dogfood gave **A2** its one piece of real-world reconfirmation.

---

## A1 — The 40% smart/dumb line
- **Assumption:** quality degrades ("context anxiety") well before the nominal
  window limit, so we checkpoint-and-reset at 40% occupancy.
- **Patches:** the model losing instructions / optimizing the wrong constraint as
  its window fills.
- **Test if stale:** run the same long task at thresholds 40 / 60 / 70 and compare
  eval pass-rate + handoff quality via `harness.sh report` (ctx trend vs the line).
  If quality holds at a higher line on the current model, **raise the default**.
  (The post reports exactly this getting better Sonnet 4.5 → Opus 4.5.)
- **Status:** registered 2026-06-12 · audited 2026-06-16 · **tested 2026-06-24** —
  **keep as a conservative heuristic; demote the empirical claim.** The CIB benchmark
  (`bench/cib/`, see `results/FINDINGS.md`) ran the first controlled experiment: probe
  held fixed, only context fill varied (Arm A). Across 3 models (gpt-4o-mini, haiku-4.5,
  Qwen2.5-7B) and 4 probe regimes, **no 40–50% cliff appeared** — including on
  **Qwen2.5-7B, the exact model of the cited paper (arXiv:2601.15300)**, even at n=25.
  Retrieval held smart to ~78–80% on frontier models. Likely cause: the paper's
  natural-length sampling confounds context length with document difficulty, which our
  Arm A removes. **So: the "a paper proved 40%" support is withdrawn**; 40% stands only
  as cheap-insurance default (checkpoint early), not an empirically-pinned constant.
  Caveat: CIB's filler is synthetic and reasoning scoring is coarse, so a pure-occupancy
  effect on dense *natural* content isn't ruled out. Next: replicate the paper's QA-F1
  task with vs without truncation-control to test the confound directly.
  · **Confound test done (2026-06-24):** real HotpotQA + token-F1, same 20 questions at
  every occupancy bucket, padded two ways. **Pure-occupancy (filler) arm: flat** (60.0→61.9
  F1, 10→70%). **Interference (related-distractor) arm: declines** (49.4→40.7). Arms equal at
  the 10% baseline, gap widens with fill. ⇒ degradation tracks **interference, not raw
  occupancy** — the mechanism behind the paper's natural-length confound. The decline is
  gradual (no sharp 40% step) and modest vs the paper's. **Verdict: 40% is a useful
  conservative *default*, not a context-occupancy law.** What fills the window matters more
  than how full it is. (One model so far; frontier-model contrast still open.)

## A2 — Anti-self-praise eval firewall
- **Assumption:** a model confidently praises its own output, so grading must run
  in a **separate context** from the work (the evaluator, the `done`-gate).
- **Patches:** the worker being an unreliable judge of itself.
- **Test if stale:** have a generator self-grade N slices, and a separate evaluator
  grade the same N; measure the false-pass gap. If it collapses, the firewall is
  cheap insurance, not a necessity — relax to L0/L1 sooner.
- **Status:** registered 2026-06-12 · audited 2026-06-16 — **keep (durable).**
  Reconfirmed in the wild: the Cursor slugify dogfood's separate-chat evaluator
  caught a real gap (only 1 of 5 criteria tested) that the building chat had
  reported as "slice done" — the false-pass gap did **not** collapse. No change.

## A3 — Explorer fan-out firewall
- **Assumption:** pulling a big read/search into the main window degrades it, so
  heavy/dirty ops are delegated to a disposable explorer that returns a distillate.
- **Patches:** the model's quality dropping once its window holds bulk content.
- **Test if stale:** compare main-agent quality on a task with vs without
  delegating a >2k-token read, on the current model + window. If equal, raise the
  delegate-it threshold.
- **Status:** registered 2026-06-12 · audited 2026-06-16 — **keep.** Partly a
  context-budget win independent of model quality, so it survives regardless; no
  signal to justify raising the >2k-token threshold. Revisit with the explorer A/B.

## A4 — Progressive disclosure (the ~100-line map)
- **Assumption:** large always-on instructions get partially dropped / dilute, so
  `AGENTS.md` is a map of pointers, pulled on demand.
- **Patches:** weak instruction-following under a fat always-loaded prompt.
- **Test if stale:** A/B instruction-following with a fat always-on file vs the map
  on the current model. If the fat file is followed faithfully, the map can grow.
- **Status:** registered 2026-06-12 · audited 2026-06-16 — **keep.** Also a
  context-budget win, so it survives even as instruction-following improves; this
  same garden sweep trimmed the map 133→117 (#32), consistent with keeping it
  small. No A/B run, so the map approach stands.

## A5 — Caps / heavy emphasis for important instructions
- **Assumption:** the model under-weights non-emphasized constraints, so critical
  imperatives are bolded / capitalized (principle #9).
- **Patches:** flat attention across instructions of unequal importance.
- **Test if stale:** A/B a constraint with vs without caps; does compliance change
  on the current model? If not, drop the caps convention (less noise).
- **Status:** registered 2026-06-12 · audited 2026-06-16 — **keep for now;
  strongest relax-candidate.** Current models follow un-emphasized instructions
  well, so heavy caps may be noise — but the convention is woven through every doc
  (principle #9) and there's no A/B signal, so don't rip it out blind. Highest-
  priority experiment: A/B a constraint with vs without caps on the current model.
