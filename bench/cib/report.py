"""CIB issue #5 — render the self-contained dashboard.

The whole report is one HTML file with an inline SVG chart and the raw data
embedded — no CDN, no external scripts, nothing to fetch. A developer can save it
and paste it anywhere offline. (A richer Plotly build with click-to-replay
drill-down is the later slice #9; the contract here is just "self-contained".)
"""
from __future__ import annotations

import html
import json
import os

import analyze

_TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates", "report.html")

# SVG plot geometry.
_W, _H = 720, 360
_ML, _MR, _MT, _MB = 52, 18, 16, 40
_PW = _W - _ML - _MR
_PH = _H - _MT - _MB


def _rows(results) -> list[dict]:
    out = []
    for r in results:
        occ = getattr(r, "occupancy_pct", None)
        sc = getattr(r, "score", None)
        if occ is None:
            occ, sc = r["occupancy_pct"], r["score"]
        out.append({"occupancy_pct": occ, "score": sc})
    return out


def _x(occ: float) -> float:
    return _ML + occ * _PW


def _y(score: float) -> float:
    return _MT + (1 - score / 100) * _PH


def _svg(rows: list[dict], cp) -> str:
    parts = [f'<svg viewBox="0 0 {_W} {_H}" width="100%" role="img" aria-label="cliff chart">']

    # zone bands split at the changepoint
    if cp.location is not None:
        xc = _x(cp.location)
        parts.append(f'<rect x="{_ML}" y="{_MT}" width="{xc - _ML:.1f}" height="{_PH}" fill="#2ea04326"/>')
        parts.append(f'<rect x="{xc:.1f}" y="{_MT}" width="{_ML + _PW - xc:.1f}" height="{_PH}" fill="#f8514926"/>')
        if cp.bootstrap_ci is not None:
            lo, hi = _x(cp.bootstrap_ci[0]), _x(cp.bootstrap_ci[1])
            parts.append(f'<rect x="{lo:.1f}" y="{_MT}" width="{hi - lo:.1f}" height="{_PH}" fill="#f0883e2e"/>')
        parts.append(f'<line x1="{xc:.1f}" y1="{_MT}" x2="{xc:.1f}" y2="{_MT + _PH}" stroke="#f0883e" stroke-width="2"/>')

    # axes
    parts.append(f'<line x1="{_ML}" y1="{_MT + _PH}" x2="{_ML + _PW}" y2="{_MT + _PH}" stroke="#30363d"/>')
    parts.append(f'<line x1="{_ML}" y1="{_MT}" x2="{_ML}" y2="{_MT + _PH}" stroke="#30363d"/>')
    for pct in (0, 20, 40, 60, 80, 100):
        x = _x(pct / 100)
        parts.append(f'<text x="{x:.1f}" y="{_MT + _PH + 22}" fill="#8b949e" font-size="11" text-anchor="middle">{pct}%</text>')
    for sc in (0, 50, 100):
        y = _y(sc)
        parts.append(f'<text x="{_ML - 8}" y="{y + 4:.1f}" fill="#8b949e" font-size="11" text-anchor="end">{sc}</text>')
    parts.append(f'<text x="{_ML + _PW / 2:.1f}" y="{_H - 4}" fill="#8b949e" font-size="11" text-anchor="middle">context occupancy</text>')

    # raw trial points (light)
    for r in rows:
        cx, cy = _x(r["occupancy_pct"]), _y(r["score"])
        parts.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="2.5" fill="#58a6ff" fill-opacity="0.30"/>')

    # per-bucket mean ± CI: connecting line, error bars, mean markers
    buckets = analyze.aggregate([(r["occupancy_pct"], r["score"]) for r in rows], ci=cp.ci_level)
    if buckets:
        line = " ".join(f"{_x(b.occupancy_pct):.1f},{_y(b.mean):.1f}" for b in buckets)
        parts.append(f'<polyline points="{line}" fill="none" stroke="#58a6ff" stroke-width="1.5" stroke-opacity="0.6"/>')
        for b in buckets:
            bx = _x(b.occupancy_pct)
            parts.append(f'<line class="errbar" x1="{bx:.1f}" y1="{_y(b.hi):.1f}" x2="{bx:.1f}" y2="{_y(b.lo):.1f}" stroke="#58a6ff" stroke-width="1.5"/>')
            parts.append(f'<circle cx="{bx:.1f}" cy="{_y(b.mean):.1f}" r="3.5" fill="#58a6ff"/>')

    parts.append("</svg>")
    return "".join(parts)


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def render(results, cp, *, model: str, window: int) -> str:
    rows = _rows(results)
    if cp.location is not None:
        cutoff = f"{cp.location * 100:.1f}%"
        ci = f"{cp.bootstrap_ci[0] * 100:.1f}–{cp.bootstrap_ci[1] * 100:.1f}%"
        before = _mean([r["score"] for r in rows if r["occupancy_pct"] < cp.location])
        after = _mean([r["score"] for r in rows if r["occupancy_pct"] >= cp.location])
        drop = f"{before - after:.0f} pts"
    else:
        cutoff, ci, drop = "none detected", "—", "—"

    with open(_TEMPLATE, encoding="utf-8") as fh:
        template = fh.read()

    subs = {
        "{{MODEL}}": html.escape(model),
        "{{WINDOW}}": f"{window:,}",
        "{{N}}": str(len(rows)),
        "{{CUTOFF}}": cutoff,
        "{{CI_LABEL}}": f"{cp.ci_level * 100:.0f}% CI",
        "{{CI}}": ci,
        "{{DROP}}": drop,
        "{{SVG}}": _svg(rows, cp),
        "{{DATA_JSON}}": html.escape(json.dumps(rows, indent=2)),
    }
    for key, value in subs.items():
        template = template.replace(key, value)
    return template


def write_report(results, cp, path: str, *, model: str, window: int) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(render(results, cp, model=model, window=window))
