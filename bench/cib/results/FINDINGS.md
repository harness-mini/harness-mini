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

## Next

- Build **D2** (multi-hop reasoning, graded scoring) and re-run on gpt-4o-mini + Qwen2.5-7B.
- Optionally replicate the paper's actual QA-F1 task to close the loop on its cliff.
