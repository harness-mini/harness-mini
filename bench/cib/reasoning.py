"""CIB #7 — D2 multi-hop reasoning probe.

D1 (exact-match retrieval) is ceiling'd for capable models and D3 (JSON) is a
formatting/capability signal — neither has graded headroom, so neither can show
the kind of decline the paper measured with QA-F1. D2 supplies that headroom: K
independent 2-hop chains scattered through the context. For each vault, a RECORD
gives a reference id; a separate REFERENCE line holds the access code. Distractor
REFERENCE lines (no matching RECORD) defeat "grab every number" shortcuts, so the
model must actually chain. Score = fraction of vaults solved → graded 0..100.
"""
from __future__ import annotations

import random
from dataclasses import dataclass


@dataclass(frozen=True)
class D2Probe:
    facts: list[str]      # RECORD/REFERENCE lines to scatter through the context
    expected: dict        # vault -> correct access code
    suffix: str           # the final-task instruction appended after the context


def _unique(rng: random.Random, lo: int, hi: int, taken: set) -> str:
    while True:
        v = str(rng.randint(lo, hi))
        if v not in taken:
            taken.add(v)
            return v


def make_d2(k: int = 5, n_distractors: int = 5, seed: int = 0) -> D2Probe:
    rng = random.Random(seed)
    refs: set = set()
    codes: set = set()
    facts: list[str] = []
    expected: dict = {}

    for i in range(1, k + 1):
        vault = f"V{i}"
        ref = "R" + _unique(rng, 1000, 9999, refs)
        code = _unique(rng, 10000, 99999, codes)
        expected[vault] = code
        facts.append(f"RECORD vault {vault}: access code filed under reference {ref}.")
        facts.append(f"REFERENCE {ref}: {code}.")

    for _ in range(n_distractors):
        ref = "R" + _unique(rng, 1000, 9999, refs)
        code = _unique(rng, 10000, 99999, codes)
        facts.append(f"REFERENCE {ref}: {code}.")  # no matching RECORD → a decoy

    rng.shuffle(facts)
    suffix = (
        "\n\n=== FINAL TASK ===\n"
        f"For each vault {', '.join('V%d' % i for i in range(1, k + 1))}: find its RECORD "
        "line to get the reference id, then find the REFERENCE line with that id to read the "
        "access code. Return ONLY a JSON object mapping each vault to its access code, e.g. "
        '{"V1": "12345", ...}.\n'
    )
    return D2Probe(facts, expected, suffix)
