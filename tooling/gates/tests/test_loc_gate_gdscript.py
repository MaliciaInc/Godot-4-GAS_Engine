#!/usr/bin/env python3
"""GDScript behaviour of `tooling/gates/loc-gate.py`.

Every test builds a throwaway project root holding real `.gd` files and runs the
gate's own `main()` against it, so what is asserted is the gate's exit code and
its JSON report, not an internal helper.

The two masking tests are written as pairs: the same declaration is measured
once behind a `#` and once bare, so a fixture that never tripped the gate in the
first place cannot masquerade as `ignored`.
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Mapping

GATE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(GATE_DIR))

GD_SOURCE = "game/sized.gd"
GD_NESTED = "game/nested.gd"
GD_FILE_SIZE = "game/bulk.gd"
GD_MASKING = "game/masking.gd"
POLICY_FILENAME = ".quality-gates.json"
SIX_PARAMETERS = "a: int, b: int, c: int, d: int, e: int, f: int"


def load_gate() -> Any:
    """Import `loc-gate.py`, whose hyphenated filename is not a module name."""
    spec = importlib.util.spec_from_file_location("loc_gate", GATE_DIR / "loc-gate.py")
    if spec is None or spec.loader is None:  # pragma: no cover - packaging accident
        raise RuntimeError("cannot load loc-gate.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["loc_gate"] = module
    spec.loader.exec_module(module)
    return module


loc_gate = load_gate()


def gdscript_function(total_lines: int, keyword: str = "func") -> str:
    """A GDScript function measuring exactly `total_lines` LOC, signature included."""
    body = "\n".join(f"\tvar step_{index}: int = {index}" for index in range(total_lines - 1))
    return f"{keyword} sized() -> void:\n{body}\n"


def gdscript_multiline_signature(total_lines: int) -> str:
    """A function whose signature spans four lines, measuring `total_lines` LOC."""
    header = "func sized(\n\t\tfirst: int,\n\t\tsecond: int\n) -> void:"
    body = "\n".join(f"\tvar step_{index}: int = {index}" for index in range(total_lines - 4))
    return f"{header}\n{body}\n"


def gdscript_parameters(count: int) -> str:
    """A short function declaring `count` typed parameters."""
    params = ", ".join(f"p{index}: int" for index in range(count))
    return f"func sized({params}) -> void:\n\tpass\n"


def gdscript_file(total_lines: int) -> str:
    """GDScript source of exactly `total_lines` lines; every function is two lines."""
    lines: list[str] = ["extends Node"] if total_lines % 2 else []
    for index in range((total_lines - len(lines)) // 2):
        lines.extend([f"func step_{index}() -> void:", "\tpass"])
    return "\n".join(lines) + "\n"


def comment_fixture(masked: bool) -> str:
    """A six-parameter declaration, optionally hidden behind a `#` comment."""
    prefix = "# " if masked else ""
    declaration = f"{prefix}func fake_in_comment({SIX_PARAMETERS}) -> void:\n{prefix}\tpass"
    return f"extends Node\n\n{declaration}\n\nfunc real() -> void:\n\tpass\n"


def string_fixture(masked: bool) -> str:
    """A six-parameter declaration, optionally hidden in a triple-quoted block."""
    declaration = f"func fake_in_string({SIX_PARAMETERS}) -> void:\n\tpass"
    if masked:
        quote = '"""'
        declaration = f"var template: String = {quote}\n{declaration}\n{quote}"
    return f"extends Node\n\n{declaration}\n\nfunc real() -> void:\n\tpass\n"


