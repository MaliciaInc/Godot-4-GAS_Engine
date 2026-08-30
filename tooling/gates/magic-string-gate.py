#!/usr/bin/env python3
"""Arhalies GAS magic-string, format-template and hard-coded-colour gate.

Three concerns share one scan: literals repeated across files, format templates
repeated across files, and colours hard-coded outside the theme layer.

GDScript is a first-class language here. `.gd` sources are tokenized by
`lib.gdscript_lexing`, so `#` comments never contribute literals, triple-quoted
blocks keep their line offsets, and a `&"Event.Damage"` StringName is exactly as
visible as the plain `"Event.Damage"` it interns. Annotations and type names are
never quoted, so the lexer cannot mistake them for literals.

The gate has no self-exclusion: it scans `tooling/gates/**` like any other
source, because a gate blind to the code implementing it is not an authority.
Exit: 0 pass, 1 configured blocking finding, 2 configuration/scan error.
"""
from __future__ import annotations

import argparse
import ast
import dataclasses
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib import allowances, gate_io, gate_report, gdscript_lexing, languages  # noqa: E402

ROOT_ENV_VAR = "MAGIC_STRING_GATE_PROJECT_ROOT"
CONFIG_SECTION = "magic_strings"
GDSCRIPT_EXTENSIONS = languages.GDSCRIPT_EXTENSIONS
PYTHON_EXTENSIONS = languages.PYTHON_EXTENSIONS
HASH_COMMENT_EXTENSIONS = languages.HASH_COMMENT_EXTENSIONS
# The kind of finding and the policy key that waives it are one word
# because they name one thing: a string literal repeated in the source.
LITERAL_KIND, TEMPLATE_KIND, COLOR_KIND = allowances.LITERAL_KEY, "template", "color"
FAIL_KINDS = frozenset({"repeated", "templates", "colors"})
DEFAULT_FAIL_ON = frozenset({"templates", "colors"})
MAXIMUM_VALUE_LENGTH, MAXIMUM_VALUE_LINES = 500, 5
REPORT_VALUE_WIDTH, REPORT_OCCURRENCE_LIMIT = 120, 12
THEME_GLOBS = (
    "**/theme/**", "**/themes/**", "**/style/**", "**/styles/**", "**/design-system/**", "**/design_system/**",
    "**/tokens/**", "**/*.css", "**/*.scss", "**/*.sass", "**/*.less", "**/theme.*", "**/themes.*", "**/colors.*",
)
COMMON_ALLOWED = frozenset({
    "utf-8", "utf8", "true", "false", "none", "null", "undefined", "localhost", "127.0.0.1", "0.0.0.0"})

# STRING_SYNTAX keeps group numbers 1..3 so its `\2` backreference survives embedding below.
STRING_SYNTAX = r"(?P<prefix>[$@fFbBrRuU]{0,2})(?P<quote>['\"`])(?P<body>(?:\\.|(?!\2).)*?)(?P=quote)"
C_COMMENT_SYNTAX = r"//[^\n]*|/\*.*?\*/"
COMMENT_SYNTAX = {suffix: r"#[^\n]*" for suffix in HASH_COMMENT_EXTENSIONS} | {
    suffix: r"--[^\n]*" for suffix in languages.extensions_commented(languages.DASH)
}
STRING_PATTERN = re.compile(STRING_SYNTAX, re.DOTALL)
COMMENT_PATTERN = re.compile(f"{C_COMMENT_SYNTAX}|#[^\n]*", re.DOTALL)
HEX_COLOR = re.compile(r"(?i)^#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$")
COLOR_FUNCTION = re.compile(r"(?i)^(?:rgb|rgba|hsl|hsla|lab|lch|oklab|oklch|color)\s*\(")
# The bare-constructor branch is case-sensitive and rejects member access, so a lowercase
# `self.color(` is not a colour. `Color8` is Godot's 0-255 constructor and must not slip past.
CODE_COLOR = re.compile(
    r"(?i:\b(?:Color|Colour)(?:::|\.)\s*(?:from_)?(?:rgb|rgba|rgb8|rgba8|fromArgb|fromARGB|fromRGBO|fromHex)\b)"
    r"|(?<![.\w])(?:Color8|Colour|Color)\s*\("
)
IMPORT_LINE = re.compile(r"^\s*(?:import|from|use|using|require|include|mod|extern\s+crate)\b")
BRACE_PLACEHOLDER = re.compile(r"\{[^{}\n]*\}")
DOLLAR_PLACEHOLDER = re.compile(r"\$\{[^{}\n]*\}")
PERCENT_PLACEHOLDER = re.compile(r"%[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[a-zA-Z%]")


