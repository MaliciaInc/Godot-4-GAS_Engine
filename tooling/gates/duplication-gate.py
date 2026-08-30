#!/usr/bin/env python3
"""Source duplication gate.

Detects structural, masked, and behavioral duplication. The implementation is
stdlib-only, deterministic, bounded, and honors the explicit generated file
registry instead of source-text markers.

Comparable units come from `lib.duplication_units`, which measures a GDScript
function by indentation, a Python function with `ast`, and a C-like function
with a quote-aware brace matcher. Pairwise comparison lives in
`lib.duplication_matching`. Repository discovery, policy lookup, report
writing and the exit-code contract come from `lib.gate_io`, shared with the
other three gates so this gate carries no copy of any of them.

Root priority: --project-root, DUPLICATION_GATE_PROJECT_ROOT,
QUALITY_GATE_PROJECT_ROOT, then repository inference from this script.

Exit codes: 0 pass, 1 configured duplication violation, 2 scan/config error.
A scan issue is never a pass.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import json
import os
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Any, Mapping, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib import allowances  # noqa: E402
from lib import duplication_matching, duplication_units, gate_io, gate_report  # noqa: E402
from lib.duplication_matching import Comparison, Finding, Kind, MatchPolicy  # noqa: E402
from lib.duplication_units import ExtractionOptions, Unit  # noqa: E402

QUALITY_EXCLUDED_GLOBS = ("tooling/gates/**",)  # engineering policy source, not product duplication
STYLE_EXTENSIONS = frozenset({".css", ".scss", ".sass", ".less"})
DEFAULT_EXTENSIONS = gate_io.SOURCE_EXTENSIONS | STYLE_EXTENSIONS
FAIL_NAMES = frozenset(kind.value for kind in Kind)
ROOT_ENV_VAR = "DUPLICATION_GATE_PROJECT_ROOT"
GateError = gate_io.GateError
CONFIG_SECTION = "duplication"
LEFT_KEY = "left"
RIGHT_KEY = "right"
#: Findings name a unit as path:lines:name; only the path is matched.
SEPARATOR = ":"


@dataclasses.dataclass(frozen=True, slots=True)
class Config:
    """Everything one run of the gate was asked to do."""

    root: Path
    output: Path
    json_output: Path | None
    policy: MatchPolicy
    fail_on: frozenset[Kind]
    pair_allowlist: tuple[Mapping[str, Any], ...] = ()
    min_lines: int = 8
    min_tokens: int = 35
    shingle_size: int = 5
    include_tests: bool = False
    include_generated: bool = False
    include_globs: tuple[str, ...] = ()
    exclude_globs: tuple[str, ...] = ()
    extensions: frozenset[str] = frozenset()
    use_git: bool = True
    fallback_blocks: bool = True
    max_file_bytes: int = 2_000_000
    allow_scan_errors: bool = False
    workers: int = 1

    @property
    def effective_extensions(self) -> frozenset[str]:
        return self.extensions or DEFAULT_EXTENSIONS

    @property
    def extraction(self) -> ExtractionOptions:
        return ExtractionOptions(
            self.root, self.min_lines, self.min_tokens, self.shingle_size, self.fallback_blocks
        )


@dataclasses.dataclass(frozen=True, slots=True)
class ScanResult:
    """One complete run: what was measured, what was found, what failed to scan."""

    units: list[Unit]
    comparison: Comparison
    issues: list[str]
    files_scanned: int


def readmit_generated(config: Config, selected: list[Path]) -> list[Path]:
    """Put registry files back when `--include-generated` asks for them.

    Shared discovery always honors the generated registry; this gate is the
    only one with a flag to look inside it anyway.
    """
    patterns = gate_io.generated_globs(config.root)
    if not patterns:
        return selected
    known = {path.relative_to(config.root).as_posix() for path in selected}
    extensions = config.effective_extensions
    extra: list[Path] = []
    for path in config.root.rglob("*"):
        relative = path.relative_to(config.root).as_posix()
        if relative in known or not path.is_file() or path.suffix.lower() not in extensions:
            continue
        if any(part in gate_io.EXCLUDED_DIRS for part in Path(relative).parts[:-1]):
            continue
        if gate_io.matches(relative, patterns):
            extra.append(path)
    return selected + extra


def discover(config: Config) -> tuple[list[Path], list[str]]:
    """Shared discovery, plus the two selectors only this gate models."""
    request = gate_io.DiscoveryRequest(
        root=config.root,
        extensions=config.effective_extensions,
        exclude_globs=config.exclude_globs,
        max_file_bytes=config.max_file_bytes,
        use_git=config.use_git,
        include_tests=config.include_tests,
    )
    selected, issues = gate_io.discover(request)
    if config.include_generated:
        selected = readmit_generated(config, selected)
    if config.include_globs:
        selected = [
            path for path in selected
            if gate_io.matches(path.relative_to(config.root).as_posix(), config.include_globs)
        ]
    return sorted(selected, key=lambda item: item.relative_to(config.root).as_posix()), issues


def extract_units(config: Config) -> tuple[list[Unit], list[str], int]:
    """Extract every comparable unit in the selected files.

    The file count travels out with the units so the report can state it.
    A run that discovered nothing has to look different from a clean one.
    """
    files, issues = discover(config)
    options = config.extraction
    if config.workers == 1:
        results = [duplication_units.extract_file(path, options) for path in files]
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=config.workers) as pool:
            results = list(pool.map(lambda path: duplication_units.extract_file(path, options), files))
    units: list[Unit] = []
    for found, issue in results:
        units.extend(found)
        if issue:
            issues.append(issue)
    units.sort(key=lambda item: (item.path, item.start, item.name))
    return units, sorted(set(issues)), len(files)


def scan(config: Config) -> ScanResult:
    """Extract, then compare. Scan issues travel with the result, never silently."""
    units, issues, files_scanned = extract_units(config)
    return ScanResult(
        units, duplication_matching.compare(units, config.policy), issues, files_scanned
    )


def unit_census(units: list[Unit]) -> str:
    """`gdscript 12, python 4` - proof of which extractors actually fired."""
    counts: dict[str, int] = defaultdict(int)
    for unit in units:
        counts[unit.language] += 1
    return ", ".join(f"{name} {counts[name]}" for name in sorted(counts)) or "none"


def extra_rows(result: ScanResult, config: Config, elapsed: float) -> tuple[str, ...]:
    """The header rows that are this gate's own, beyond the shared ones.

    The census and both suppression counters are here on purpose: a run that
    extracted nothing, or that silently capped its own output, must say so in
    the report rather than present an empty PASS.
    """
    policy = config.policy
    caps = result.comparison.suppressed
    return (
        gate_report.summary_row("Units scanned", len(result.units)),
        gate_report.summary_row("Units by language", unit_census(result.units)),
        gate_report.summary_row("Findings", len(result.comparison.findings)),
        gate_report.summary_row("Elapsed", f"{elapsed:.3f}s"),
        gate_report.summary_row("Explicit default exclusions", ", ".join(QUALITY_EXCLUDED_GLOBS)),
        gate_report.summary_row(
            "Shape-only pairs not counted",
            f"{result.comparison.shape_only} (identifier overlap < {policy.structural_vocabulary} "
            f"or fewer than {policy.structural_min_vocabulary} identifiers)",
        ),
        gate_report.summary_row(
            f"Pairs found but not listed, per-kind cap {policy.max_pairs}",
            ", ".join(f"{kind.value} {caps[kind.value]}" for kind in Kind)
            + " (raise with --max-pairs)",
        ),
    )


def kind_sections(result: ScanResult) -> tuple[gate_report.ReportSection, ...]:
    """One section per match kind, in declaration order."""
    sections = []
    for kind in Kind:
        bullets = tuple(
            f"- {item.score:.3f} [{item.category.value}]: `{item.left}` <-> `{item.right}`"
            for item in result.comparison.findings
            if item.kind is kind
        )
        sections.append(gate_report.ReportSection(kind.value.title(), bullets))
    return tuple(sections)


def render(result: ScanResult, config: Config, elapsed: float) -> str:
    """Full Markdown report, deterministic for a given scan."""
    return gate_report.render_report(
        gate_report.Report(
            title="Duplication Gate",
            root=config.root,
            blocking=blocking(result, config),
            scan_issues=result.issues,
            files_scanned=result.files_scanned,
            allow_scan_errors=config.allow_scan_errors,
            extra_rows=extra_rows(result, config, elapsed),
            sections=kind_sections(result),
        )
    )


def json_payload(result: ScanResult, config: Config, elapsed: float) -> dict[str, object]:
    """Machine-readable mirror of the Markdown report."""
    blocked = blocking(result, config)
    return {
        "units": len(result.units),
        "units_by_language": unit_census(result.units),
        "elapsed_seconds": elapsed,
        "scan_issues": result.issues,
        "shape_only_pairs": result.comparison.shape_only,
        "suppressed": result.comparison.suppressed,
        "blocking": len(blocked),
        "findings": [
            {
                "kind": item.kind.value,
                "left": item.left,
                "right": item.right,
                "score": item.score,
                "category": item.category.value,
            }
            for item in result.comparison.findings
        ],
    }


def parse_fail_on(value: str) -> frozenset[Kind]:
    """Parse `--fail-on structural,masked`; `none` disables blocking entirely."""
    return frozenset(Kind(item) for item in gate_io.parse_kinds(value, FAIL_NAMES))


def positive(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def probability(value: str) -> float:
    parsed = float(value)
    if not 0 <= parsed <= 1:
        raise argparse.ArgumentTypeError("must be between 0 and 1")
    return parsed


def build_parser() -> argparse.ArgumentParser:
    """The CLI surface. The canonical pipeline depends on these exact names."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    gate_io.add_core_arguments(parser)
    gate_io.add_policy_arguments(parser)
    parser.set_defaults(output=Path("duplication-report.md"))
    parser.add_argument("--min-lines", type=positive, default=8)
    parser.add_argument("--min-tokens", type=positive, default=35)
    parser.add_argument("--shingle-size", type=positive, default=5)
    parser.add_argument("--masked-threshold", type=probability, default=0.86)
    parser.add_argument("--behavioral-threshold", type=probability, default=0.78)
    parser.add_argument("--structural-vocabulary", type=probability, default=0.55)
    parser.add_argument("--structural-min-vocabulary", type=positive, default=3)
    parser.add_argument("--max-pairs-per-kind", dest="max_pairs", type=positive, default=250)
    parser.add_argument("--max-feature-owners", type=positive, default=200)
    parser.add_argument("--workers", type=positive, default=max(1, min(8, os.cpu_count() or 2)))
    parser.add_argument("--max-snippet-lines", type=positive, default=180)
    gate_io.add_include_tests(parser)
    gate_io.add_flags(
        parser, "--include-generated", "--cross-language", "--no-fallback-blocks", "--print-config"
    )
    parser.add_argument(
        "--extensions", type=gate_io.normalize_extension, action=gate_io.APPEND, default=[]
    )
    # --include-extension is the shared spelling; --extensions is this gate's own.
    gate_io.add_repeatable(parser, gate_io.PATH_INCLUDE_FLAG, gate_io.PATH_EXCLUDE_FLAG)
    gate_io.add_fail_on(parser, parse_fail_on, frozenset({Kind.STRUCTURAL}))
    return parser


