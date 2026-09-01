#!/usr/bin/env python3
"""Behaviour of `tooling/project_invariants.py`.

This checker had no tests of its own, and it is the only thing standing between
a Godot rewrite of `project.godot` and a commit that ships the rewritten file.
It checked one of the nine GDScript warning lines and reported the file sound
without the other eight, so the tests that matter here are the negative ones:
each required line removed on its own has to be named in the output.

Every test builds a throwaway project root and calls `problems()` against it,
so what is asserted is the checker's verdict, not an internal helper.
"""
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

TOOLING_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(TOOLING_DIR))

REPO_ROOT = TOOLING_DIR.parent


def load_checker() -> Any:
    spec = importlib.util.spec_from_file_location(
        "project_invariants_under_test", TOOLING_DIR / "project_invariants.py"
    )
    if spec is None or spec.loader is None:  # pragma: no cover - packaging accident
        raise RuntimeError("cannot load project_invariants.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


project_invariants = load_checker()


def sound_project_file() -> str:
    """A `project.godot` carrying the whole warning contract and nothing else."""
    return "\n".join(
        ["config_version=5", "", "[debug]", ""]
        + list(project_invariants.STRICT_WARNING_LINES)
        + [""]
    )


class WarningContractTests(unittest.TestCase):
    def test_a_file_carrying_every_required_line_is_sound(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            (root / project_invariants.PROJECT_FILE).write_text(
                sound_project_file(), encoding="utf-8"
            )
            self.assertEqual(project_invariants.problems(root), [])

    def test_every_required_line_is_missed_when_it_is_the_one_removed(self) -> None:
        # Removed one at a time rather than all at once: a check that only fires
        # on the exclusion would still pass a test that deleted the whole block.
        for required in project_invariants.STRICT_WARNING_LINES:
            with self.subTest(required=required):
                text = "\n".join(
                    line
                    for line in sound_project_file().splitlines()
                    if line != required
                )
                with tempfile.TemporaryDirectory() as raw:
                    root = Path(raw)
                    (root / project_invariants.PROJECT_FILE).write_text(
                        text, encoding="utf-8"
                    )
                    found = project_invariants.problems(root)
                self.assertTrue(
                    any(required in item for item in found),
                    "removing %r has to be reported, got %r" % (required, found),
                )

    def test_the_contract_covers_the_exclusion_and_the_eight_warnings(self) -> None:
        # The comment in project.godot promises "the eight settings below", and
        # the exclusion is a ninth line with a different job. A contract that
        # quietly shrank would still pass every test above.
        self.assertEqual(len(project_invariants.STRICT_WARNING_LINES), 9)
        self.assertIn(
            project_invariants.EXCLUDE_ADDONS_LINE,
            project_invariants.STRICT_WARNING_LINES,
        )

    def test_the_real_checkout_satisfies_its_own_contract(self) -> None:
        text = (REPO_ROOT / project_invariants.PROJECT_FILE).read_text(encoding="utf-8")
        for required in project_invariants.STRICT_WARNING_LINES:
            self.assertIn(required, text)


class MissingFileTests(unittest.TestCase):
    def test_an_absent_project_file_is_reported_rather_than_crashing(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            found = project_invariants.problems(Path(raw))
        self.assertEqual(len(found), 1)
        self.assertIn(project_invariants.PROJECT_FILE, found[0])


class AutoloadTests(unittest.TestCase):
    def test_an_autoload_pointing_at_a_missing_script_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            text = sound_project_file() + '\n[autoload]\nGone="*res://gone.gd"\n'
            (root / project_invariants.PROJECT_FILE).write_text(text, encoding="utf-8")
            found = project_invariants.problems(root)
        self.assertTrue(
            any("gone.gd" in item and "does not exist" in item for item in found),
            found,
        )


if __name__ == "__main__":
    unittest.main()
