"""CIB issue #4 — changepoint analysis (zero-dep skeleton backend).

Answers the only question that matters for A1: *is there a cliff, and where?* —
honestly. We compare a single-changepoint step model against a plain linear
decline by BIC, so a gradual slope is never mis-reported as a cliff, and we put a
bootstrap confidence interval on the changepoint location.

Skeleton uses a pure-Python brute-force split (no third-party deps, hermetic
tests). `ruptures` is a planned optional higher-fidelity backend behind this same
contract — see requirements.txt — not needed to prove the pipeline.

Contract: analyze(points) -> ChangepointResult{location, bootstrap_ci,
cliff_vs_linear_support, bic_piecewise, bic_linear}.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass

_EPS = 1e-9


@dataclass(frozen=True)
class ChangepointResult:
    location: float | None
    bootstrap_ci: tuple[float, float] | None
    cliff_vs_linear_support: bool
    bic_piecewise: float
    bic_linear: float


def _linear_sse(xs: list[float], ys: list[float]) -> float:
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx < _EPS:
        return sum((y - my) ** 2 for y in ys)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    slope = sxy / sxx
    intercept = my - slope * mx
    return sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))


def _segment_sse(ys: list[float]) -> float:
    m = sum(ys) / len(ys)
    return sum((y - m) ** 2 for y in ys)


def _best_split(xs: list[float], ys: list[float]) -> tuple[float, float]:
    """Brute-force the two-means split that minimises within-segment SSE.

    Returns (location, sse) where location is the midpoint between the two points
    bracketing the cut. Assumes xs is sorted ascending.
    """
    n = len(xs)
    best_sse = math.inf
    best_loc = xs[len(xs) // 2]
    for i in range(1, n):
        sse = _segment_sse(ys[:i]) + _segment_sse(ys[i:])
        if sse < best_sse:
            best_sse = sse
            best_loc = (xs[i - 1] + xs[i]) / 2
    return best_loc, best_sse


def _bic(sse: float, n: int, k: int) -> float:
    return n * math.log(max(sse, _EPS) / n) + k * math.log(n)


def _sorted_xy(points: list[tuple[float, float]]) -> tuple[list[float], list[float]]:
    ordered = sorted(points, key=lambda p: p[0])
    return [p[0] for p in ordered], [p[1] for p in ordered]


def analyze(
    points: list[tuple[float, float]],
    *,
    n_boot: int = 400,
    ci: float = 0.90,
    seed: int = 0,
) -> ChangepointResult:
    if len(points) < 4:
        raise ValueError("need at least 4 points for changepoint analysis")

    xs, ys = _sorted_xy(points)
    n = len(xs)

    bic_linear = _bic(_linear_sse(xs, ys), n, k=2)
    location, pw_sse = _best_split(xs, ys)
    bic_piecewise = _bic(pw_sse, n, k=3)
    support = bic_piecewise < bic_linear

    if not support:
        return ChangepointResult(None, None, False, bic_piecewise, bic_linear)

    rng = random.Random(seed)
    locs = []
    for _ in range(n_boot):
        sample = [points[rng.randrange(n)] for _ in range(n)]
        bxs, bys = _sorted_xy(sample)
        locs.append(_best_split(bxs, bys)[0])
    locs.sort()
    tail = (1 - ci) / 2
    lo = locs[int(tail * (len(locs) - 1))]
    hi = locs[int((1 - tail) * (len(locs) - 1))]

    return ChangepointResult(location, (lo, hi), True, bic_piecewise, bic_linear)
