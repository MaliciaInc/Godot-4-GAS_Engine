#!/usr/bin/env python3
"""GAS_Engine LOC and source-structure gate.

Enforces the frozen limits in `.quality-gates.json`: lines per file, lines per
function, parameters per function, module-frontier rules, entrypoint shape and
canonical headers. Generated source is exempt only when registered in
`tooling/gates/generated-files.json`.

Function measurement is dispatched by extension, because the three families of
source here delimit a body three different ways:

    .py / .pyi   the standard library `ast`, which reports exact end lines
    .gd          `lib.gdscript_regions`, which closes a body by indentation
    braces       a declaration regex plus a quote/comment-aware brace matcher

GDScript needs its own path: a brace matcher finds no body at all in a `.gd`
file and `ast.parse` rejects the syntax, so without it every GDScript file
measured as zero functions and passed unconditionally.

Exit: 0 pass, 1 violation, 2 error/incomplete scan.
"""
from __future__ import annotations

import argparse
import ast
import dataclasses
import re
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib import gate_io, gate_report, loc_regions  # noqa: E402
from lib import allowances  # noqa: E402
from lib.loc_regions import FunctionRegion, extract_functions  # noqa: E402

GateError = gate_io.GateError

#: Shared with the magic-string gate's allowlist: one mechanism, one
#: spelling of the keys that make an exemption auditable.
EXEMPTION_KEYS = allowances.EXEMPTION_KEYS
MAX_LINES_KEY = "max_lines"

FORBIDDEN_FRONTIER = re.compile(
    r"^(?:export\s+)?(?:const|let|var|function|class|interface|enum|namespace|default)\b"
    r"|^export\s+type\s+[A-Za-z_$]"
)
FRONTIER_EXPORT_PREFIXES = ("export {", "export type {")
FRONTIER_BOUNDARY_PREFIXES = ("export ", "import type ")
INDEX_FRONTIER_NAMES = ("index.ts", "index.tsx")
DEFAULT_FRONTIER_GLOBS = ("**/index.ts", "**/index.tsx")
DEFAULT_MAX_FILE_LINES = 450
DEFAULT_MAX_FUNCTION_LINES = 120
DEFAULT_MAX_PARAMETERS = 5


@dataclasses.dataclass(frozen=True, slots=True)
class Settings:
    """Resolved policy: CLI over `.quality-gates.json` over built-in defaults."""

    max_file_lines: int
    max_function_lines: int
    max_parameters: int
    max_file_bytes: int
    extensions: frozenset[str]
    exclude_globs: tuple[str, ...]
    frontier_globs: tuple[str, ...]
    entrypoints: tuple[Mapping[str, Any], ...]
    required_headers: tuple[Mapping[str, Any], ...]
    file_allowlist: tuple[Mapping[str, Any], ...]
    function_allowlist: tuple[Mapping[str, Any], ...]
    parameter_allowlist: tuple[Mapping[str, Any], ...]
    use_git: bool
    allow_scan_errors: bool


@dataclasses.dataclass(frozen=True, slots=True)
class Result:
    """Outcome. Scan issues stay apart from violations: an incomplete scan is an
    error (exit 2), never a pass."""

    files_scanned: int
    violations: tuple[str, ...]
    scan_issues: tuple[str, ...]


def _bad_count(value: Any, minimum: int) -> bool:
    """True when an optional policy integer is present but out of range."""
    return value is not None and (isinstance(value, bool) or not isinstance(value, int) or value < minimum)


def validate_rules(settings: Settings) -> None:
    """Reject malformed policy objects before any file is read."""
    for rule in settings.entrypoints:
        if not isinstance(rule.get(allowances.GLOB_KEY), str):
            raise GateError("each loc.entrypoints item requires 'glob'")
        if rule.get("allowed_functions") is not None:
            gate_io.strings(rule["allowed_functions"], "loc.entrypoints allowed_functions")
        if _bad_count(rule.get("exact_function_count"), 0):
            raise GateError("entrypoint exact_function_count must be non-negative")
        if _bad_count(rule.get(MAX_LINES_KEY), 1):
            raise GateError("entrypoint max_lines must be positive")
    for rule in settings.file_allowlist:
        validate_file_allowance(rule)
    for rule in settings.required_headers:
        if not isinstance(rule.get(allowances.GLOB_KEY), str) or not isinstance(rule.get("lines"), list):
            raise GateError("required_headers requires glob and lines")
    for rule in settings.function_allowlist:
        validate_exemption(rule, "function_length_allowlist")
    for rule in settings.parameter_allowlist:
        validate_exemption(rule, "function_parameter_allowlist")


def validate_file_allowance(rule: Mapping[str, Any]) -> None:
    """A raised file ceiling must name where, how high, and why."""
    named: bool = all(
        isinstance(rule.get(key), str) and rule.get(key)
        for key in (allowances.GLOB_KEY, allowances.REASON_KEY)
    )
    if not named:
        raise GateError("file_length_allowlist requires glob/reason")
    if rule.get(MAX_LINES_KEY) is None or _bad_count(rule.get(MAX_LINES_KEY), 1):
        raise GateError("file_length_allowlist requires a positive max_lines")


