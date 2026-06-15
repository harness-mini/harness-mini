import unittest

from slugify import slugify


class SlugifyTest(unittest.TestCase):
    def test_lowercases_and_joins_words_with_hyphens(self):
        self.assertEqual(slugify("Hello, World!"), "hello-world")


if __name__ == "__main__":
    unittest.main()
