"""CIB issue #1 — prompt construction + occupancy measurement (TDD, written first).

Hermetic: no network, no third-party deps. Occupancy is measured with a declared
proxy tokenizer (char/4, matching bin/ctx.sh); the proxy name must travel in the
metadata so results are honest about how tokens were counted.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import build  # noqa: E402

WINDOW = 200_000
NEEDLE = "test_token: 9527"
BUCKETS = (0.10, 0.40, 0.70)


def _corpus() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(os.path.dirname(here), "fixtures", "filler_sample.txt")
    with open(path, encoding="utf-8") as fh:
        return fh.read()


class TestBuildPrompt(unittest.TestCase):
    def test_hits_target_occupancy_within_tolerance(self):
        corpus = _corpus()
        for target in BUCKETS:
            bp = build.build_prompt(target, WINDOW, corpus, NEEDLE)
            self.assertLessEqual(
                abs(bp.occupancy_pct - target), 0.02,
                f"bucket {target}: got occupancy {bp.occupancy_pct}",
            )

    def test_metadata_matches_remeasure(self):
        bp = build.build_prompt(0.40, WINDOW, _corpus(), NEEDLE)
        self.assertEqual(bp.token_count, build.count_tokens(bp.text, bp.tokenizer))
        self.assertEqual(bp.window, WINDOW)
        self.assertAlmostEqual(bp.occupancy_pct, bp.token_count / WINDOW, places=6)

    def test_declared_proxy_tokenizer_recorded(self):
        bp = build.build_prompt(0.40, WINDOW, _corpus(), NEEDLE)
        self.assertEqual(bp.tokenizer, build.DEFAULT_TOKENIZER)
        self.assertIn(bp.tokenizer, build.TOKENIZERS)

    def test_needle_planted_at_recorded_position(self):
        bp = build.build_prompt(0.40, WINDOW, _corpus(), NEEDLE)
        self.assertIn(NEEDLE, bp.text)
        window_after_pos = bp.text[bp.needle_pos: bp.needle_pos + len(NEEDLE) + 32]
        self.assertIn(NEEDLE, window_after_pos)

    def test_filler_hash_is_sha256_hex(self):
        bp = build.build_prompt(0.40, WINDOW, _corpus(), NEEDLE)
        self.assertEqual(len(bp.filler_hash), 64)
        int(bp.filler_hash, 16)  # raises if not hex

    def test_higher_bucket_has_more_tokens(self):
        corpus = _corpus()
        low = build.build_prompt(0.10, WINDOW, corpus, NEEDLE)
        high = build.build_prompt(0.70, WINDOW, corpus, NEEDLE)
        self.assertGreater(high.token_count, low.token_count)


def _lumpy(text):
    """A non-4-chars/token counter, standing in for a real model tokenizer."""
    return max(1, round(len(text) / 3.6))


class TestInjectedTokenizer(unittest.TestCase):
    def test_trim_loop_hits_target_with_injected_counter(self):
        bp = build.build_prompt(0.40, WINDOW, _corpus(), NEEDLE,
                                tokenizer="anthropic:test", token_counter=_lumpy)
        self.assertEqual(bp.tokenizer, "anthropic:test")  # label recorded
        self.assertLessEqual(abs(bp.occupancy_pct - 0.40), 0.02)
        self.assertEqual(bp.token_count, _lumpy(bp.text))  # measured by the injected counter


if __name__ == "__main__":
    unittest.main()
