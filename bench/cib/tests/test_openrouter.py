"""CIB issue #13 — OpenRouter transport (TDD, hermetic via an injected HTTP fn)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import openrouter  # noqa: E402
import probe       # noqa: E402


def _fake_http(response):
    def poster(url, payload, headers):
        poster.calls.append((url, payload, headers))
        return response
    poster.calls = []
    return poster


class TestParse(unittest.TestCase):
    def test_parses_tool_call_and_usage(self):
        data = {"choices": [{"message": {"role": "assistant", "content": None, "tool_calls": [
            {"id": "c1", "type": "function",
             "function": {"name": "verify_token", "arguments": '{"token": "9527"}'}}]}}],
            "usage": {"prompt_tokens": 1234}}
        turn = openrouter.parse_response(data)
        self.assertEqual(turn["tool_calls"], [{"name": "verify_token", "args": {"token": "9527"}, "id": "c1"}])
        self.assertEqual(turn["usage"]["prompt_tokens"], 1234)

    def test_parses_final_text(self):
        data = {"choices": [{"message": {"role": "assistant", "content": '{"sessions": 5}'}}],
                "usage": {"prompt_tokens": 10}}
        turn = openrouter.parse_response(data)
        self.assertEqual(turn["tool_calls"], [])
        self.assertEqual(turn["text"], '{"sessions": 5}')


class TestTransport(unittest.TestCase):
    def test_posts_with_auth_and_converts_tool_schema(self):
        resp = {"choices": [{"message": {"role": "assistant", "content": '{"sessions": 5}'}}],
                "usage": {"prompt_tokens": 42}}
        http = _fake_http(resp)
        transport = openrouter.make_transport("openai/gpt-4o-mini", "sk-test", http=http)
        turn = transport([{"role": "user", "content": "hi"}], [probe.VERIFY_TOKEN_TOOL])
        self.assertEqual(turn["text"], '{"sessions": 5}')
        _, payload, headers = http.calls[0]
        self.assertEqual(payload["model"], "openai/gpt-4o-mini")
        self.assertEqual(payload["tools"][0]["type"], "function")
        self.assertEqual(payload["tools"][0]["function"]["name"], "verify_token")
        self.assertEqual(headers["Authorization"], "Bearer sk-test")


class TestRetry(unittest.TestCase):
    def test_retries_on_429_then_succeeds(self):
        import urllib.error
        resp = {"choices": [{"message": {"role": "assistant", "content": "ok"}}],
                "usage": {"prompt_tokens": 1}}
        state = {"n": 0}

        def http(url, payload, headers):
            state["n"] += 1
            if state["n"] == 1:
                raise urllib.error.HTTPError(url, 429, "rate limited", None, None)
            return resp

        slept = []
        transport = openrouter.make_transport("m", "k", http=http, sleep=slept.append)
        turn = transport([{"role": "user", "content": "hi"}], [])
        self.assertEqual(turn["text"], "ok")
        self.assertEqual(state["n"], 2)      # one retry
        self.assertEqual(len(slept), 1)      # backed off once

    def test_retries_on_connection_error_then_succeeds(self):
        import urllib.error
        resp = {"choices": [{"message": {"role": "assistant", "content": "ok"}}], "usage": {}}
        state = {"n": 0}

        def http(url, payload, headers):
            state["n"] += 1
            if state["n"] == 1:
                raise urllib.error.URLError("SSL: UNEXPECTED_EOF_WHILE_READING")
            return resp

        slept = []
        transport = openrouter.make_transport("m", "k", http=http, sleep=slept.append)
        turn = transport([{"role": "user", "content": "hi"}], [])
        self.assertEqual(turn["text"], "ok")
        self.assertEqual(state["n"], 2)
        self.assertEqual(len(slept), 1)

    def test_non_retryable_error_raises(self):
        import urllib.error

        def http(url, payload, headers):
            raise urllib.error.HTTPError(url, 400, "bad request", None, None)

        transport = openrouter.make_transport("m", "k", http=http, sleep=lambda s: None)
        with self.assertRaises(urllib.error.HTTPError):
            transport([{"role": "user", "content": "hi"}], [])


if __name__ == "__main__":
    unittest.main()
