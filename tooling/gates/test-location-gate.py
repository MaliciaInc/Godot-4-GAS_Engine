#!/usr/bin/env python3
"""GAS_Engine test-location quality gate.

Rejects test implementation hidden inside production source while recognizing
the test files and directories the project actually uses.

GDScript is a first-class language here. A GUT test is a `func test_*` living
inside a `.gd` file that usually extends `GutTest`, and GDScript delimits that
function by indentation, so the gate measures `.gd` with the shared
indentation-aware region extractor instead of guessing with a raw-text regex.
A `func test_*` written inside a comment or a triple-quoted block is therefore
invisible, and a fixture that only declares helpers is not a test.

Discovery, policy loading and report writing come from `lib.gate_io`; this file
owns only the question "is this file a test, and does it live where tests live".

Exit codes: 0 pass, 1 test-location violation, 2 configuration/scan error.
"""
from __future__ import annotations

import argparse
import ast
import dataclasses
import re
import sys
from pathlib import Path
from typing import Mapping, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib import gate_io, gate_report, gdscript_lexing, gdscript_regions, languages  # noqa: E402

ENV_PROJECT_ROOT = "TEST_LOCATION_GATE_PROJECT_ROOT"

GDSCRIPT_SUFFIXES = languages.GDSCRIPT_EXTENSIONS
PYTHON_SUFFIXES = languages.PYTHON_EXTENSIONS
TEST_FUNCTION_PREFIX = gdscript_regions.TEST_FUNCTION_PREFIX

#: Both catalogs live in gate_io so this gate and file discovery answer
#: "is this a test?" from one place. Re-exported under the gate's own
#: names because the policy file and the CLI still speak in these terms.
DEFAULT_ALLOWED_DIRS = tuple(sorted(gate_io.TEST_DIRS))
DEFAULT_TEST_GLOBS = gate_io.TEST_GLOBS

#: A `.gd` file whose base class is the GUT suite type is a test no matter how
#: its methods are named. Matched against comment-stripped source with string
#: literals intact, because the path form of the base class is a string.
GUT_BASE_PATTERN = re.compile(
    r"(?m)^[ \t]*(?:class[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+)?extends[ \t]+"
    r"(?:GutTest\b|(?P<quote>[\"'])res://addons/gut/test\.gd(?P=quote))"
)

#: Languages the gate recognizes by pattern rather than by parsing.
INLINE_PATTERNS: Mapping[str, tuple[tuple[str, re.Pattern[str]], ...]] = {
    languages.TYPESCRIPT: (
        ("TypeScript test suite", re.compile(r"(?m)(?<![\w.])(?:describe|suite)\s*(?:\.\s*(?:only|skip))?\s*\(")),
        ("TypeScript test case", re.compile(r"(?m)(?<![\w.])(?:it|test)\s*(?:\.\s*(?:only|skip|todo))?\s*\(")),
        ("Vitest/Jest import", re.compile(r"\bfrom\s+['\"](?:vitest|@jest/globals|jest)['\"]|\brequire\s*\(\s*['\"](?:vitest|jest)['\"]")),
    ),
    languages.JAVASCRIPT: (
        ("JavaScript test suite", re.compile(r"(?m)(?<![\w.])(?:describe|suite)\s*(?:\.\s*(?:only|skip))?\s*\(")),
        ("JavaScript test case", re.compile(r"(?m)(?<![\w.])(?:it|test)\s*(?:\.\s*(?:only|skip|todo))?\s*\(")),
        ("Jest import", re.compile(r"\bfrom\s+['\"](?:@jest/globals|jest)['\"]")),
    ),
    languages.RUST: (
        ("Rust #[cfg(test)] module", re.compile(r"(?s)#\s*\[\s*cfg\s*\(\s*test\s*\)\s*\]\s*(?:pub\s+)?mod\s+\w+\s*\{")),
        ("Rust test function", re.compile(r"(?m)#\s*\[\s*(?:tokio::)?test(?:\s*\([^]]*\))?\s*\]")),
    ),
    languages.JAVA: (("Java test annotation", re.compile(r"(?m)^\s*@(?:Test|ParameterizedTest|RepeatedTest|TestFactory|TestTemplate)\b")),),
    languages.KOTLIN: (("Kotlin test annotation", re.compile(r"(?m)^\s*@(?:Test|ParameterizedTest|RepeatedTest)\b")),),
    languages.CSHARP: (("C# test attribute", re.compile(r"(?m)^\s*\[(?:Test|TestCase|TestFixture|Fact|Theory|DataTestMethod)")),),
    languages.GO: (("Go test function", re.compile(r"(?m)^\s*func\s+(?:Test|Benchmark|Fuzz)[A-Z0-9_]\w*\s*\(")),),
    languages.SWIFT: (("Swift XCTest case", re.compile(r"\bclass\s+\w+\s*:\s*XCTestCase\b")),),
    languages.RUBY: (("Ruby RSpec suite", re.compile(r"(?m)^\s*(?:RSpec\.)?describe\s+")),),
    languages.POWERSHELL: (("Pester test", re.compile(r"(?im)^\s*(?:Describe|Context|It)\s+['\"]")),),
    languages.ELIXIR: (("ExUnit case", re.compile(r"(?m)^\s*use\s+ExUnit\.Case\b")),),
    languages.DART: (("Dart test declaration", re.compile(r"(?m)(?<![\w.])(?:group|test|testWidgets)\s*\(")),),
}

