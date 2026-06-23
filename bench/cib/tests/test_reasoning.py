"""CIB #7 — D2 multi-hop reasoning probe + lenient scorer (TDD, first)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import reasoning  # noqa: E402
import score      # noqa: E402


class TestMakeD2(unittest.TestCase):
    def test_each_vault_has_a_record_and_a_reference_to_its_code(self):
        p = reasoning.make_d2(k=5, n_distractors=5, seed=1)
        self.assertEqual(len(p.expected), 5)
        joined = "\n".join(p.facts)
        for vault, code in p.expected.items():
            self.assertIn(f"RECORD vault {vault}", joined)
            self.assertIn(code, joined)
        self.assertEqual(joined.count("REFERENCE"), 10)   # 5 real + 5 distractors
        self.assertIn("JSON", p.suffix)

    def test_codes_and_refs_are_unique(self):
        p = reasoning.make_d2(k=5, n_distractors=5, seed=3)
        self.assertEqual(len(set(p.expected.values())), 5)

    def test_seed_is_deterministic(self):
        self.assertEqual(reasoning.make_d2(seed=2).expected, reasoning.make_d2(seed=2).expected)


class TestScoreD2(unittest.TestCase):
    def test_perfect_json(self):
        exp = {"V1": "11111", "V2": "22222"}
        self.assertEqual(score.score_d2('{"V1": "11111", "V2": "22222"}', exp), 100)

    def test_partial_graded(self):
        exp = {"V1": "11111", "V2": "22222", "V3": "33333", "V4": "44444", "V5": "55555"}
        ans = '{"V1": "11111", "V2": "22222", "V3": "33333", "V4": "99999", "V5": "00000"}'
        self.assertEqual(score.score_d2(ans, exp), 60)

    def test_lenient_non_json(self):
        exp = {"V1": "11111", "V2": "22222"}
        self.assertEqual(score.score_d2("V1 = 11111, and V2 = 22222", exp), 100)

    def test_zero_when_wrong(self):
        self.assertEqual(score.score_d2("no idea", {"V1": "11111"}), 0)


if __name__ == "__main__":
    unittest.main()