class GateCase(unittest.TestCase):
    """Runs the real gate CLI against a throwaway project root."""

    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()

    def write(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        return path

    def run_gate(self, *extra: str, use_git: bool = False) -> tuple[int, Mapping[str, Any]]:
        """Invoke `main()` exactly as the canonical chain does and read its report."""
        report = self.root / "report.json"
        argv = ["--project-root", str(self.root), "--quiet",
                "--output", str(self.root / "report.md"), "--json-output", str(report)]
        if not use_git:
            argv.append("--no-git")
        code = loc_gate.main([*argv, *extra])
        return code, json.loads(report.read_text(encoding="utf-8"))

    def markdown(self) -> str:
        return (self.root / "report.md").read_text(encoding="utf-8")

    def assert_clean(self, code: int, payload: Mapping[str, Any]) -> None:
        self.assertEqual(payload["violations"], [])
        self.assertEqual(payload["scan_issues"], [])
        self.assertEqual(code, 0)

    def assert_only_violation(self, payload: Mapping[str, Any], expected: str) -> None:
        self.assertEqual(payload["scan_issues"], [])
        self.assertEqual(list(payload["violations"]), [expected])


class FunctionLengthBoundary(GateCase):
    """119 passes, 120 passes, 121 fails: the limit is inclusive."""

    def test_function_of_119_lines_passes(self) -> None:
        self.write(GD_SOURCE, gdscript_function(119))
        self.assert_clean(*self.run_gate())

    def test_function_of_120_lines_passes(self) -> None:
        self.write(GD_SOURCE, gdscript_function(120))
        self.assert_clean(*self.run_gate())

    def test_function_of_121_lines_fails_with_the_measured_span(self) -> None:
        self.write(GD_SOURCE, gdscript_function(121))
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_SOURCE}:1: sized LOC 121 > 120 (lines 1-121)")
        self.assertEqual(code, 1)

    def test_static_function_of_121_lines_fails(self) -> None:
        self.write(GD_SOURCE, gdscript_function(121, keyword="static func"))
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_SOURCE}:1: sized LOC 121 > 120 (lines 1-121)")
        self.assertEqual(code, 1)

    def test_multiline_signature_is_measured_as_one_function(self) -> None:
        self.write(GD_SOURCE, gdscript_multiline_signature(121))
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_SOURCE}:1: sized LOC 121 > 120 (lines 1-121)")
        self.assertEqual(code, 1)

    def test_multiline_signature_of_120_lines_passes(self) -> None:
        self.write(GD_SOURCE, gdscript_multiline_signature(120))
        self.assert_clean(*self.run_gate())

    def test_space_indented_function_is_measured(self) -> None:
        """Bodies close on indentation width, not on a particular indent character."""
        body = "\n".join(f"    var step_{index}: int = {index}" for index in range(120))
        self.write(GD_SOURCE, f"func sized() -> void:\n{body}\n")
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_SOURCE}:1: sized LOC 121 > 120 (lines 1-121)")
        self.assertEqual(code, 1)

    def test_trailing_blank_lines_are_not_billed_to_the_function(self) -> None:
        self.write(GD_SOURCE, gdscript_function(120) + "\n\n\n")
        self.assert_clean(*self.run_gate())

    def test_body_ends_at_the_next_declaration_not_at_end_of_file(self) -> None:
        """A short function followed by a long one must not absorb its lines."""
        tail = "\n".join(f"\tvar step_{index}: int = {index}" for index in range(200))
        self.write(GD_SOURCE, f"func short_one() -> void:\n\tpass\n\nfunc long_one() -> void:\n{tail}\n")
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_SOURCE}:4: long_one LOC 201 > 120 (lines 4-204)")
        self.assertEqual(code, 1)


class ParameterLimit(GateCase):
    """GDScript signatures are subject to the same 5-parameter ceiling."""

    def test_five_parameters_pass(self) -> None:
        self.write(GD_SOURCE, gdscript_parameters(5))
        self.assert_clean(*self.run_gate())

    def test_six_parameters_fail(self) -> None:
        self.write(GD_SOURCE, gdscript_parameters(6))
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_SOURCE}:1: sized params 6 > 5")
        self.assertEqual(code, 1)

    def test_parameters_of_a_multiline_signature_are_counted(self) -> None:
        self.write(GD_SOURCE, "func sized(\n\t\ta: int,\n\t\tb: int\n) -> void:\n\tpass\n")
        code, payload = self.run_gate("--max-parameters", "1")
        self.assert_only_violation(payload, f"{GD_SOURCE}:1: sized params 2 > 1")
        self.assertEqual(code, 1)