#: Both tables come from the one language catalog. They used to be local,
#: and they had already drifted: a `.rs` file was `rust` here and `rs` to
#: the duplication gate, with nothing to notice.
LANGUAGE_BY_SUFFIX = languages.BY_EXTENSION
HASH_COMMENT_SUFFIXES = languages.HASH_COMMENT_EXTENSIONS


@dataclasses.dataclass(frozen=True, slots=True)
class Finding:
    """One misplaced test, reported at the line that proves it."""

    path: str
    line: int
    description: str


@dataclasses.dataclass(frozen=True, slots=True)
class Settings:
    """The frozen policy plus the CLI overrides, resolved once."""

    allowed_directories: tuple[str, ...]
    test_file_globs: tuple[str, ...]
    allow_inline_globs: tuple[str, ...]
    exclude_globs: tuple[str, ...]
    extensions: frozenset[str]
    require_test_directory: bool
    max_file_bytes: int
    use_git: bool
    allow_scan_errors: bool


@dataclasses.dataclass(frozen=True, slots=True)
class Result:
    """Everything the Markdown and JSON reports are rendered from."""

    files_scanned: int
    test_files: int
    findings: tuple[Finding, ...]
    scan_issues: tuple[str, ...]


def load_settings(root: Path, args: argparse.Namespace) -> Settings:
    """Resolve policy from `.quality-gates.json`, letting CLI flags win."""
    section = gate_io.config_section(root, args.config, "test_location")
    require = section.get("require_test_directory", False)
    if not isinstance(require, bool):
        raise gate_io.GateError("test_location.require_test_directory must be boolean")
    return Settings(
        allowed_directories=tuple(
            args.allowed_directory
            or gate_io.strings(section.get("allowed_directories"), "allowed_directories")
            or DEFAULT_ALLOWED_DIRS
        ),
        test_file_globs=tuple(
            args.test_file_glob
            or gate_io.strings(section.get("test_file_globs"), "test_file_globs")
            or DEFAULT_TEST_GLOBS
        ),
        allow_inline_globs=tuple((
            *gate_io.strings(section.get("allow_inline_globs"), "allow_inline_globs"),
            *args.allow_inline_glob,
        )),
        exclude_globs=tuple((
            *gate_io.strings(
                section.get(gate_io.EXCLUDE_GLOBS_KEY), gate_io.EXCLUDE_GLOBS_KEY
            ),
            *args.exclude_glob,
        )),
        extensions=gate_io.resolve_extensions(
            args.include_extension, section, "test_location.include_extensions"
        ),
        require_test_directory=args.require_test_directory or require,
        max_file_bytes=args.max_file_bytes,
        use_git=not args.no_git,
        allow_scan_errors=args.allow_scan_errors,
    )


