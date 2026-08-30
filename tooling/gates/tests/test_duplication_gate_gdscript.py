#!/usr/bin/env python3
"""GDScript behaviour of the duplication gate.

Every case writes real `.gd` files to a temporary directory and runs the gate
entry point against them, so what is measured is the gate a pipeline would
run, not a hand-built object graph. The mandatory matrix of Paso 0.5 is:

    two structurally identical GDScript funcs -> structural finding
    two renamed copies                        -> masked finding
    behaviorally similar, structurally distinct -> behavioral only
    comment/string copies                     -> ignored
    tests excluded by default                 -> upstream behaviour preserved
    canonical run with --include-tests        -> fork tests are scanned too
    scan error                                -> exit 2, never PASS
"""
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from typing import Any

GATE_PATH = Path(__file__).resolve().parents[1] / "duplication-gate.py"
sys.path.insert(0, str(GATE_PATH.parent))


def load_gate() -> Any:
    """Import the hyphenated entry point as a module.

    The module must be registered before it executes: `dataclasses` resolves
    string annotations through `sys.modules[cls.__module__]`, which is absent
    for a spec loaded straight from a path.
    """
    spec = importlib.util.spec_from_file_location("duplication_gate", GATE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


GATE = load_gate()

PASS = 0
BLOCKED = 1
SCAN_ERROR = 2

DAMAGE = """extends RefCounted


func apply_burn(stacks: int, potency: float) -> float:
\tvar accumulated: float = 0.0
\tvar ramp: float = potency
\tfor tick in range(stacks):
\t\taccumulated += ramp
\t\tramp = ramp * 1.5
\tif accumulated > 250.0:
\t\taccumulated = 250.0
\treturn accumulated
"""

#: Same shape as DAMAGE, every name changed. Vocabulary overlap collapses, so
#: the structural check declines the pair and the masked check must catch it.
DAMAGE_RENAMED = """extends RefCounted


func spread_chill(layers: int, bite: float) -> float:
\tvar gathered: float = 0.0
\tvar slope: float = bite
\tfor pulse in range(layers):
\t\tgathered += slope
\t\tslope = slope * 1.5
\tif gathered > 250.0:
\t\tgathered = 250.0
\treturn gathered
"""

#: Same control-flow profile as QUEUE below, different statement order.
WAVE = """extends Node


func resolve_wave(count: int) -> int:
\tvar total: int = 0
\tfor index in range(count):
\t\ttotal += index
\tif total > 50:
\t\ttotal = 50
\twhile total % 3 == 1:
\t\ttotal -= 1
\treturn total
"""

QUEUE = """extends Node


func trim_queue(limit: int) -> int:
\tvar pending: int = 0
\twhile pending < limit:
\t\tpending += 2
\tif pending > 50:
\t\tpending = 50
\tfor slot in range(limit):
\t\tpending -= 1
\treturn pending
"""

#: A verbatim copy of `apply_burn`, but quoted. None of it is code.
QUOTED_COPY = '''extends RefCounted

# func apply_burn(stacks: int, potency: float) -> float:
# \tvar accumulated: float = 0.0
# \tvar ramp: float = potency
# \tfor tick in range(stacks):
# \t\taccumulated += ramp
# \t\tramp = ramp * 1.5
# \tif accumulated > 250.0:
# \t\taccumulated = 250.0
# \treturn accumulated

const SNIPPET: String = """
func apply_burn(stacks: int, potency: float) -> float:
\tvar accumulated: float = 0.0
\tvar ramp: float = potency
\tfor tick in range(stacks):
\t\taccumulated += ramp
\t\tramp = ramp * 1.5
\tif accumulated > 250.0:
\t\taccumulated = 250.0
\treturn accumulated
"""
'''

INNER_CLASS_TWINS = """class_name Container
extends RefCounted


class Alpha:
\tfunc run(value: int) -> int:
\t\tvar total: int = 0
\t\tvar factor: int = 2
\t\tfor step in range(value):
\t\t\ttotal += step * factor
\t\tif total > 10:
\t\t\ttotal = 10
\t\ttotal = total + factor
\t\treturn total


class Beta:
\tfunc run(value: int) -> int:
\t\tvar total: int = 0
\t\tvar factor: int = 2
\t\tfor step in range(value):
\t\t\ttotal += step * factor
\t\tif total > 10:
\t\t\ttotal = 10
\t\ttotal = total + factor
\t\treturn total
"""

#: Two inner classes, one method name, two unrelated bodies.
INNER_CLASS_NAMESAKES = """class_name Registry
extends RefCounted


class Loader:
\tfunc run(source: String) -> String:
\t\tvar buffer: String = source
\t\tbuffer = buffer.strip_edges()
\t\tif buffer.is_empty():
\t\t\treturn "empty"
\t\tbuffer = buffer.to_upper()
\t\tbuffer = buffer.replace("-", "_")
\t\treturn buffer


class Ticker:
\tfunc run(rounds: int) -> String:
\t\tvar elapsed: float = 0.0
\t\twhile rounds > 0:
\t\t\telapsed = elapsed + 0.25
\t\t\trounds -= 1
\t\tif elapsed > 9.0:
\t\t\telapsed = 9.0
\t\treturn str(elapsed)
"""

STATIC_AND_OVERRIDE = """extends Node2D


static func tally(values: PackedInt32Array) -> int:
\tvar total: int = 0
\tvar bonus: int = 3
\tfor entry in values:
\t\ttotal += entry * bonus
\tif total > 999:
\t\ttotal = 999
\treturn total


func _physics_process(delta: float) -> void:
\tvar drift: float = delta
\tdrift = drift * 4.0
\tif drift > 1.0:
\t\tdrift = 1.0
\twhile drift < 0.0:
\t\tdrift += 0.1
\tset_physics_process(drift > 0.0)
"""

TINY = """extends Node


func nudge(seed_value: int) -> int:
\tvar carry: int = seed_value
\tcarry = carry + 7
\treturn carry
"""


def write(root: Path, relative: str, text: str) -> Path:
    """Create one source file under `root`, parents included."""
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")
    return target


def run_gate(root: Path, *extra: str) -> tuple[int, dict[str, Any], str]:
    """Run the gate over `root` and return exit code, JSON payload, Markdown."""
    output = root / "duplication.md"
    json_output = root / "duplication.json"
    code = GATE.main([
        "--project-root", str(root),
        "--output", str(output),
        "--json-output", str(json_output),
        "--quiet",
        *extra,
    ])
    return code, json.loads(json_output.read_text(encoding="utf-8")), output.read_text(encoding="utf-8")


def kinds(payload: dict[str, Any]) -> Counter[str]:
    """How many findings of each kind the run produced."""
    return Counter(item["kind"] for item in payload["findings"])


def refs(payload: dict[str, Any], kind: str) -> list[tuple[str, str]]:
    """`(left, right)` reference pairs of every finding of one kind."""
    return [(item["left"], item["right"]) for item in payload["findings"] if item["kind"] == kind]


class GateCase(unittest.TestCase):
    """Base case owning one temporary project root per test."""

    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self._temporary.cleanup)
        self.root = Path(self._temporary.name).resolve()


