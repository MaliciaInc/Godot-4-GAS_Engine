#!/usr/bin/env python3
"""Shared infrastructure for the Arhalies GAS quality gates.

Every gate needs the same four things: locate the repository root, read the
frozen policy from `.quality-gates.json`, discover candidate source files, and
write reports atomically. Keeping one implementation here is what lets the
gates run against the repository that contains them without the duplication
gate flagging their shared plumbing.

Exit-code contract shared by all gates:
    0  pass
    1  blocking finding
    2  configuration error, scan error, or incomplete scan
"""
from __future__ import annotations

import argparse
import dataclasses
import fnmatch
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

from . import languages

CONFIG_FILENAME = ".quality-gates.json"

#: The executable the gates and tooling shell out to. Named because more
#: than one of them asks git a question.
GIT_EXECUTABLE: str = "git"

#: git's file listing, asked two different ways by two different callers.
GIT_LIST_FILES: str = "ls-files"

#: This repository's layout, used to find the root by walking upward.
TOOLING_DIRNAME: str = "tooling"
GATES_DIRNAME: str = "gates"

#: Policy keys and the encoding, named once. Three gates read the same
#: exclusion list and two readers open files the same way.
#: argparse action names, written once. Three gates were repeating them.
APPEND, STORE_TRUE = "append", "store_true"

#: The canonical CLI, named once. The verification chain depends on these
#: exact spellings and Task 0 sealed them, so they are constants a caller can
#: reference rather than strings a caller retypes. tooling/gates/run_gate.py
#: builds every invocation from them.
PROJECT_ROOT_FLAG: str = "--project-root"
OUTPUT_FLAG: str = "--output"
JSON_OUTPUT_FLAG: str = "--json-output"
FAIL_ON_FLAG: str = "--fail-on"
INCLUDE_TESTS_FLAG: str = "--include-tests"
CONFIG_FLAG: str = "--config"
QUIET_FLAG: str = "--quiet"
NO_GIT_FLAG: str = "--no-git"
ALLOW_SCAN_ERRORS_FLAG: str = "--allow-scan-errors"
MAX_FILE_BYTES_FLAG: str = "--max-file-bytes"
INCLUDE_EXTENSION_FLAG: str = "--include-extension"
EXCLUDE_GLOB_FLAG: str = "--exclude-glob"

EXCLUDE_GLOBS_KEY = "exclude_globs"

#: duplication-gate's own path filters, distinct from the shared
#: --include-glob/--exclude-glob above. Spelled here so the gate declaring
#: them and run_gate passing them cannot drift apart.
PATH_INCLUDE_FLAG: str = "--include"
PATH_EXCLUDE_FLAG: str = "--exclude"
SOURCE_ENCODING = "utf-8-sig"

#: Single catalog, owned by lib.languages. Re-exported under the name every
#: gate already uses, so there is one table and one spelling of it.
SOURCE_EXTENSIONS = languages.SOURCE_EXTENSIONS

EXCLUDED_DIRS = frozenset({
    ".git", ".hg", ".svn", ".idea", ".vscode", ".cache", ".mypy_cache",
    ".pytest_cache", ".ruff_cache", ".tox", ".venv", "venv", "__pycache__",
    "node_modules", "vendor", "vendors", "third_party", "dist", "build",
    "out", ".next", ".nuxt", ".svelte-kit", ".turbo", "coverage", "target",
    ".godot", ".import",
})

EXCLUDED_GLOBS = ("*.min.js", "*.min.css", "*.map", "*.lock", "*.generated.*")

#: Directory names that mark a test tree. Single authority: the test-location
#: gate reads this set too, so discovery and that gate cannot disagree about
#: whether a given path is a test.
TEST_DIRS = frozenset({
    "test", "tests", "__tests__", "spec", "specs", "testing",
    "integration-tests", "integration_tests", "e2e", "__snapshots__",
})

