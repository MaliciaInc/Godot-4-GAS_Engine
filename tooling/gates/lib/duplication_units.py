#!/usr/bin/env python3
"""Comparable-unit extraction for the duplication gate.

The gate compares *units*. A unit is one function, measured the way its source
language actually delimits a body. Three families are handled here:

    GDScript   indentation-delimited, via `gdscript_regions`
    Python     the `ast` module
    C-like     a declaration regex plus a quote-aware brace matcher

GDScript is the reason this module exists. A `.gd` body closes by dedent, so
the brace matcher can never find its end, and `#` comments plus the prefixed
literals `&"..."` / `^"..."` / `r"..."` are invisible to the C-like
comment/string regexes. A GDScript unit is named by its
`FunctionRegion.qualified_name`, so `Alpha.run` and `Beta.run` remain two
distinct units belonging to two different inner classes instead of collapsing
into one ambiguous `run`.

Nothing here reads the filesystem beyond one `read_text`, and nothing here
decides policy. Thresholds arrive as `ExtractionOptions`; the gate owns them.
"""
from __future__ import annotations

import ast
import dataclasses
import enum
import hashlib
import re
from collections import Counter
from pathlib import Path

from . import gdscript_lexing, gdscript_regions, languages
from . import gate_io
from .gate_io import GateError, python_parse_error

GDSCRIPT = languages.GDSCRIPT
GDSCRIPT_SUFFIXES = languages.GDSCRIPT_EXTENSIONS
PYTHON_SUFFIXES = languages.PYTHON_EXTENSIONS
WHOLE_FILE = "<file>"
STRING_TOKEN = " STR "
BLANK = " "
PUNCTUATION = "{}()[];,.:@"

TOKEN = re.compile(
    r"::|->|=>|===|!==|==|!=|<=|>=|&&|\|\||\?\?|\?\.|\+=|-=|\*=|/=|"
    r"[A-Za-z_$][A-Za-z0-9_$]*|\d+(?:\.\d+)?|[{}()\[\];,.:+\-*/%<>=!&|?@]"
)
IDENTIFIER = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
STRING = re.compile(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"|`(?:\\.|[^`\\])*`", re.DOTALL)
COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/|#[^\n]*", re.DOTALL)
DECLARATION = re.compile(
    r"(?m)^[ \t]*(?:(?:export|default|public|private|protected|internal|static|final|async|"
    r"virtual|override|abstract|inline|open|suspend|unsafe|const|extern|pub(?:\([^)]*\))?)[ \t]+)*"
    r"(?:(?:function|fn|func)[ \t]+)?(?!pub[ \t]*\()(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)[ \t]*"
    r"(?:<[^{};\n]*>)?[ \t]*\([^;{}]*\)[^{;\n]*(?<!=>)[ \t]*\{"
)
ARROW = re.compile(
    r"(?m)^[ \t]*(?:export[ \t]+)?(?:const|let|var)[ \t]+(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)"
    r"[^=\n]*=[ \t]*(?:async[ \t]+)?(?:\([^;{}]*\)|\w+)[ \t]*(?::[^=\n]+)?=>[ \t]*\{"
)

#: The same 22 control words were written out twice here, once to build
#: KEYWORDS and again to intersect it back down. Both come from the shared
#: catalog now, and the intersection is unnecessary.
CONTROL = languages.CONTROL_KEYWORDS
KEYWORDS = CONTROL | languages.DECLARATION_KEYWORDS
OPERATORS = frozenset({
    "+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=", "&&", "||", "?", "!",
    "=>", "->", "=", "+=", "-=", "*=", "/=", "??", "?.",
})

