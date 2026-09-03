"""What the engine stages ran against, and whether it is still that.

Two stages happen outside this gate chain, driven by whatever tool the operator
uses to reach Godot, so the chain reads their verdict out of a receipt. A
receipt is a claim, and a claim nobody checks drifts: the suite receipt was once
four hours older than the commit that added the tests it vouched for, and the
chain reported PASS over tests it had never run.

So a receipt now carries a fingerprint of the sources those stages cover, and
the chain recomputes it. Content rather than timestamps, because the documented
workflow rewrites `project.godot` after every driven run and would age a receipt
that is in fact current.

Both halves live here on purpose. The writer and the reader of a fingerprint
that disagree would agree on a wrong answer, and verify.ps1 spelling the same
prefix in another language is exactly how that starts.
"""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
from pathlib import Path

## What the driven stages load. Spelled here, independently of any other scan in
## tooling, because this script decides for itself what it covers.
##
## README.md is in the list for a reason that is easy to miss: a test reads it,
## so it is a source the suite loads rather than prose beside the code. Left out,
## an edit to the quick start would leave the receipt claiming to have run
## against a README that no longer says what it said.
COVERED: tuple[str, ...] = ("*.gd", "*.tscn", "project.godot", "README.md")

## Which receipt belongs to which stage. The chain asks for the verdict and is
## told; it does not know these names.
STAGES: dict[str, str] = {
	"godot-import": "mcp-godot-import.txt",
	"gut-suite": "mcp-gut.txt",
}

VERDICT_PREFIX = "RESULT: "
SOURCE_PREFIX = "SOURCE: "
PASSED = "PASS"


def covered_files() -> list[str]:
	"""Every tracked file the driven stages load. Sorted, so the hash is stable."""
	# --others as well as the index: a script that exists but has not been added
	# yet is still a script the suite loaded, and a fingerprint blind to it
	# reports evidence as current over code nobody ran. --exclude-standard keeps
	# ignored files out, so a stray tool artifact does not age a good receipt.
	listed = subprocess.run(
		["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", *COVERED],
		capture_output=True, text=True, check=True,
	)
	return sorted(line for line in listed.stdout.splitlines() if line.strip())


def fingerprint() -> str:
	digest = hashlib.sha256()
	for relative in covered_files():
		path = Path(relative)
		if not path.is_file():
			continue
		digest.update(relative.encode("utf-8"))
		digest.update(b"\0")
		digest.update(path.read_bytes())
		digest.update(b"\0")
	return digest.hexdigest()


def record(directory: Path, stage: str, verdict: str, detail: str) -> int:
	"""Write one stage's receipt, stamped with what it ran against."""
	if stage not in STAGES:
		print("%s is not a stage: %s" % (stage, ", ".join(sorted(STAGES))))
		return 1
	directory.mkdir(parents=True, exist_ok=True)
	receipt = directory / STAGES[stage]
	receipt.write_text(
		"%s%s\n%s%s\n%s\n" % (VERDICT_PREFIX, verdict, SOURCE_PREFIX, fingerprint(), detail),
		encoding="utf-8", newline="\n",
	)
	print("%s: recorded %s" % (stage, verdict))
	return 0


def _fault(directory: Path, stage: str, expected: str) -> str:
	"""What is wrong with this stage's receipt, or nothing."""
	receipt = directory / STAGES[stage]
	if not receipt.is_file():
		return "MISSING engine evidence at %s" % receipt
	lines = receipt.read_text(encoding="utf-8").splitlines()
	verdict = lines[0].removeprefix(VERDICT_PREFIX).strip() if lines else ""
	if verdict != PASSED:
		return "engine evidence reports %s" % (verdict or "nothing at all")
	stamped = [one for one in lines if one.startswith(SOURCE_PREFIX)]
	if not stamped:
		return "engine evidence does not say what it ran against"
	ran = stamped[0].removeprefix(SOURCE_PREFIX).strip()
	if ran != expected:
		return "STALE engine evidence, it ran against %s, the tree is now %s" % (
			ran[:12], expected[:12]
		)
	return ""


def check(directory: Path) -> int:
	"""Report every driven stage, and fail if any of them cannot be trusted."""
	expected = fingerprint()
	worst = 0
	for stage in STAGES:
		fault = _fault(directory, stage, expected)
		print("%s: %s" % (stage, fault or "%s (evidence current)" % PASSED))
		if fault:
			worst = 1
	return worst


def main() -> int:
	"""Check by default; the chain should not have to name what it wants.

	Every word the caller has to spell is a word two languages now agree on, and
	each one is a place they can quietly stop agreeing. Checking is what the
	chain does, so checking is what happens when it says nothing else.
	"""
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("receipts", nargs="?", default="")
	parser.add_argument("--stage", default="")
	parser.add_argument("--verdict", default="")
	parser.add_argument("--detail", default="")

	parsed = parser.parse_args()
	if not parsed.receipts:
		parser.error("say which directory the receipts are in")
	if parsed.stage:
		return record(Path(parsed.receipts), parsed.stage, parsed.verdict, parsed.detail)
	return check(Path(parsed.receipts))


if __name__ == "__main__":
	sys.exit(main())