@dataclasses.dataclass(frozen=True, slots=True)
class Occurrence:
    """One literal, template or colour and where it was written."""

    value: str
    path: str
    line: int
    kind: str


@dataclasses.dataclass(frozen=True, slots=True)
class SourceFile:
    """A discovered file plus everything an analyser needs to read it."""

    relative: str
    suffix: str
    text: str


@dataclasses.dataclass(frozen=True, slots=True)
class Settings:
    """Resolved policy: CLI beats configuration, configuration beats defaults."""

    minimum_length: int
    minimum_occurrences: int
    minimum_distinct_files: int
    fail_on: frozenset[str]
    allow_literals: frozenset[str]
    allow_globs: tuple[str, ...]
    theme_globs: tuple[str, ...]
    exclude_globs: tuple[str, ...]
    extensions: frozenset[str]
    include_tests: bool
    max_file_bytes: int
    use_git: bool
    allow_scan_errors: bool


@dataclasses.dataclass(frozen=True, slots=True)
class Result:
    """Everything the Markdown and JSON reports are rendered from."""

    files_scanned: int
    repeated_literals: tuple[tuple[str, tuple[Occurrence, ...]], ...]
    repeated_templates: tuple[tuple[str, tuple[Occurrence, ...]], ...]
    colors: tuple[Occurrence, ...]
    scan_issues: tuple[str, ...]
    blocking_count: int


def parse_fail_on(value: str) -> frozenset[str]:
    """argparse type for `--fail-on`, validated against this gate's kinds."""
    return gate_io.parse_kinds(value, FAIL_KINDS)


def config_fail_on(value: Any) -> frozenset[str]:
    """Validate the policy's `fail_on` list, falling back to the built-in default."""
    if value is None:
        return DEFAULT_FAIL_ON
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise gate_io.GateError("magic_strings.fail_on must be a list of strings")
    normalized = frozenset(item.strip().lower() for item in value if item.strip())
    unknown = normalized - FAIL_KINDS
    if unknown:
        raise gate_io.GateError(f"magic_strings.fail_on unknown kinds: {', '.join(sorted(unknown))}")
    return normalized


def combined(section: Mapping[str, Any], key: str, extra: Sequence[str]) -> tuple[str, ...]:
    """Concatenate a policy list with the CLI additions for the same knob."""
    return (*gate_io.strings(section.get(key), key), *extra)
def load_settings(root: Path, args: argparse.Namespace) -> Settings:
    """Merge the frozen policy with the CLI into one immutable Settings value.

    No gate-owned exclusion is injected: the only exclusions in force are those
    the policy and the caller declare, which is what lets this gate hold
    authority over the directory that contains it.
    """
    section = gate_io.config_section(root, args.config, CONFIG_SECTION)
    return Settings(
        minimum_length=args.minimum_length or gate_io.positive(section.get("minimum_length"), "minimum_length", 3),
        minimum_occurrences=args.minimum_occurrences
        or gate_io.positive(section.get("minimum_occurrences"), "minimum_occurrences", 2),
        minimum_distinct_files=args.minimum_distinct_files
        or gate_io.positive(section.get("minimum_distinct_files"), "minimum_distinct_files", 2),
        fail_on=args.fail_on if args.fail_on is not None else config_fail_on(section.get("fail_on")),
        allow_literals=frozenset(
            allowances.allowed_literals(section.get("allow_literals"), args.allow_literal)
        ),
        allow_globs=combined(section, "allow_globs", args.allow_glob),
        theme_globs=tuple(args.theme_glob or combined(section, "theme_globs", ()) or THEME_GLOBS),
        exclude_globs=combined(section, gate_io.EXCLUDE_GLOBS_KEY, args.exclude_glob),
        extensions=gate_io.resolve_extensions(args.include_extension, section, "magic_strings.include_extensions"),
        include_tests=args.include_tests or bool(section.get("include_tests", False)),
        max_file_bytes=args.max_file_bytes,
        use_git=not args.no_git,
        allow_scan_errors=args.allow_scan_errors,
    )


