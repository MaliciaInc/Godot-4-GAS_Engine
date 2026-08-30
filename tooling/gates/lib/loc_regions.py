#!/usr/bin/env python3
"""Finding and measuring functions, in every language the LOC gate reads.

Three front ends, chosen by how a language delimits a body: Python by its own
parser, GDScript by indentation, and everything C-like by matching braces. A
language with no reliable extractor is deliberately not measured rather than
measured wrongly.

Split out of loc-gate.py when the gate reported ITSELF over its own 450-line
limit after the parameter allowlist was added. The limit applies to the gate
like it applies to anything else, and the seam is a real responsibility
boundary rather than a cut made to fit.
"""
from __future__ import annotations

import ast
import dataclasses
import re
from pathlib import Path

from . import gate_io, gdscript_regions, languages
from .gate_io import GateError

#: Which measurement path a file takes. All four sets come from the one
#: language catalog, so a language added there cannot land in the wrong path
#: here by omission.
PYTHON_SUFFIXES = languages.PYTHON_EXTENSIONS
GDSCRIPT_SUFFIXES = languages.GDSCRIPT_EXTENSIONS
UNMEASURED_SUFFIXES = languages.UNMEASURED_EXTENSIONS
BRACE_SUFFIXES = languages.BRACE_EXTENSIONS

#: Names the declaration patterns can capture that are not declarations.
#: The control words come from the shared catalog; the rest are the test
#: callbacks and Python's context manager, which are this layer's own.
NON_DECLARATION_NAMES = frozenset({"with", "describe", "it", "test"})
CONTROL_NAMES = languages.CONTROL_KEYWORDS | NON_DECLARATION_NAMES

DECLARATION = re.compile(
    r"(?m)^[ \t]*(?:(?:export|default|public|private|protected|internal|static|final|async|"
    r"virtual|override|abstract|inline|open|suspend|unsafe|const|extern|pub(?:\([^)]*\))?)[ \t]+)*"
    r"(?:(?:function|fn|func)[ \t]+)?(?!pub[ \t]*\()(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)[ \t]*"
    r"(?:<[^{};\n]*>)?[ \t]*\((?P<params>[^;{}]*)\)[^{;\n]*(?<!=>)[ \t]*\{"
)
ARROW = re.compile(
    r"(?m)^[ \t]*(?:export[ \t]+)?(?:const|let|var)[ \t]+(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)"
    r"[ \t]*(?::[^=\n]+)?=[ \t]*(?:async[ \t]+)?(?:\((?P<params>[^;{}]*)\)|(?P<single>[A-Za-z_$][A-Za-z0-9_$]*))"
    r"[ \t]*(?::[^=\n]+)?=>[ \t]*\{"
)
#: Names the declaration patterns can capture that are not declarations.
#: The control words come from the shared catalog; the rest are the test
#: callbacks and Python's context manager, which are this gate's own.


@dataclasses.dataclass(frozen=True, slots=True)
class FunctionRegion:
    """One measured function. `name` is the bare identifier the policy allowlist
    matches; `label` is what the report prints, and for a GDScript inner-class
    method it is `Class.method` so same-named methods are never conflated."""

    name: str
    label: str
    start_line: int
    end_line: int
    parameter_count: int

    @property
    def line_count(self) -> int:
        return self.end_line - self.start_line + 1


def count_parameters(text: str) -> int:
    """Count top-level parameters in a brace-language parameter list."""
    text = text.strip()
    if not text:
        return 0
    if text.endswith(","):
        text = text[:-1]
    depth, count, quote, escaped = 0, 1, None, False
    for char in text:
        if quote:
            if escaped: escaped = False
            elif char == "\\": escaped = True
            elif char == quote: quote = None
        elif char in "'\"`": quote = char
        elif char in "([{<": depth += 1
        elif char in ")]}>" and depth: depth -= 1
        elif char == "," and depth == 0: count += 1
    return count


def matching_brace(text: str, opening: int) -> int | None:
    """Index of the `}` closing the `{` at `opening`, skipping strings and comments."""
    depth, quote, escaped, i = 0, None, False, opening
    while i < len(text):
        char, pair = text[i], text[i:i + 2]
        if quote:
            if escaped: escaped = False
            elif char == "\\": escaped = True
            elif char == quote: quote = None
        elif pair == "//":
            newline = text.find("\n", i + 2)
            i = len(text) if newline < 0 else newline
        elif pair == "/*":
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 1
        elif char in "'\"`": quote = char
        elif char == "{": depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def python_functions(relative: str, text: str) -> list[FunctionRegion]:
    """Measure Python with `ast`, which already knows every body's end line."""
    try:
        tree = ast.parse(text)
    except SyntaxError as exc:
        raise gate_io.python_parse_error(f"{relative}:{exc.lineno}", exc) from exc
    except ValueError as exc:
        raise GateError(f"{relative}: Python source rejected: {exc}") from exc
    found: list[FunctionRegion] = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        spec = node.args
        count = (len(spec.posonlyargs) + len(spec.args) + len(spec.kwonlyargs)
                 + int(spec.vararg is not None) + int(spec.kwarg is not None))
        found.append(FunctionRegion(node.name, node.name, node.lineno, node.end_lineno or node.lineno, count))
    return sorted(found, key=lambda item: (item.start_line, item.label))


def gdscript_functions(text: str) -> list[FunctionRegion]:
    """Measure GDScript by indentation, through the shared region extractor.

    It runs over masked source, so a `func` inside a `#` comment or a
    triple-quoted block is invisible; it follows a signature across as many
    lines as its parentheses span; and it ends a body at the first non-blank
    line indented no deeper than the `func` keyword.
    """
    return [
        FunctionRegion(item.name, item.qualified_name, item.start_line, item.end_line, item.parameter_count)
        for item in gdscript_regions.extract_functions(text)
    ]


def brace_functions(text: str) -> list[FunctionRegion]:
    """Measure a brace language by matching the declaration's opening brace."""
    found: list[FunctionRegion] = []
    for pattern in (DECLARATION, ARROW):
        for match in pattern.finditer(text):
            name = match.group(gdscript_regions.NAME_GROUP)
            if name in CONTROL_NAMES:
                continue
            opening = text.find("{", match.start(), match.end() + 1)
            if pattern is DECLARATION and opening >= 0 and "=>" in text[match.start():opening]:
                continue
            closing = matching_brace(text, opening) if opening >= 0 else None
            if closing is None:
                continue
            params = match.groupdict().get("params") or match.groupdict().get("single") or ""
            start = text.count("\n", 0, match.start()) + 1
            end = text.count("\n", 0, closing) + 1
            found.append(FunctionRegion(name, name, start, end, count_parameters(params)))
    unique = {(item.name, item.start_line, item.end_line): item for item in found}
    return sorted(unique.values(), key=lambda item: (item.start_line, item.label))


def extract_functions(relative: str, text: str) -> list[FunctionRegion]:
    """Dispatch to the measuring strategy that matches this file's extension."""
    suffix = Path(relative).suffix.lower()
    if suffix in PYTHON_SUFFIXES:
        return python_functions(relative, text)
    if suffix in GDSCRIPT_SUFFIXES:
        return gdscript_functions(text)
    if suffix in BRACE_SUFFIXES:
        return brace_functions(text)
    return []