#: Filename patterns that mark a test file, across every language the gates
#: recognize. Same single-authority rule as TEST_DIRS.
TEST_GLOBS = (
    "test_*.gd", "*_test.gd",
    "test_*.py", "*_test.py", "*_tests.py",
    "*.test.*", "*.spec.*",
    "*_test.go", "*_test.rs", "*_tests.rs",
    "*Test.java", "*Tests.java", "*Test.kt", "*Tests.kt",
    "*Test.cs", "*Tests.cs", "*Tests.swift", "*Spec.swift",
    "*_test.rb", "*_spec.rb", "*Test.php", "*TestCase.php",
    "*_test.exs", "*_test.lua", "*.bats",
)

GIT_TIMEOUT_SECONDS = 30


class GateError(RuntimeError):
    """Configuration, discovery, or I/O failure. Always maps to exit code 2."""


def matches(path: str, patterns: Iterable[str]) -> bool:
    """Case-sensitive glob match against a POSIX-normalized relative path."""
    normalized = path.replace("\\", "/")
    return any(fnmatch.fnmatchcase(normalized, item.replace("\\", "/")) for item in patterns)


def normalize_extension(value: str) -> str:
    """Normalize `gd` or `.GD` to `.gd`. Raises for argparse on empty input."""
    cleaned = value.strip().lower()
    if not cleaned:
        raise argparse.ArgumentTypeError("empty extension")
    return cleaned if cleaned.startswith(".") else f".{cleaned}"


def infer_root() -> Path:
    """Walk upward from this file until a directory holding tooling/gates."""
    for candidate in Path(__file__).resolve().parents:
        if (candidate / TOOLING_DIRNAME / GATES_DIRNAME).is_dir():
            return candidate
    raise GateError("cannot infer repository root; pass --project-root")


def resolve_root(cli_value: Path | None, env_var: str) -> Path:
    """Resolve the project root from CLI, gate-specific env, shared env, or inference."""
    raw = cli_value or os.getenv(env_var) or os.getenv("QUALITY_GATE_PROJECT_ROOT")
    root = Path(raw).expanduser().resolve() if raw else infer_root()
    if not root.is_dir():
        raise GateError(f"project root does not exist: {root}")
    return root