#: GDScript spells several operators as words, and several structural keywords
#: (`func`, `extends`, `signal`) have no equivalent in the C-like set.
GDSCRIPT_WORD_OPERATORS = frozenset({"and", "or", "not", "in", "is", "as"})
GDSCRIPT_KEYWORDS = KEYWORDS | GDSCRIPT_WORD_OPERATORS | frozenset({
    "func", "static", "extends", "class_name", "signal", "pass", "self", "super",
    "assert", "void", "when", "preload", "onready", "tool", "setget", "breakpoint",
})
GDSCRIPT_CONTROL = CONTROL | frozenset({"pass", "assert"})
GDSCRIPT_OPERATORS = OPERATORS | GDSCRIPT_WORD_OPERATORS


class Category(str, enum.Enum):
    """Why a unit exists. Only `EXECUTABLE` duplication can block a build."""

    EXECUTABLE = "executable"
    FIXTURE_DATA = "fixture_data"
    DECLARATIVE_I18N = "declarative_i18n"
    DECLARATIVE_SVG = "declarative_svg"
    DECLARATIVE_THEME = "declarative_theme"
    FALSE_POSITIVE_SHAPE = "false_positive_shape"


@dataclasses.dataclass(frozen=True, slots=True)
class Dialect:
    """The three vocabularies token normalization needs, per language family."""

    keywords: frozenset[str]
    control: frozenset[str]
    operators: frozenset[str]
    indentation_scoped: bool = False


DEFAULT_DIALECT = Dialect(KEYWORDS, CONTROL, OPERATORS)
GDSCRIPT_DIALECT = Dialect(GDSCRIPT_KEYWORDS, GDSCRIPT_CONTROL, GDSCRIPT_OPERATORS, True)


@dataclasses.dataclass(frozen=True, slots=True)
class Unit:
    """One comparable region of source, reduced to shape, shingles and vocabulary."""

    path: str
    language: str
    name: str
    start: int
    end: int
    normalized: tuple[str, ...]
    shingles: frozenset[str]
    behavior: Counter[str]
    category: Category
    identifiers: frozenset[str]

    @property
    def ref(self) -> str:
        return f"{self.path}:{self.start}-{self.end}:{self.name}"


@dataclasses.dataclass(frozen=True, slots=True)
class ExtractionOptions:
    """Everything extraction needs from the gate's configuration, as one value."""

    root: Path
    min_lines: int = 8
    min_tokens: int = 35
    shingle_size: int = 5
    fallback_blocks: bool = True


#: `(name, start_line, end_line, source)` for one candidate unit.
Region = tuple[str, int, int, str]


def language(path: Path) -> str:
    """Language label used to keep unrelated file types from being compared.

    Read from the shared catalog rather than re-derived here. The local
    version fell back to the bare suffix, so `.rs` was `rs` to this gate and
    `rust` to the test-location gate.
    """
    return languages.language_for(path.suffix)


def dialect_for(lang: str) -> Dialect:
    """Select the token vocabulary for a language label."""
    return GDSCRIPT_DIALECT if lang == GDSCRIPT else DEFAULT_DIALECT


def _gdscript_stripped(text: str, placeholder: str) -> str:
    """Drop GDScript comments and swap every literal for `placeholder`."""
    pieces: list[str] = []
    cursor = 0
    for kind, start, end, _prefix in gdscript_lexing.iter_tokens(text):
        pieces.append(text[cursor:start])
        pieces.append(placeholder if kind == gdscript_lexing.STRING else BLANK)
        cursor = end
    pieces.append(text[cursor:])
    return "".join(pieces)


def stripped(dialect: Dialect, body: str, placeholder: str) -> str:
    """Body with comments removed and string literals replaced by `placeholder`.

    Literal *contents* never reach the comparison: a copy that only edits the
    text inside a quote is still a copy, and a `func` written inside a comment
    is not code at all.
    """
    if dialect.indentation_scoped:
        return _gdscript_stripped(body, placeholder)
    return COMMENT.sub(BLANK, STRING.sub(placeholder, body))


def tokenize(dialect: Dialect, body: str) -> list[str]:
    """Reduce a body to its shape: keywords and punctuation kept, names erased."""
    normalized: list[str] = []
    for token in TOKEN.findall(stripped(dialect, body, STRING_TOKEN)):
        if token in dialect.keywords or token in dialect.operators or token in PUNCTUATION:
            normalized.append(token.lower())
        elif token[0].isdigit():
            normalized.append("NUM")
        else:
            normalized.append("ID")
    return normalized


