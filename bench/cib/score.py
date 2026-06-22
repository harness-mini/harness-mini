"""CIB issue #2 — machine scorers for the D1 and D3 probe dimensions.

A *trajectory* is the runner's normalized record of a single agent run: a list of
steps, each a dict with "type" in {"text", "tool_call"}. A tool_call step carries
"name" (str) and "args" (dict). Both scorers are pure functions — no IO, no model
in the loop — so scoring is reproducible and auditable.
"""
from __future__ import annotations

import json
import re
from typing import Any

_FENCE = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)


def score_d1(trajectory: list[dict[str, Any]], expected_token: str) -> int:
    """100 iff verify_token was called with the expected token; else 0.

    Covers the failure modes the spec calls out: not found, wrong tool, wrong
    value, and phantom (empty) parameters all score 0.
    """
    calls = [
        step for step in trajectory
        if step.get("type") == "tool_call" and step.get("name") == "verify_token"
    ]
    for call in calls:
        if expected_token in (str(v) for v in call.get("args", {}).values()):
            return 100
    return 0


def _parses(text: str) -> bool:
    try:
        json.loads(text)
        return True
    except (ValueError, TypeError):
        return False


def _extract_json(text: str) -> str | None:
    fenced = _FENCE.search(text)
    if fenced:
        return fenced.group(1).strip()
    start, end = text.find("{"), text.rfind("}")
    if 0 <= start < end:
        return text[start:end + 1]
    return None


def score_d3(text: str) -> int:
    """100 pure JSON · 50 JSON wrapped in prose/fences · 0 no valid JSON."""
    stripped = text.strip()
    if "```" not in stripped and _parses(stripped):
        return 100
    extracted = _extract_json(stripped)
    if extracted is not None and _parses(extracted):
        return 50
    return 0