def read_json(path: Path) -> Mapping[str, Any]:
    """Read a JSON object, returning an empty mapping when the file is absent."""
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise GateError(f"cannot read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise GateError(f"JSON root must be an object: {path}")
    return value


def config_section(root: Path, config_path: Path | None, name: str) -> Mapping[str, Any]:
    """Read one named section of the frozen policy file."""
    source = config_path.resolve() if config_path else root / CONFIG_FILENAME
    section = read_json(source).get(name, {})
    if not isinstance(section, dict):
        raise GateError(f"configuration section '{name}' must be an object")
    return section


def positive(value: Any, name: str, default: int) -> int:
    """Validate an optional positive integer policy value."""
    if value is None:
        return default
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise GateError(f"{name} must be a positive integer")
    return value


def strings(value: Any, name: str) -> list[str]:
    """Validate an optional list of non-empty strings."""
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise GateError(f"{name} must be a list of non-empty strings")
    return list(value)


def objects(value: Any, name: str) -> list[Mapping[str, Any]]:
    """Validate an optional list of JSON objects."""
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise GateError(f"{name} must be a list of objects")
    return list(value)


def resolve_extensions(cli_values: Sequence[str] | None, section: Mapping[str, Any], name: str) -> frozenset[str]:
    """CLI extensions win over policy, policy wins over the built-in default set."""
    configured = [normalize_extension(item) for item in strings(section.get("include_extensions"), name)]
    return frozenset(cli_values or configured or SOURCE_EXTENSIONS)


def generated_globs(root: Path) -> tuple[str, ...]:
    """Read the opt-in registry of generated files exempted from every gate."""
    paths = read_json(root / TOOLING_DIRNAME / GATES_DIRNAME / "generated-files.json").get("paths", [])
    if not isinstance(paths, list) or not all(isinstance(item, str) and item for item in paths):
        raise GateError("generated-files.json 'paths' must be non-empty strings")
    return tuple(paths)


def git_files(root: Path) -> list[Path] | None:
    """List tracked and untracked-but-not-ignored files, or None when unavailable.

    Returning None (rather than raising) lets the caller fall back to a
    filesystem walk, so the gates still work outside a checkout.
    """
    try:
        result = subprocess.run(
            [GIT_EXECUTABLE, "-C", str(root), GIT_LIST_FILES, "-co", "--exclude-standard", "-z"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=GIT_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return [
        root / raw.decode("utf-8", errors="surrogateescape")
        for raw in result.stdout.split(b"\0")
        if raw
    ]


def is_test_path(relative: str) -> bool:
    """True when a repository-relative path denotes a test file by directory or name."""
    path = Path(relative)
    if {part.lower() for part in path.parts[:-1]} & TEST_DIRS:
        return True
    return matches(path.name, TEST_GLOBS)


@dataclasses.dataclass(frozen=True, slots=True)
class DiscoveryRequest:
    """Everything `discover` needs, as one typed value.

    Bundling these keeps the call site readable and keeps the function inside
    the project's parameter-count limit, which the LOC gate enforces against
    this file like any other.
    """

    root: Path
    extensions: frozenset[str]
    exclude_globs: tuple[str, ...]
    max_file_bytes: int
    use_git: bool = True
    include_tests: bool = True


def discover(request: DiscoveryRequest) -> tuple[list[Path], list[str]]:
    """Select candidate source files and report per-file scan issues.

    Issues are returned rather than raised so a gate can decide whether an
    unreadable file is fatal. A gate must never report PASS while holding
    unresolved scan issues.
    """
    root = request.root
    candidates = git_files(root) if request.use_git else None
    if candidates is None:
        candidates = [path for path in root.rglob("*") if path.is_file()]
    generated = generated_globs(root)
    selected: list[Path] = []
    issues: list[str] = []
    seen: set[str] = set()
    for path in candidates:
        try:
            relative = path.relative_to(root).as_posix()
        except ValueError:
            continue
        if relative in seen or any(part in EXCLUDED_DIRS for part in Path(relative).parts[:-1]):
            continue
        seen.add(relative)
        if path.suffix.lower() not in request.extensions:
            continue
        if matches(relative, (*EXCLUDED_GLOBS, *request.exclude_globs, *generated)):
            continue
        if not request.include_tests and is_test_path(relative):
            continue
        try:
            size = path.stat().st_size
        except OSError as exc:
            issues.append(f"{relative}: cannot stat: {exc}")
            continue
        if size > request.max_file_bytes:
            issues.append(f"{relative}: exceeds {request.max_file_bytes} bytes")
            continue
        selected.append(path)
    return sorted(selected, key=lambda item: item.relative_to(root).as_posix()), issues


def read_source(path: Path, relative: str, issues: list[str]) -> str | None:
    """Read UTF-8 source, appending a scan issue and returning None on failure."""
    try:
        return path.read_text(encoding=SOURCE_ENCODING)
    except (OSError, UnicodeError) as exc:
        issues.append(f"{relative}: cannot read: {exc}")
        return None


def write_report(path: Path | None, content: str) -> None:
    """Write a report with LF endings so its hash is stable across platforms."""
    if path is None:
        return
    target = path.resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8", newline="\n")


def write_json_report(path: Path | None, payload: Any) -> None:
    """Write a JSON report with LF endings and a trailing newline."""
    if path is None:
        return
    write_report(path, json.dumps(payload, indent=2) + "\n")


def add_core_arguments(parser: argparse.ArgumentParser) -> None:
    """Register the options every gate reads, whatever it measures.

    The canonical verification pipeline depends on these exact names; a gate
    must not rename them.
    """
    parser.add_argument(PROJECT_ROOT_FLAG, type=Path)
    parser.add_argument(MAX_FILE_BYTES_FLAG, type=int, default=2_000_000)
    add_flags(parser, NO_GIT_FLAG, ALLOW_SCAN_ERRORS_FLAG, QUIET_FLAG)
    parser.add_argument(OUTPUT_FLAG, type=Path)
    parser.add_argument(JSON_OUTPUT_FLAG, type=Path)


def add_policy_arguments(parser: argparse.ArgumentParser) -> None:
    """Register the options only a policy-driven, extension-filtered gate reads.

    Kept separate from the core so a gate cannot advertise a flag it ignores.
    A CLI that silently accepts `--config` and never reads it is the same
    failure as a gate that reports PASS without scanning anything.
    """
    parser.add_argument(CONFIG_FLAG, type=Path)
    parser.add_argument(INCLUDE_EXTENSION_FLAG, action=APPEND, type=normalize_extension)
    add_repeatable(parser, EXCLUDE_GLOB_FLAG)


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    """Both halves, for a gate that reads a policy section."""
    add_core_arguments(parser)
    add_policy_arguments(parser)


def status_word(
    scan_issues: Sequence[str], blocking: Sequence[Any], allow_scan_errors: bool = False
) -> str:
    """Map a gate outcome to the word used in its Markdown report.

    Kept in step with `exit_code` on purpose. The report used to print ERROR
    while the process exited 0 under `--allow-scan-errors`, so a reader of the
    report and a reader of the exit code drew opposite conclusions from the
    same run. Waived issues now say so instead of hiding behind either word.
    """
    if scan_issues and not allow_scan_errors:
        return "ERROR"
    if blocking:
        return "FAIL"
    return "PASS (scan issues waived)" if scan_issues else "PASS"


def exit_code(scan_issues: Sequence[str], blocking_count: int, allow_scan_errors: bool) -> int:
    """Apply the shared exit-code contract: 2 beats 1, 1 beats 0."""
    if scan_issues and not allow_scan_errors:
        return 2
    return 1 if blocking_count else 0


# --------------------------------------------------------------------------
# Shared validation and CLI helpers
# --------------------------------------------------------------------------


def check_positive(values: Iterable[Any]) -> None:
    """Reject non-positive CLI limits before any scanning starts."""
    if any(value is not None and value <= 0 for value in values):
        raise GateError("limits must be positive")


def add_fail_on(parser: argparse.ArgumentParser, parse: Any, default: Any = None) -> None:
    """Register `--fail-on`, whose spelling both blocking gates share."""
    parser.add_argument(FAIL_ON_FLAG, type=parse, default=default)


def parse_kinds(value: str, known: Iterable[str]) -> frozenset[str]:
    """argparse type for a comma-separated `--fail-on`; `none` or `off` disables blocking."""
    normalized = {item.strip().lower() for item in value.split(",") if item.strip()}
    if normalized <= {"none", "off"}:
        return frozenset()
    unknown = normalized - frozenset(known)
    if unknown:
        raise argparse.ArgumentTypeError(f"unknown fail kinds: {', '.join(sorted(unknown))}")
    return frozenset(normalized)


def python_parse_message(location: str, exc: SyntaxError) -> str:
    """Uniform scan-issue text for a Python source the AST refuses to parse."""
    return f"{location}: Python parse error: {exc.msg}"


def python_parse_error(location: str, exc: SyntaxError) -> GateError:
    """The same text, raised rather than collected."""
    return GateError(python_parse_message(location, exc))


def add_flags(parser: argparse.ArgumentParser, *flags: str) -> None:
    """Register boolean opt-ins that default to off."""
    for flag in flags:
        parser.add_argument(flag, action=STORE_TRUE)


def add_include_tests(parser: argparse.ArgumentParser) -> None:
    """Register the opt-in that lets a gate scan test sources too."""
    add_flags(parser, INCLUDE_TESTS_FLAG)


def add_repeatable(parser: argparse.ArgumentParser, *flags: str) -> None:
    """Register repeatable string options that accumulate into a list."""
    for flag in flags:
        parser.add_argument(flag, action=APPEND, default=[])



def configure_stdio() -> None:
    """Force UTF-8 on the console so report text survives a Windows code page."""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