class ParameterExemption(GateCase):
    """`function_parameter_allowlist` exempts one named signature, not a limit.

    It exists because Godot declares some virtuals with more parameters than the
    project allows - `EditorInspectorPlugin._parse_property` takes seven - and
    overriding one with fewer simply stops it working. Raising max_parameters
    would exempt every function in the project; naming one exempts one.

    Every test here is paired with a negative: an exemption that matched
    everything, or nothing, would pass a one-sided test either way.
    """

    def write_policy(self, rules: list[dict[str, str]]) -> None:
        self.write(
            POLICY_FILENAME,
            json.dumps({"loc": {"function_parameter_allowlist": rules}}, indent=2),
        )

    def test_a_named_function_is_exempt(self) -> None:
        self.write(GD_SOURCE, gdscript_parameters(6))
        self.write_policy([{"glob": GD_SOURCE, "function": "sized", "reason": "engine virtual"}])
        self.assert_clean(*self.run_gate())

    def test_an_unnamed_function_in_the_same_file_is_not_exempt(self) -> None:
        # The exemption names `sized`; this file declares `other`, so the rule
        # must not cover it. Without this, a rule that matched any function in
        # the file would pass the test above just as well.
        self.write(GD_SOURCE, gdscript_parameters(6).replace("sized", "other"))
        self.write_policy([{"glob": GD_SOURCE, "function": "sized", "reason": "engine virtual"}])
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_SOURCE}:1: other params 6 > 5")
        self.assertEqual(code, 1)

    def test_the_same_function_in_another_file_is_not_exempt(self) -> None:
        self.write(GD_NESTED, gdscript_parameters(6))
        self.write_policy([{"glob": GD_SOURCE, "function": "sized", "reason": "engine virtual"}])
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_NESTED}:1: sized params 6 > 5")
        self.assertEqual(code, 1)

    def test_a_parameter_exemption_does_not_exempt_length(self) -> None:
        # The two dimensions are separate declarations. An exemption for one
        # must not quietly cover the other.
        self.write(GD_SOURCE, gdscript_function(121))
        self.write_policy([{"glob": GD_SOURCE, "function": "sized", "reason": "engine virtual"}])
        code, payload = self.run_gate()
        self.assertIn("LOC 121 > 120", " ".join(payload["violations"]))
        self.assertEqual(code, 1)

    def test_an_exemption_without_a_reason_is_a_configuration_error(self) -> None:
        # An exemption with no written reason is indistinguishable from an
        # oversight, so the gate refuses to run rather than honouring it.
        self.write(GD_SOURCE, gdscript_parameters(6))
        self.write_policy([{"glob": GD_SOURCE, "function": "sized"}])
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = loc_gate.main(
                ["--project-root", str(self.root), "--quiet", "--no-git"]
            )
        self.assertEqual(code, 2)
        self.assertIn("function_parameter_allowlist requires glob/function/reason", stderr.getvalue())


class FileLengthBoundary(GateCase):
    """450 passes, 451 fails."""

    def test_file_of_450_lines_passes(self) -> None:
        source = gdscript_file(450)
        self.assertEqual(len(source.splitlines()), 450)
        self.write(GD_FILE_SIZE, source)
        self.assert_clean(*self.run_gate())

    def test_file_of_451_lines_fails(self) -> None:
        source = gdscript_file(451)
        self.assertEqual(len(source.splitlines()), 451)
        self.write(GD_FILE_SIZE, source)
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_FILE_SIZE}: file LOC 451 > 450")
        self.assertEqual(code, 1)


