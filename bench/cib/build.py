"""CIB issue #1 — prompt construction + occupancy measurement.

Build a single prompt to a *target context occupancy* (tokens / window) by tiling
filler sampled from a corpus and planting a retrieval needle at a known position.
This is the independent variable of the whole benchmark: occupancy %, per
docs/smart-dumb.md ("occupancy, not content") — never an invented composite load.

Tokens are counted with an *injectable* tokenizer. The default is a declared
proxy (char/4, the same heuristic as bin/ctx.sh) so the unit tests stay hermetic
and offline; the proxy name travels in the metadata so results never hide how
tokens were counted. The real model tokenizer is swapped in at run time
(issue #3) without changing this module.
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Callable

NEEDLE_TEMPLATE = "\n\n[DEVELOPER NOTE] {needle}\n\n"


def char4_tokens(text: str) -> int:
    """Declared proxy: ~4 chars per token, matching bin/ctx.sh's bytes/4."""
    return max(1, round(len(text) / 4))


DEFAULT_TOKENIZER = "char4"
TOKENIZERS: dict[str, Callable[[str], int]] = {"char4": char4_tokens}


def count_tokens(text: str, tokenizer: str = DEFAULT_TOKENIZER) -> int:
    try:
        return TOKENIZERS[tokenizer](text)
    except KeyError:
        raise ValueError(f"unknown tokenizer {tokenizer!r}; have {sorted(TOKENIZERS)}")


@dataclass(frozen=True)
class BuiltPrompt:
    text: str
    token_count: int
    occupancy_pct: float
    window: int
    filler_hash: str
    needle: str
    needle_pos: int          # character offset of the needle within `text`
    tokenizer: str


def _tile_to_length(corpus: str, length: int) -> str:
    """Repeat the corpus until it covers `length` chars, then truncate exactly."""
    if not corpus:
        raise ValueError("corpus is empty")
    reps = (length // len(corpus)) + 1
    return (corpus * reps)[:length]


def _scatter(filler: str, items: list[str]) -> str:
    """Place items in order at evenly spread positions through the filler."""
    if not items:
        return filler
    step = max(1, len(filler) // (len(items) + 1))
    parts, pos = [], 0
    for item in items:
        parts.append(filler[pos:pos + step])
        parts.append(item)
        pos += step
    parts.append(filler[pos:])
    return "".join(parts)


def build_prompt(
    target_pct: float,
    window: int,
    corpus: str,
    needle: str | None = None,
    *,
    inserts: list[str] = (),
    tokenizer: str = DEFAULT_TOKENIZER,
    token_counter: Callable[[str], int] | None = None,
    needle_frac: float = 0.5,
    tolerance: float = 0.02,
    max_iter: int = 16,
) -> BuiltPrompt:
    """Construct a prompt whose occupancy lands on `target_pct` of `window`.

    `needle` (D1) is planted as a single block at `needle_frac`. `inserts` (D2's
    scattered RECORD/REFERENCE lines) are spread evenly through the filler. Tokens
    are counted with the local char/4 proxy by default; pass `token_counter` for a
    real per-model count, with a descriptive `tokenizer` label. Real tokenizers are
    lumpier than char/4, so filler length is trimmed iteratively to within `tolerance`.
    """
    if not 0 < target_pct < 1:
        raise ValueError("target_pct must be in (0, 1)")

    counter = token_counter if token_counter is not None else (lambda t: count_tokens(t, tokenizer))
    target_tokens = round(target_pct * window)
    needle_block = NEEDLE_TEMPLATE.format(needle=needle) if needle else ""
    insert_blocks = [f"\n{s}\n" for s in inserts]
    extras = needle_block + "".join(insert_blocks)
    if counter(extras) >= target_tokens:
        raise ValueError("target occupancy too small to hold the probe content")

    chars = 4 * target_tokens
    filler = _tile_to_length(corpus, max(len(extras) + 1, chars))
    for _ in range(max_iter):
        measured = counter(filler + extras)
        if abs(measured - target_tokens) <= tolerance * window:
            break
        chars = max(len(extras) + 1, round(chars * target_tokens / max(1, measured)))
        filler = _tile_to_length(corpus, chars)

    filler_hash = hashlib.sha256(filler.encode("utf-8")).hexdigest()
    if insert_blocks:
        items = list(insert_blocks) + ([needle_block] if needle_block else [])
        text = _scatter(filler, items)
    else:
        cut = int(needle_frac * len(filler))
        text = filler[:cut] + needle_block + filler[cut:]
    needle_pos = text.index(needle) if needle else -1

    token_count = counter(text)
    return BuiltPrompt(
        text=text,
        token_count=token_count,
        occupancy_pct=token_count / window,
        window=window,
        filler_hash=filler_hash,
        needle=needle or "",
        needle_pos=needle_pos,
        tokenizer=tokenizer,
    )
