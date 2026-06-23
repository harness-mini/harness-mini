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


def run(prompt: str, tools: list, transport: Transport, *, max_steps: int = 8,
        tool_handler=None, meta: dict | None = None) -> Trajectory:
    """Run one agent task to completion (or until max_steps); return its trajectory.

    Tool-use turns are executed (via `tool_handler`, default returns "ok") and
    threaded back in OpenAI/OpenRouter format (the assistant message + `role:"tool"`
    results); a turn with no tool calls is the final answer. If `meta` (a dict) is
    passed, the first turn's `usage.prompt_tokens` is recorded into it — the exact
    measured occupancy for a live run. The mock omits `raw`/`usage` and a placeholder
    message pair is used (which it ignores).
    """
    handler = tool_handler or (lambda name, args: "ok")
    trajectory: Trajectory = []
    messages: list = [{"role": "user", "content": prompt}]
    for _ in range(max_steps):
        turn = transport(messages, tools)
        if meta is not None and not meta.get("prompt_tokens"):
            tokens = (turn.get("usage") or {}).get("prompt_tokens")
            if tokens:
                meta["prompt_tokens"] = tokens
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
            messages.append(raw)
            for c, out in outcomes:
                messages.append({"role": "tool", "tool_call_id": c.get("id", ""), "content": str(out)})
        else:
            messages.append({"role": "assistant", "content": "(tool calls)"})
            messages.append({"role": "user", "content": "(tool results)"})
    return trajectory


def final_text(trajectory: Trajectory) -> str:
    for step in reversed(trajectory):
        if step["type"] == "text":
            return step["text"]
    return ""


# The live backend is OpenRouter (OpenAI-compatible) — see openrouter.make_transport.
# It is reached over stdlib urllib (no SDK), and run() above threads tool results in
# OpenAI format, so no Anthropic-specific client lives here.