class StructuralDuplication(GateCase):
    def test_two_identical_gdscript_functions_are_a_structural_finding(self) -> None:
        write(self.root, "alpha.gd", DAMAGE)
        write(self.root, "beta.gd", DAMAGE)
        code, payload, report = run_gate(self.root)
        self.assertEqual(kinds(payload)["structural"], 1)
        self.assertEqual(payload["units"], 2)
        self.assertEqual(payload["units_by_language"], "gdscript 2")
        self.assertEqual(code, BLOCKED)
        self.assertIn("Status: **FAIL**", report)

    def test_structural_finding_names_the_gdscript_function(self) -> None:
        write(self.root, "alpha.gd", DAMAGE)
        write(self.root, "beta.gd", DAMAGE)
        _code, payload, _report = run_gate(self.root)
        left, right = refs(payload, "structural")[0]
        self.assertEqual(left, "alpha.gd:4-12:apply_burn")
        self.assertEqual(right, "beta.gd:4-12:apply_burn")

    def test_static_func_and_virtual_override_are_both_extracted(self) -> None:
        write(self.root, "left.gd", STATIC_AND_OVERRIDE)
        write(self.root, "right.gd", STATIC_AND_OVERRIDE)
        code, payload, _report = run_gate(self.root)
        found = {ref.rsplit(":", 1)[1] for pair in refs(payload, "structural") for ref in pair}
        self.assertEqual(found, {"tally", "_physics_process"})
        self.assertEqual(code, BLOCKED)