def discovery_request(root: Path, settings: Settings) -> gate_io.DiscoveryRequest:
    """Project the resolved settings onto the shared discovery contract."""
    return gate_io.DiscoveryRequest(
        root, settings.extensions, settings.exclude_globs, settings.max_file_bytes,
        settings.use_git, settings.include_tests,
    )


def normalize_template(value: str) -> str:
    """Collapse format placeholders so `Damage: %d` and `Damage: %s` group together."""
    value = BRACE_PLACEHOLDER.sub("{}", value)
    return PERCENT_PLACEHOLDER.sub("{}", DOLLAR_PLACEHOLDER.sub("${}", value))


def suspicious(value: str, settings: Settings) -> bool:
    """True when a value is long enough, textual enough, and not allow-listed."""
    cleaned = value.strip()
    if not settings.minimum_length <= len(cleaned) <= MAXIMUM_VALUE_LENGTH:
        return False
    if cleaned.lower() in COMMON_ALLOWED or cleaned in settings.allow_literals:
        return False
    return any(char.isalnum() for char in cleaned) and len(cleaned.splitlines()) <= MAXIMUM_VALUE_LINES


def blank_region(match: re.Match[str]) -> str:
    """Blank a matched region, keeping its newlines so later line numbers hold."""
    return "".join("\n" if char == "\n" else " " for char in match.group(0))


def python_docstring_ids(tree: ast.AST) -> set[int]:
    """Identify the constant nodes that are docstrings rather than values."""
    found: set[int] = set()
    for owner in ast.walk(tree):
        body = getattr(owner, "body", None)
        head = body[0] if isinstance(body, list) and body else None
        if isinstance(head, ast.Expr) and isinstance(head.value, ast.Constant) and isinstance(head.value.value, str):
            found.add(id(head.value))
    return found


def python_occurrences(source: SourceFile) -> list[Occurrence]:
    """Collect literals and f-string templates from a Python file via the AST."""
    try:
        tree = ast.parse(source.text)
    except SyntaxError as exc:
        raise gate_io.python_parse_error(f"{source.relative}:{exc.lineno}", exc) from exc
    docstrings = python_docstring_ids(tree)
    result: list[Occurrence] = []
    for node in ast.walk(tree):
        line = getattr(node, "lineno", 1)
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            if id(node) not in docstrings:
                result.append(Occurrence(node.value.strip(), source.relative, line, LITERAL_KIND))
        elif isinstance(node, ast.JoinedStr):
            parts = [
                item.value if isinstance(item, ast.Constant) and isinstance(item.value, str) else "{}"
                for item in node.values
            ]
            value = normalize_template("".join(parts).strip())
            result.append(Occurrence(value, source.relative, line, TEMPLATE_KIND))
    return result


def is_documentation_block(text: str, literal: gdscript_lexing.StringLiteral) -> bool:
    """True for a triple-quoted GDScript block standing alone at statement position.

    GDScript has no docstring syntax, but such a block is written as a comment, so
    it is exempt exactly as the Python analyser exempts a docstring.
    """
    if not text.startswith(gdscript_lexing.TRIPLE_QUOTES, literal.start + len(literal.prefix)):
        return False
    return not text[literal.start - literal.column:literal.start].strip()


def gdscript_occurrences(source: SourceFile) -> list[Occurrence]:
    """Collect every GDScript literal, StringName and NodePath included.

    Comments never reach this list; the lexer classifies them separately. The
    `&`, `^` and `r` prefixes are dropped, so `&"Event.Damage"` groups with the
    plain `"Event.Damage"` it interns: a StringName is not a hiding place.
    """
    result: list[Occurrence] = []
    for literal in gdscript_lexing.iter_string_literals(source.text):
        if is_documentation_block(source.text, literal):
            continue
        value = literal.value.strip()
        normalized = normalize_template(value)
        kind = TEMPLATE_KIND if normalized != value else LITERAL_KIND
        result.append(Occurrence(normalized, source.relative, literal.line, kind))
    return result


