"""CIB #14 — real QA-F1 + HotpotQA parsing (TDD, first). Hermetic: inline fixture."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import qa  # noqa: E402

ROW = {
    "question": "Were Scott Derrickson and Ed Wood of the same nationality?",
    "answer": "yes",
    "supporting_facts": {"title": ["Scott Derrickson", "Ed Wood"], "sent_id": [0, 0]},
    "context": {
        "title": ["Ed Wood (film)", "Scott Derrickson", "Ed Wood"],
        "sentences": [
            ["Ed Wood is a 1994 American film directed by Tim Burton.", " It is a comedy."],
            ["Scott Derrickson is an American director.", " He was born in 1966."],
            ["Edward Davis Wood Jr. was an American filmmaker.", " He made B-movies."],
        ],
    },
}


class TestF1(unittest.TestCase):
    def test_exact_match_is_1(self):
        self.assertEqual(qa.token_f1("yes", "yes"), 1.0)

    def test_normalization_ignores_articles_punct_case(self):
        self.assertEqual(qa.token_f1("The Eiffel Tower.", "eiffel tower"), 1.0)

    def test_partial_overlap_is_graded(self):
        # pred "american director" vs gold "american filmmaker": 1 of 2 overlap
        self.assertAlmostEqual(qa.token_f1("american director", "american filmmaker"), 0.5)

    def test_no_overlap_is_0(self):
        self.assertEqual(qa.token_f1("paris", "london"), 0.0)

    def test_verbosity_lowers_f1_standard_squad_behavior(self):
        # Standard SQuAD-F1 (the paper's metric) scores raw token overlap, so a
        # verbose answer is penalized. We keep this rather than custom-extracting,
        # to replicate the paper faithfully; the prompt asks for answer-only and
        # verbosity is ~constant across occupancy buckets, so it adds no spurious cliff.
        self.assertAlmostEqual(qa.token_f1("The answer is yes.", "yes"), 0.5)


class TestHotpotParse(unittest.TestCase):
    def test_splits_gold_and_distractor_paragraphs(self):
        item = qa.parse_hotpot(ROW)
        self.assertEqual(item.answer, "yes")
        gold_titles = {p[0] for p in item.gold}
        self.assertEqual(gold_titles, {"Scott Derrickson", "Ed Wood"})
        dist_titles = {p[0] for p in item.distractors}
        self.assertEqual(dist_titles, {"Ed Wood (film)"})

    def test_paragraph_is_title_plus_joined_text(self):
        item = qa.parse_hotpot(ROW)
        gold = dict(item.gold)
        self.assertIn("American director", gold["Scott Derrickson"])


class TestBuildQAPrompt(unittest.TestCase):
    def setUp(self):
        self.item = qa.parse_hotpot(ROW)
        self.counter = lambda t: max(1, len(t) // 4)
        self.pool = [("Big Ben", "Big Ben: a clock tower in London."),
                     ("Louvre", "Louvre: a museum in Paris.")]

    def test_gold_always_present_and_question_appended(self):
        for mode in ("filler", "distractor"):
            text, _ = qa.build_qa_prompt(self.item, 0.3, 4000, mode, self.pool, "lorem ipsum ", self.counter)
            self.assertIn("American director", text)         # gold content
            self.assertIn(self.item.question, text)          # the question

    def test_distractor_mode_uses_pool_filler_mode_does_not(self):
        d, _ = qa.build_qa_prompt(self.item, 0.5, 4000, "distractor", self.pool, "lorem ipsum ", self.counter)
        f, _ = qa.build_qa_prompt(self.item, 0.5, 4000, "filler", self.pool, "lorem ipsum ", self.counter)
        self.assertIn("clock tower in London", d)            # distractor present
        self.assertNotIn("clock tower in London", f)         # filler arm has no distractors
        self.assertIn("lorem ipsum", f)

    def test_higher_target_yields_more_tokens(self):
        _, lo = qa.build_qa_prompt(self.item, 0.2, 8000, "filler", self.pool, "lorem ", self.counter)
        _, hi = qa.build_qa_prompt(self.item, 0.6, 8000, "filler", self.pool, "lorem ", self.counter)
        self.assertGreater(hi, lo)


if __name__ == "__main__":
    unittest.main()
