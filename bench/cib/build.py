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


def build_prompt(
    target_pct: float,
    window: int,
    corpus: str,
    needle: str,
    *,
    tokenizer: str = DEFAULT_TOKENIZER,
    token_counter: Callable[[str], int] | None = None,
    needle_frac: float = 0.5,
    tolerance: float = 0.02,
    max_iter: int = 16,
) -> BuiltPrompt:
    """Construct a prompt whose occupancy lands on `target_pct` of `window`.

    `tokenizer` is the label recorded in metadata. By default tokens are counted
    with the matching local proxy in TOKENIZERS (char/4). For a real per-model
    count, pass `token_counter` (e.g. the Anthropic count_tokens API) plus a
    descriptive `tokenizer` label like "anthropic:claude-opus-4-8".

    Real tokenizers are lumpier than the char/4 proxy, so the filler length is
    trimmed iteratively until occupancy is within `tolerance` of target rather
    than assuming a fixed chars-per-token ratio.
    """
    if not 0 < target_pct < 1:
        raise ValueError("target_pct must be in (0, 1)")

    counter = token_counter if token_counter is not None else (lambda t: count_tokens(t, tokenizer))
    target_tokens = round(target_pct * window)
    needle_block = NEEDLE_TEMPLATE.format(needle=needle)
    if counter(needle_block) >= target_tokens:
        raise ValueError("target occupancy too small to hold the needle")

    chars = 4 * target_tokens
    filler = _tile_to_length(corpus, max(len(needle_block) + 1, chars))
    for _ in range(max_iter):
        measured = counter(filler + needle_block)
        if abs(measured - target_tokens) <= tolerance * window:
            break
        chars = max(len(needle_block) + 1, round(chars * target_tokens / max(1, measured)))
        filler = _tile_to_length(corpus, chars)

    filler_hash = hashlib.sha256(filler.encode("utf-8")).hexdigest()
    cut = int(needle_frac * len(filler))
    text = filler[:cut] + needle_block + filler[cut:]
    needle_pos = text.index(needle)

    token_count = counter(text)
    return BuiltPrompt(
        text=text,
        token_count=token_count,
        occupancy_pct=token_count / window,
        window=window,
        filler_hash=filler_hash,
        needle=needle,
        needle_pos=needle_pos,
        tokenizer=tokenizer,
    )
