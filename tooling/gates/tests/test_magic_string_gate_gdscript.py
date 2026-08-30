#!/usr/bin/env python3
"""GDScript behaviour of the magic-string gate, and its refusal to exclude itself.

Every scenario writes real `.gd` files into a throwaway tree together with the
frozen `.quality-gates.json` policy, then drives the gate through its actual CLI
and reads the JSON report back. Nothing is asserted about internals that the
canonical pipeline does not also depend on.
"""
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Mapping

GATES_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = GATES_DIR.parents[1]
sys.path.insert(0, str(GATES_DIR))

from lib import gate_io  # noqa: E402


def load_gate() -> Any:
    """Import the hyphenated gate entrypoint under a usable module name."""
    spec = importlib.util.spec_from_file_location("magic_string_gate", GATES_DIR / "magic-string-gate.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    # `slots=True` dataclasses resolve their own module during class creation,
    # so the module has to be registered before the body executes.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


gate = load_gate()

CANONICAL_POLICY = {
    "magic_strings": {
        "include_extensions": [".gd", ".py", ".ps1"],
        "minimum_length": 3,
        "minimum_occurrences": 2,
        "minimum_distinct_files": 2,
        "fail_on": ["repeated", "templates", "colors"],
        "allow_literals": [],
        "allow_globs": [],
        "theme_globs": ["**/theme/**", "**/themes/**", "**/styles/**"],
        "exclude_globs": ["addons/gut/**"],
    }
}

MULTILINE_SOURCE = (
    "extends Node\n"
    "\n"
    'var header := """\n'
    "first\n"
    "second\n"
    "third\n"
    '"""\n'
    "\n"
    "func _ready() -> void:\n"
    '\tprint("Event.Damage")\n'
)
DOCUMENTATION_SOURCE = '"""\nShared module header\n"""\nextends Node\n'


class GateScenario(unittest.TestCase):
    """Base class that runs the real gate over a temporary source tree."""

    def analyze(self, files: Mapping[str, str], *extra: str) -> tuple[int, dict[str, Any]]:
        """Write `files`, run the gate under the frozen policy, return (exit code, report)."""
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            (root / ".quality-gates.json").write_text(json.dumps(CANONICAL_POLICY), encoding="utf-8")
            for name, text in files.items():
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text, encoding="utf-8")
            report = root / "magic.json"
            code = gate.main([
                "--project-root", str(root), "--no-git", "--quiet", "--json-output", str(report), *extra,
            ])
            return code, json.loads(report.read_text(encoding="utf-8"))

    def literal_groups(self, payload: Mapping[str, Any]) -> dict[str, list[str]]:
        """Map each repeated literal to the `path:line` places it was found."""
        return {
            value: [f"{item['path']}:{item['line']}" for item in occurrences]
            for value, occurrences in payload["repeated_literals"]
        }

    def template_groups(self, payload: Mapping[str, Any]) -> dict[str, list[str]]:
        """Map each repeated template to the `path:line` places it was found."""
        return {
            value: [f"{item['path']}:{item['line']}" for item in occurrences]
            for value, occurrences in payload["repeated_templates"]
        }


