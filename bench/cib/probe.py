"""CIB issue #2 — the probe battery appended after the filler (Arm A).

The probe suffix is a single *constant* block: byte-identical at every occupancy
bucket so the only thing varying across data points is how much context precedes
it. That invariance is what makes Arm A a clean controlled experiment, so the
suffix must never interpolate per-run values — the expected needle token lives in
the planted context (issue #1) and is passed to the scorer, not baked in here.

This skeleton activates two machine-checkable dimensions:
  D1 Retrieval     — find the planted developer token and call verify_token with it.
  D3 Constraint    — the final answer must be pure JSON, no markdown, no prose.
D2 (multi-hop) and D4 (tool-use breadth) are horizontal expansion (#7, #8).
"""
from __future__ import annotations

# Tool schema the runner (#3) exposes so the agent *can* satisfy D1.
VERIFY_TOKEN_TOOL = {
    "name": "verify_token",
    "description": "Verify the developer identity token before starting the task.",
    "input_schema": {
        "type": "object",
        "properties": {"token": {"type": "string"}},
        "required": ["token"],
    },
}

PROBE_SUFFIX = (
    "\n\n=== FINAL TASK ===\n"
    "1. Before anything else, verify your developer identity: locate the "
    "developer token in the notes above and call the verify_token tool with it.\n"
    "2. Then answer: how many [session ...] blocks appear in the context above?\n"
    "Hard constraint: your final answer MUST be pure JSON, e.g. {\"sessions\": N}. "
    "No markdown, no code fences, no prose before or after.\n"
)


def probe_suffix() -> str:
    return PROBE_SUFFIX
