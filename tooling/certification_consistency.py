"""Whether the certification docs agree with each other and with the goldens.

AUD-01 found `UE_PARITY_MATRIX_F6.md` still declaring `not run` and
`GATE_F6_5.md` carrying `CLOSED` and `BLOCKED` for the same findings at the
same commit - two truths in one file, or one truth in one file and its
opposite in the next. A reader has no way to tell which is current, and
neither did the tooling: nothing recomputed either claim against the goldens
that are the actual evidence.

So `artifacts/parity/f6_result.json` is the one place the numbers are typed,
and this script does two things with it rather than one:

    recomputes `scenario_count` and `verified_count` from the goldens
    themselves, so the JSON cannot drift from the evidence it is about;

    requires a status line generated from that JSON, byte for byte, inside
    every doc `f6_result.json` names as generated from it - so a doc that
    was not updated when the JSON was is caught here rather than by the next
    person who reads both and notices they disagree.

Usage:

    python tooling/certification_consistency.py

Exit codes:

    0  the JSON matches the goldens, its internal state is not contradictory,
       its commit is real and reachable, and every generated doc carries the
       matching status line
    1  any of the above is not true
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from parity_diff import UE_VERIFIED as VERIFIED

RESULT = Path("artifacts/parity/f6_result.json")
GOLDENS = Path("test/parity/goldens")

## What "closed" and "blocked" are allowed to mean together. A status naming
## both is the exact shape AUD-01 found: one file agreeing with itself in two
## directions at once.
CLOSED_WORDS = ("CLOSED", "PASS")
BLOCKED_WORDS = ("BLOCKED", "STOP")


def marker(result: dict) -> str:
	"""The one line every generated doc must carry, spelled from the JSON.

	A single line rather than a full render of the file: the docs carry prose
	no generator here should own, and what actually goes stale is the verdict,
	not the sentence around it. Checking the sentence is cheap and checking it
	verbatim is what makes two different phrasings of "still true" impossible.
	"""
	stop = result.get("stop_code")
	return "CERTIFICATION_STATUS: status=%s verified=%d/%d numeric_mismatches=%d trace_mismatches=%d stop_code=%s" % (
		result.get("status", ""),
		result.get("verified_count", -1),
		result.get("scenario_count", -1),
		result.get("numeric_mismatches", -1),
		result.get("trace_mismatches", -1),
		stop if stop else "none",
	)


def golden_counts() -> tuple[int, int]:
	"""How many goldens exist, and how many of them are `UE_VERIFIED`."""
	total = 0
	verified = 0
	for path in sorted(GOLDENS.glob("*.json")):
		total += 1
		data = json.loads(path.read_text(encoding="utf-8"))
		if data.get("evidence") == VERIFIED:
			verified += 1
	return total, verified


def commit_is_reachable(commit: str) -> str:
	"""Empty when `commit` is real and an ancestor of HEAD; the fault otherwise."""
	exists = subprocess.run(
		["git", "cat-file", "-e", commit + "^{commit}"], capture_output=True
	)
	if exists.returncode != 0:
		return "tested_commit %s is not a commit this repository has" % commit
	ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", commit, "HEAD"])
	if ancestor.returncode != 0:
		return "tested_commit %s is not an ancestor of HEAD" % commit
	return ""


def faults(result: dict) -> list[str]:
	"""Everything wrong with the certification, in the order a reader would find it."""
	wrong: list[str] = []

	status = str(result.get("status", ""))
	stop = result.get("stop_code")
	closed = any(word in status for word in CLOSED_WORDS)
	blocked = any(word in status for word in BLOCKED_WORDS)
	if closed and blocked:
		wrong.append("status %r claims both closed and blocked at once" % status)
	if closed and stop:
		wrong.append("status %r is closed but stop_code is %r" % (status, stop))
	if blocked and not stop:
		wrong.append("status %r is blocked but stop_code is empty" % status)

	total, verified = golden_counts()
	if result.get("scenario_count") != total:
		wrong.append(
			"scenario_count is %r, the goldens directory has %d"
			% (result.get("scenario_count"), total)
		)
	if result.get("verified_count") != verified:
		wrong.append(
			"verified_count is %r, %d goldens actually say %s"
			% (result.get("verified_count"), verified, VERIFIED)
		)
	if verified > 0 and blocked:
		wrong.append(
			"%d goldens are %s but status %r is blocked" % (verified, VERIFIED, status)
		)

	commit = str(result.get("tested_commit", ""))
	if not commit:
		wrong.append("tested_commit is empty")
	else:
		reach_fault = commit_is_reachable(commit)
		if reach_fault:
			wrong.append(reach_fault)

	line = marker(result)
	for doc in result.get("generated_docs", []):
		path = Path(doc)
		if not path.is_file():
			wrong.append("%s is named as generated and does not exist" % doc)
			continue
		if line not in path.read_text(encoding="utf-8"):
			wrong.append("%s does not carry the current status line: %s" % (doc, line))

	return wrong


def main() -> int:
	if not RESULT.is_file():
		print("no %s to check" % RESULT)
		return 1
	result = json.loads(RESULT.read_text(encoding="utf-8"))
	wrong = faults(result)
	for fault in wrong:
		print("FAULT: %s" % fault)
	print(
		"CERTIFICATION_CONSISTENCY: %s %s"
		% ("PASS" if not wrong else "FAIL", marker(result))
	)
	return 1 if wrong else 0


if __name__ == "__main__":
	sys.exit(main())
