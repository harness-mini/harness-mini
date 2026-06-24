# CIB — first real-model findings (Arm A)

Live runs through OpenRouter, June 2026. Probe = **D1** (find a planted token, call
`verify_token`) + **D3** (final answer must be pure JSON). Occupancy = the exact
`usage.prompt_tokens / window` reported per response. `--max-steps 4`.

## Headline

**No model showed the paper's 40–50% intelligence cliff — and that includes the
paper's own model.** The difference from Wang/Min/Zou (arXiv:2601.15300, Qwen2.5-7B,
F1 0.55→0.30 at 40–50%) is the **measurement method, not the models.**

## Per-model (mean composite score by occupancy)

| Model | window | shape | detected cliff |
|---|---|---|---|
| openai/gpt-4o-mini | 128k | flat ~90–100 to 77% | none |
| anthropic/claude-haiku-4.5 | 200k | flat 75 to 78%, dips at ~89% | 88.9% (just the top bucket) |
| qwen/qwen-2.5-7b-instruct | 32k (native) | flat-noisy 40–60%, **no 40–50% cliff** | none |

## Why the cliff didn't reproduce — it's the method

The decisive test was running **Qwen2.5-7B (the paper's exact model) on our probe**.
It did *not* cliff. So the explanation is the probe/metric, in three parts:

1. **Ceiling on D1.** Exact-match needle retrieval + a tool call is essentially solved,
   even for Qwen2.5-7B (mostly 100). No graded headroom → nothing to "decline" from.
   The paper's task was **F1 on (inferred) QA** with a *mid-range* 0.55 baseline — graded,
   with room to fall.
2. **Floor/offset on D3.** The JSON-constraint score is a *capability/style* signal, not a
   context one: Qwen2.5-7B floors near **0** (can't honor "no markdown"), haiku sits at a
   constant **50** (always fences), gpt-4o-mini is high-but-noisy. None of these is a
   graded function of occupancy.
3. **Confound removed.** The paper uses *natural, unpadded* document lengths, so length is
   confounded with document difficulty; our Arm A holds the probe identical and varies only
   filler — so a partly-confounded cliff has even less reason to appear.

Net: our current probe lacks a **graded, sub-ceiling baseline that taxes reasoning**, so it
cannot detect (or refute) the paper's cliff *regardless of model*.

## Implication for A1 (the 40% line)

These results say **easy retrieval/formatting does not degrade by 40% in current models**
(the line is conservative for that). They do **not** test what A1 actually worries about —
reasoning under load (dropping instructions, mis-optimizing). That needs **D2: multi-hop
reasoning** (backlog #7) — a graded probe with F1-like headroom. Until D2 runs, A1 is
neither validated nor refuted by this data; only the "easy-task" regime is.

## D2 multi-hop reasoning — the controlled replication on Qwen2.5-7B

Built D2 (graded: K independent 2-hop chains, scored as fraction solved, lenient on
format) to give the headroom D1/D3 lacked, then ran it on the **paper's own model**.
The point was to reproduce the paper's 40–50% cliff under a *controlled* design
(probe fixed, only fill varies). Four passes, each fixing the previous limitation:

| pass | probe | trials/bucket | low-occ baseline | shape | cliff? |
|---|---|---|---|---|---|
| 1 | D1 retrieval | 5 | 100 (ceiling) | flat | none |
| 2 | D2, k=5 chains | 5 | ~24 (floored — too hard) | flat-low | none |
| 3 | D2, k=2 chains | 6 | ~42 (mid — calibrated!) | noisy, faint dip | none (noise) |
| 4 | **D2, k=2 chains** | **25** | ~30 | **flat, ±15 CI** | **none (decisive)** |

Pass-4 means by occupancy (11→82%): 32, 26, 8, 20, 32, 26, 20, 28, 32, 38 — flat;
the highest bucket is the *most*-filled (82%). The apparent decline in the low-N
pass-3 was sampling noise; n=25 erased it.

## Conclusion — the paper's cliff did NOT reproduce under control

Across **four probe regimes on the paper's exact model (Qwen2.5-7B)** — retrieval,
hard reasoning, calibrated reasoning at low- and high-N — **no 40–50% cliff appeared
when task difficulty was held fixed and only context fill varied.**

The most likely explanation is the **confound our Arm A removes**: the paper samples
*natural, unpadded* document lengths, so its longer contexts are *different, harder
documents*. Its "cliff" is then partly **"longer real documents are intrinsically
harder to answer," not "the same task degrades as the window fills."** Control for
difficulty and the cliff largely disappears.

**Honest limits (what this does NOT prove):** our filler is synthetic and may be more
"ignorable" than dense real prose; k=2 scoring is coarse (±15 CIs); this is one model
and one probe family. So we cannot claim *no* pure-occupancy effect exists — only that
a controlled probe on the paper's own model does not show the advertised cliff.

## Implication for A1 (the 40% line)

The strongest external citation for a hard ~40% threshold **does not survive a
controlled replication on its own model.** That doesn't refute A1 as an *operating
default* (checkpointing early is cheap insurance, and frontier models held smart to
~78–80% on retrieval here), but it removes "a paper proved 40%" as support. A1 should
be recorded as a **conservative engineering heuristic, not an empirically-pinned
constant** — and the real degradation signal A1 cares about (reasoning under load)
was not observed up to 80% on the models tested.

## Method lesson (the reusable result)

A context cliff is only observable when three conditions hold at once: (1) probe
difficulty calibrated so the low-occupancy baseline is mid-range (not ceiling/floor),
(2) enough trials to beat per-trial variance (n=6 produced a false cliff; n=25 erased
it), and (3) a model stable enough to start high. Miss any one → "no cliff." This
fragility is itself the argument against trusting any single-number "X% rule."

## Next (optional)

- Replicate the paper's *actual* QA-F1 task on natural documents to directly test the
  confound hypothesis (would the cliff reappear with natural lengths but vanish when
  the same docs are truncation-controlled?).
- Run D2 k=2 high-N on a frontier model (gpt-4o-mini) for a capability contrast.