def build_policy(args: argparse.Namespace) -> MatchPolicy:
    """Collect the comparison thresholds the command line asked for."""
    return MatchPolicy(
        masked_threshold=args.masked_threshold,
        behavioral_threshold=args.behavioral_threshold,
        structural_vocabulary=args.structural_vocabulary,
        structural_min_vocabulary=args.structural_min_vocabulary,
        max_pairs=args.max_pairs,
        max_feature_owners=args.max_feature_owners,
        cross_language=args.cross_language,
    )


def anchored(root: Path, value: Path | None) -> Path | None:
    """Resolve a report path against the project root when it is not absolute."""
    if value is None:
        return None
    return value if value.is_absolute() else root / value


def pair_rules(args: argparse.Namespace) -> tuple[Mapping[str, Any], ...]:
    """The mirrors the policy declares, each having had to say why."""
    section = gate_io.config_section(args.project_root, args.config, CONFIG_SECTION)
    rules = tuple(gate_io.objects(section.get("pair_allowlist"), "duplication.pair_allowlist"))
    for rule in rules:
        validate_pair(rule)
    return rules


def validate_pair(rule: Mapping[str, Any]) -> None:
    """A declared mirror must name both sides and why they are one."""
    if not all(
        isinstance(rule.get(key), str) and rule.get(key)
        for key in (LEFT_KEY, RIGHT_KEY, allowances.REASON_KEY)
    ):
        raise GateError("duplication.pair_allowlist requires left/right/reason")


