#!/usr/bin/env python3
"""Markdown reporting shared by every Arhalies GAS quality gate.

All four gates published near-identical reports, so every heading and every
summary label existed three or four times over. The magic-string gate holds
authority over this directory and said so. The vocabulary lives here once,
and a gate supplies only what is genuinely its own.

Two rules are enforced by the renderer rather than left to each caller:
an empty section prints `- None` instead of disappearing, and the scan-issues
section is always appended. A report that quietly omits what it is holding is
the same defect as a gate that passes without scanning anything.
"""
from __future__ import annotations

import dataclasses
from pathlib import Path
from typing import Any, Sequence

from .gate_io import status_word

NONE_BULLET = "- None"
SCAN_ISSUES_TITLE = "Scan Issues"
VIOLATIONS_TITLE = "Violations"


@dataclasses.dataclass(frozen=True, slots=True)
class ReportSection:
    """One `## Title` block. An empty block renders as `- None`, never as nothing.

    A section that vanishes when it is empty is how a report starts looking
    clean while the scan behind it did no work.
    """

    title: str
    bullets: tuple[str, ...]


@dataclasses.dataclass(frozen=True, slots=True)
class Report:
    """Everything the shared Markdown renderer needs, as one typed value."""

    title: str
    root: Path
    blocking: Sequence[Any]
    scan_issues: Sequence[str]
    files_scanned: int | None = None
    allow_scan_errors: bool = False
    extra_rows: tuple[str, ...] = ()
    sections: tuple[ReportSection, ...] = ()


def summary_row(label: str, value: Any) -> str:
    """One `- Label: value` line of a report header."""
    return f"- {label}: {value}"


def section_lines(section: ReportSection) -> list[str]:
    """Render one `## Title` block, falling back to `- None`."""
    return [f"## {section.title}", "", *(section.bullets or (NONE_BULLET,)), ""]


def header_lines(report: Report) -> list[str]:
    """Render the title and the summary rows every gate shares."""
    lines = [
        f"# {report.title}",
        "",
        summary_row("Status", f"**{status_word(report.scan_issues, report.blocking, report.allow_scan_errors)}**"),
        summary_row("Project", f"`{report.root}`"),
    ]
    if report.files_scanned is not None:
        lines.append(summary_row("Source files scanned", report.files_scanned))
    lines.append(summary_row("Blocking findings", len(report.blocking)))
    lines.append(summary_row("Scan issues", len(report.scan_issues)))
    lines.extend(report.extra_rows)
    lines.append("")
    return lines


def render_report(report: Report) -> str:
    """Render a complete gate report, always ending in exactly one newline.

    The scan-issues section is appended by this function, not by the caller, so
    no gate can publish a report that omits the issues it is holding.
    """
    lines = header_lines(report)
    for section in report.sections:
        lines.extend(section_lines(section))
    issues = ReportSection(SCAN_ISSUES_TITLE, tuple(f"- {item}" for item in report.scan_issues))
    lines.extend(section_lines(issues))
    return "\n".join(lines).rstrip("\n") + "\n"
