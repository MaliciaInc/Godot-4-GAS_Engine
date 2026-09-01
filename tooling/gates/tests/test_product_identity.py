from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[2] / "product_identity.py"
SPEC = importlib.util.spec_from_file_location("product_identity", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
product_identity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(product_identity)


class ProductIdentityTests(unittest.TestCase):
    def test_third_party_legacy_section_is_the_only_markdown_legacy_exception(self) -> None:
        text = "\n".join(
            [
                "# Third-party dependencies and notices",
                "current " + "Godot" + "GAS",
                product_identity.LEGACY_SECTION_START,
                "historical " + "Godot" + "GAS",
                product_identity.LEGACY_SECTION_END,
            ]
        )
        allowed = product_identity.third_party_legacy_lines(text)
        self.assertNotIn(2, allowed)
        self.assertIn(4, allowed)

    def test_forbidden_vocabulary_contains_every_legacy_identity_family(self) -> None:
        joined = "\n".join(product_identity.FORBIDDEN)
        self.assertIn("Arhalies" + "_GAS", joined)
        self.assertIn("Arhalies" + " GAS", joined)
        self.assertIn("Godot" + "GAS", joined)
        self.assertIn("godot" + "_gas", joined)

    def test_every_separator_including_none_is_forbidden(self) -> None:
        # The list enumerated underscore, space and hyphen and stopped there.
        # `Godot` + `GAS` was already listed with no separator at all, so the
        # spelling was on the list's mind for one family and simply missing for
        # the other - and one live instance was sitting behind the hole, in a
        # wire protocol string a designer types into a Dialogic timeline.
        for separator in ("_", " ", "-", ""):
            with self.subTest(separator=separator):
                self.assertIn(
                    "Arhalies" + separator + "GAS", product_identity.FORBIDDEN
                )

    def test_positive_authorities_are_canonical_in_real_checkout(self) -> None:
        root = Path(__file__).resolve().parents[3]
        self.assertEqual(product_identity.authority_problems(root), [])


if __name__ == "__main__":
    unittest.main()
