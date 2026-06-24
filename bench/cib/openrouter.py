"""CIB issue #13 — OpenRouter transport (OpenAI-compatible, stdlib-only).

Every model is reached through OpenRouter's OpenAI-compatible chat/completions
endpoint over plain urllib — no SDK, so the island stays stdlib-only even for live
runs. OpenRouter has no token-count endpoint, so occupancy is read from each
response's `usage.prompt_tokens` (the exact per-model count): we build toward the
target bucket with the char/4 proxy, then bin each trial by its measured count.
"""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request

BASE_URL = "https://openrouter.ai/api/v1/chat/completions"
_RETRY_CODES = {429, 500, 502, 503, 529}


def _with_retry(call, *, max_retries: int, sleep, base: float = 2.0, cap: float = 30.0):
    """Retry a call on transient HTTP errors (429/5xx) with exponential backoff.

    Honors a numeric Retry-After header when present. Cheap providers rate-limit
    hard, so this is required for any real sweep, not a nicety.
    """
    for attempt in range(max_retries + 1):
        try:
            return call()
        except urllib.error.HTTPError as exc:
            if exc.code not in _RETRY_CODES or attempt == max_retries:
                raise
            retry_after = exc.headers.get("Retry-After") if exc.headers else None
            delay = float(retry_after) if (retry_after and str(retry_after).isdigit()) else base ** attempt
            sleep(min(delay, cap))
        except (urllib.error.URLError, TimeoutError) as exc:
            # transient connection/SSL/timeout drop (not an HTTP status) — retry too.
            # HTTPError subclasses URLError, so it is handled above and won't reach here.
            if attempt == max_retries:
                raise
            sleep(min(base ** attempt, cap))
    raise RuntimeError("unreachable")  # pragma: no cover


def to_openai_tool(tool: dict) -> dict:
    """Convert the probe's Anthropic-style tool schema to OpenAI function format."""
    return {
        "type": "function",
        "function": {
            "name": tool["name"],
            "description": tool.get("description", ""),
            "parameters": tool.get("input_schema", {"type": "object", "properties": {}}),
        },
    }


def parse_response(data: dict) -> dict:
    """Normalize an OpenAI/OpenRouter response into our turn shape."""
    message = (data.get("choices") or [{}])[0].get("message", {}) or {}
    tool_calls = []
    for call in message.get("tool_calls") or []:
        fn = call.get("function", {})
        try:
            args = json.loads(fn.get("arguments") or "{}")
        except (ValueError, TypeError):
            args = {}
        tool_calls.append({"name": fn.get("name"), "args": args, "id": call.get("id", "")})
    return {
        "tool_calls": tool_calls,
        "text": message.get("content"),
        "raw": message,
        "usage": data.get("usage") or {},
    }


def _http_post(url: str, payload: dict, headers: dict) -> dict:
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        return json.loads(resp.read().decode("utf-8"))


def make_transport(model: str, api_key: str, *, http=None, max_tokens: int = 512,
                   max_retries: int = 6, sleep=time.sleep):
    """A single-turn transport bound to OpenRouter. `http`/`sleep` injectable for tests."""
    poster = http or _http_post
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/harness-mini/harness-mini",
        "X-Title": "harness-mini CIB",
    }

    def transport(messages: list, tools: list) -> dict:
        payload = {"model": model, "messages": messages, "max_tokens": max_tokens}
        if tools:
            payload["tools"] = [to_openai_tool(t) for t in tools]
        data = _with_retry(lambda: poster(BASE_URL, payload, headers),
                           max_retries=max_retries, sleep=sleep)
        return parse_response(data)

    return transport
