---
plan: cib-context-benchmark
seq: 0005
stage: implement
owner: main
mode: full
eval: L2        # new code + public artifact; A1's credibility rests on the method
---
# CIB — empirical backing for A1 (the 40% smart/dumb line)

> **Full mode.** New code, a new dependency island, a public-facing artifact, and
> the harness's most load-bearing belief (the 40% line) rests on the method being
> sound. Tracks issue **#34**.

## Intake
- **Five-step** (question → delete → simplify → accelerate → automate):
  - *Question:* do we need a benchmark at all, or just run A1's 40/60/70 A/B by hand
    once? → We need it: A1 should be **re-runnable per model tier** (the register is
    audited "whenever the builder model tier moves"), and a one-off manual run leaves
    no artifact. A repeatable tool earns its keep; a one-off does not.
  - *Delete (the biggest cut):* the original spec's **`Intelligence Load` formula**
    (gzip × token × (1+αC)(1+βT)). It's the most code and the least defensible. The
    x-axis is just `tokens / window`. Deleting it removes the free parameters, the
    circularity, and a chunk of implementation.
  - *Delete #2:* forcing **three segments** via two `ruptures` passes — replaced by
    penalty-selected changepoints. Less code, honest result.
  - *Simplify:* skeleton ships **D1+D3 only** (both machine-checkable); D2/D4 and the
    replay UI are horizontal expansion, not skeleton.
- **Riskiest assumption:** that we can hit a *target context occupancy precisely* in
  a real agent client. We probably can't (client injects uncontrolled scaffolding) →
  **Arm A runs via the API/SDK** with a self-built message; occupancy is measured,
  not assumed. Validate this in the skeleton before building anything else.

