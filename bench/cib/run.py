"""CIB issue #3 (+ #6 CLI) — single-trial wiring and the benchmark orchestrator.

run_trial() composes the pieces of Arm A: build a prompt at a target occupancy
(#1), append the byte-identical probe (#2), run the agent (#3), and score the
dimensions the skeleton activates (D1, D3). main() sweeps buckets × trials, writes
results.jsonl, runs changepoint analysis (#4), and renders the report (#5).
"""
from __future__ import annotations

import argparse
import json
import os
from dataclasses import asdict, dataclass, field

import build
import probe
import runner_api
import score
# analyze (#4) and report (#5) are imported lazily in main() so the trial layer
# stays importable and testable without the analysis/report layers present.

# Weights of the full AIDB battery; the skeleton activates D1 + D3 and normalizes
# the composite over whatever dimensions are present.
BATTERY_WEIGHTS = {"D1": 0.20, "D2": 0.30, "D3": 0.20, "D4": 0.30}


@dataclass(frozen=True)
class TrialResult:
    occupancy_pct: float
    token_count: int
    window: int
    filler_hash: str
    scores: dict
    score: float
    trajectory: list = field(default_factory=list)


def _composite(scores: dict) -> float:
    weight = sum(BATTERY_WEIGHTS[d] for d in scores)
    return sum(BATTERY_WEIGHTS[d] * s for d, s in scores.items()) / weight


def _expected_token(needle: str) -> str:
    return needle.split(":")[-1].strip()


def run_trial(target_pct, window, corpus, needle, transport, *, max_steps=8) -> TrialResult:
    bp = build.build_prompt(target_pct, window, corpus, needle)
    full_prompt = bp.text + probe.probe_suffix()
    trajectory = runner_api.run(full_prompt, [probe.VERIFY_TOKEN_TOOL], transport, max_steps=max_steps)
    scores = {
        "D1": score.score_d1(trajectory, _expected_token(needle)),
        "D3": score.score_d3(runner_api.final_text(trajectory)),
    }
    return TrialResult(
        occupancy_pct=bp.occupancy_pct,
        token_count=bp.token_count,
        window=window,
        filler_hash=bp.filler_hash,
        scores=scores,
        score=_composite(scores),
        trajectory=trajectory,
    )


def _mock_transport(occupancy_pct: float, cliff: float = 0.45):
    """Offline demo: smart below the cliff, dumb at/above it — yields a real curve."""
    if occupancy_pct < cliff:
        return runner_api.ScriptedTransport([
            {"tool_calls": [{"name": "verify_token", "args": {"token": "9527"}}], "text": None},
            {"tool_calls": [], "text": '{"sessions": 5}'},
        ])
    return runner_api.ScriptedTransport([
        {"tool_calls": [], "text": "I'll just start; the answer is around five sessions."},
    ])


def _corpus(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Context Intelligence Benchmark (CIB) — Arm A")
    p.add_argument("--model", default="claude-opus-4-8")
    p.add_argument("--window", type=int, default=200_000)
    p.add_argument("--buckets", default="10,20,30,40,50,60,70,80",
                   help="comma-separated occupancy percentages")
    p.add_argument("--trials", type=int, default=5)
    p.add_argument("--needle", default="test_token: 9527")
    p.add_argument("--mock", action="store_true", help="offline scripted run (no API)")
    p.add_argument("--out", default=".")
    here = os.path.dirname(os.path.abspath(__file__))
    p.add_argument("--corpus", default=os.path.join(here, "fixtures", "filler_sample.txt"))
    args = p.parse_args(argv)

    import analyze
    import report

    corpus = _corpus(args.corpus)
    buckets = [int(b) / 100 for b in args.buckets.split(",")]
    os.makedirs(args.out, exist_ok=True)
    jsonl_path = os.path.join(args.out, "results.jsonl")

    results = []
    with open(jsonl_path, "w", encoding="utf-8") as fh:
        for target in buckets:
            for _ in range(args.trials):
                transport = (_mock_transport(target) if args.mock
                             else runner_api.default_transport(args.model))
                r = run_trial(target, args.window, corpus, args.needle, transport)
                results.append(r)
                fh.write(json.dumps(asdict(r)) + "\n")

    points = [(r.occupancy_pct, r.score) for r in results]
    cp = analyze.analyze(points)
    report.write_report(results, cp, os.path.join(args.out, "cib_report.html"),
                        model=args.model, window=args.window)
    print(f"wrote {jsonl_path} ({len(results)} trials) and cib_report.html")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
