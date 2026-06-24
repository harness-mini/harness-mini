"""CIB issue #2 — probe battery (D1 needle / D3 pure-JSON) + scorers (TDD, first).

Hermetic: no network, no deps. The probe suffix must be byte-identical across
buckets (it's what makes Arm A a clean controlled experiment), and the scorers
are pure machine checks.
"""
import hashlib
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import probe   # noqa: E402
import score   # noqa: E402


class TestProbeSuffix(unittest.TestCase):
    def test_suffix_is_byte_identical_across_calls(self):
        self.assertEqual(probe.probe_suffix(), probe.probe_suffix())
        self.assertEqual(probe.probe_suffix(), probe.PROBE_SUFFIX)

    def test_suffix_digest_is_stable(self):
        digest = hashlib.sha256(probe.probe_suffix().encode("utf-8")).hexdigest()
        self.assertEqual(digest, hashlib.sha256(probe.PROBE_SUFFIX.encode("utf-8")).hexdigest())

    def test_suffix_mentions_both_dimensions(self):
        s = probe.probe_suffix()
        self.assertIn("verify_token", s)        # D1
        self.assertIn("JSON", s)                # D3


class TestScoreD1(unittest.TestCase):
    def _call(self, name, args):
        return [{"type": "tool_call", "name": name, "args": args}]

    def test_correct_call_scores_100(self):
        traj = self._call("verify_token", {"token": "9527"})
        self.assertEqual(score.score_d1(traj, "9527"), 100)

    def test_missing_call_scores_0(self):
        traj = [{"type": "text", "text": "I'll start the main task."}]
        self.assertEqual(score.score_d1(traj, "9527"), 0)

    def test_wrong_token_scores_0(self):
        traj = self._call("verify_token", {"token": "0000"})
        self.assertEqual(score.score_d1(traj, "9527"), 0)

    def test_phantom_param_scores_0(self):
        traj = self._call("verify_token", {})
        self.assertEqual(score.score_d1(traj, "9527"), 0)

    def test_wrong_tool_name_scores_0(self):
        traj = self._call("check_token", {"token": "9527"})
        self.assertEqual(score.score_d1(traj, "9527"), 0)


class TestScoreD3(unittest.TestCase):
    def test_pure_json_scores_100(self):
        self.assertEqual(score.score_d3('{"answer": 42}'), 100)

    def test_preamble_scores_50(self):
        self.assertEqual(score.score_d3('Here is the JSON: {"answer": 42}'), 50)

    def test_fenced_json_scores_50(self):
        self.assertEqual(score.score_d3('```json\n{"answer": 42}\n```'), 50)

    def test_invalid_scores_0(self):
        self.assertEqual(score.score_d3("there is no json here"), 0)


if __name__ == "__main__":
    unittest.main()
