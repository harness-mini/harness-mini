"""CIB #14 — real QA-F1 on HotpotQA, for the confound test.

The synthetic D2 probe showed no controlled cliff, but it could not rule out an
effect that needs dense *natural* content. This module runs the paper's actual
kind of task: multi-hop QA over Wikipedia paragraphs, scored with SQuAD-style
token-F1 (the paper's metric) — graded, with real headroom.

The decisive comparison fills context to the same occupancy two ways, with the
**same fixed questions**:
  - filler-fill   : pad with irrelevant repeated text  → occupancy ↑, interference flat
  - distractor-fill: pad with related Wikipedia paras  → occupancy ↑, interference ↑
A cliff under distractor but not filler ⇒ the effect is interference density, not
raw occupancy — the mechanism behind the natural-length confound.
"""
from __future__ import annotations

import re
import string
from dataclasses import dataclass

_ARTICLES = re.compile(r"\b(a|an|the)\b")
_PUNCT = str.maketrans("", "", string.punctuation)


def _normalize(text: str) -> list[str]:
    text = text.lower().translate(_PUNCT)
    text = _ARTICLES.sub(" ", text)
    return text.split()


def token_f1(prediction: str, gold: str) -> float:
    """SQuAD/HotpotQA token-level F1 (normalized: lowercase, no punct/articles)."""
    pred, g = _normalize(prediction), _normalize(gold)
    if not pred or not g:
        return float(pred == g)
    common: dict = {}
    for t in g:
        common[t] = common.get(t, 0)
    overlap = 0
    gset: dict = {}
    for t in g:
        gset[t] = gset.get(t, 0) + 1
    pcount: dict = {}
    for t in pred:
        pcount[t] = pcount.get(t, 0) + 1
    for t, c in pcount.items():
        overlap += min(c, gset.get(t, 0))
    if overlap == 0:
        return 0.0
    precision = overlap / len(pred)
    recall = overlap / len(g)
    return 2 * precision * recall / (precision + recall)


@dataclass(frozen=True)
class QAItem:
    question: str
    answer: str
    gold: list          # [(title, paragraph_text), ...] — the supporting paragraphs
    distractors: list   # [(title, paragraph_text), ...] — non-supporting paragraphs


def _paragraph(title: str, sentences: list) -> str:
    return f"{title}: {''.join(sentences).strip()}"


def parse_hotpot(row: dict) -> QAItem:
    gold_titles = set(row["supporting_facts"]["title"])
    titles = row["context"]["title"]
    sents = row["context"]["sentences"]
    gold, distractors = [], []
    for title, para_sents in zip(titles, sents):
        para = _paragraph(title, para_sents)
        (gold if title in gold_titles else distractors).append((title, para))
    return QAItem(row["question"], row["answer"], gold, distractors)


QA_SUFFIX = (
    "\n\nQuestion: {q}\n"
    "Answer using only the documents above. Reply with the answer text only — "
    "no explanation, no JSON, no preamble.\n"
)


def _scatter(units: list[str], gold: list[str]) -> str:
    """Spread gold paragraphs evenly among the fill units (gold not all at the top)."""
    if not units:
        return "\n\n".join(gold)
    step = max(1, len(units) // (len(gold) + 1))
    out, gi = [], 0
    for i, u in enumerate(units):
        out.append(u)
        if gi < len(gold) and (i + 1) % step == 0:
            out.append(gold[gi]); gi += 1
    out.extend(gold[gi:])
    return "\n\n".join(out)


def build_qa_prompt(item, target_pct, window, fill_mode, distractor_pool, corpus, counter):
    """Build a QA prompt to a target occupancy. Gold paragraphs are always present;
    padding is irrelevant `corpus` filler (fill_mode='filler') or related Wikipedia
    paragraphs from `distractor_pool` (fill_mode='distractor'). Same questions across
    buckets ⇒ difficulty fixed; only fill amount/kind varies."""
    gold_paras = [p for _, p in item.gold]
    suffix = QA_SUFFIX.format(q=item.question)
    target_tokens = round(target_pct * window)
    budget_chars = 4 * target_tokens - counter(suffix + "".join(gold_paras)) * 4

    units: list[str] = []
    if budget_chars > 0:
        if fill_mode == "distractor":
            pool = [p for _, p in distractor_pool] or [c for _, c in item.distractors]
            acc, i = 0, 0
            while acc < budget_chars and pool:
                u = pool[i % len(pool)]
                units.append(u); acc += len(u) + 2; i += 1
        else:
            chunk = corpus if corpus else "filler. "
            acc = 0
            while acc < budget_chars:
                take = chunk[: max(1, budget_chars - acc)]
                units.append(take); acc += len(take) + 2

    text = _scatter(units, gold_paras) + suffix
    return text, counter(text) / window

