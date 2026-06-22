"""CIB issue #5 — self-contained report rendering (TDD, first).

The headline requirement is *self-contained*: a developer saves the HTML and
pastes it into a blog with no network. So the test forbids any external resource
and asserts the data + detected cliff are embedded inline.
"""
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import analyze  # noqa: E402
import report   # noqa: E402

MODEL = "claude-opus-4-8"
WINDOW = 200_000


def _cliff_results(seed=0):
    rng = random.Random(seed)
    rows = []
    for i in range(5, 96, 3):
        occ = i / 100
        sc = 100.0 if occ < 0.45 else 0.0
        rows.append({"occupancy_pct": occ, "score": max(0.0, min(100.0, sc + rng.gauss(0, 2)))})
    return rows


class TestReport(unittest.TestCase):
    def setUp(self):
        self.rows = _cliff_results()
        self.cp = analyze.analyze([(r["occupancy_pct"], r["score"]) for r in self.rows])
        self.html = report.render(self.rows, self.cp, model=MODEL, window=WINDOW)

    def test_is_self_contained(self):
        low = self.html.lower()
        self.assertNotIn('src="http', low)
        self.assertNotIn("cdn", low)

    def test_has_inline_svg_chart(self):
        self.assertIn("<svg", self.html)

    def test_embeds_data_inline(self):
        self.assertIn("cib-data", self.html)
        self.assertIn("occupancy_pct", self.html)

    def test_shows_model_and_detected_cutoff(self):
        self.assertIn(MODEL, self.html)
        self.assertTrue(self.cp.cliff_vs_linear_support)
        self.assertIn(f"{self.cp.location * 100:.1f}", self.html)

    def test_renders_per_bucket_error_bars(self):
        self.assertIn('class="errbar"', self.html)

    def test_ci_label_matches_computed_level(self):
        self.assertIn(f"{self.cp.ci_level * 100:.0f}% CI", self.html)

    def test_write_report_creates_file(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "cib_report.html")
            report.write_report(self.rows, self.cp, path, model=MODEL, window=WINDOW)
            self.assertTrue(os.path.exists(path))
            with open(path, encoding="utf-8") as fh:
                self.assertIn("<svg", fh.read())


if __name__ == "__main__":
    unittest.main()