def mask_comments(text: str, suffix: str) -> str:
    """Blank comments that are not inside a literal, preserving every offset.

    The string alternative is tried first at each position, so a `#` or a `//`
    inside a literal is consumed with it instead of opening a comment.
    """
    if suffix in PYTHON_EXTENSIONS or suffix in GDSCRIPT_EXTENSIONS:
        return text
    syntax = COMMENT_SYNTAX.get(suffix, C_COMMENT_SYNTAX)
    masker = re.compile(f"{STRING_SYNTAX}|(?P<line_comment>{syntax})", re.DOTALL)
    return masker.sub(lambda match: blank_region(match) if match.group("line_comment") else match.group(0), text)


def generic_occurrences(source: SourceFile) -> list[Occurrence]:
    """Regex-scan a language the gate has no dedicated front end for."""
    clean_text = mask_comments(source.text, source.suffix)
    lines = clean_text.splitlines()
    result: list[Occurrence] = []
    for match in STRING_PATTERN.finditer(clean_text):
        line = clean_text.count("\n", 0, match.start()) + 1
        if 1 <= line <= len(lines) and IMPORT_LINE.search(lines[line - 1]):
            continue
        prefix, quote, body = match.group("prefix", "quote", "body")
        is_template = quote == "`" or "f" in prefix.lower() or "$" in prefix
        value = normalize_template(body.strip()) if is_template else body.strip()
        result.append(Occurrence(value, source.relative, line, TEMPLATE_KIND if is_template else LITERAL_KIND))
    return result


def occurrences_for(source: SourceFile) -> list[Occurrence]:
    """Dispatch a file to the analyser that understands its language."""
    if source.suffix in GDSCRIPT_EXTENSIONS:
        return gdscript_occurrences(source)
    if source.suffix in PYTHON_EXTENSIONS:
        return python_occurrences(source)
    return generic_occurrences(source)


def masked_code(source: SourceFile) -> str:
    """Blank comments and literals, preserving offsets, so only code remains."""
    if source.suffix in GDSCRIPT_EXTENSIONS:
        return gdscript_lexing.mask_source(source.text)
    return COMMENT_PATTERN.sub(blank_region, STRING_PATTERN.sub(blank_region, source.text))


def dedupe(items: Iterable[Occurrence]) -> list[Occurrence]:
    """Collapse identical (path, line, value) findings into a stable order."""
    unique = {(item.path, item.line, item.value): item for item in items}
    return sorted(unique.values(), key=lambda item: (item.path, item.line, item.value))


def hard_coded_colors(source: SourceFile, occurrences: list[Occurrence], settings: Settings) -> list[Occurrence]:
    """Find colour literals and colour constructor calls outside the theme layer."""
    if gate_io.matches(source.relative, settings.theme_globs):
        return []
    result = [
        dataclasses.replace(item, kind=COLOR_KIND)
        for item in occurrences
        if HEX_COLOR.fullmatch(item.value) or COLOR_FUNCTION.match(item.value)
    ]
    masked = masked_code(source)
    for match in CODE_COLOR.finditer(masked):
        line = masked.count("\n", 0, match.start()) + 1
        result.append(Occurrence(match.group(0).strip(), source.relative, line, COLOR_KIND))
    return dedupe(result)


def grouped(items: list[Occurrence], settings: Settings) -> tuple[tuple[str, tuple[Occurrence, ...]], ...]:
    """Group suspicious values clearing both the occurrence and distinct-file floors."""
    buckets: dict[str, list[Occurrence]] = defaultdict(list)
    for item in items:
        if suspicious(item.value, settings):
            buckets[item.value].append(item)
    groups = []
    for value, occurrences in buckets.items():
        distinct = len({item.path for item in occurrences})
        if len(occurrences) < settings.minimum_occurrences or distinct < settings.minimum_distinct_files:
            continue
        groups.append((value, tuple(sorted(occurrences, key=lambda item: (item.path, item.line)))))
    return tuple(sorted(groups, key=lambda item: item[0].casefold()))


