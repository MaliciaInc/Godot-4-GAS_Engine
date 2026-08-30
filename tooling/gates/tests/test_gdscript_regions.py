#!/usr/bin/env python3
"""Behaviour of GDScript region extraction used by the LOC, duplication and test-location gates."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import gdscript_regions  # noqa: E402


def build_function(body_lines: int, name: str = "sized") -> str:
    """A function whose total measured LOC is `body_lines` + 1 signature line."""
    body = "\n".join(f"\tvar step_{index}: int = {index}" for index in range(body_lines))
    return f"func {name}() -> void:\n{body}\n"


class FunctionDiscovery(unittest.TestCase):
    def test_plain_function_is_found(self) -> None:
        regions = gdscript_regions.extract_functions("func ready() -> void:\n\tpass\n")
        self.assertEqual([region.name for region in regions], ["ready"])

    def test_static_function_is_found(self) -> None:
        regions = gdscript_regions.extract_functions("static func helper() -> int:\n\treturn 1\n")
        self.assertEqual([region.name for region in regions], ["helper"])

    def test_underscored_virtual_override_is_found(self) -> None:
        regions = gdscript_regions.extract_functions("func _process(delta: float) -> void:\n\tpass\n")
        self.assertEqual([region.name for region in regions], ["_process"])

    def test_function_inside_a_comment_is_ignored(self) -> None:
        source = "# func commented_out() -> void:\nfunc real() -> void:\n\tpass\n"
        self.assertEqual([region.name for region in gdscript_regions.extract_functions(source)], ["real"])

    def test_function_inside_a_triple_quoted_block_is_ignored(self) -> None:
        source = 'var doc = """\nfunc fake_in_string() -> void:\n\tpass\n"""\nfunc real() -> void:\n\tpass\n'
        self.assertEqual([region.name for region in gdscript_regions.extract_functions(source)], ["real"])

    def test_empty_source_yields_no_regions(self) -> None:
        self.assertEqual(gdscript_regions.extract_functions(""), [])


class FunctionMeasurement(unittest.TestCase):
    def test_signature_plus_body_is_measured(self) -> None:
        region = gdscript_regions.extract_functions("func f() -> void:\n\tvar a: int = 1\n\tvar b: int = 2\n")[0]
        self.assertEqual(region.start_line, 1)
        self.assertEqual(region.end_line, 3)
        self.assertEqual(region.line_count, 3)

    def test_trailing_blank_lines_are_not_billed_to_the_function(self) -> None:
        region = gdscript_regions.extract_functions("func f() -> void:\n\tpass\n\n\n")[0]
        self.assertEqual(region.line_count, 2)

    def test_next_declaration_ends_the_previous_body(self) -> None:
        source = "func first() -> void:\n\tpass\nfunc second() -> void:\n\tpass\n"
        regions = gdscript_regions.extract_functions(source)
        self.assertEqual(regions[0].end_line, 2)
        self.assertEqual(regions[1].start_line, 3)

    def test_blank_line_inside_a_body_does_not_end_it(self) -> None:
        source = "func f() -> void:\n\tvar a: int = 1\n\n\tvar b: int = 2\n"
        self.assertEqual(gdscript_regions.extract_functions(source)[0].end_line, 4)

    def test_function_of_one_hundred_nineteen_body_lines_measures_one_hundred_twenty(self) -> None:
        region = gdscript_regions.extract_functions(build_function(119))[0]
        self.assertEqual(region.line_count, 120)

    def test_function_of_one_hundred_twenty_body_lines_measures_one_hundred_twenty_one(self) -> None:
        region = gdscript_regions.extract_functions(build_function(120))[0]
        self.assertEqual(region.line_count, 121)

    def test_space_indented_body_is_measured_like_a_tab_indented_one(self) -> None:
        source = "func f() -> void:\n    var a: int = 1\n    var b: int = 2\n"
        self.assertEqual(gdscript_regions.extract_functions(source)[0].line_count, 3)


class MultilineSignatures(unittest.TestCase):
    def test_signature_split_across_lines_is_one_region(self) -> None:
        source = (
            "func long(\n"
            "\t\tfirst: int,\n"
            "\t\tsecond: int) -> void:\n"
            "\tpass\n"
        )
        regions = gdscript_regions.extract_functions(source)
        self.assertEqual(len(regions), 1)
        self.assertEqual(regions[0].start_line, 1)
        self.assertEqual(regions[0].end_line, 4)

    def test_parameters_in_a_multiline_signature_are_counted(self) -> None:
        source = "func long(\n\t\tfirst: int,\n\t\tsecond: int) -> void:\n\tpass\n"
        self.assertEqual(gdscript_regions.extract_functions(source)[0].parameter_count, 2)


class ParameterCounting(unittest.TestCase):
    def test_no_parameters_counts_zero(self) -> None:
        self.assertEqual(gdscript_regions.extract_functions("func f() -> void:\n\tpass\n")[0].parameter_count, 0)

    def test_single_parameter_counts_one(self) -> None:
        self.assertEqual(gdscript_regions.extract_functions("func f(a: int) -> void:\n\tpass\n")[0].parameter_count, 1)

    def test_default_value_with_a_comma_inside_a_call_counts_once(self) -> None:
        source = "func f(a: Vector2 = Vector2(0, 0), b: int = 1) -> void:\n\tpass\n"
        self.assertEqual(gdscript_regions.extract_functions(source)[0].parameter_count, 2)

    def test_string_default_containing_a_comma_counts_once(self) -> None:
        source = 'func f(label: String = "a,b") -> void:\n\tpass\n'
        self.assertEqual(gdscript_regions.extract_functions(source)[0].parameter_count, 1)

    def test_typed_array_default_counts_once(self) -> None:
        source = "func f(items: Array[int] = []) -> void:\n\tpass\n"
        self.assertEqual(gdscript_regions.extract_functions(source)[0].parameter_count, 1)


class InnerClassScope(unittest.TestCase):
    SOURCE = (
        "class Inner:\n"
        "\tfunc method() -> void:\n"
        "\t\tpass\n"
        "\n"
        "func outer() -> void:\n"
        "\tpass\n"
    )

    def test_inner_method_is_measured(self) -> None:
        regions = gdscript_regions.extract_functions(self.SOURCE)
        method = next(region for region in regions if region.name == "method")
        self.assertEqual(method.line_count, 2)

    def test_inner_method_is_qualified_by_its_class(self) -> None:
        regions = gdscript_regions.extract_functions(self.SOURCE)
        method = next(region for region in regions if region.name == "method")
        self.assertEqual(method.qualified_name, "Inner.method")

    def test_file_scope_function_is_not_qualified(self) -> None:
        regions = gdscript_regions.extract_functions(self.SOURCE)
        outer = next(region for region in regions if region.name == "outer")
        self.assertEqual(outer.qualified_name, "outer")

    def test_identical_names_in_different_classes_stay_distinct(self) -> None:
        source = (
            "class A:\n\tfunc run() -> void:\n\t\tpass\n"
            "class B:\n\tfunc run() -> void:\n\t\tpass\n"
        )
        qualified = sorted(region.qualified_name for region in gdscript_regions.extract_functions(source))
        self.assertEqual(qualified, ["A.run", "B.run"])


class TestFunctionHelpers(unittest.TestCase):
    def test_gut_style_test_function_is_detected(self) -> None:
        self.assertTrue(gdscript_regions.has_test_functions("func test_damage_is_clamped() -> void:\n\tpass\n"))

    def test_fixture_without_test_functions_is_not_detected(self) -> None:
        self.assertFalse(gdscript_regions.has_test_functions("func build_asc() -> Node:\n\treturn null\n"))

    def test_collect_test_functions_reports_name_and_line(self) -> None:
        source = "func helper() -> void:\n\tpass\nfunc test_alpha() -> void:\n\tpass\n"
        self.assertEqual(gdscript_regions.collect_test_functions(source), [("test_alpha", 3)])


class SourceSlicing(unittest.TestCase):
    def test_function_source_returns_exactly_its_lines(self) -> None:
        source = "var before: int = 0\nfunc f() -> void:\n\tpass\nvar after: int = 1\n"
        region = gdscript_regions.extract_functions(source)[0]
        self.assertEqual(gdscript_regions.function_source(source, region), "func f() -> void:\n\tpass")


if __name__ == "__main__":
    unittest.main()
