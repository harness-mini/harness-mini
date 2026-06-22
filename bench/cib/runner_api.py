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


def run(prompt: str, tools: list, transport: Transport, *, max_steps: int = 8) -> Trajectory:
    """Run one agent task to completion (or until max_steps) and return its trajectory."""
    trajectory: Trajectory = []
    messages: list = [{"role": "user", "content": prompt}]
    for _ in range(max_steps):
        turn = transport(messages, tools)
        for call in turn.get("tool_calls") or []:
            trajectory.append({"type": "tool_call", "name": call["name"], "args": call.get("args", {})})
            messages.append({"role": "assistant", "content": f"[tool_call {call['name']}]"})
            messages.append({"role": "user", "content": "[tool_result ok]"})
        if turn.get("text") is not None:
            trajectory.append({"type": "text", "text": turn["text"]})
            break
    return trajectory


def final_text(trajectory: Trajectory) -> str:
    for step in reversed(trajectory):
        if step["type"] == "text":
            return step["text"]
    return ""


def default_transport(model: str) -> Transport:
    """Build the real Anthropic-backed transport. Credential-gated; lazy import."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise RuntimeError(
            "ANTHROPIC_API_KEY not set — real runs need credentials "
            "(use --mock for an offline demo)."
        )
    from anthropic import Anthropic  # lazy: not a test-time dependency

    client = Anthropic(api_key=api_key)

    def transport(messages: list, tools: list) -> dict:
        resp = client.messages.create(model=model, max_tokens=1024, messages=messages, tools=tools)
        tool_calls, text = [], None
        for block in resp.content:
            if block.type == "tool_use":
                tool_calls.append({"name": block.name, "args": block.input})
            elif block.type == "text":
                text = block.text
        return {"tool_calls": tool_calls, "text": text}

    return transport