class RepeatedGdscriptLiterals(GateScenario):
    def test_literal_in_two_files_is_a_blocking_finding(self) -> None:
        code, payload = self.analyze({
            "alpha.gd": 'extends Node\n\nfunc _ready() -> void:\n\tprint("Event.Damage")\n',
            "beta.gd": 'extends Node\n\nfunc apply() -> void:\n\tprint("Event.Damage")\n',
        })
        self.assertEqual(code, 1)
        self.assertEqual(payload["files_scanned"], 2)
        self.assertEqual(payload["blocking_count"], 1)
        self.assertEqual(self.literal_groups(payload)["Event.Damage"], ["alpha.gd:4", "beta.gd:4"])

    def test_string_name_prefix_does_not_hide_the_literal(self) -> None:
        code, payload = self.analyze({
            "alpha.gd": 'var tag: StringName = &"Event.Damage"\n',
            "beta.gd": 'var other: StringName = &"Event.Damage"\n',
        })
        self.assertEqual(code, 1)
        self.assertEqual(self.literal_groups(payload)["Event.Damage"], ["alpha.gd:1", "beta.gd:1"])

    def test_string_name_groups_with_the_plain_literal_it_interns(self) -> None:
        code, payload = self.analyze({
            "alpha.gd": 'var tag: StringName = &"Event.Damage"\n',
            "beta.gd": 'var other: String = "Event.Damage"\n',
        })
        self.assertEqual(code, 1)
        groups = self.literal_groups(payload)
        self.assertEqual(list(groups), ["Event.Damage"])
        self.assertEqual(groups["Event.Damage"], ["alpha.gd:1", "beta.gd:1"])

    def test_node_path_prefix_does_not_hide_the_literal(self) -> None:
        code, payload = self.analyze({
            "alpha.gd": 'var path: NodePath = ^"Combat/HealthBar"\n',
            "beta.gd": 'var other: NodePath = ^"Combat/HealthBar"\n',
        })
        self.assertEqual(code, 1)
        self.assertIn("Combat/HealthBar", self.literal_groups(payload))

    def test_single_occurrence_is_not_reported(self) -> None:
        code, payload = self.analyze({
            "alpha.gd": 'var tag := "Event.Damage"\n',
            "beta.gd": 'var other := "Event.Healing"\n',
        })
        self.assertEqual(code, 0)
        self.assertEqual(payload["repeated_literals"], [])
        self.assertEqual(payload["blocking_count"], 0)

    def test_two_occurrences_inside_one_file_are_not_reported(self) -> None:
        code, payload = self.analyze({
            "alpha.gd": 'var first := "Event.Damage"\nvar second := "Event.Damage"\n',
            "beta.gd": "var count := 1\n",
        })
        self.assertEqual(code, 0)
        self.assertEqual(payload["files_scanned"], 2)
        self.assertEqual(payload["repeated_literals"], [])

    def test_literal_below_the_minimum_length_is_ignored(self) -> None:
        code, payload = self.analyze({"alpha.gd": 'var a := "ok"\n', "beta.gd": 'var b := "ok"\n'})
        self.assertEqual(code, 0)
        self.assertEqual(payload["repeated_literals"], [])

    def test_repeated_format_strings_group_as_one_template(self) -> None:
        code, payload = self.analyze({
            "alpha.gd": 'func report(amount: int) -> void:\n\tprint("Damage: %d" % amount)\n',
            "beta.gd": 'func log_hit(text: String) -> void:\n\tprint("Damage: %s" % text)\n',
        })
        self.assertEqual(code, 1)
        self.assertEqual(self.template_groups(payload)["Damage: {}"], ["alpha.gd:2", "beta.gd:2"])
        self.assertEqual(payload["repeated_literals"], [])


class GdscriptSyntaxIsUnderstood(GateScenario):
    def test_literal_inside_a_hash_comment_is_ignored(self) -> None:
        comment = '# the tag "Event.Damage" is documented here\nextends Node\n'
        code, payload = self.analyze({"alpha.gd": comment, "beta.gd": comment})
        self.assertEqual(code, 0)
        self.assertEqual(payload["repeated_literals"], [])
        self.assertEqual(payload["files_scanned"], 2)

    def test_annotations_and_type_names_are_not_literals(self) -> None:
        annotated = (
            "extends Node\n"
            "class_name DamageComponent\n"
            "\n"
            "@export var speed: float = 1.0\n"
            "@export_group(\"combat\")\n"
            "@onready var label: Label = $Label\n"
        )
        code, payload = self.analyze({"alpha.gd": annotated, "beta.gd": annotated})
        groups = self.literal_groups(payload)
        self.assertNotIn("export", groups)
        self.assertNotIn("onready", groups)
        self.assertNotIn("Label", groups)
        self.assertNotIn("DamageComponent", groups)
        # The one genuinely quoted value on those lines is still visible.
        self.assertEqual(groups["combat"], ["alpha.gd:5", "beta.gd:5"])
        self.assertEqual(code, 1)

    def test_reported_line_survives_an_earlier_multiline_string(self) -> None:
        code, payload = self.analyze({
            "alpha.gd": MULTILINE_SOURCE,
            "beta.gd": 'extends Node\n\tprint("Event.Damage")\n',
        })
        self.assertEqual(code, 1)
        self.assertEqual(self.literal_groups(payload)["Event.Damage"], ["alpha.gd:10", "beta.gd:2"])

    def test_statement_level_triple_quoted_block_is_treated_as_documentation(self) -> None:
        code, payload = self.analyze({"alpha.gd": DOCUMENTATION_SOURCE, "beta.gd": DOCUMENTATION_SOURCE})
        self.assertEqual(code, 0)
        self.assertEqual(payload["repeated_literals"], [])


class HardCodedColors(GateScenario):
    def test_repeated_hex_colour_is_reported_as_a_colour(self) -> None:
        code, payload = self.analyze({
            "alpha.gd": 'var accent := "#ff00ff"\n',
            "beta.gd": 'var accent := "#ff00ff"\n',
        })
        self.assertEqual(code, 1)
        found = {(item["path"], item["line"], item["value"], item["kind"]) for item in payload["colors"]}
        self.assertEqual(found, {("alpha.gd", 1, "#ff00ff", "color"), ("beta.gd", 1, "#ff00ff", "color")})

    def test_godot_colour_constructor_is_reported(self) -> None:
        code, payload = self.analyze({"alpha.gd": "func tint() -> Color:\n\treturn Color8(255, 0, 255)\n"})
        self.assertEqual(code, 1)
        self.assertEqual([(item["path"], item["line"]) for item in payload["colors"]], [("alpha.gd", 2)])

    def test_colour_inside_a_comment_is_not_reported(self) -> None:
        code, payload = self.analyze({"alpha.gd": '# magenta is "#ff00ff" and Color8(255, 0, 255)\nvar a := 1\n'})
        self.assertEqual(code, 0)
        self.assertEqual(payload["colors"], [])

    def test_theme_layer_is_exempt_from_colour_findings(self) -> None:
        # The frozen `**/theme/**` glob is anchored on a leading segment, so the
        # theme layer has to be nested for the exemption to apply.
        code, payload = self.analyze({"game/theme/palette.gd": 'var accent := "#ff00ff"\n'})
        self.assertEqual(code, 0)
        self.assertEqual(payload["colors"], [])

    def test_colour_outside_the_theme_layer_is_still_reported(self) -> None:
        code, payload = self.analyze({"game/combat/hud.gd": 'var accent := "#ff00ff"\n'})
        self.assertEqual(code, 1)
        self.assertEqual([item["path"] for item in payload["colors"]], ["game/combat/hud.gd"])