def unit_label(finding_side: str) -> str:
    """A finding names a unit as path:lines:name. Matched on path and name only,
    because line numbers move every time anything above them is edited."""
    parts = finding_side.split(SEPARATOR)
    if len(parts) < 3:
        return finding_side
    return parts[0] + SEPARATOR + parts[-1]


def declared(left: str, right: str, rules: Sequence[Mapping[str, Any]]) -> bool:
    """Whether this pair is one the policy already accounts for."""
    here: str = unit_label(left)
    there: str = unit_label(right)
    for rule in rules:
        one: str = str(rule[LEFT_KEY])
        other: str = str(rule[RIGHT_KEY])
        if gate_io.matches(here, [one]) and gate_io.matches(there, [other]):
            return True
        if gate_io.matches(here, [other]) and gate_io.matches(there, [one]):
            return True
    return False


def blocking(result: ScanResult, config: Config) -> list[Finding]:
    """What can fail the build, minus the mirrors the policy explains."""
    found = duplication_matching.blocking_findings(
        result.comparison.findings, config.fail_on
    )
    if not config.pair_allowlist:
        return found
    return [
        item for item in found if not declared(item.left, item.right, config.pair_allowlist)
    ]


def build_config(args: argparse.Namespace) -> Config:
    """Turn parsed arguments into the frozen configuration the scan reads."""
    root = gate_io.resolve_root(args.project_root, ROOT_ENV_VAR)
    output = anchored(root, args.output)
    if output is None:  # unreachable: --output carries a default
        raise gate_io.GateError("--output is required")
    return Config(
        root=root,
        output=output,
        json_output=anchored(root, args.json_output),
        policy=build_policy(args),
        fail_on=args.fail_on,
        pair_allowlist=pair_rules(args),
        min_lines=args.min_lines,
        min_tokens=args.min_tokens,
        shingle_size=args.shingle_size,
        include_tests=args.include_tests,
        include_generated=args.include_generated,
        include_globs=tuple(args.include),
        exclude_globs=tuple((*QUALITY_EXCLUDED_GLOBS, *args.exclude)),
        extensions=frozenset(args.extensions),
        use_git=not args.no_git,
        fallback_blocks=not args.no_fallback_blocks,
        max_file_bytes=args.max_file_bytes,
        allow_scan_errors=args.allow_scan_errors,
        workers=args.workers,
    )


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        gate_io.check_positive((args.max_file_bytes,))
        config = build_config(args)
        if args.print_config:
            print(json.dumps(dataclasses.asdict(config), default=str, indent=2))
        started = time.perf_counter()
        result = scan(config)
        elapsed = time.perf_counter() - started
        report = render(result, config, elapsed)
        gate_io.write_report(config.output, report)
        gate_io.write_json_report(config.json_output, json_payload(result, config, elapsed))
        if not args.quiet:
            print(report, end="")
        blocked = blocking(result, config)
        return gate_io.exit_code(result.issues, len(blocked), config.allow_scan_errors)
    except (gate_io.GateError, OSError) as exc:
        print(f"duplication-gate: ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    gate_io.configure_stdio()
    raise SystemExit(main())