class MaskedDuplication(GateCase):
    def test_two_renamed_copies_are_a_masked_finding(self) -> None:
        write(self.root, "burn.gd", DAMAGE)
        write(self.root, "chill.gd", DAMAGE_RENAMED)
        _code, payload, _report = run_gate(self.root)
        self.assertEqual(kinds(payload)["masked"], 1)
        self.assertEqual(kinds(payload)["structural"], 0)

    def test_renamed_copies_do_not_block_until_masked_is_configured(self) -> None:
        write(self.root, "burn.gd", DAMAGE)
        write(self.root, "chill.gd", DAMAGE_RENAMED)
        default_code, _payload, _report = run_gate(self.root)
        self.assertEqual(default_code, PASS)
        blocking_code, payload, report = run_gate(self.root, "--fail-on", "structural,masked")
        self.assertEqual(blocking_code, BLOCKED)
        self.assertEqual(payload["blocking"], 1)
        self.assertIn("Status: **FAIL**", report)

    def test_the_rejected_structural_pair_is_reported_not_hidden(self) -> None:
        write(self.root, "burn.gd", DAMAGE)
        write(self.root, "chill.gd", DAMAGE_RENAMED)
        _code, payload, _report = run_gate(self.root)
        self.assertEqual(payload["shape_only_pairs"], 1)


class BehavioralDuplication(GateCase):
    def test_similar_behaviour_with_a_different_shape_is_behavioral_only(self) -> None:
        write(self.root, "wave.gd", WAVE)
        write(self.root, "queue.gd", QUEUE)
        _code, payload, _report = run_gate(self.root)
        self.assertEqual(kinds(payload), Counter({"behavioral": 1}))

    def test_behavioral_findings_never_block_in_the_canonical_configuration(self) -> None:
        write(self.root, "wave.gd", WAVE)
        write(self.root, "queue.gd", QUEUE)
        code, payload, report = run_gate(self.root, "--fail-on", "structural,masked")
        self.assertEqual(payload["blocking"], 0)
        self.assertEqual(code, PASS)
        self.assertIn("Status: **PASS**", report)


class QuotedCopies(GateCase):
    def test_copies_inside_comments_and_strings_are_ignored(self) -> None:
        write(self.root, "real.gd", DAMAGE)
        write(self.root, "quoted.gd", QUOTED_COPY)
        code, payload, _report = run_gate(self.root, "--fail-on", "structural,masked")
        self.assertEqual(payload["findings"], [])
        self.assertEqual(code, PASS)

    def test_the_quoted_file_contributes_no_unit_at_all(self) -> None:
        write(self.root, "real.gd", DAMAGE)
        write(self.root, "quoted.gd", QUOTED_COPY)
        _code, payload, _report = run_gate(self.root)
        self.assertEqual(payload["units"], 1)


class InnerClassScope(GateCase):
    def test_identical_methods_of_two_inner_classes_keep_their_class_scope(self) -> None:
        write(self.root, "container.gd", INNER_CLASS_TWINS)
        _code, payload, _report = run_gate(self.root)
        left, right = refs(payload, "structural")[0]
        self.assertTrue(left.endswith(":Alpha.run"), left)
        self.assertTrue(right.endswith(":Beta.run"), right)

    def test_namesake_methods_with_different_bodies_are_not_confused(self) -> None:
        write(self.root, "registry.gd", INNER_CLASS_NAMESAKES)
        code, payload, _report = run_gate(self.root, "--fail-on", "structural,masked")
        self.assertEqual(payload["units"], 2)
        self.assertEqual(kinds(payload)["structural"], 0)
        self.assertEqual(kinds(payload)["masked"], 0)
        self.assertEqual(code, PASS)


