#!/usr/bin/env python3
"""The single catalog of source languages the quality gates recognize.

Before this module the same alphabet was declared five times over. `gate_io`
held the master extension set, and the LOC, duplication, magic-string and
test-location gates each re-derived their own answer to "which extension is
GDScript", "which uses `#` comments", "which delimits bodies with braces".

Two of them already disagreed: a `.rs` file was `rust` to the test-location
gate and `rs` to the duplication gate, and nothing anywhere reported the
divergence. That is the same defect as a gate that passes without scanning -
an authority that is silently not one.

Adding a language is now one row in `LANGUAGES`. An extension outside the
table classifies as `UNKNOWN` rather than falling into a silent default.
"""
from __future__ import annotations

import dataclasses
from typing import Mapping

#: How a language opens a line comment.
HASH, SLASH, DASH = "hash", "slash", "dash"

#: How a language delimits a function body. `UNMEASURED` means the gates have
#: no reliable extractor for it, so its functions are deliberately not counted
#: rather than counted wrongly.
BRACE, INDENT, UNMEASURED = "brace", "indent", "unmeasured"

GDSCRIPT, PYTHON, UNKNOWN = "gdscript", "python", "unknown"

#: Every label, as a name. A gate that dispatches on a language must
#: import the constant, not retype the string, or a rename here goes
#: unnoticed there.
TYPESCRIPT = "typescript"
JAVASCRIPT = "javascript"
RUST = "rust"
JAVA = "java"
KOTLIN = "kotlin"
CSHARP = "csharp"
GO = "go"
SWIFT = "swift"
DART = "dart"
SCALA = "scala"
PHP = "php"
C = "c"
CPP = "cpp"
VUE = "vue"
SVELTE = "svelte"
LUA = "lua"
POWERSHELL = "powershell"
ELIXIR = "elixir"
RUBY = "ruby"
SHELL = "shell"
SQL = "sql"



@dataclasses.dataclass(frozen=True, slots=True)
class Language:
    """One recognized language: its extensions, its comments, its blocks."""

    name: str
    extensions: tuple[str, ...]
    comments: str
    blocks: str


LANGUAGES: tuple[Language, ...] = (
    Language(GDSCRIPT, (".gd",), HASH, INDENT),
    Language(PYTHON, (".py", ".pyi"), HASH, INDENT),
    Language(TYPESCRIPT, (".ts", ".tsx", ".mts", ".cts"), SLASH, BRACE),
    Language(JAVASCRIPT, (".js", ".jsx", ".mjs", ".cjs"), SLASH, BRACE),
    Language(RUST, (".rs",), SLASH, BRACE),
    Language(JAVA, (".java",), SLASH, BRACE),
    Language(KOTLIN, (".kt", ".kts"), SLASH, BRACE),
    Language(CSHARP, (".cs",), SLASH, BRACE),
    Language(GO, (".go",), SLASH, BRACE),
    Language(SWIFT, (".swift",), SLASH, BRACE),
    Language(DART, (".dart",), SLASH, BRACE),
    Language(SCALA, (".scala",), SLASH, BRACE),
    Language(PHP, (".php",), SLASH, BRACE),
    Language(C, (".c", ".h"), SLASH, BRACE),
    Language(CPP, (".cc", ".cpp", ".cxx", ".hpp"), SLASH, BRACE),
    Language(VUE, (".vue",), SLASH, BRACE),
    Language(SVELTE, (".svelte",), SLASH, BRACE),
    Language(LUA, (".lua",), DASH, BRACE),
    Language(POWERSHELL, (".ps1", ".psm1"), HASH, BRACE),
    Language(ELIXIR, (".ex", ".exs"), HASH, BRACE),
    Language(RUBY, (".rb",), HASH, UNMEASURED),
    Language(SHELL, (".sh", ".bash", ".zsh", ".fish"), HASH, UNMEASURED),
    Language(SQL, (".sql",), DASH, UNMEASURED),
)

BY_EXTENSION: Mapping[str, Language] = {
    extension: language for language in LANGUAGES for extension in language.extensions
}

#: Every extension the gates will open. Derived, never hand-maintained.
SOURCE_EXTENSIONS = frozenset(BY_EXTENSION)


def language_for(suffix: str) -> str:
    """Language label for a file suffix, or `UNKNOWN` when it is not in the table."""
    found = BY_EXTENSION.get(suffix.lower())
    return found.name if found else UNKNOWN


def extensions_named(*names: str) -> frozenset[str]:
    """Every extension belonging to the named languages."""
    wanted = frozenset(names)
    return frozenset(
        extension
        for language in LANGUAGES
        if language.name in wanted
        for extension in language.extensions
    )


def extensions_commented(style: str) -> frozenset[str]:
    """Every extension whose line comments use `style`."""
    return frozenset(
        extension
        for language in LANGUAGES
        if language.comments == style
        for extension in language.extensions
    )


def extensions_blocked(style: str) -> frozenset[str]:
    """Every extension whose bodies are delimited the way `style` describes."""
    return frozenset(
        extension
        for language in LANGUAGES
        if language.blocks == style
        for extension in language.extensions
    )


#: Words that are control flow in the C-like languages the gates read.
#: The duplication gate scores behaviour with them and the LOC gate uses
#: them to tell a control statement from a declaration. Both used to keep
#: their own partial copy.
CONTROL_KEYWORDS = frozenset({
    "if", "else", "elif", "for", "foreach", "while", "loop", "switch", "case", "match",
    "return", "break", "continue", "try", "catch", "except", "finally", "throw", "raise",
    "await", "async", "yield",
})

#: Declaration and value words that are not control flow.
DECLARATION_KEYWORDS = frozenset({
    "new", "class", "struct", "enum", "impl", "function", "fn",
    "const", "let", "var", "true", "false", "null", "none", "undefined", "import", "export",
})

GDSCRIPT_EXTENSIONS = extensions_named(GDSCRIPT)
PYTHON_EXTENSIONS = extensions_named(PYTHON)

#: `#`-commented extensions that neither of the two native front ends handles,
#: so the generic regex scanner has to be told about them.
HASH_COMMENT_EXTENSIONS = extensions_commented(HASH) - GDSCRIPT_EXTENSIONS - PYTHON_EXTENSIONS

BRACE_EXTENSIONS = extensions_blocked(BRACE)
UNMEASURED_EXTENSIONS = extensions_blocked(UNMEASURED)