def validate_exemption(rule: Mapping[str, Any], name: str) -> None:
    """An exemption must name where, what, and why."""
    if not all(isinstance(rule.get(key), str) and rule.get(key) for key in EXEMPTION_KEYS):
        raise GateError(f"{name} requires glob/function/reason")


def load_settings(root: Path, args: argparse.Namespace) -> Settings:
    """Merge CLI flags over the frozen `loc` policy section."""
    section = gate_io.config_section(root, args.config, "loc")
    frontier = (*gate_io.strings(section.get("frontier_globs"), "loc.frontier_globs"), *args.frontier_glob)
    settings = Settings(
        max_file_lines=args.max_file_lines
        or gate_io.positive(section.get("max_file_lines"), "loc.max_file_lines", DEFAULT_MAX_FILE_LINES),
        max_function_lines=args.max_function_lines
        or gate_io.positive(section.get("max_function_lines"), "loc.max_function_lines", DEFAULT_MAX_FUNCTION_LINES),
        max_parameters=args.max_parameters
        or gate_io.positive(section.get("max_parameters"), "loc.max_parameters", DEFAULT_MAX_PARAMETERS),
        max_file_bytes=args.max_file_bytes,
        extensions=gate_io.resolve_extensions(args.include_extension, section, "loc.include_extensions"),
        exclude_globs=(
            *gate_io.strings(section.get(gate_io.EXCLUDE_GLOBS_KEY), gate_io.EXCLUDE_GLOBS_KEY),
            *args.exclude_glob,
        ),
        frontier_globs=frontier or DEFAULT_FRONTIER_GLOBS,
        entrypoints=tuple(gate_io.objects(section.get("entrypoints"), "loc.entrypoints")),
        required_headers=tuple(gate_io.objects(section.get("required_headers"), "loc.required_headers")),
        file_allowlist=tuple(
            gate_io.objects(section.get("file_length_allowlist"), "loc.file_length_allowlist")
        ),
        function_allowlist=tuple(
            gate_io.objects(section.get("function_length_allowlist"), "loc.function_length_allowlist")
        ),
        parameter_allowlist=tuple(
            gate_io.objects(section.get("function_parameter_allowlist"), "loc.function_parameter_allowlist")
        ),
        use_git=not args.no_git,
        allow_scan_errors=args.allow_scan_errors,
    )
    validate_rules(settings)
    return settings


def exempt(relative: str, function: FunctionRegion, rules: Sequence[Mapping[str, Any]]) -> bool:
    """True when one of `rules` names this function in this file.

    Both dimensions share this. An exemption is a declaration with a written
    reason, auditable in the policy file - it is not a relaxed limit. Raising
    max_parameters from 5 to 7 would exempt every function in the project;
    naming one function in one file exempts exactly that.
    """
    return any(
        gate_io.matches(relative, [str(rule[allowances.GLOB_KEY])]) and rule[allowances.FUNCTION_KEY] in (function.name, function.label)
        for rule in rules
    )


def function_findings(relative: str, functions: Sequence[FunctionRegion], settings: Settings) -> list[str]:
    """Length and parameter-count violations, reported with the exact span."""
    findings: list[str] = []
    for item in functions:
        where = f"{relative}:{item.start_line}: {item.label}"
        over_lines: bool = item.line_count > settings.max_function_lines
        if over_lines and not exempt(relative, item, settings.function_allowlist):
            findings.append(f"{where} LOC {item.line_count} > {settings.max_function_lines}"
                            f" (lines {item.start_line}-{item.end_line})")
        over_params: bool = item.parameter_count > settings.max_parameters
        if over_params and not exempt(relative, item, settings.parameter_allowlist):
            findings.append(f"{where} params {item.parameter_count} > {settings.max_parameters}")
    return findings


def frontier_findings(
    relative: str, text: str, functions: Sequence[FunctionRegion], settings: Settings
) -> list[str]:
    """A module frontier re-exports; it must not define implementation."""
    if not gate_io.matches(relative, settings.frontier_globs):
        return []
    findings = [f"{relative}: module frontier contains function body '{item.label}'" for item in functions]
    if not (relative.endswith(INDEX_FRONTIER_NAMES) or relative in INDEX_FRONTIER_NAMES):
        return findings
    export_block = False
    for number, line in enumerate(text.splitlines(), 1):
        clean = line.strip()
        if not clean or clean.startswith(("//", "/*", "*")):
            continue
        if export_block:
            export_block = "}" not in clean
        elif FORBIDDEN_FRONTIER.search(clean):
            findings.append(f"{relative}:{number}: index frontier defines implementation/type: {clean[:100]}")
        elif clean.startswith(FRONTIER_EXPORT_PREFIXES) and "}" not in clean:
            export_block = True
        elif not clean.startswith(FRONTIER_BOUNDARY_PREFIXES):
            findings.append(f"{relative}:{number}: index frontier contains non-boundary statement: {clean[:100]}")
    return findings