class NestedClassMethods(GateCase):
    """Inner-class methods are measured and reported as `Class.method`."""

    def test_nested_class_method_is_measured(self) -> None:
        body = "\n".join(f"\t\tvar step_{index}: int = {index}" for index in range(120))
        self.write(GD_NESTED, f"class Inner:\n\tfunc measured() -> void:\n{body}\n")
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_NESTED}:2: Inner.measured LOC 121 > 120 (lines 2-122)")
        self.assertEqual(code, 1)

    def test_nested_class_method_of_120_lines_passes(self) -> None:
        body = "\n".join(f"\t\tvar step_{index}: int = {index}" for index in range(119))
        self.write(GD_NESTED, f"class Inner:\n\tfunc measured() -> void:\n{body}\n")
        self.assert_clean(*self.run_gate())

    def test_same_named_methods_of_two_classes_are_reported_apart(self) -> None:
        long_body = "\n".join(f"\t\tvar step_{index}: int = {index}" for index in range(121))
        source = (f"class First:\n\tfunc run() -> void:\n{long_body}\n"
                  "class Second:\n\tfunc run() -> void:\n\t\tpass\n")
        self.write(GD_NESTED, source)
        code, payload = self.run_gate()
        self.assert_only_violation(payload, f"{GD_NESTED}:2: First.run LOC 122 > 120 (lines 2-123)")
        self.assertNotIn("Second.run", self.markdown())
        self.assertEqual(code, 1)


class MaskedDeclarations(GateCase):
    """`func` inside a comment or a string is not a function.

    Each case runs the identical declaration twice. The unmasked control must
    fail, which is what proves the masked variant passed for the right reason.
    """

    def test_bare_declaration_is_the_failing_control(self) -> None:
        self.write(GD_MASKING, comment_fixture(masked=False))
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("fake_in_comment params 6 > 5", " ".join(payload["violations"]))

    def test_func_in_a_comment_is_ignored(self) -> None:
        self.write(GD_MASKING, comment_fixture(masked=True))
        self.assert_clean(*self.run_gate())
        self.assertNotIn("fake_in_comment", self.markdown())

    def test_bare_declaration_is_the_failing_control_for_strings(self) -> None:
        self.write(GD_MASKING, string_fixture(masked=False))
        code, payload = self.run_gate()
        self.assertEqual(code, 1)
        self.assertIn("fake_in_string params 6 > 5", " ".join(payload["violations"]))

    def test_func_in_a_multiline_string_is_ignored(self) -> None:
        self.write(GD_MASKING, string_fixture(masked=True))
        self.assert_clean(*self.run_gate())
        self.assertNotIn("fake_in_string", self.markdown())


class Discovery(GateCase):
    """`.gd` is in scope by default and through both discovery back-ends."""

    def test_gd_files_are_scanned_without_any_configuration(self) -> None:
        self.write(GD_SOURCE, gdscript_function(121))
        code, payload = self.run_gate()
        self.assertEqual(payload["files_scanned"], 1)
        self.assertEqual(code, 1)

    def test_policy_include_extensions_narrow_the_scan(self) -> None:
        self.write(POLICY_FILENAME, json.dumps({"loc": {"include_extensions": [".gd"]}}))
        self.write(GD_SOURCE, gdscript_function(120))
        self.write("tooling/long.py", "def sized() -> None:\n" + "    pass\n" * 200)
        code, payload = self.run_gate()
        self.assertEqual(payload["files_scanned"], 1)
        self.assert_clean(code, payload)

    def test_git_discovery_finds_gd_files(self) -> None:
        if shutil.which("git") is None:
            self.skipTest("git is not installed")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, capture_output=True)
        self.write(GD_SOURCE, gdscript_function(121))
        code, payload = self.run_gate(use_git=True)
        self.assertEqual(payload["files_scanned"], 1)
        self.assertEqual(code, 1)