## Problem
A1 (the 40% checkpoint-and-reset line) is the harness's intellectual core, yet
`docs/assumptions.md` admits it has **zero experimental signal** ("max 33%, 0 eval
pass/fail"). The one external paper (arXiv:2601.15300) is a single small model on
retrieval F1. We are defaulting `HARNESS_CTX_THRESHOLD=40` on faith. Who hurts: every
agent run that resets too early (wasted resets) or too late (degraded handoff) because
the line is un-tuned for the current model. Why now: builder tier moved to `opus`; A1
says the line is "plausibly raisable" but won't move it without data.

## PRD (run `to-prd`)
- **Goal:** a re-runnable tool that, for a given model, plots Agent score vs context
  occupancy %, detects whether/where a degradation cliff exists (with a CI), and
  renders a self-contained dashboard — turning A1 from faith into a measured,
  per-model line.
- **Out of scope (deleted via five-step):** the `Intelligence Load` composite axis;
  forced 3-band segmentation; multi-model sweep in v1 (one model first); any change to
  core harness deps (CIB is an isolated island).

## Acceptance criteria
(mirrors #34; `M` = machine-checkable, `J` = judgment)
- [ ] (M) `bench/cib/run.sh --model M --buckets … --trials K` → `results.jsonl` + self-contained `cib_report.html`.
- [ ] (M) every point records `occupancy_pct = constructed_tokens / window`; **no α/β IL formula** in the code.
- [ ] (M) Arm A probe suffix is **byte-identical** across buckets (hash-equality assert).
- [ ] (M) ≥K trials per bucket; report stores mean + CI per bucket.
- [ ] (M) changepoint output `{location, bootstrap_CI, cliff_vs_linear_support}`; not forced to 3 segments.
- [ ] (M) report self-contained — `grep -i 'src="http\|cdn'` finds nothing.
- [ ] (J) chart shows CI ribbon + zones from the *detected* changepoint; headline bound to `model@window`.
- [ ] (J) click a point → trajectory replay with drift/loop annotations.
- [ ] (M) core `tests/run.sh` green; `harness.sh doctor` clean; all CIB deps under `bench/cib/`, not imported by core.

## Issues — walking skeleton (decomposed via `to-issues`, TDD-ready)
<!-- each: outcome · failing test (write first) · layers · FILE footprint · depends-on · done -->

### #1 — Prompt construction + occupancy measurement  ⟵ riskiest assumption · ✅ DONE (6/6)
- **Outcome:** `build_prompt(target_pct, window, corpus, needle)` → one message whose
  measured `tokens/window` hits `target_pct` within ±2%, plus metadata (`token_count`,
  `occupancy_pct`, `filler_hash`, needle position).
- **Failing test:** for buckets {0.10, 0.40, 0.70}, assert measured occupancy within
  ±0.02 of target and that metadata `occupancy_pct` equals the re-measured count; assert
  the model's tokenizer is used (or a declared proxy is recorded in metadata).
- **Layers:** Types (`BuiltPrompt`) · Service (assembly).
- **Files:** `bench/cib/build.py`, `bench/cib/tests/test_build.py`, `bench/cib/fixtures/filler_sample.txt`.
- **depends-on:** none. **done =** occupancy within tolerance across ≥3 buckets + metadata recorded.

### #2 — Probe battery D1 (needle/`verify_token`) + D3 (pure-JSON) + scorers · ✅ DONE (11/11)
- **Outcome:** byte-identical probe suffix (D1: instruction to call `verify_token` with
  the planted token; D3: pure-JSON constraint) + machine scorers for both.
- **Failing test:** (a) `probe_suffix()` byte-identical across calls/buckets (hash
  equality); (b) D1 scorer → 100 for `verify_token("9527")`, 0 for missing/wrong/phantom;
  (c) D3 scorer → 100 pure JSON, 50 with preamble ("Here is the JSON:"), 0 invalid
  (`json.loads` + regex).
- **Layers:** Types (`Probe`, `Score`) · Service (scorers).
- **Files:** `bench/cib/probe.py`, `bench/cib/score.py`, `bench/cib/tests/test_score.py`.
- **depends-on:** #1 (needle planted via build). **done =** suffix hash-stable + both scorers match the rubric.

### #3 — Agent runner (API/SDK), Arm A  ⟵ end-to-end skeleton closes here · ✅ DONE (4/4)
- **Outcome:** run a constructed prompt + tool schemas against the model, return a
  normalized trajectory (messages, tool calls, final text) for scoring.
- **Failing test:** against a **mock transport**, `run(prompt, tools)` returns a
  trajectory in which a `verify_token` tool call is captured and routed to the D1 scorer;
  the real-API path is gated behind a credential env var (skipped in unit tests).
- **Layers:** Config (model id/window/creds) · Runtime (runner).
- **Files:** `bench/cib/runner_api.py`, `bench/cib/run.py`, `bench/cib/tests/test_runner.py`.
- **depends-on:** #1, #2. **done =** mock run yields a scored trajectory; real run gated behind creds.

### #4 — Changepoint analysis  (independent — parallel with #1→#3) · ✅ DONE (3/3, zero-dep)
- **Outcome:** `analyze(points)` → `{location, bootstrap_CI, cliff_vs_linear_support}`,
  penalty-selected changepoints (ruptures), **not** forced to 3 segments.
- **Failing test:** synthetic cliff at 0.45 → location within ±0.05 and CI brackets it,
  `cliff_vs_linear_support` True; synthetic linear decline → support False / 0 changepoints.
- **Layers:** Service (pure, no IO).
- **Files:** `bench/cib/analyze.py`, `bench/cib/tests/test_analyze.py`.
- **depends-on:** none. **done =** known cliff recovered + linear null handled.

### #5 — Minimal self-contained chart · ✅ DONE (5/5, inline SVG)
- **Outcome:** render `cib_report.html` — occupancy-vs-score scatter, mean+CI ribbon per
  bucket, zones from the detected changepoint; everything inline.
- **Failing test:** generated HTML embeds the data + changepoint/CI inline and
  `grep -i 'src="http\|cdn'` finds nothing (regex assert on the rendered string).
- **Layers:** UI (template + render).
- **Files:** `bench/cib/report.py`, `bench/cib/templates/report.html`, `bench/cib/tests/test_report.py`.
- **depends-on:** #4. **done =** self-contained assert passes; renders with skeleton data.

### #6 — Orchestrator `run.sh` · ✅ DONE (smoke green)
- **Outcome:** `bench/cib/run.sh --model M --buckets … --trials K [--mock]` runs
  buckets × trials → `results.jsonl` → `analyze` → `cib_report.html`.
- **Failing test:** `run.sh --mock --buckets 10,40,70 --trials 2` writes a 6-line
  `results.jsonl` and a `cib_report.html` (shell smoke test, `tests/run.sh` style).
- **Layers:** Runtime (orchestration) · Config (`requirements.txt`).
- **Files:** `bench/cib/run.sh`, `bench/cib/requirements.txt`, `bench/cib/tests/test_run_smoke.sh`.
- **depends-on:** #1–#5. **done =** mock end-to-end produces jsonl + html.

### Horizontal backlog (coarse; expand via `to-issues` when promoted, after skeleton passes evaluate)
7. **D2 multi-hop + infinite-loop detector** — `bench/cib/probe.py`, `bench/cib/loopdetect.py` — dep #2
8. **D4 tool-use (hallucination + param drift)** — `bench/cib/probe.py`, `bench/cib/score.py` — dep #2
9. **Drill-down trajectory replay UI** — `bench/cib/templates/report.html`, `bench/cib/report.py` — dep #5,#7
10. **Arm B naturalistic + Logger middleware** — `bench/cib/logger.py`, `bench/cib/run.py` — dep #3
11. **gzip density covariate overlay** — `bench/cib/analyze.py`, `bench/cib/report.py` — dep #4,#5

## Vertical slices (build order)
1. **Walking skeleton (Arm A, end-to-end):** #1 → #2 (D1+D3) → #3 → #4 → #5 → #6.
   One model, ~5 buckets, low trial count — prove construct→run→score→changepoint→chart
   and the riskiest assumption (occupancy controllable via API). Passes evaluate first.
2. Then expand horizontally: #7, #8, #9, #10, #11.

## Parallel groups
**Skeleton (two lanes):** the chain **#1 → #2 → #3** is sequential (shared `build`/`probe`
lineage); **#4** is independent (disjoint files, no dep) → build it in parallel with that
chain. The lanes converge at **#5** (needs #4) → **#6** (integrates all).

**Horizontal (after skeleton passes evaluate):** #7 and #8 both touch `probe.py`/`score.py`
→ sequential to each other; **#10** is disjoint → parallel with #7/#8; **#9** waits on
#5 + #7 (needs the loop detector); **#11** waits on #4 + #5.

## Evaluation
- Tier **L2**: cross-slice, a new public artifact, and the method underwrites A1.
  Grader is a **separate context** from the builder. Method-soundness (occupancy axis,
  byte-identical probe, honest changepoint) is itself an acceptance criterion, not just
  "tests pass."

## Now (resume here)
- **SKELETON COMPLETE: #1–#6 all green.** 29 bench tests + smoke; core suite 157/157.
  `run.sh --mock` does build→probe→run→score→analyze→report end-to-end and detects the
  mock cliff at 45.0%. Still zero third-party deps installed (mock path is stdlib-only).
- **Next:** **L2 separate-context evaluate** (A2 firewall) — grade #1–#6 against the
  acceptance criteria from a fresh context (method-soundness is itself a criterion).
  Then mark PR #35 ready, or proceed to horizontal expansion (#7–#11). Draft PR: #35.

## Next
- Skeleton → evaluate (L2) → horizontal expansion (#7–#11) → run on current model →
  feed the measured line back into **A1** (raise the default if it lands materially
  above 40%).

## Decisions log
- 2026-06-22: Design reviewed against the original CIB spec. **Deleted** the
  `Intelligence Load` formula (x-axis = occupancy %, per `smart-dumb.md` "occupancy,
  not content" and arXiv:2601.15300's %-of-window axis); **deleted** forced 3-segment
  fit (→ penalty-selected changepoint + bootstrap CI vs linear null). Added Arm A
  (fixed probe, varied fill) as primary evidence to kill the length/difficulty
  confound; Arm B (naturalistic) demoted to corroboration. gzip kept as a covariate,
  not the axis. Headline bound to `model@window`, not a universal "40%".
- 2026-06-22: **Dependency island** decision — CIB under `bench/cib/` with its own
  `requirements.txt`; core harness stays zero-dep POSIX shell; `doctor`/`tests/run.sh`
  unaffected. (Open: confirm `bench/` vs `examples/` placement at first PR.)
- 2026-06-22: Issue **#34** opened; this plan tracks it. Stage = issues.
- 2026-06-22: `to-issues` — skeleton (#1–#6) decomposed into TDD-ready atomic units
  (outcome · failing test · layers · files · depends-on · done); #7–#11 left coarse.
  Two parallel lanes (#1→#2→#3 alongside #4) converging at #5→#6. Issues tracked in
  this plan (repo convention; GitHub #34 is the umbrella). Stage stays `issues` until
  #1 is handed to the generator.
- 2026-06-22: #1 built TDD (red→green) in the main session (bounded slice, no generator
  spawn). `build_prompt` hits target occupancy within ±2% (char/4 proxy, recorded in
  metadata; real tokenizer + trim loop deferred to #3). 6/6 unit tests; core
  `tests/run.sh` 157/157. L0 self-check only — the L2 separate-context evaluate runs
  when the skeleton (#1–#6) is complete (A2 firewall). Stage → implement.
- 2026-06-22: #2 built TDD — byte-identical `PROBE_SUFFIX` (D1 verify_token + D3
  pure-JSON task) + pure scorers (`score_d1`/`score_d3`); covers the spec's failure
  modes (missing/wrong/phantom call; preamble/fence/invalid JSON). 11/11.
- 2026-06-22: #4 built TDD — **deviation:** zero-dep changepoint backend (brute-force
  two-means split + BIC vs linear null + bootstrap CI) instead of `ruptures`, to keep
  skeleton tests hermetic and the island install-free. Same output contract; `ruptures`
  stays a planned *optional* higher-fidelity backend (requirements.txt, later slice).
  Recovers a synthetic cliff at 0.45 (±0.05, CI brackets it) and rejects a linear
  decline. 3/3. Branch pushed; draft PR #35 against #34.
- 2026-06-22: #3 built TDD — agentic loop in `runner_api.run` (injectable transport;
  `ScriptedTransport` for hermetic tests/mock, lazy credential-gated `AnthropicTransport`
  for real runs) + `run_trial` wiring (build→probe→run→score D1/D3, composite normalized
  over present battery weights) + a max_steps loop guard. 4/4.
- 2026-06-22: #5 built TDD — **deviation:** the self-contained chart is **inline SVG**
  generated in Python, not Plotly-via-CDN — the honest way to satisfy "no external
  resource" and keep the test hermetic. Inlined Plotly + click-to-replay drill-down is
  the later slice #9. Report embeds zones/CI/data inline. 5/5.
- 2026-06-22: #6 built — `run.sh` (thin wrapper over `run.py` argparse CLI) +
  `requirements.txt` (mock = stdlib-only; `anthropic` for real runs; `ruptures`
  optional) + offline smoke test. **Skeleton #1–#6 complete**, 29 bench tests + smoke,
  core 157/157; `--mock` default sweep detects the cliff at 45.0%. Lazy `analyze`/`report`
  imports keep the trial layer testable without the analysis/report layers.
