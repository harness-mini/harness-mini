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

    def test_ci_level_is_recorded(self):
        self.assertEqual(analyze.analyze(_cliff_points()).ci_level, 0.95)


class TestAggregate(unittest.TestCase):
    def test_per_bucket_mean_and_ci(self):
        points = [(0.1, 80), (0.1, 100), (0.1, 90), (0.7, 0), (0.7, 20), (0.7, 10)]
        stats = analyze.aggregate(points, ci=0.95)
        self.assertEqual([s.occupancy_pct for s in stats], [0.1, 0.7])
        b0 = stats[0]
        self.assertAlmostEqual(b0.mean, 90.0)
        self.assertEqual(b0.n, 3)
        self.assertLess(b0.lo, b0.mean)
        self.assertGreater(b0.hi, b0.mean)

    def test_ci_clamped_to_valid_score_range(self):
        stats = analyze.aggregate([(0.1, 100), (0.1, 100)], ci=0.95)
        self.assertLessEqual(stats[0].hi, 100.0)


if __name__ == "__main__":
    unittest.main()
