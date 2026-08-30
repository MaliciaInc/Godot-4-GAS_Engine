#!/usr/bin/env python3
"""Indentation-based region extraction for GDScript.

GDScript delimits bodies by indentation, not braces, so the brace matcher the
gates use for C-like languages cannot measure a `.gd` function. This module
finds functions and inner classes the way the language actually nests them.

Everything here operates on masked source (see `gdscript_lexing.mask_source`)
so a `func` written inside a comment or a triple-quoted block is invisible,
while line numbers still refer to the original file.
"""
from __future__ import annotations

import dataclasses
import re

from . import gdscript_lexing

#: `func name(` and `static func name(`, anchored to the start of a line.
FUNCTION_PATTERN = re.compile(r"(?m)^(?P<leading>[ \t]*)(?:static[ \t]+)?func[ \t]+(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*\(")

#: An inner `class Name:` or `class Name extends Base:` declaration.
CLASS_PATTERN = re.compile(r"(?m)^(?P<leading>[ \t]*)class[ \t]+(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*(?:extends[ \t]+[A-Za-z_][A-Za-z0-9_.]*)?[ \t]*:")

#: Width a tab expands to when comparing indentation depth.
TAB_WIDTH = 4

#: Capture-group names shared with the other extractors. The convention is
#: real, so it is written once rather than retyped at every match site.
NAME_GROUP = "name"
LEADING_GROUP = "leading"

#: The prefix GUT uses to recognize a test method. Single owner: the
#: test-location gate reads it from here.
TEST_FUNCTION_PREFIX = "test_"

OPENING_BRACKETS = "([{"
CLOSING_BRACKETS = ")]}"


@dataclasses.dataclass(frozen=True, slots=True)
class FunctionRegion:
    """One GDScript function, measured from its `func` line to its last body line."""

    name: str
    scope: str
    start_line: int
    end_line: int
    parameter_count: int

    @property
    def line_count(self) -> int:
        return self.end_line - self.start_line + 1

    @property
    def qualified_name(self) -> str:
        """`Inner.method` inside a nested class, plain `method` at file scope."""
        return f"{self.scope}.{self.name}" if self.scope else self.name


def indent_width(line: str) -> int:
    """Visual indentation width, expanding tabs so mixed files still compare."""
    width = 0
    for char in line:
        if char == " ":
            width += 1
        elif char == "\t":
            width += TAB_WIDTH - (width % TAB_WIDTH)
        else:
            break
    return width


def is_blank(line: str) -> bool:
    """True for an empty or whitespace-only line."""
    return not line.strip()


def _line_index_of(text: str, offset: int) -> int:
    """0-indexed line containing `offset`."""
    return text.count("\n", 0, offset)


def _signature_end_line(masked_lines: list[str], start_index: int) -> int:
    """Index of the line holding the `:` that closes a possibly multi-line signature.

    Bracket depth is tracked across lines so a signature split over several
    lines is measured as one unit. Falls back to the opening line when the
    signature never closes, so a malformed file cannot consume the rest of the
    document.
    """
    depth = 0
    opened = False
    for index in range(start_index, len(masked_lines)):
        for char in masked_lines[index]:
            if char in OPENING_BRACKETS:
                depth += 1
                opened = True
            elif char in CLOSING_BRACKETS and depth:
                depth -= 1
        if opened and depth == 0:
            return index
    return start_index


def _body_end_line(masked_lines: list[str], signature_index: int, declaration_indent: int) -> int:
    """Index of the last line belonging to this body.

    A body line is any non-blank line indented deeper than the declaration.
    Trailing blank lines are excluded so they are not billed to the function.
    """
    last = signature_index
    for index in range(signature_index + 1, len(masked_lines)):
        line = masked_lines[index]
        if is_blank(line):
            continue
        if indent_width(line) <= declaration_indent:
            break
        last = index
    return last


