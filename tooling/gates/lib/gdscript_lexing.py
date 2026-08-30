#!/usr/bin/env python3
"""GDScript lexical scanning for the quality gates.

GDScript is indentation-based like Python but has its own literal syntax:
`#` comments, single and double quotes, triple-quoted blocks, and the prefixed
forms `&"..."` (StringName), `^"..."` (NodePath) and `r"..."` (raw). A gate
that treats a `.gd` file as C-like or as Python will mis-detect all of them.

Two services are provided, both offset-preserving:

    mask_source()          code with literals and comments blanked out
    iter_string_literals()  every literal with its exact position

Offset preservation matters: masked text keeps the original length and the
original newline positions, so a caller can map any index back to a line
number using the masked or the original text interchangeably.
"""
from __future__ import annotations

import dataclasses
from typing import Iterator

#: Literal prefixes GDScript accepts before an opening quote.
#: `&` interns a StringName, `^` builds a NodePath, `r` disables escapes.
STRING_PREFIXES = frozenset({"&", "^", "r"})

#: Token kinds yielded by `iter_tokens`. Named because they cross a module
#: boundary: the duplication gate masks literals by testing `kind == STRING`,
#: so a rename here would silently stop that masking.
STRING, COMMENT = "string", "comment"

TRIPLE_QUOTES = ('"""', "'''")
SINGLE_QUOTES = ('"', "'")
COMMENT_CHAR = "#"
BLANK = " "


@dataclasses.dataclass(frozen=True, slots=True)
class StringLiteral:
    """One GDScript string literal and where it was found.

    `value` is the raw text between the quotes, escapes untouched. `prefix` is
    the empty string for a plain literal, or one of `&`, `^`, `r`.
    """

    value: str
    prefix: str
    line: int
    column: int
    start: int
    end: int

    @property
    def is_string_name(self) -> bool:
        return self.prefix == "&"

    @property
    def is_node_path(self) -> bool:
        return self.prefix == "^"


def _blank_run(text: str, start: int, end: int) -> str:
    """Return `end - start` characters of filler, keeping newlines in place."""
    return "".join("\n" if char == "\n" else BLANK for char in text[start:end])


def _quote_at(text: str, index: int) -> str | None:
    """Return the quote token opening at `index`, longest first, or None."""
    for quote in TRIPLE_QUOTES:
        if text.startswith(quote, index):
            return quote
    for quote in SINGLE_QUOTES:
        if text.startswith(quote, index):
            return quote
    return None


def _prefix_at(text: str, index: int) -> tuple[str, int]:
    """Detect a literal prefix immediately before a quote.

    Returns the prefix and the index where the quote itself starts. A prefix
    character only counts when it is not part of a longer identifier, so
    `var_r = 1` and `a & "x"` are not mistaken for prefixed literals.
    """
    char = text[index]
    if char not in STRING_PREFIXES:
        return "", index
    if _quote_at(text, index + 1) is None:
        return "", index
    if char == "r" and index > 0:
        previous = text[index - 1]
        if previous.isalnum() or previous == "_":
            return "", index
    return char, index + 1


def _scan_string(text: str, quote_start: int, quote: str, raw: bool) -> int:
    """Return the index just past the closing quote, or len(text) if unterminated."""
    index = quote_start + len(quote)
    length = len(text)
    while index < length:
        char = text[index]
        if char == "\\" and not raw:
            index += 2
            continue
        if text.startswith(quote, index):
            return index + len(quote)
        if quote in SINGLE_QUOTES and char == "\n":
            # A single-quoted GDScript string cannot span lines; treat the
            # newline as the terminator so one unclosed quote does not swallow
            # the remainder of the file.
            return index
        index += 1
    return length


def _scan_comment(text: str, start: int) -> int:
    """Return the index of the newline ending this comment, or len(text)."""
    newline = text.find("\n", start)
    return len(text) if newline < 0 else newline


def iter_tokens(text: str) -> Iterator[tuple[str, int, int, str]]:
    """Yield `(kind, start, end, prefix)` for every comment and string literal.

    `kind` is either `"comment"` or `"string"`. Regions are non-overlapping and
    yielded in source order; everything not yielded is executable code.
    """
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char == COMMENT_CHAR:
            end = _scan_comment(text, index)
            yield (COMMENT, index, end, "")
            index = end
            continue
        prefix, quote_start = _prefix_at(text, index)
        quote = _quote_at(text, quote_start)
        if quote is not None:
            end = _scan_string(text, quote_start, quote, raw=prefix == "r")
            yield (STRING, index, end, prefix)
            index = end
            continue
        index += 1


def mask_source(text: str) -> str:
    """Blank out comments and string literals, preserving length and newlines.

    The result has the same number of characters and the same newline offsets
    as the input, so line numbers computed on either string agree. Use it when
    a gate must reason about code structure without literal contents leaking
    into the analysis.
    """
    if not text:
        return text
    pieces: list[str] = []
    cursor = 0
    for _kind, start, end, _prefix in iter_tokens(text):
        pieces.append(text[cursor:start])
        pieces.append(_blank_run(text, start, end))
        cursor = end
    pieces.append(text[cursor:])
    return "".join(pieces)


def iter_string_literals(text: str) -> Iterator[StringLiteral]:
    """Yield every string literal with its value, prefix and position.

    Comments are skipped. A `&"Event.Damage"` StringName yields the same value
    a plain `"Event.Damage"` would, because both are equally magic when they
    appear twice across the codebase.
    """
    line_starts = _line_start_offsets(text)
    for kind, start, end, prefix in iter_tokens(text):
        if kind != STRING:
            continue
        quote_start = start + len(prefix)
        quote = _quote_at(text, quote_start)
        if quote is None:
            continue
        inner_start = quote_start + len(quote)
        inner_end = end - len(quote) if end - len(quote) >= inner_start else inner_start
        line, column = _position(line_starts, start)
        yield StringLiteral(
            value=text[inner_start:inner_end],
            prefix=prefix,
            line=line,
            column=column,
            start=start,
            end=end,
        )


def _line_start_offsets(text: str) -> list[int]:
    """Offsets at which each 1-indexed line begins."""
    offsets = [0]
    for index, char in enumerate(text):
        if char == "\n":
            offsets.append(index + 1)
    return offsets


def _position(line_starts: list[int], offset: int) -> tuple[int, int]:
    """Map an absolute offset to a 1-indexed line and 0-indexed column."""
    low, high = 0, len(line_starts) - 1
    while low < high:
        middle = (low + high + 1) // 2
        if line_starts[middle] <= offset:
            low = middle
        else:
            high = middle - 1
    return low + 1, offset - line_starts[low]


def strip_comments_only(text: str) -> str:
    """Blank out comments but keep string literals intact, preserving offsets."""
    if not text:
        return text
    pieces: list[str] = []
    cursor = 0
    for kind, start, end, _prefix in iter_tokens(text):
        if kind != COMMENT:
            continue
        pieces.append(text[cursor:start])
        pieces.append(_blank_run(text, start, end))
        cursor = end
    pieces.append(text[cursor:])
    return "".join(pieces)
