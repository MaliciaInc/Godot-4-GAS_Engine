#!/usr/bin/env python3
"""End-to-end behaviour of the test-location gate on GDScript and GUT.

Every case builds a real temporary repository with the canonical frozen policy
and runs the gate's own `main()` against it, so the assertions cover discovery,
policy loading, detection, reporting and the exit-code contract together.
"""
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

GATE_PATH = Path(__file__).resolve().parents[1] / "test-location-gate.py"

#: The exact `test_location` section of the frozen `.quality-gates.json`.
POLICY = json.dumps({
    "test_location": {
        "include_extensions": [".gd", ".py", ".ps1"],
        "allowed_directories": ["test", "tests", "tooling/gates/tests"],
        "test_file_globs": ["test_*.gd", "*_test.gd", "test_*.py", "*_test.py"],
        "require_test_directory": True,
        "exclude_globs": ["addons/gut/**"],
    }
}, indent=2)

PRODUCTION_GD = "addons/GAS_Engine/components/ability_system_component.gd"

ASC_WITH_HIDDEN_TEST = (
    "class_name AbilitySystemComponent\n"
    "extends Node\n"
    "\n"
    "var _health: float = 100.0\n"
    "\n"
    "func apply_damage(amount: float) -> float:\n"
    "\t_health = clampf(_health - amount, 0.0, 100.0)\n"
    "\treturn _health\n"
    "\n"
    "func test_damage_is_clamped() -> void:\n"
    "\tassert(apply_damage(500.0) == 0.0)\n"
)

ASC_PRODUCTION_ONLY = (
    "class_name AbilitySystemComponent\n"
    "extends Node\n"
    "\n"
    "var _health: float = 100.0\n"
    "\n"
    "func apply_damage(amount: float) -> float:\n"
    "\t_health = clampf(_health - amount, 0.0, 100.0)\n"
    "\treturn _health\n"
)

#: A fixture: helpers only, and a name that merely starts with `testing`.
FIXTURE_HELPERS_ONLY = (
    "class_name AscFixture\n"
    "extends RefCounted\n"
    "\n"
    "static func build_asc() -> Node:\n"
    "\tvar node: Node = Node.new()\n"
    "\tnode.name = \"AbilitySystemComponent\"\n"
    "\treturn node\n"
    "\n"
    "static func testing_helper_value() -> float:\n"
    "\treturn 1.0\n"
)

COMMENTED_TEST = (
    "extends Node\n"
    "\n"
    "# func test_damage_is_clamped() -> void:\n"
    "#\tassert(false)\n"
    "\n"
    "func apply_damage(amount: float) -> float:\n"
    "\treturn amount\n"
)

QUOTED_TEST = (
    "extends Node\n"
    "\n"
    "const TEMPLATE: String = \"\"\"\n"
    "func test_damage_is_clamped() -> void:\n"
    "\tassert(false)\n"
    "\"\"\"\n"
    "\n"
    "func apply_damage(amount: float) -> float:\n"
    "\treturn amount\n"
)

GUT_SUITE_BY_CLASS = (
    "extends GutTest\n"
    "\n"
    "func before_each() -> void:\n"
    "\tpass\n"
)

GUT_SUITE_BY_PATH = (
    "extends \"res://addons/gut/test.gd\"\n"
    "\n"
    "func before_each() -> void:\n"
    "\tpass\n"
)