def count_parameters(masked_lines: list[str], start_index: int, end_index: int, open_offset: int) -> int:
    """Count top-level parameters in a signature spanning one or more lines."""
    segment = "\n".join(masked_lines[start_index:end_index + 1])
    opening = segment.find("(", open_offset)
    if opening < 0:
        return 0
    depth = 0
    count = 0
    seen_content = False
    for char in segment[opening:]:
        if char in OPENING_BRACKETS:
            depth += 1
            continue
        if char in CLOSING_BRACKETS:
            depth -= 1
            if depth == 0:
                break
            continue
        if depth == 1:
            if char == ",":
                count += 1
            elif not char.isspace():
                seen_content = True
    return count + 1 if seen_content else 0


def _class_scopes(masked: str, masked_lines: list[str]) -> list[tuple[int, int, str]]:
    """Return `(start_line_index, end_line_index, name)` for each inner class."""
    scopes: list[tuple[int, int, str]] = []
    for match in CLASS_PATTERN.finditer(masked):
        start_index = _line_index_of(masked, match.start())
        declaration_indent = indent_width(match.group(LEADING_GROUP))
        end_index = _body_end_line(masked_lines, start_index, declaration_indent)
        scopes.append((start_index, end_index, match.group(NAME_GROUP)))
    return scopes


def _scope_for(scopes: list[tuple[int, int, str]], line_index: int) -> str:
    """Innermost class name containing `line_index`, or an empty string."""
    best = ""
    best_start = -1
    for start_index, end_index, name in scopes:
        if start_index < line_index <= end_index and start_index > best_start:
            best = name
            best_start = start_index
    return best


def extract_functions(text: str) -> list[FunctionRegion]:
    """Extract every GDScript function, including methods of inner classes.

    Functions declared inside comments or string literals are ignored because
    the scan runs over masked source. Line numbers refer to the original text.
    """
    if not text:
        return []
    masked = gdscript_lexing.mask_source(text)
    masked_lines = masked.splitlines()
    if not masked_lines:
        return []
    scopes = _class_scopes(masked, masked_lines)
    found: list[FunctionRegion] = []
    for match in FUNCTION_PATTERN.finditer(masked):
        start_index = _line_index_of(masked, match.start())
        if start_index >= len(masked_lines):
            continue
        declaration_indent = indent_width(match.group(LEADING_GROUP))
        signature_index = _signature_end_line(masked_lines, start_index)
        end_index = _body_end_line(masked_lines, signature_index, declaration_indent)
        line_start_offset = match.start() - sum(
            len(masked_lines[index]) + 1 for index in range(start_index)
        )
        found.append(
            FunctionRegion(
                name=match.group(NAME_GROUP),
                scope=_scope_for(scopes, start_index),
                start_line=start_index + 1,
                end_line=end_index + 1,
                parameter_count=count_parameters(
                    masked_lines, start_index, signature_index, max(line_start_offset, 0)
                ),
            )
        )
    return sorted(found, key=lambda item: (item.start_line, item.qualified_name))


def function_source(text: str, region: FunctionRegion) -> str:
    """Return the original source lines of one function, inclusive of both ends."""
    lines = text.splitlines()
    return "\n".join(lines[region.start_line - 1:region.end_line])


def has_test_functions(text: str) -> bool:
    """True when the file declares at least one GUT-style `test_*` function."""
    return any(region.name.startswith(TEST_FUNCTION_PREFIX) for region in extract_functions(text))


def collect_test_functions(text: str) -> list[tuple[str, int]]:
    """Return `(name, line)` for every `test_*` function declared in the file.

    Deliberately not named `test_*`: this is production code, and any Python
    function whose name starts with `test_` is what a collector picks up as a
    test. The test-location gate flags exactly that, and it flagged this
    function when it was called `test_function_lines`.
    """
    return [
        (region.name, region.start_line)
        for region in extract_functions(text)
        if region.name.startswith(TEST_FUNCTION_PREFIX)
    ]
