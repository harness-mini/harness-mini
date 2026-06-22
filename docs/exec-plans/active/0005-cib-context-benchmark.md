---
plan: cib-context-benchmark
seq: 0005
stage: issues
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

## Issues (run `to-issues`)
<!-- outcome · failing test · layer footprint · FILE footprint · depends-on -->
1. **Prompt construction + occupancy measurement** — build a message to a target token
   budget from the filler corpus; record actual occupancy. — files: `bench/cib/build.py`, `bench/cib/tests/test_build.py` — depends-on: none
2. **Probe battery D1 (needle/`verify_token`) + D3 (pure-JSON)** — byte-identical
   suffix + machine scorers. — files: `bench/cib/probe.py`, `bench/cib/score.py`, `bench/cib/tests/test_score.py` — depends-on: #1
3. **Agent runner (API/SDK), Arm A** — run constructed prompt, capture trajectory. — files: `bench/cib/run.py`, `bench/cib/runner_api.py` — depends-on: #1,#2
4. **Changepoint analysis** — penalty-selected; location + bootstrap CI + cliff-vs-linear. — files: `bench/cib/analyze.py`, `bench/cib/tests/test_analyze.py` — depends-on: none
5. **Minimal self-contained chart** — occupancy vs score, CI ribbon, detected zones. — files: `bench/cib/report.py`, `bench/cib/templates/report.html` — depends-on: #4
6. **Orchestrator `run.sh`** — buckets × trials → jsonl → analyze → report. — files: `bench/cib/run.sh`, `bench/cib/requirements.txt` — depends-on: #1–#5
7. *(horizontal)* **D2 multi-hop + infinite-loop detector** — files: `bench/cib/probe.py`, `bench/cib/loopdetect.py` — depends-on: #2
8. *(horizontal)* **D4 tool-use (hallucination + param drift)** — files: `bench/cib/probe.py`, `bench/cib/score.py` — depends-on: #2
9. *(horizontal)* **Drill-down trajectory replay UI** — files: `bench/cib/templates/report.html`, `bench/cib/report.py` — depends-on: #5,#7
10. *(horizontal)* **Arm B naturalistic + Logger middleware** — files: `bench/cib/logger.py`, `bench/cib/run.py` — depends-on: #3
11. *(horizontal)* **gzip density covariate overlay** — files: `bench/cib/analyze.py`, `bench/cib/report.py` — depends-on: #4,#5

## Vertical slices (build order)
1. **Walking skeleton (Arm A, end-to-end):** #1 → #2 (D1+D3) → #3 → #4 → #5 → #6.
   One model, ~5 buckets, low trial count — prove construct→run→score→changepoint→chart
   and the riskiest assumption (occupancy controllable via API). Passes evaluate first.
2. Then expand horizontally: #7, #8, #9, #10, #11.

## Parallel groups (after the skeleton passes evaluate)
- #4 (changepoint) is independent of #1–#3 — can build alongside the runner.
- Group A (parallel, disjoint-ish footprints): #7, #8, #10 — but #7/#8 both touch
  `probe.py`/`score.py`, so **sequential within that file**; #10 is truly disjoint.
- #9 depends on #5 + #7 → after the replay's loop detector exists.

## Evaluation
- Tier **L2**: cross-slice, a new public artifact, and the method underwrites A1.
  Grader is a **separate context** from the builder. Method-soundness (occupancy axis,
  byte-identical probe, honest changepoint) is itself an acceptance criterion, not just
  "tests pass."

## Now (resume here)
- Run `to-issues` to split the skeleton (#1–#6) into the repo's issue tracker, then
  start the walking skeleton at **#1** (prompt construction + occupancy measurement),
  TDD. First prove occupancy is controllable via the API runner before building #4–#6.

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