def identifiers(dialect: Dialect, body: str) -> frozenset[str]:
    """Vocabulary of a unit: the names `tokenize` erases when it writes `ID`.

    Copy-paste keeps the names; two parallel domain tables that merely share a
    shape do not.
    """
    cleaned = stripped(dialect, body, BLANK)
    return frozenset(item for item in IDENTIFIER.findall(cleaned) if item not in dialect.keywords)


def brace_depth(tokens: list[str]) -> int:
    """Deepest brace nesting in a C-like body."""
    current = maximum = 0
    for token in tokens:
        if token == "{":
            current += 1
            maximum = max(maximum, current)
        elif token == "}":
            current = max(0, current - 1)
    return maximum


def indentation_depth(body: str) -> int:
    """Nesting levels of an indentation-delimited body, signature line excluded.

    GDScript has no braces to count, so nesting is the number of distinct
    indentation widths below the declaration.
    """
    widths = {gdscript_regions.indent_width(line) for line in body.splitlines() if line.strip()}
    return max(0, len(widths) - 1)


def structural_depth(dialect: Dialect, body: str, tokens: list[str]) -> int:
    """Nesting depth measured the way the language expresses nesting."""
    return indentation_depth(body) if dialect.indentation_scoped else brace_depth(tokens)


def behavior(dialect: Dialect, tokens: list[str], depth: int) -> Counter[str]:
    """Control-flow, operator and call profile: what a unit does, not how it reads."""
    result: Counter[str] = Counter()
    for index, token in enumerate(tokens):
        if token in dialect.control:
            result[f"control:{token}"] += 1
        elif token in dialect.operators:
            result[f"op:{token}"] += 1
        elif token == "ID" and index + 1 < len(tokens) and tokens[index + 1] == "(":
            result["call"] += 1
    result[f"depth:{depth}"] += 1
    return result


def matching_brace(text: str, opening: int) -> int | None:
    """Index of the `}` closing `text[opening]`, skipping strings and comments."""
    depth = 0
    quote: str | None = None
    escaped = False
    index = opening
    while index < len(text):
        char, pair = text[index], text[index:index + 2]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif pair == "//":
            newline = text.find("\n", index + 2)
            index = len(text) if newline < 0 else newline
        elif pair == "/*":
            end = text.find("*/", index + 2)
            index = len(text) if end < 0 else end + 1
        elif char in "'\"`":
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def python_regions(text: str) -> list[Region]:
    """Every `def` and `async def`, measured by the Python parser itself."""
    try:
        tree = ast.parse(text)
    except SyntaxError as exc:
        raise python_parse_error(f"line {exc.lineno}", exc) from exc
    lines = text.splitlines()
    found: list[Region] = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            end = node.end_lineno or node.lineno
            found.append((node.name, node.lineno, end, "\n".join(lines[node.lineno - 1:end])))
    return found


def gdscript_units(text: str) -> list[Region]:
    """Every GDScript function, including methods of inner classes.

    The name carried forward is the qualified one, so two inner classes that
    both declare `run()` stay separable in every report the gate writes.
    """
    return [
        (region.qualified_name, region.start_line, region.end_line,
         gdscript_regions.function_source(text, region))
        for region in gdscript_regions.extract_functions(text)
    ]


def brace_regions(text: str) -> list[Region]:
    """Functions of a C-like language, delimited by their outermost brace pair."""
    found: list[Region] = []
    for pattern in (DECLARATION, ARROW):
        for match in pattern.finditer(text):
            opening = text.find("{", match.start(), match.end() + 1)
            closing = matching_brace(text, opening) if opening >= 0 else None
            if closing is None:
                continue
            start = text.count("\n", 0, match.start()) + 1
            end = text.count("\n", 0, closing) + 1
            found.append((match.group(gdscript_regions.NAME_GROUP), start, end, text[match.start():closing + 1]))
    unique = {(name, start, end): body for name, start, end, body in found}
    return [(name, start, end, body) for (name, start, end), body in sorted(unique.items(), key=lambda item: item[0][1])]