def contains_run(parts: Sequence[str], segments: Sequence[str]) -> bool:
    """True when `segments` appear as a contiguous run inside `parts`."""
    span = len(segments)
    return any(
        list(parts[index:index + span]) == list(segments)
        for index in range(len(parts) - span + 1)
    )


def under_allowed_directory(relative: str, allowed: Sequence[str]) -> bool:
    """True when the file's directory chain contains an approved test directory.

    Multi-segment entries such as `tooling/gates/tests` are matched as a
    contiguous run of directories, so the frozen policy means what it says.
    """
    parts = [part.lower() for part in Path(relative).parts[:-1]]
    for item in allowed:
        segments = [part for part in item.replace("\\", "/").lower().split("/") if part]
        if segments and contains_run(parts, segments):
            return True
    return False


def gdscript_findings(text: str, relative: str) -> list[Finding]:
    """Report GUT tests implemented in a production `.gd` file.

    Both signals run over source with comments neutralized by the shared lexer,
    so a commented-out or quoted declaration never counts.
    """
    findings = [
        Finding(relative, line, f"inline GDScript test function '{name}'")
        for name, line in gdscript_regions.collect_test_functions(text)
    ]
    stripped = gdscript_lexing.strip_comments_only(text)
    for match in GUT_BASE_PATTERN.finditer(stripped):
        line = stripped.count("\n", 0, match.start()) + 1
        findings.append(Finding(relative, line, "inline GUT test suite base class"))
    return findings


def python_findings(text: str, relative: str, issues: list[str]) -> list[Finding]:
    """Report unittest/pytest declarations in a production Python file.

    A parse failure becomes a scan issue rather than an exception so the rest
    of the tree is still scanned; an unresolved issue can never report PASS.
    """
    try:
        tree = ast.parse(text)
    except SyntaxError as exc:
        issues.append(gate_io.python_parse_message(f"{relative}:{exc.lineno}", exc))
        return []
    findings: list[Finding] = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith(TEST_FUNCTION_PREFIX):
            findings.append(Finding(relative, node.lineno, f"inline Python test function '{node.name}'"))
        elif isinstance(node, ast.ClassDef):
            bases = {ast.unparse(base) for base in node.bases}
            if node.name.startswith("Test") or "TestCase" in bases or "unittest.TestCase" in bases:
                findings.append(Finding(relative, node.lineno, f"inline Python test class '{node.name}'"))
    return findings


def mask_comments(text: str, suffix: str) -> str:
    """Blank out comments for the pattern-matched languages, keeping offsets."""
    chars = list(text)
    index = 0
    quote: str | None = None
    escaped = False
    hash_comments = suffix in HASH_COMMENT_SUFFIXES
    c_comments = not hash_comments
    while index < len(chars):
        char = chars[index]
        nxt = chars[index + 1] if index + 1 < len(chars) else ""
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            index += 1
            continue
        if char in "'\"`":
            quote = char
            index += 1
            continue
        if (hash_comments and char == "#") or (c_comments and char == "/" and nxt == "/"):
            end = text.find("\n", index)
            end = len(chars) if end < 0 else end
            for position in range(index, end):
                chars[position] = " "
            index = end
            continue
        if c_comments and char == "/" and nxt == "*":
            end = text.find("*/", index + 2)
            end = len(chars) - 2 if end < 0 else end
            for position in range(index, min(len(chars), end + 2)):
                if chars[position] != "\n":
                    chars[position] = " "
            index = end + 2
            continue
        index += 1
    return "".join(chars)


