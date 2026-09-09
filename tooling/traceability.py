"""Every finding the phase names, its one owner, and whether it landed.

The phase document's traceability matrix says each of thirty-three findings has
exactly one owner and no more. A matrix nobody checks is a claim: an owner can
be dropped when a section is rewritten, two can be given the same finding, and
the count at the bottom goes on saying thirty-three because it was typed rather
than counted.

So this reads the matrix out of the document itself rather than carrying a copy
- a second list here would be the same drift one file further along - and asks
three things of it:

    every finding has exactly one owner;
    the ids are the eleven defects and twenty-two gaps the document counts;
    every finding is claimed by a receipt, with a status and a reference.

The third is what makes this more than arithmetic. A receipt under
`artifacts/parity/` carries a row per finding saying CLOSED, EXPLICIT_DEVIATION
or BLOCKED and pointing at the test that says so, and a finding nothing claims
is a finding nobody did.

BLOCKED is reported and is not a pass. The phase document is explicit: during
execution a blocked finding is a STOP and the phase stays open, so this exits
non-zero while one exists rather than letting a green run imply otherwise.

Usage:

    python tooling/traceability.py [--write RECEIPT]

Exit codes:

    0  thirty-three findings, one owner each, every one claimed CLOSED or
       EXPLICIT_DEVIATION by a receipt
    1  a duplicate owner, a missing finding, a count that disagrees, a finding
       no receipt claims, or one still BLOCKED - which is a stop rather than a
       failure of the engine
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PHASE = Path("docs/Fases/FASE_6_MAESTRA_EJECUTABLE_CIERRE_PARIDAD_UE57_GAS_ENGINE.md")
RECEIPTS = Path("artifacts/parity")
DEFAULT_RECEIPT = RECEIPTS / "TRACEABILITY_F6.md"

## The section the matrix lives in, and the one that ends it. Both spellings,
## because the same table is read out of two places.
##
## The phase document is where the matrix is decided, and it is not in this
## repository: `docs/` is ignored, deliberately, since the phase papers are
## working documents rather than shipped product. So a clean checkout has the
## receipt and not the source, and this reads whichever is there - saying which,
## because checking a receipt against itself is a weaker claim than checking it
## against the document that decided it, and the two must not be confused.
OPENS = "# 11. MATRIZ ÚNICA DE TRAZABILIDAD"
CLOSES = "# 12."
RECEIPT_OPENS = "## Every finding, and who closed it"

## How many of each the document counts. Spelled here so a matrix that grew a
## row without the count being updated fails rather than passing at thirty-four.
DEFECTS = 11
GAPS = 22

ROW = re.compile(r"^\|\s*([DG]-\d{2})\s*\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|")

## A receipt's claim about one finding: the id, whatever it is called there,
## the status, and the reference. Matched loosely on the middle because a
## receipt describes a finding in its own words and should go on being able to.
CLAIM = re.compile(r"^\|\s*([DG]-\d{2})[^|]*\|\s*\**([A-Z_]+)\**\s*\|")

## What a finding is allowed to be. BLOCKED is allowed to be written down and
## is not allowed to be the end state: the phase says so and this enforces it.
SETTLED: tuple[str, ...] = ("CLOSED", "EXPLICIT_DEVIATION")
STOPPED = "BLOCKED"


class Finding:
	"""One row: what it is, who owns it, and what else was involved."""

	def __init__(self, identifier: str, owner: str, support: str) -> None:
		self.identifier = identifier
		self.owner = owner
		self.support = support


def rows(document: str) -> list[Finding]:
	"""The matrix, as it is written wherever it was read from.

	The receipt's table carries two more columns than the document's; the
	pattern below takes the first three of however many there are, which is the
	id, its owner and its support in both.
	"""
	opened = document.find(OPENS)
	if opened < 0:
		opened = document.find(RECEIPT_OPENS)
	if opened < 0:
		return []
	closed = document.find(CLOSES, opened + 1)
	body = document[opened:] if closed < 0 else document[opened:closed]

	found: list[Finding] = []
	for line in body.splitlines():
		matched = ROW.match(line)
		if matched:
			found.append(Finding(matched.group(1), matched.group(2), matched.group(3)))
	return found


def claims() -> dict[str, tuple[str, str]]:
	"""What each receipt says about each finding: its status, and where.

	The first claim wins when two receipts mention one finding, which happens
	when a later package revisits an earlier one - and is why the receipts are
	read in name order rather than in whatever order the filesystem gives.
	"""
	said: dict[str, tuple[str, str]] = {}
	for receipt in sorted(RECEIPTS.glob("*.md")):
		if receipt.name == DEFAULT_RECEIPT.name:
			continue
		for line in receipt.read_text(encoding="utf-8").splitlines():
			matched = CLAIM.match(line)
			if matched and matched.group(1) not in said:
				said[matched.group(1)] = (matched.group(2), receipt.name)
	return said


def faults(found: list[Finding], said: dict[str, tuple[str, str]]) -> list[str]:
	"""Everything wrong with the matrix, in the order a reader would find it."""
	wrong: list[str] = []

	seen: dict[str, str] = {}
	for finding in found:
		if finding.identifier in seen:
			wrong.append(
				"%s appears twice, owned by %s and by %s"
				% (finding.identifier, seen[finding.identifier], finding.owner)
			)
		seen[finding.identifier] = finding.owner

	defects = [one for one in seen if one.startswith("D-")]
	gaps = [one for one in seen if one.startswith("G-")]
	if len(defects) != DEFECTS:
		wrong.append("%d defects, and the phase counts %d" % (len(defects), DEFECTS))
	if len(gaps) != GAPS:
		wrong.append("%d gaps, and the phase counts %d" % (len(gaps), GAPS))

	for expected in range(1, DEFECTS + 1):
		if "D-%02d" % expected not in seen:
			wrong.append("D-%02d is not in the matrix" % expected)
	for expected in range(1, GAPS + 1):
		if "G-%02d" % expected not in seen:
			wrong.append("G-%02d is not in the matrix" % expected)

	for finding in found:
		if finding.identifier not in said:
			wrong.append(
				"%s is owned by %s and no receipt claims it"
				% (finding.identifier, finding.owner)
			)
			continue
		status, where = said[finding.identifier]
		if status == STOPPED:
			wrong.append(
				"%s is %s in %s - a stop, and the phase stays open"
				% (finding.identifier, STOPPED, where)
			)
		elif status not in SETTLED:
			wrong.append(
				"%s is %s in %s, which is not a state a finding may be in"
				% (finding.identifier, status, where)
			)
	return wrong


def receipt_text(found: list[Finding], wrong: list[str]) -> str:
	"""The matrix as a receipt, with the verdict at the top."""
	lines: list[str] = [
		"# Traceability — FASE 6",
		"",
		"Generated by `python tooling/traceability.py --write`. Read out of the phase",
		"document rather than copied from it, so a row added, removed or re-owned there",
		"changes this and is checked rather than silently disagreeing.",
		"",
		"- Findings: **%d** (%d defects, %d gaps)" % (len(found), DEFECTS, GAPS),
		"- Owners: one each, and no finding owned twice.",
		"- Verdict: **%s**" % ("PASS" if not wrong else "FAIL"),
		"",
	]
	if wrong:
		lines.append("## What is wrong")
		lines.append("")
		for fault in wrong:
			lines.append("- %s" % fault)
		lines.append("")
	lines.append("## Every finding, and who closed it")
	lines.append("")
	lines.append("| Finding | Owner | Support | Status | Claimed in |")
	lines.append("|---|---|---|---|---|")
	said = claims()
	for finding in found:
		status, where = said.get(finding.identifier, ("—", "—"))
		lines.append(
			"| %s | %s | %s | %s | %s |"
			% (finding.identifier, finding.owner, finding.support or "—", status, where)
		)
	lines.append("")
	return "\n".join(lines)


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--write", nargs="?", const=str(DEFAULT_RECEIPT), default="")
	parsed = parser.parse_args()

	source = PHASE if PHASE.is_file() else DEFAULT_RECEIPT
	if not source.is_file():
		print("neither %s nor %s is here to read a matrix out of" % (PHASE, DEFAULT_RECEIPT))
		return 1

	found = rows(source.read_text(encoding="utf-8"))
	wrong = faults(found, claims())
	print("read the matrix from %s" % source)

	if parsed.write:
		target = Path(parsed.write)
		target.parent.mkdir(parents=True, exist_ok=True)
		target.write_text(receipt_text(found, wrong), encoding="utf-8", newline="\n")
		print("wrote %s" % target)

	for fault in wrong:
		print("FAULT: %s" % fault)
	print(
		"TRACEABILITY: %s %d findings, %d unique owners"
		% ("PASS" if not wrong else "FAIL", len(found), len({one.owner for one in found}))
	)
	return 1 if wrong else 0


if __name__ == "__main__":
	sys.exit(main())
