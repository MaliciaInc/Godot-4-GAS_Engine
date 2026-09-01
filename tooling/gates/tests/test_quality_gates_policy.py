#!/usr/bin/env python3
"""The policy file's own exceptions, checked against the tree they exempt.

Every allowance in `.quality-gates.json` names something: a pair of functions
the duplication gate may ignore, a file the length gate may let past, a
function whose parameter count is Godot's rather than this project's. Each is
argued for in a `reason`, and each stops being true the moment what it names
moves.

Nothing checked that. A pin whose function has been split into another file is
dead policy: the allowance no longer applies to anything, the argument written
beside it no longer describes the code, and the only way anyone finds out is
the gate turning red for a reason the message does not explain. That happened
here the first time a test suite outgrew the length gate and was split.

These tests read the real policy and the real checkout, the same way
`test_product_identity` asserts its positive authorities against the tree.
"""
from __future__ import annotations

import fnmatch
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
POLICY_PATH = ROOT / "tooling" / ".quality-gates.json"

#: Where a pin may point. GUT is vendored and pinned byte-identical, so nothing
#: in the policy is allowed to name a function inside it.
SOURCE_SUFFIXES = ("*.gd", "*.py", "*.ps1")
VENDORED = "addons/gut/"

#: The member a pin may name instead of a function: the whole file.
WHOLE_FILE = "<file>"


def policy() -> dict:
    return json.loads(POLICY_PATH.read_text(encoding="utf-8"))


def declarations() -> dict[str, set[str]]:
    """Every function and inner class each source file declares."""
    found: dict[str, set[str]] = {}
    for pattern in SOURCE_SUFFIXES:
        for path in ROOT.rglob(pattern):
            relative = path.relative_to(ROOT).as_posix()
            if relative.startswith(VENDORED):
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            names = set(re.findall(r"^\s*(?:static )?(?:func|def) (\w+)", text, re.M))
            names |= set(re.findall(r"^\s*class (\w+)", text, re.M))
            found[relative] = names
    return found


DECLARED = declarations()


def pin_resolves(spec: str) -> bool:
    """Whether `path:member` still names something that exists."""
    if ":" not in spec:
        return any(fnmatch.fnmatch(name, spec) for name in DECLARED)
    path, member = spec.split(":", 1)
    if member == WHOLE_FILE or "*" in member:
        return any(fnmatch.fnmatch(name, path) for name in DECLARED)
    # `ClassName.method` pins a method of an inner class; the class name is
    # context, the method is what has to exist.
    member = member.split(".")[-1]
    for name, declared in DECLARED.items():
        if fnmatch.fnmatch(name, path) and member in declared:
            return True
    return False


def glob_resolves(pattern: str) -> bool:
    return any(fnmatch.fnmatch(name, pattern) for name in DECLARED)


class PairAllowlistTests(unittest.TestCase):
    def test_every_pinned_pair_still_names_code_that_exists(self) -> None:
        for entry in policy()["duplication"]["pair_allowlist"]:
            for side in ("left", "right"):
                spec = entry[side]
                with self.subTest(side=side, spec=spec):
                    self.assertTrue(
                        pin_resolves(spec),
                        "%s names nothing in this checkout; the allowance is dead "
                        "policy and its reason no longer describes the code" % spec,
                    )

    def test_every_pinned_pair_argues_for_itself(self) -> None:
        for entry in policy()["duplication"]["pair_allowlist"]:
            with self.subTest(left=entry["left"]):
                self.assertTrue(
                    len(entry.get("reason", "").strip()) > 0,
                    "an exception with no reason is one nobody can re-examine",
                )


class LengthAllowlistTests(unittest.TestCase):
    def test_every_raised_file_still_exists(self) -> None:
        for entry in policy()["loc"]["file_length_allowlist"]:
            with self.subTest(glob=entry["glob"]):
                self.assertTrue(glob_resolves(entry["glob"]), entry["glob"])

    def test_every_raised_ceiling_is_still_needed(self) -> None:
        # A ceiling far above what the file actually is stopped being a
        # considered exception and became headroom nobody decided on.
        limit = policy()["loc"]["max_file_lines"]
        for entry in policy()["loc"]["file_length_allowlist"]:
            for name in DECLARED:
                if not fnmatch.fnmatch(name, entry["glob"]):
                    continue
                actual = len((ROOT / name).read_text(encoding="utf-8").splitlines())
                with self.subTest(file=name):
                    self.assertGreater(
                        actual, limit,
                        "%s is %d lines, under the %d the gate allows everyone: the "
                        "raise to %d is no longer an exception to anything"
                        % (name, actual, limit, entry["max_lines"]),
                    )


class ParameterAllowlistTests(unittest.TestCase):
    def test_every_exempted_function_still_exists(self) -> None:
        for entry in policy()["loc"]["function_parameter_allowlist"]:
            spec = entry["glob"] + ":" + entry["function"]
            with self.subTest(spec=spec):
                self.assertTrue(pin_resolves(spec), spec)


if __name__ == "__main__":
    unittest.main()