def regex_findings(text: str, relative: str, suffix: str) -> list[Finding]:
    """Report test declarations for languages matched by pattern."""
    clean = mask_comments(text, suffix)
    findings: list[Finding] = []
    for description, pattern in INLINE_PATTERNS.get(languages.language_for(suffix), ()):
        for match in pattern.finditer(clean):
            findings.append(Finding(relative, clean.count("\n", 0, match.start()) + 1, description))
    return findings


def file_findings(suffix: str, text: str, relative: str, issues: list[str]) -> list[Finding]:
    """Dispatch one production file to the analyzer that understands it."""
    if suffix in GDSCRIPT_SUFFIXES:
        return gdscript_findings(text, relative)
    if suffix in PYTHON_SUFFIXES:
        return python_findings(text, relative, issues)
    return regex_findings(text, relative, suffix)


def evaluate(root: Path, settings: Settings) -> Result:
    """Scan the tree and collect every misplaced test."""
    files, issues = gate_io.discover(gate_io.DiscoveryRequest(
        root=root,
        extensions=settings.extensions,
        exclude_globs=settings.exclude_globs,
        max_file_bytes=settings.max_file_bytes,
        use_git=settings.use_git,
        include_tests=True,
    ))
    findings: list[Finding] = []
    test_files = 0
    for path in files:
        relative = path.relative_to(root).as_posix()
        in_test_dir = under_allowed_directory(relative, settings.allowed_directories)
        named_test = gate_io.matches(Path(relative).name, settings.test_file_globs)
        if in_test_dir or named_test:
            test_files += 1
            if settings.require_test_directory and named_test and not in_test_dir:
                findings.append(Finding(relative, 1, "test file is outside an approved test directory"))
            continue
        if gate_io.matches(relative, settings.allow_inline_globs):
            continue
        text = gate_io.read_source(path, relative, issues)
        if text is None:
            continue
        findings.extend(file_findings(path.suffix.lower(), text, relative, issues))
    unique = {(item.path, item.line, item.description): item for item in findings}
    ordered = sorted(unique.values(), key=lambda item: (item.path, item.line, item.description))
    return Result(len(files), test_files, tuple(ordered), tuple(sorted(set(issues))))


def report(result: Result, root: Path, settings: Settings) -> gate_report.Report:
    """Project the scan onto the shared report contract."""
    return gate_report.Report(
        title="Test Location Gate",
        root=root,
        blocking=result.findings,
        scan_issues=result.scan_issues,
        files_scanned=result.files_scanned,
        allow_scan_errors=settings.allow_scan_errors,
        extra_rows=(gate_report.summary_row("Test files recognized", result.test_files),),
        sections=(
            gate_report.ReportSection(
                gate_report.VIOLATIONS_TITLE,
                tuple(f"- `{item.path}:{item.line}`: {item.description}" for item in result.findings),
            ),
        ),
    )


def build_parser() -> argparse.ArgumentParser:
    """The canonical CLI. Argument names are sealed by the verification chain."""
    parser = argparse.ArgumentParser(description=__doc__)
    gate_io.add_common_arguments(parser)
    gate_io.add_repeatable(parser, "--allowed-directory", "--test-file-glob", "--allow-inline-glob")
    gate_io.add_flags(parser, "--require-test-directory")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.max_file_bytes <= 0:
            raise gate_io.GateError("max-file-bytes must be positive")
        root = gate_io.resolve_root(args.project_root, ENV_PROJECT_ROOT)
        settings = load_settings(root, args)
        result = evaluate(root, settings)
        text = gate_report.render_report(report(result, root, settings))
        gate_io.write_report(args.output, text)
        gate_io.write_json_report(args.json_output, dataclasses.asdict(result))
        if not args.quiet:
            print(text, end="")
        return gate_io.exit_code(result.scan_issues, len(result.findings), settings.allow_scan_errors)
    except (gate_io.GateError, OSError) as exc:
        print(f"test-location-gate: ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    gate_io.configure_stdio()
    raise SystemExit(main())