class ScanIntegrity(GateCase):
    """An incomplete scan is exit 2, never PASS."""

    def test_oversized_file_is_a_scan_issue_and_exits_two(self) -> None:
        self.write(GD_SOURCE, gdscript_function(10))
        code, payload = self.run_gate("--max-file-bytes", "10")
        self.assertEqual(payload["violations"], [])
        self.assertEqual(len(payload["scan_issues"]), 1)
        self.assertIn("exceeds 10 bytes", payload["scan_issues"][0])
        self.assertEqual(code, 2)
        self.assertIn("Status: **ERROR**", self.markdown())

    def test_allow_scan_errors_is_the_only_way_past_a_scan_issue(self) -> None:
        self.write(GD_SOURCE, gdscript_function(10))
        code, payload = self.run_gate("--max-file-bytes", "10", "--allow-scan-errors")
        self.assertEqual(len(payload["scan_issues"]), 1)
        self.assertEqual(code, 0)

    def test_unparseable_python_is_a_scan_issue_not_a_pass(self) -> None:
        self.write(GD_SOURCE, gdscript_function(10))
        self.write("tooling/broken.py", "def broken(:\n    pass\n")
        code, payload = self.run_gate()
        self.assertEqual(payload["violations"], [])
        self.assertEqual(len(payload["scan_issues"]), 1)
        self.assertIn("Python parse error", payload["scan_issues"][0])
        self.assertEqual(code, 2)

    def test_non_positive_limits_are_rejected(self) -> None:
        self.write(GD_SOURCE, gdscript_function(10))
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = loc_gate.main(["--project-root", str(self.root), "--quiet",
                                  "--no-git", "--max-function-lines", "0"])
        self.assertEqual(code, 2)
        self.assertIn("limits must be positive", stderr.getvalue())


class OtherLanguagesStillMeasured(GateCase):
    """Adding GDScript must not disturb the Python or brace strategies."""

    def test_python_function_limit_is_still_enforced(self) -> None:
        self.write("tooling/sized.py", "def sized() -> None:\n" + "    pass\n" * 120)
        code, payload = self.run_gate()
        self.assert_only_violation(payload, "tooling/sized.py:1: sized LOC 121 > 120 (lines 1-121)")
        self.assertEqual(code, 1)

    def test_python_function_of_120_lines_passes(self) -> None:
        self.write("tooling/sized.py", "def sized() -> None:\n" + "    pass\n" * 119)
        self.assert_clean(*self.run_gate())

    def test_brace_language_function_limit_is_still_enforced(self) -> None:
        body = "\n".join(f"  const step_{index} = {index};" for index in range(119))
        self.write("web/sized.ts", f"export function sized(): void {{\n{body}\n}}\n")
        code, payload = self.run_gate()
        self.assert_only_violation(payload, "web/sized.ts:1: sized LOC 121 > 120 (lines 1-121)")
        self.assertEqual(code, 1)


class CanonicalCli(unittest.TestCase):
    """The verification chain depends on these exact flag names."""

    def test_every_canonical_flag_is_accepted(self) -> None:
        args = loc_gate.build_parser().parse_args([
            "--project-root", ".", "--config", "c.json", "--max-file-lines", "450",
            "--max-function-lines", "120", "--max-parameters", "5", "--max-file-bytes", "10",
            "--include-extension", "gd", "--exclude-glob", "a/**", "--frontier-glob", "b/**",
            "--no-git", "--allow-scan-errors", "--output", "o.md", "--json-output", "o.json", "--quiet",
        ])
        self.assertEqual(args.max_file_lines, 450)
        self.assertEqual(args.max_function_lines, 120)
        self.assertEqual(args.max_parameters, 5)
        self.assertEqual(args.include_extension, [".gd"])
        self.assertEqual(args.frontier_glob, ["b/**"])
        self.assertTrue(args.no_git and args.allow_scan_errors and args.quiet)


if __name__ == "__main__":
    unittest.main()