def rule_findings(
    relative: str, lines: Sequence[str], functions: Sequence[FunctionRegion], settings: Settings
) -> list[str]:
    """Entrypoint shape and canonical-header violations."""
    findings: list[str] = []
    for rule in settings.entrypoints:
        allowed = rule.get("allowed_functions")
        if not gate_io.matches(relative, [str(rule[allowances.GLOB_KEY])]):
            continue
        if rule.get("max_lines") is not None and len(lines) > rule["max_lines"]:
            findings.append(f"{relative}: entrypoint LOC {len(lines)} > {rule['max_lines']}")
        if rule.get("exact_function_count") is not None and len(functions) != rule["exact_function_count"]:
            findings.append(f"{relative}: entrypoint expected {rule['exact_function_count']}"
                            f" functions, found {len(functions)}")
        unexpected = sorted({item.label for item in functions} - set(allowed)) if allowed else []
        if unexpected:
            findings.append(f"{relative}: entrypoint unexpected functions: {', '.join(unexpected)}")
    for rule in settings.required_headers:
        if gate_io.matches(relative, [str(rule[allowances.GLOB_KEY])]) and list(lines[:len(rule["lines"])]) != rule["lines"]:
            findings.append(f"{relative}: missing configured canonical header")
    return findings


def file_ceiling(relative: str, settings: Settings) -> int:
    """This file's line ceiling: the policy's, unless an exception raises it."""
    ceiling = settings.max_file_lines
    for rule in settings.file_allowlist:
        if gate_io.matches(relative, [str(rule[allowances.GLOB_KEY])]):
            ceiling = max(ceiling, int(rule[MAX_LINES_KEY]))
    return ceiling


def file_findings(
    relative: str, text: str, functions: Sequence[FunctionRegion], settings: Settings
) -> list[str]:
    """Every violation this one file produces."""
    lines = text.splitlines()
    findings: list[str] = []
    ceiling = file_ceiling(relative, settings)
    if len(lines) > ceiling:
        findings.append(f"{relative}: file LOC {len(lines)} > {ceiling}")
    findings.extend(function_findings(relative, functions, settings))
    findings.extend(frontier_findings(relative, text, functions, settings))
    findings.extend(rule_findings(relative, lines, functions, settings))
    return findings


def evaluate(root: Path, settings: Settings) -> Result:
    """Discover, measure and judge every in-scope source file."""
    request = gate_io.DiscoveryRequest(
        root=root,
        extensions=settings.extensions,
        exclude_globs=settings.exclude_globs,
        max_file_bytes=settings.max_file_bytes,
        use_git=settings.use_git,
    )
    files, issues = gate_io.discover(request)
    violations: list[str] = []
    for path in files:
        relative = path.relative_to(root).as_posix()
        text = gate_io.read_source(path, relative, issues)
        if text is None:
            continue
        try:
            functions = extract_functions(relative, text)
        except GateError as exc:
            # An unparseable file is an incomplete scan, not a clean file. It is
            # recorded so the run still writes reports and still exits 2.
            issues.append(str(exc))
            continue
        violations.extend(file_findings(relative, text, functions, settings))
    return Result(len(files), tuple(sorted(set(violations))), tuple(sorted(set(issues))))


def report(result: Result, root: Path, settings: Settings) -> gate_report.Report:
    """Project the scan onto the shared report contract."""
    return gate_report.Report(
        title="LOC and Structure Gate",
        root=root,
        blocking=result.violations,
        scan_issues=result.scan_issues,
        files_scanned=result.files_scanned,
        allow_scan_errors=settings.allow_scan_errors,
        sections=(
            gate_report.ReportSection(gate_report.VIOLATIONS_TITLE, tuple(f"- {item}" for item in result.violations)),
        ),
    )


def build_parser() -> argparse.ArgumentParser:
    """The canonical CLI. The verification chain depends on these exact names."""
    parser = argparse.ArgumentParser(description="GAS_Engine LOC and source-structure gate.")
    gate_io.add_common_arguments(parser)
    parser.add_argument("--max-file-lines", type=int)
    parser.add_argument("--max-function-lines", type=int)
    parser.add_argument("--max-parameters", type=int)
    gate_io.add_repeatable(parser, "--frontier-glob")
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the gate. 0 pass, 1 violation, 2 configuration or scan error."""
    args = build_parser().parse_args(argv)
    try:
        limits = (args.max_file_bytes, args.max_file_lines, args.max_function_lines, args.max_parameters)
        gate_io.check_positive(limits)
        root = gate_io.resolve_root(args.project_root, "LOC_GATE_PROJECT_ROOT")
        settings = load_settings(root, args)
        result = evaluate(root, settings)
        text = gate_report.render_report(report(result, root, settings))
        gate_io.write_report(args.output, text)
        gate_io.write_json_report(args.json_output, dataclasses.asdict(result))
        if not args.quiet:
            print(text, end="")
        return gate_io.exit_code(result.scan_issues, len(result.violations), settings.allow_scan_errors)
    except (GateError, OSError) as exc:
        print(f"loc-gate: ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    gate_io.configure_stdio()
    raise SystemExit(main())