def regions(path: Path, text: str) -> list[Region]:
    """Dispatch to the extractor that matches how this file delimits a body."""
    suffix = path.suffix.lower()
    if suffix in GDSCRIPT_SUFFIXES:
        return gdscript_units(text)
    if suffix in PYTHON_SUFFIXES:
        return python_regions(text)
    return brace_regions(text)


def unit_category(path: str, lang: str, body: str) -> Category:
    """Classify a unit so declarative look-alikes cannot block a build."""
    normalized = f"/{path.replace(chr(92), '/').lower()}/"
    if any(part in normalized for part in ("/fixtures/", "/fixture/", "/__fixtures__/")):
        return Category.FIXTURE_DATA
    if lang in {languages.TYPESCRIPT, languages.JAVASCRIPT}:
        executable = re.search(r"\b(?:function|if|for|while|switch|try|catch|await|return)\b|=>", body)
        if body.count("defineMessages") == 1 and re.search(r"\bdefineMessages\s*\(\s*\{", body) and not executable:
            return Category.DECLARATIVE_I18N
        if ("/components/icons/" in normalized
                and re.search(r"(?:return\s*\(?\s*<|=>\s*\(?\s*<)(?:svg|SvgIcon)\b", body)
                and not re.search(r"\b(?:use[A-Z]\w*|if|for|while|switch|try|catch|await|fetch|axios)\b", body)):
            return Category.DECLARATIVE_SVG
    if lang in {"css", "scss", "sass", "less"}:
        compact = body.lstrip()
        return Category.DECLARATIVE_THEME if compact.startswith(":root") or re.match(r"\.dark\b", compact) else Category.FALSE_POSITIVE_SHAPE
    return Category.EXECUTABLE


def finding_category(left: Unit, right: Unit) -> Category:
    """A pair is only as exempt as its weaker half."""
    return left.category if left.category is right.category else Category.EXECUTABLE


def make_unit(path: str, lang: str, region: Region, options: ExtractionOptions) -> Unit | None:
    """Build one comparable unit, or None when it is too small to mean anything."""
    name, start, end, body = region
    if end - start + 1 < options.min_lines:
        return None
    dialect = dialect_for(lang)
    tokens = tokenize(dialect, body)
    if len(tokens) < options.min_tokens:
        return None
    size = options.shingle_size
    shingles = frozenset(
        hashlib.sha1("\x1f".join(tokens[index:index + size]).encode()).hexdigest()[:16]
        for index in range(max(1, len(tokens) - size + 1))
    )
    depth = structural_depth(dialect, body, tokens)
    return Unit(
        path, lang, name, start, end, tuple(tokens), shingles,
        behavior(dialect, tokens, depth), unit_category(path, lang, body),
        identifiers(dialect, body),
    )


def extract_file(path: Path, options: ExtractionOptions) -> tuple[list[Unit], str | None]:
    """Extract every unit of one file, or return the scan issue that stopped it.

    The issue is returned rather than raised: the gate decides whether an
    unreadable or unparsable file is fatal, and it must never report PASS
    while any issue is outstanding.
    """
    relative = path.relative_to(options.root).as_posix()
    try:
        text = path.read_text(encoding=gate_io.SOURCE_ENCODING)
        found = regions(path, text)
    except (OSError, UnicodeError, GateError) as exc:
        return [], f"{relative}: {exc}"
    if not found and options.fallback_blocks:
        line_count = len(text.splitlines())
        if line_count >= options.min_lines:
            found = [(WHOLE_FILE, 1, line_count, text)]
    lang = language(path)
    units = [unit for region in found if (unit := make_unit(relative, lang, region, options)) is not None]
    return units, None
