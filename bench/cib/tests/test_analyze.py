"""CIB issue #4 — changepoint analysis (TDD, written first).

Honest changepoint detection: recover a cliff *where one exists* with a bootstrap
CI, and refuse to invent one where the decline is merely linear. Zero-dep and
seeded so the test is deterministic and hermetic.
"""
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import analyze  # noqa: E402


def _cliff_points(seed=0):
    rng = random.Random(seed)
    pts = []
    for i in range(5, 96, 2):           # occupancy 0.05 … 0.95
        x = i / 100
        base = 90.0 if x < 0.45 else 40.0
        pts.append((x, base + rng.gauss(0, 1)))
    return pts


def _linear_points(seed=1):
    rng = random.Random(seed)
    return [(i / 100, 90.0 - 50.0 * (i / 100) + rng.gauss(0, 1))
            for i in range(5, 96, 2)]


class TestAnalyze(unittest.TestCase):
    def test_detects_known_cliff(self):
        r = analyze.analyze(_cliff_points())
        self.assertTrue(r.cliff_vs_linear_support)
        self.assertIsNotNone(r.location)
        self.assertLessEqual(abs(r.location - 0.45), 0.05)

    def test_cliff_ci_brackets_truth(self):
        r = analyze.analyze(_cliff_points())
        self.assertIsNotNone(r.bootstrap_ci)
        lo, hi = r.bootstrap_ci
        self.assertLessEqual(lo, 0.45)
        self.assertGreaterEqual(hi, 0.45)

    def test_linear_decline_is_not_a_cliff(self):
        r = analyze.analyze(_linear_points())
        self.assertFalse(r.cliff_vs_linear_support)


if __name__ == "__main__":
    unittest.main()