def load_gate() -> Any:
    """Import the hyphenated gate entrypoint as a module."""
    spec = importlib.util.spec_from_file_location("gas_engine_test_location_gate", GATE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import gate at {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


GATE = load_gate()


class GateCase(unittest.TestCase):
    """A disposable repository plus a runner for the gate's real CLI."""

    def setUp(self) -> None:
        repository = tempfile.TemporaryDirectory()
        reports = tempfile.TemporaryDirectory()
        self.addCleanup(repository.cleanup)
        self.addCleanup(reports.cleanup)
        self.root = Path(repository.name)
        self.reports = Path(reports.name)
        (self.root / ".quality-gates.json").write_text(POLICY, encoding="utf-8")

    def write(self, relative: str, content: str) -> Path:
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8", newline="\n")
        return target

    def write_bytes(self, relative: str, payload: bytes) -> Path:
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        return target

    def run_gate(self, *extra: str) -> tuple[int, dict[str, Any]]:
        """Run the gate over the temporary repository and return (exit code, JSON)."""
        report = self.reports / "test-location.json"
        code = GATE.main([
            "--project-root", str(self.root),
            "--json-output", str(report),
            "--quiet", "--no-git", *extra,
        ])
        payload = json.loads(report.read_text(encoding="utf-8"))
        return code, payload

    def descriptions(self, payload: dict[str, Any]) -> list[str]:
        return [str(item["description"]) for item in payload["findings"]]

    def assert_clean(self, code: int, payload: dict[str, Any]) -> None:
        self.assertEqual(payload["findings"], [])
        self.assertEqual(payload["scan_issues"], [])
        self.assertEqual(code, 0)


class GdScriptTestDetection(GateCase):
    def test_gut_test_function_in_production_file_is_a_finding(self) -> None:
        self.write(PRODUCTION_GD, ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertEqual(len(payload["findings"]), 1)
        finding = payload["findings"][0]
        self.assertEqual(finding["path"], PRODUCTION_GD)
        self.assertEqual(finding["line"], 10)
        self.assertIn("test_damage_is_clamped", finding["description"])

    def test_same_content_inside_test_directory_is_clean(self) -> None:
        self.write("test/unit/test_ability_system_component.gd", ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate()
        self.assert_clean(code, payload)
        self.assertEqual(payload["test_files"], 1)
        self.assertEqual(payload["files_scanned"], 1)

    def test_fixture_without_test_functions_is_not_a_misplaced_test(self) -> None:
        self.write("test/fixtures/asc_fixture.gd", FIXTURE_HELPERS_ONLY)
        code, payload = self.run_gate()
        self.assert_clean(code, payload)
        self.assertEqual(payload["files_scanned"], 1)

    def test_fixture_outside_the_test_tree_is_still_not_a_test(self) -> None:
        self.write("game/fixtures/asc_fixture.gd", FIXTURE_HELPERS_ONLY)
        code, payload = self.run_gate()
        self.assert_clean(code, payload)

    def test_production_gdscript_without_test_functions_is_clean(self) -> None:
        self.write(PRODUCTION_GD, ASC_PRODUCTION_ONLY)
        code, payload = self.run_gate()
        self.assert_clean(code, payload)
        self.assertEqual(payload["files_scanned"], 1)
        self.assertEqual(payload["test_files"], 0)

    def test_test_function_inside_a_comment_is_ignored(self) -> None:
        self.write(PRODUCTION_GD, COMMENTED_TEST)
        code, payload = self.run_gate()
        self.assert_clean(code, payload)

    def test_test_function_inside_a_triple_quoted_block_is_ignored(self) -> None:
        self.write(PRODUCTION_GD, QUOTED_TEST)
        code, payload = self.run_gate()
        self.assert_clean(code, payload)

    def test_gut_base_class_alone_is_a_finding(self) -> None:
        self.write("game/combat/damage_probe.gd", GUT_SUITE_BY_CLASS)
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertEqual(self.descriptions(payload), ["inline GUT test suite base class"])
        self.assertEqual(payload["findings"][0]["line"], 1)

    def test_gut_base_class_by_resource_path_is_a_finding(self) -> None:
        self.write("game/combat/damage_probe.gd", GUT_SUITE_BY_PATH)
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertEqual(self.descriptions(payload), ["inline GUT test suite base class"])

    def test_multiple_hidden_tests_are_reported_in_line_order(self) -> None:
        source = ASC_WITH_HIDDEN_TEST + "\nfunc test_health_never_negative() -> void:\n\tassert(true)\n"
        self.write(PRODUCTION_GD, source)
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertEqual([item["line"] for item in payload["findings"]], [10, 13])


class TestFileLocation(GateCase):
    def test_test_named_gd_file_outside_allowed_directories_is_a_finding(self) -> None:
        self.write("game/combat/test_damage.gd", FIXTURE_HELPERS_ONLY)
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertEqual(self.descriptions(payload), ["test file is outside an approved test directory"])
        self.assertEqual(payload["findings"][0]["line"], 1)

    def test_suffix_glob_is_recognized_outside_allowed_directories(self) -> None:
        self.write("game/combat/damage_test.gd", FIXTURE_HELPERS_ONLY)
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertEqual(self.descriptions(payload), ["test file is outside an approved test directory"])

    def test_test_named_gd_file_inside_allowed_directory_is_clean(self) -> None:
        self.write("test/unit/test_damage.gd", ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate()
        self.assert_clean(code, payload)

    def test_multi_segment_allowed_directory_is_honoured(self) -> None:
        self.write("tooling/gates/suites/test_damage.gd", ASC_WITH_HIDDEN_TEST)
        blocked_code, blocked = self.run_gate("--allowed-directory", "test")
        self.assertEqual(blocked_code, 1)
        self.assertEqual(self.descriptions(blocked), ["test file is outside an approved test directory"])
        allowed_code, allowed = self.run_gate("--allowed-directory", "tooling/gates/suites")
        self.assert_clean(allowed_code, allowed)

    def test_multi_segment_prefix_alone_does_not_allow_a_sibling(self) -> None:
        self.write("tooling/gates/other/test_damage.gd", ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate("--allowed-directory", "tooling/gates/suites")
        self.assertEqual(code, 1)


class OtherLanguagesStillWork(GateCase):
    def test_python_test_function_in_production_is_still_reported(self) -> None:
        self.write("tooling/scripts/helper.py", "def test_thing() -> None:\n    assert True\n")
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("inline Python test function 'test_thing'", self.descriptions(payload))

    def test_python_unittest_class_in_production_is_still_reported(self) -> None:
        source = "import unittest\n\n\nclass ThingCase(unittest.TestCase):\n    pass\n"
        self.write("tooling/scripts/helper.py", source)
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("inline Python test class 'ThingCase'", self.descriptions(payload))

    def test_powershell_pester_block_in_production_is_still_reported(self) -> None:
        self.write("tooling/verify.ps1", "Describe \"gate\" {\n    It \"runs\" { }\n}\n")
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("Pester test", self.descriptions(payload))

    def test_vendored_gut_addon_is_excluded_by_policy(self) -> None:
        self.write("addons/gut/test.gd", ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate()
        self.assert_clean(code, payload)
        self.assertEqual(payload["files_scanned"], 0)


class ScanErrorContract(GateCase):
    BROKEN = b"extends Node\n\nfunc test_damage() -> void:\n\tvar label: String = \"\xff\xfe\"\n"

    def test_unreadable_file_is_exit_two_without_the_flag(self) -> None:
        self.write_bytes("addons/GAS_Engine/broken.gd", self.BROKEN)
        code, payload = self.run_gate()
        self.assertEqual(code, 2)
        self.assertEqual(len(payload["scan_issues"]), 1)
        self.assertIn("addons/GAS_Engine/broken.gd", payload["scan_issues"][0])

    def test_unreadable_file_is_tolerated_with_allow_scan_errors(self) -> None:
        self.write_bytes("addons/GAS_Engine/broken.gd", self.BROKEN)
        code, payload = self.run_gate("--allow-scan-errors")
        self.assertEqual(code, 0)
        self.assertEqual(len(payload["scan_issues"]), 1)

    def test_scan_error_outranks_a_real_violation(self) -> None:
        self.write_bytes("addons/GAS_Engine/broken.gd", self.BROKEN)
        self.write(PRODUCTION_GD, ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate()
        self.assertEqual(code, 2)
        self.assertEqual(len(payload["findings"]), 1)

    def test_oversized_file_is_a_scan_issue_not_a_silent_skip(self) -> None:
        self.write(PRODUCTION_GD, ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate("--max-file-bytes", "10")
        self.assertEqual(code, 2)
        self.assertEqual(payload["files_scanned"], 0)
        self.assertIn("exceeds 10 bytes", payload["scan_issues"][0])

    def test_broken_python_file_does_not_abort_the_whole_scan(self) -> None:
        self.write("tooling/scripts/broken.py", "def (:\n")
        self.write(PRODUCTION_GD, ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate()
        self.assertEqual(code, 2)
        self.assertEqual(len(payload["findings"]), 1)
        self.assertIn("Python parse error", payload["scan_issues"][0])


class CliSurface(GateCase):
    def test_every_frozen_argument_is_accepted(self) -> None:
        args = GATE.build_parser().parse_args([
            "--project-root", ".", "--config", "c.json", "--include-extension", "gd",
            "--exclude-glob", "x/**", "--allowed-directory", "test",
            "--test-file-glob", "test_*.gd", "--allow-inline-glob", "y/**",
            "--require-test-directory", "--max-file-bytes", "10", "--no-git",
            "--allow-scan-errors", "--output", "o.md", "--json-output", "o.json", "--quiet",
        ])
        self.assertEqual(args.include_extension, [".gd"])
        self.assertEqual(args.allowed_directory, ["test"])
        self.assertEqual(args.test_file_glob, ["test_*.gd"])
        self.assertEqual(args.allow_inline_glob, ["y/**"])
        self.assertEqual(args.max_file_bytes, 10)
        self.assertTrue(args.require_test_directory)
        self.assertTrue(args.no_git and args.quiet and args.allow_scan_errors)

    def test_include_extension_override_narrows_the_scan(self) -> None:
        self.write(PRODUCTION_GD, ASC_PRODUCTION_ONLY)
        self.write("tooling/scripts/helper.py", "VALUE: int = 1\n")
        code, payload = self.run_gate("--include-extension", ".gd")
        self.assert_clean(code, payload)
        self.assertEqual(payload["files_scanned"], 1)

    def test_allow_inline_glob_exempts_a_production_file(self) -> None:
        self.write(PRODUCTION_GD, ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate("--allow-inline-glob", "addons/GAS_Engine/**")
        self.assert_clean(code, payload)
        self.assertEqual(payload["files_scanned"], 1)

    def test_exclude_glob_removes_the_file_from_discovery(self) -> None:
        self.write(PRODUCTION_GD, ASC_WITH_HIDDEN_TEST)
        code, payload = self.run_gate("--exclude-glob", "addons/GAS_Engine/**")
        self.assert_clean(code, payload)
        self.assertEqual(payload["files_scanned"], 0)

    def test_markdown_report_states_the_failure(self) -> None:
        self.write(PRODUCTION_GD, ASC_WITH_HIDDEN_TEST)
        report = self.reports / "test-location.md"
        code = GATE.main([
            "--project-root", str(self.root), "--output", str(report), "--quiet", "--no-git",
        ])
        text = report.read_text(encoding="utf-8")
        self.assertEqual(code, 1)
        self.assertIn("- Status: **FAIL**", text)
        self.assertIn("test_damage_is_clamped", text)

    def test_missing_project_root_is_a_configuration_error(self) -> None:
        code = GATE.main(["--project-root", str(self.root / "absent"), "--quiet", "--no-git"])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
