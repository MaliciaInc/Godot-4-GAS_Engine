#!/usr/bin/env python3
"""Behaviour of the GDScript lexer used by the magic-string and duplication gates."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import gdscript_lexing  # noqa: E402


class MaskSourcePreservesGeometry(unittest.TestCase):
    def test_masked_text_keeps_length(self) -> None:
        source = 'var greeting: String = "hello"\n'
        self.assertEqual(len(gdscript_lexing.mask_source(source)), len(source))

    def test_masked_text_keeps_newline_positions(self) -> None:
        source = 'var a = "one"\nvar b = "two"\nvar c = 3\n'
        masked = gdscript_lexing.mask_source(source)
        original_newlines = [index for index, char in enumerate(source) if char == "\n"]
        masked_newlines = [index for index, char in enumerate(masked) if char == "\n"]
        self.assertEqual(original_newlines, masked_newlines)

    def test_triple_quoted_block_keeps_its_newlines(self) -> None:
        source = 'var doc = """\nline one\nline two\n"""\nvar after = 1\n'
        masked = gdscript_lexing.mask_source(source)
        self.assertEqual(source.count("\n"), masked.count("\n"))
        self.assertIn("var after = 1", masked)

    def test_empty_source_is_returned_unchanged(self) -> None:
        self.assertEqual(gdscript_lexing.mask_source(""), "")


class MaskSourceRemovesLiterals(unittest.TestCase):
    def test_double_quoted_content_is_blanked(self) -> None:
        masked = gdscript_lexing.mask_source('var tag = "Event.Damage"\n')
        self.assertNotIn("Event.Damage", masked)
        self.assertIn("var tag =", masked)

    def test_single_quoted_content_is_blanked(self) -> None:
        masked = gdscript_lexing.mask_source("var tag = 'Event.Damage'\n")
        self.assertNotIn("Event.Damage", masked)

    def test_comment_content_is_blanked(self) -> None:
        masked = gdscript_lexing.mask_source("var x = 1  # func fake_function():\n")
        self.assertNotIn("fake_function", masked)
        self.assertIn("var x = 1", masked)

    def test_hash_inside_string_does_not_start_a_comment(self) -> None:
        masked = gdscript_lexing.mask_source('var color = "#ff00ff"\nvar after = 2\n')
        self.assertIn("var after = 2", masked)
        self.assertNotIn("ff00ff", masked)

    def test_escaped_quote_does_not_end_the_string(self) -> None:
        masked = gdscript_lexing.mask_source('var s = "a\\"b"\nvar after = 3\n')
        self.assertIn("var after = 3", masked)
        self.assertNotIn("a\\\"b", masked)

    def test_unterminated_single_quote_stops_at_the_newline(self) -> None:
        masked = gdscript_lexing.mask_source('var broken = "oops\nvar after = 4\n')
        self.assertIn("var after = 4", masked)


class StringLiteralExtraction(unittest.TestCase):
    def _values(self, source: str) -> list[str]:
        return [literal.value for literal in gdscript_lexing.iter_string_literals(source)]

    def test_plain_literal_is_reported(self) -> None:
        self.assertEqual(self._values('var t = "Event.Damage"\n'), ["Event.Damage"])

    def test_string_name_literal_is_reported_like_a_plain_string(self) -> None:
        literals = list(gdscript_lexing.iter_string_literals('var t: StringName = &"Event.Damage"\n'))
        self.assertEqual(len(literals), 1)
        self.assertEqual(literals[0].value, "Event.Damage")
        self.assertEqual(literals[0].prefix, "&")
        self.assertTrue(literals[0].is_string_name)

    def test_node_path_literal_is_reported(self) -> None:
        literals = list(gdscript_lexing.iter_string_literals('var p = ^"Player/Sprite"\n'))
        self.assertEqual(literals[0].value, "Player/Sprite")
        self.assertTrue(literals[0].is_node_path)

    def test_raw_literal_keeps_backslashes(self) -> None:
        literals = list(gdscript_lexing.iter_string_literals('var re = r"\\d+"\n'))
        self.assertEqual(literals[0].value, "\\d+")
        self.assertEqual(literals[0].prefix, "r")

    def test_literals_inside_comments_are_not_reported(self) -> None:
        self.assertEqual(self._values('# var t = "Event.Damage"\n'), [])

    def test_line_numbers_are_one_indexed_and_exact(self) -> None:
        source = 'var a = 1\nvar b = "second"\nvar c = 3\n'
        literals = list(gdscript_lexing.iter_string_literals(source))
        self.assertEqual(literals[0].line, 2)

    def test_column_is_zero_indexed_from_the_literal_start(self) -> None:
        literals = list(gdscript_lexing.iter_string_literals('var b = "x"\n'))
        self.assertEqual(literals[0].column, 8)

    def test_identifier_ending_in_r_is_not_a_raw_prefix(self) -> None:
        literals = list(gdscript_lexing.iter_string_literals('var counter = "value"\n'))
        self.assertEqual(literals[0].prefix, "")
        self.assertEqual(literals[0].value, "value")

    def test_multiple_literals_on_one_line_are_all_reported(self) -> None:
        self.assertEqual(self._values('call("a", "b")\n'), ["a", "b"])


class CommentOnlyStripping(unittest.TestCase):
    def test_strings_survive_but_comments_do_not(self) -> None:
        stripped = gdscript_lexing.strip_comments_only('var t = "keep"  # drop\n')
        self.assertIn("keep", stripped)
        self.assertNotIn("drop", stripped)

    def test_length_is_preserved(self) -> None:
        source = 'var t = "keep"  # drop\n'
        self.assertEqual(len(gdscript_lexing.strip_comments_only(source)), len(source))


if __name__ == "__main__":
    unittest.main()
