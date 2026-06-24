"""CIB issue #3 — agent runner (Arm A) + single-trial wiring (TDD, first).

Hermetic: a ScriptedTransport stands in for the model, so the agentic loop, the
trajectory normalization, and the trial scoring are all tested offline. The real
AnthropicTransport is gated behind credentials and never touched here.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import runner_api  # noqa: E402
import run          # noqa: E402

WINDOW = 200_000
NEEDLE = "test_token: 9527"


def _smart():
    return runner_api.ScriptedTransport([
        {"tool_calls": [{"name": "verify_token", "args": {"token": "9527"}}], "text": None},
        {"tool_calls": [], "text": '{"sessions": 5}'},
    ])


def _dumb():
    return runner_api.ScriptedTransport([
        {"tool_calls": [], "text": "I'll just start. Probably five sessions."},
    ])


def _looping():
    return runner_api.ScriptedTransport([
        {"tool_calls": [{"name": "verify_token", "args": {}}], "text": None},
    ])


class TestRunnerLoop(unittest.TestCase):
    def test_captures_tool_call_and_final_text(self):
        traj = runner_api.run("prompt", [], _smart())
        names = [s["name"] for s in traj if s["type"] == "tool_call"]
        self.assertIn("verify_token", names)
        self.assertEqual(runner_api.final_text(traj), '{"sessions": 5}')

    def test_max_steps_guards_a_nonterminating_model(self):
        traj = runner_api.run("prompt", [], _looping(), max_steps=4)
        self.assertEqual(runner_api.final_text(traj), "")
        self.assertLessEqual(sum(s["type"] == "tool_call" for s in traj), 4)


class TestRealishThreading(unittest.TestCase):
    def test_tool_handler_invoked_and_usage_captured(self):
        seen = []
        transport = runner_api.ScriptedTransport([
            {"tool_calls": [{"name": "verify_token", "args": {"token": "9527"}, "id": "tu_1"}],
             "raw": {"role": "assistant", "content": None, "tool_calls": [
                 {"id": "tu_1", "type": "function",
                  "function": {"name": "verify_token", "arguments": '{"token": "9527"}'}}]},
             "text": None, "usage": {"prompt_tokens": 1234}},
            {"tool_calls": [], "text": "done"},
        ])
        meta = {"prompt_tokens": None}
        traj = runner_api.run("p", [], transport, tool_handler=lambda n, a: seen.append((n, a)) or "ok", meta=meta)
        self.assertEqual(seen, [("verify_token", {"token": "9527"})])
        self.assertEqual(runner_api.final_text(traj), "done")
        self.assertEqual(meta["prompt_tokens"], 1234)  # measured occupancy, first turn


class TestRunTrial(unittest.TestCase):
    def test_smart_trial_scores_perfect(self):
        r = run.run_trial(0.20, WINDOW, "filler corpus ", NEEDLE, _smart())
        self.assertEqual(r.scores["D1"], 100)
        self.assertEqual(r.scores["D3"], 100)
        self.assertEqual(r.score, 100)
        self.assertLessEqual(abs(r.occupancy_pct - 0.20), 0.02)

    def test_dumb_trial_scores_zero(self):
        r = run.run_trial(0.70, WINDOW, "filler corpus ", NEEDLE, _dumb())
        self.assertEqual(r.scores["D1"], 0)
        self.assertEqual(r.scores["D3"], 0)
        self.assertEqual(r.score, 0)

    def test_occupancy_from_measured_prompt_tokens(self):
        transport = runner_api.ScriptedTransport([
            {"tool_calls": [{"name": "verify_token", "args": {"token": "9527"}, "id": "c1"}],
             "raw": {"role": "assistant", "content": None, "tool_calls": [
                 {"id": "c1", "type": "function",
                  "function": {"name": "verify_token", "arguments": '{"token": "9527"}'}}]},
             "text": None, "usage": {"prompt_tokens": 50000}},
            {"tool_calls": [], "text": '{"sessions": 5}'},
        ])
        r = run.run_trial(0.20, WINDOW, "filler corpus ", NEEDLE, transport)
        self.assertEqual(r.token_count, 50000)              # from usage, not the build estimate
        self.assertAlmostEqual(r.occupancy_pct, 50000 / WINDOW)


if __name__ == "__main__":
    unittest.main()
