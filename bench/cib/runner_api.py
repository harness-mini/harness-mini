"""CIB issue #3 — the agent runner (Arm A).

Drives a minimal agentic loop (model → tool calls → tool results → model) and
returns a *normalized trajectory* — the same shape score_d1 consumes and the
replay UI (#9) will render. The model is reached through an injectable transport:

    transport(messages, tools) -> {"tool_calls": [{"name", "args"}], "text": str|None}

A turn with text=None means "I made tool calls, continue"; a turn with text set
is the final answer. ScriptedTransport supplies deterministic turns for hermetic
tests and for `run.sh --mock`; AnthropicTransport (lazy-imported, credential-gated)
is the real backend and is never exercised by the test suite.
"""
from __future__ import annotations

import os
from typing import Any, Callable

Transport = Callable[[list, list], dict]
Trajectory = list[dict[str, Any]]


class ScriptedTransport:
    """Returns predefined turns in order, repeating the last (mock/test backend)."""

    def __init__(self, turns: list[dict]):
        if not turns:
            raise ValueError("ScriptedTransport needs at least one turn")
        self._turns = list(turns)
        self._i = 0

    def __call__(self, messages: list, tools: list) -> dict:
        turn = self._turns[min(self._i, len(self._turns) - 1)]
        self._i += 1
        return turn


def run(prompt: str, tools: list, transport: Transport, *, max_steps: int = 8, tool_handler=None) -> Trajectory:
    """Run one agent task to completion (or until max_steps); return its trajectory.

    A turn carrying tool calls is executed (via `tool_handler`, default returns
    "ok") and the results threaded back into the conversation; a turn with no tool
    calls is the final answer. The real API needs valid threading, so when the
    transport supplies `raw` (the assistant content blocks) we append it plus
    proper tool_result blocks keyed by tool_use id; the mock omits `raw` and a
    placeholder pair is used (which it ignores).
    """
    handler = tool_handler or (lambda name, args: "ok")
    trajectory: Trajectory = []
    messages: list = [{"role": "user", "content": prompt}]
    for _ in range(max_steps):
        turn = transport(messages, tools)
        calls = turn.get("tool_calls") or []
        for call in calls:
            trajectory.append({"type": "tool_call", "name": call["name"], "args": call.get("args", {})})
        if not calls:
            if turn.get("text") is not None:
                trajectory.append({"type": "text", "text": turn["text"]})
            break
        outcomes = [(c, handler(c["name"], c.get("args", {}))) for c in calls]
        raw = turn.get("raw")
        if raw is not None:
            messages.append({"role": "assistant", "content": raw})
            messages.append({"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": c.get("id", ""), "content": str(out)}
                for c, out in outcomes
            ]})
        else:
            messages.append({"role": "assistant", "content": "(tool calls)"})
            messages.append({"role": "user", "content": "(tool results)"})
    return trajectory


def final_text(trajectory: Trajectory) -> str:
    for step in reversed(trajectory):
        if step["type"] == "text":
            return step["text"]
    return ""


def make_transport(model: str, client) -> Transport:
    """A single-turn transport bound to an Anthropic client (the real backend).

    NOTE: the live message/tool threading here is exercised only against the real
    API — it is not covered by the hermetic suite, so validate one live run before
    trusting real numbers.
    """
    def transport(messages: list, tools: list) -> dict:
        resp = client.messages.create(model=model, max_tokens=1024, messages=messages, tools=tools)
        tool_calls, text = [], None
        for block in resp.content:
            if block.type == "tool_use":
                tool_calls.append({"name": block.name, "args": block.input, "id": block.id})
            elif block.type == "text":
                text = block.text
        return {"tool_calls": tool_calls, "text": text, "raw": resp.content}

    return transport


def anthropic_client():
    """Build a real client. Credential-gated; lazy import (not a test dependency)."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise RuntimeError(
            "ANTHROPIC_API_KEY not set — real runs need credentials (use --mock for offline)."
        )
    from anthropic import Anthropic
    return Anthropic(api_key=api_key)


def anthropic_token_counter(model: str, client) -> Callable[[str], int]:
    """Per-model token count via the API — real occupancy instead of the char/4 proxy."""
    def count(text: str) -> int:
        resp = client.messages.count_tokens(model=model, messages=[{"role": "user", "content": text}])
        return resp.input_tokens
    return count


def default_transport(model: str) -> Transport:
    return make_transport(model, anthropic_client())
