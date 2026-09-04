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
    """What the gate flags, rather than what its list happens to contain.

    The two tests that used to stand here asserted the contents of FORBIDDEN -
    that it held `<name>_GAS`, `<name> GAS`, and so on for every separator. A
    vocabulary test can only be checked for the entries somebody thought to
    check for, which is exactly how this one stayed green over
    `ARHALIES_GUT_RESULT`: the verdict line the headless test runner printed on
    every single run since the rename, in a casing the list did not carry and
    with a suffix that is not `GAS` at all.
    """

    def _flagged(self, name: str, line: str) -> list[str]:
        """What the gate says about one line of one file, off in a temp tree."""
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / name).write_text(line + "\n", encoding="utf-8")
            return product_identity.text_problems(root, [name])

    def test_the_spellings_that_got_through_are_caught_now(self) -> None:
        for line in (
            'const RESULT_PREFIX: String = "ARHALIES' + '_GUT_RESULT:"',
            'spec_from_file_location("arhalies' + '_test_location_gate", GATE_PATH)',
            "ARHALIES" + "_GAS",
            "arhalies" + " gas",
            "Arhalies" + "GAS",
            "res://addons/" + "Godot" + "GAS" + "/plugin.cfg",
            "res://" + "godot" + "_gas" + "/thing.gd",
        ):
            with self.subTest(line=line):
                self.assertTrue(self._flagged("probe.gd", line), line)

    def test_a_log_is_a_file_this_gate_reads(self) -> None:
        # Half the release receipt set is log files, and the freeze points this
        # gate at that set. A suffix missing from the list is not a lenient
        # check, it is no check: the file is never opened, and reads as clean.
        self.assertTrue(self._flagged("probe.log", "Arhalies" + "GAS"))

    def test_every_token_is_lowercase_because_the_line_is_lowered_first(self) -> None:
        # The contract between the list and the matcher. A token carrying a
        # capital could never match anything, because the line is lowered before
        # the comparison - it would be looking for a shape that no longer exists
        # by the time it is asked. Not a hypothetical: the previous list was
        # spelled in title case, and that is how it missed a shouted one.
        for token in product_identity.FORBIDDEN:
            with self.subTest(token=token):
                self.assertEqual(token, token.lower())

    def test_the_origin_acknowledgment_stays_readable(self) -> None:
        # THIRD_PARTY.md has to be able to say where this came from. The
        # upstream repository is named with a hyphen and that spelling is not
        # forbidden, deliberately: recording a true origin is not the same as
        # claiming an identity.
        self.assertEqual(
            self._flagged(
                "THIRD_PARTY.md", "began as a fork of `github.com/yulrun/godot-gas`"
            ),
            [],
        )

    def test_the_legacy_wire_name_stays_allowed_where_it_is_declared(self) -> None:
        # A protocol name a designer types into a Dialogic timeline. Renaming it
        # would break their timelines, so it is declared once as a LEGACY_
        # constant and allowed exactly there.
        self.assertTrue(
            product_identity.occurrence_allowed(
                product_identity.COMMAND_PARSER,
                1,
                'const LEGACY_BRIDGE_NAME: String = "' + "Arhalies" + 'GAS"',
            )
        )

    def test_positive_authorities_are_canonical_in_real_checkout(self) -> None:
        root = Path(__file__).resolve().parents[3]
        self.assertEqual(product_identity.authority_problems(root), [])


if __name__ == "__main__":
    unittest.main()