def evaluate(root: Path, settings: Settings) -> Result:
    """Scan every discovered file and reduce the findings to one Result."""
    files, issues = gate_io.discover(discovery_request(root, settings))
    literals: list[Occurrence] = []
    templates: list[Occurrence] = []
    colors: list[Occurrence] = []
    for path in files:
        relative = path.relative_to(root).as_posix()
        if gate_io.matches(relative, settings.allow_globs):
            continue
        text = gate_io.read_source(path, relative, issues)
        if text is None:
            continue
        source = SourceFile(relative, path.suffix.lower(), text)
        occurrences = occurrences_for(source)
        literals.extend(item for item in occurrences if item.kind == LITERAL_KIND)
        templates.extend(item for item in occurrences if item.kind == TEMPLATE_KIND)
        colors.extend(hard_coded_colors(source, occurrences, settings))
    found = {"repeated": grouped(literals, settings), "templates": grouped(templates, settings)}
    found["colors"] = tuple(dedupe(colors))
    blocking = sum(len(value) for kind, value in found.items() if kind in settings.fail_on)
    sections = (found["repeated"], found["templates"], found["colors"], tuple(sorted(set(issues))))
    return Result(len(files), *sections, blocking)


def group_bullets(groups: tuple[tuple[str, tuple[Occurrence, ...]], ...]) -> tuple[str, ...]:
    """One bullet per repeated value, listing where it was written."""
    bullets = []
    for value, occurrences in groups:
        places = ", ".join(f"`{item.path}:{item.line}`" for item in occurrences[:REPORT_OCCURRENCE_LIMIT])
        bullets.append(f"- `{value[:REPORT_VALUE_WIDTH]}` -> {places}")
    return tuple(bullets)


def color_bullets(result: Result) -> tuple[str, ...]:
    """One bullet per hard-coded colour, truncated to the report width."""
    return tuple(
        f"- `{item.path}:{item.line}`: `{item.value[:REPORT_VALUE_WIDTH]}`" for item in result.colors
    )


def report(result: Result, root: Path, settings: Settings) -> gate_report.Report:
    """Project the scan onto the shared report contract."""
    return gate_report.Report(
        title="Magic String Gate",
        root=root,
        blocking=range(result.blocking_count),
        scan_issues=result.scan_issues,
        files_scanned=result.files_scanned,
        allow_scan_errors=settings.allow_scan_errors,
        extra_rows=(
            gate_report.summary_row("Blocking kinds", ", ".join(sorted(settings.fail_on)) or "none"),
            gate_report.summary_row(
                "Configured exclusions", ", ".join(settings.exclude_globs) or "none"
            ),
        ),
        sections=(
            gate_report.ReportSection("Repeated Literals", group_bullets(result.repeated_literals)),
            gate_report.ReportSection("Repeated Templates", group_bullets(result.repeated_templates)),
            gate_report.ReportSection("Hard-coded Colors", color_bullets(result)),
        ),
    )


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI. The canonical pipeline depends on these exact option names."""
    parser = argparse.ArgumentParser(description=__doc__)
    gate_io.add_common_arguments(parser)
    parser.add_argument("--minimum-length", type=int)
    parser.add_argument("--minimum-occurrences", type=int)
    parser.add_argument("--minimum-distinct-files", type=int)
    gate_io.add_fail_on(parser, parse_fail_on)
    gate_io.add_repeatable(parser, "--allow-literal", "--allow-glob", "--theme-glob")
    gate_io.add_include_tests(parser)
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the gate and return its exit code."""
    args = build_parser().parse_args(argv)
    try:
        thresholds = (args.minimum_length, args.minimum_occurrences, args.minimum_distinct_files)
        gate_io.check_positive((args.max_file_bytes, *thresholds))
        root = gate_io.resolve_root(args.project_root, ROOT_ENV_VAR)
        settings = load_settings(root, args)
        result = evaluate(root, settings)
        text = gate_report.render_report(report(result, root, settings))
        gate_io.write_report(args.output, text)
        gate_io.write_json_report(args.json_output, dataclasses.asdict(result))
        if not args.quiet:
            print(text, end="")
        return gate_io.exit_code(result.scan_issues, result.blocking_count, settings.allow_scan_errors)
    except (gate_io.GateError, OSError) as exc:
        print(f"magic-string-gate: ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    gate_io.configure_stdio()
    raise SystemExit(main())