class SizeFloor(GateCase):
    def test_functions_below_min_lines_are_not_compared(self) -> None:
        write(self.root, "one.gd", TINY)
        write(self.root, "two.gd", TINY)
        code, payload, _report = run_gate(self.root, "--fail-on", "structural,masked")
        self.assertEqual(payload["units"], 0)
        self.assertEqual(payload["findings"], [])
        self.assertEqual(code, PASS)

    def test_lowering_the_floor_exposes_the_same_pair(self) -> None:
        write(self.root, "one.gd", TINY)
        write(self.root, "two.gd", TINY)
        code, payload, _report = run_gate(
            self.root, "--min-lines", "4", "--min-tokens", "10", "--fail-on", "structural,masked"
        )
        self.assertEqual(payload["units"], 2)
        self.assertEqual(kinds(payload)["structural"], 1)
        self.assertEqual(code, BLOCKED)


class TestDirectoryPolicy(GateCase):
    def populate(self) -> None:
        write(self.root, "runtime.gd", WAVE)
        write(self.root, "tests/test_alpha.gd", DAMAGE)
        write(self.root, "tests/test_beta.gd", DAMAGE)

    def test_tests_are_excluded_by_default(self) -> None:
        self.populate()
        code, payload, _report = run_gate(self.root, "--fail-on", "structural,masked")
        self.assertEqual(payload["units"], 1)
        self.assertEqual(payload["findings"], [])
        self.assertEqual(code, PASS)

    def test_include_tests_scans_the_forks_own_tests(self) -> None:
        self.populate()
        code, payload, _report = run_gate(self.root, "--include-tests", "--fail-on", "structural,masked")
        self.assertEqual(payload["units"], 3)
        self.assertEqual(kinds(payload)["structural"], 1)
        left, right = refs(payload, "structural")[0]
        self.assertEqual(left, "tests/test_alpha.gd:4-12:apply_burn")
        self.assertEqual(right, "tests/test_beta.gd:4-12:apply_burn")
        self.assertEqual(code, BLOCKED)


class ScanErrors(GateCase):
    def test_a_scan_error_exits_two_and_never_reports_pass(self) -> None:
        write(self.root, "clean.gd", DAMAGE)
        write(self.root, "broken.py", "def unfinished(:\n    return 1\n")
        code, payload, report = run_gate(self.root, "--fail-on", "structural,masked")
        self.assertEqual(code, SCAN_ERROR)
        self.assertEqual(payload["findings"], [])
        self.assertEqual(len(payload["scan_issues"]), 1)
        self.assertIn("broken.py", payload["scan_issues"][0])
        self.assertIn("Status: **ERROR**", report)
        self.assertNotIn("Status: **PASS**", report)

    def test_a_scan_error_outranks_a_blocking_finding(self) -> None:
        write(self.root, "alpha.gd", DAMAGE)
        write(self.root, "beta.gd", DAMAGE)
        write(self.root, "broken.py", "def unfinished(:\n    return 1\n")
        code, payload, _report = run_gate(self.root, "--fail-on", "structural,masked")
        self.assertEqual(payload["blocking"], 1)
        self.assertEqual(code, SCAN_ERROR)

    def test_an_unreadable_project_root_is_a_configuration_error(self) -> None:
        code = GATE.main(["--project-root", str(self.root / "absent"), "--quiet"])
        self.assertEqual(code, SCAN_ERROR)


class SelfExclusion(GateCase):
    def test_the_tooling_gates_exclusion_is_still_declared(self) -> None:
        self.assertEqual(GATE.QUALITY_EXCLUDED_GLOBS, ("tooling/gates/**",))

    def test_the_exclusion_is_announced_in_every_report(self) -> None:
        write(self.root, "alpha.gd", DAMAGE)
        _code, _payload, report = run_gate(self.root)
        self.assertIn("Explicit default exclusions: tooling/gates/**", report)


if __name__ == "__main__":
    unittest.main()