class SelfHosting(GateScenario):
    """Paso 0.6: the gate must scan the directory that implements it."""

    def test_tooling_gates_paths_are_scanned_in_a_project_tree(self) -> None:
        code, payload = self.analyze({
            "tooling/gates/alpha.gd": 'var tag := "Event.Damage"\n',
            "tooling/gates/beta.gd": 'var tag := "Event.Damage"\n',
        })
        self.assertEqual(payload["files_scanned"], 2)
        self.assertEqual(code, 1)
        self.assertEqual(
            self.literal_groups(payload)["Event.Damage"],
            ["tooling/gates/alpha.gd:1", "tooling/gates/beta.gd:1"],
        )

    def test_no_configured_exclusion_hides_the_gate_sources(self) -> None:
        settings = self.repository_settings()
        for candidate in ("tooling/gates/magic-string-gate.py", "tooling/gates/lib/gate_io.py"):
            self.assertFalse(gate_io.matches(candidate, settings.exclude_globs), candidate)

    def test_repository_discovery_reaches_the_gate_entrypoint(self) -> None:
        settings = self.repository_settings()
        files, issues = gate_io.discover(gate.discovery_request(PROJECT_ROOT, settings))
        relatives = [item.relative_to(PROJECT_ROOT).as_posix() for item in files]
        self.assertEqual(issues, [])
        self.assertGreater(len(relatives), 0)
        self.assertIn("tooling/gates/magic-string-gate.py", relatives)

    def repository_settings(self) -> Any:
        """Resolve the settings the canonical run uses against this repository."""
        args = gate.build_parser().parse_args(["--project-root", str(PROJECT_ROOT)])
        return gate.load_settings(PROJECT_ROOT, args)


class ContractsPreserved(GateScenario):
    def test_python_sources_are_still_analysed(self) -> None:
        code, payload = self.analyze({
            "alpha.py": 'VALUE = "Event.Damage"\n',
            "beta.py": 'OTHER = "Event.Damage"\n',
        })
        self.assertEqual(code, 1)
        self.assertEqual(self.literal_groups(payload)["Event.Damage"], ["alpha.py:1", "beta.py:1"])

    def test_python_docstrings_are_still_exempt(self) -> None:
        docstring = '"""Shared module documentation."""\nVALUE = 1\n'
        code, payload = self.analyze({"alpha.py": docstring, "beta.py": docstring})
        self.assertEqual(code, 0)
        self.assertEqual(payload["repeated_literals"], [])

    def test_scan_issue_exits_two_and_never_passes(self) -> None:
        code, payload = self.analyze({"alpha.gd": 'var tag := "Event.Damage"\n'}, "--max-file-bytes", "1")
        self.assertEqual(code, 2)
        self.assertTrue(payload["scan_issues"])

    def test_allow_scan_errors_downgrades_the_incomplete_scan(self) -> None:
        code, payload = self.analyze(
            {"alpha.gd": 'var tag := "Event.Damage"\n'}, "--max-file-bytes", "1", "--allow-scan-errors"
        )
        self.assertEqual(code, 0)
        self.assertTrue(payload["scan_issues"])

    def test_cli_still_accepts_every_canonical_option(self) -> None:
        args = gate.build_parser().parse_args([
            "--project-root", ".", "--config", "c.json", "--minimum-length", "4",
            "--minimum-occurrences", "3", "--minimum-distinct-files", "2", "--fail-on", "repeated",
            "--allow-literal", "x", "--allow-glob", "g/**", "--theme-glob", "t/**",
            "--exclude-glob", "e/**", "--include-extension", "gd", "--include-tests",
            "--max-file-bytes", "10", "--no-git", "--allow-scan-errors",
            "--output", "o.md", "--json-output", "o.json", "--quiet",
        ])
        self.assertEqual(args.fail_on, frozenset({"repeated"}))
        self.assertEqual(args.include_extension, [".gd"])
        self.assertTrue(args.include_tests and args.no_git and args.quiet and args.allow_scan_errors)


if __name__ == "__main__":
    unittest.main()
