#!/usr/bin/env python3
"""Check that a parity receipt still names scenarios that exist.

A receipt is a claim about the suite: this case is covered, and here is the
test that covers it. The claim rots the moment somebody renames a test - and it
rots silently, because a markdown table is not run by anything. So the
references in it are checked against the repository.

Each reference is written as ``path/to/file.gd::test_function`` inside
backticks. Every one must resolve to a file that exists and to a `func` of that
name declared in it. Nothing else in the receipt is inspected: the prose is for
a reader, the references are for this.

    python tooling/parity_receipt.py artifacts/parity/GATE_F5_2.md
    python tooling/parity_receipt.py --self-test

Exit 0 when every reference resolves, 1 when any does not, 2 on a usage error.
"""
from __future__ import annotations

import re
import sys
import tempfile
from pathlib import Path

import _gatelib

#: `some/file.gd::test_name`, which is the only shape a reference may take.
REFERENCE = re.compile(r"`([^`\s]+\.gd)::(\w+)`")


def declared(path: Path, function: str) -> bool:
    """Whether `path` declares `function` at the top level or inside a class."""
    try:
        source = path.read_text(encoding="utf-8")
    except OSError:
        return False
    return re.search(r"(?m)^\s*(?:static\s+)?func\s+%s\s*\(" % re.escape(function), source) is not None


def unresolved(receipt: Path) -> list[str]:
    """Every reference in `receipt` that does not name a real test."""
    root = Path.cwd()
    faults: list[str] = []
    seen: set[tuple[str, str]] = set()
    for relative, function in REFERENCE.findall(receipt.read_text(encoding="utf-8")):
        if (relative, function) in seen:
            continue
        seen.add((relative, function))
        target = root / relative
        if not target.is_file():
            faults.append("%s::%s - no such file" % (relative, function))
        elif not declared(target, function):
            faults.append("%s::%s - the file declares no such function" % (relative, function))
    if not seen:
        faults.append("%s names no scenario at all" % receipt)
    return faults


def self_test() -> int:
    """Prove the checker refuses what it is meant to refuse.

    A checker nobody has watched fail is a checker that might be reporting
    green on everything, and this one would then quietly bless a receipt whose
    every scenario had been renamed away. The three ways a reference can be
    wrong are each fed to it here.
    """
    real = "test/unit/test_compatibility_profile.gd::test_a_new_profile_is_godot_native"
    cases = [
        ("a reference to a file that is not there",
         "`test/unit/test_no_such_suite.gd::test_anything`", 1),
        ("a reference to a function that is not declared",
         "`test/unit/test_compatibility_profile.gd::test_nothing_declares_this`", 1),
        ("a receipt naming no scenario at all", "nothing in backticks here", 1),
        ("a reference that resolves", "`%s`" % real, 0),
    ]

    faults: list[str] = []
    with tempfile.TemporaryDirectory() as workspace:
        for described, body, expected in cases:
            probe = Path(workspace) / "probe.md"
            probe.write_text(body, encoding="utf-8")
            answered = 1 if unresolved(probe) else 0
            if answered != expected:
                faults.append("%s: answered %d, expected %d" % (described, answered, expected))

    if faults:
        print("PARITY_RECEIPT_SELF_TEST_FAIL")
        for fault in faults:
            print("  %s" % fault)
        return 1
    print("PARITY_RECEIPT_SELF_TEST_PASS %d cases" % len(cases))
    return 0


## The receipts that have to name scenarios. A gate receipt with no evidence in
## it is a gate receipt with no evidence, whatever else it says; the
## measurement and listing receipts beside them - a benchmark table, a
## distribution report, the traceability matrix - name none and are not
## expected to.
MUST_NAME = "GATE_"


def one(receipt: Path, must_name: bool) -> int:
    """Check a single receipt. Answers zero when there is nothing wrong."""
    faults = [
        fault for fault in unresolved(receipt)
        if must_name or "names no scenario at all" not in fault
    ]
    if faults:
        print("PARITY_RECEIPT_FAIL %s" % receipt)
        for fault in faults:
            print("  %s" % fault)
        return 1
    print("PARITY_RECEIPT_PASS %s" % receipt)
    return 0


def sweep() -> int:
    """Every receipt, in one go.

    Added because nothing ran this. A receipt is a claim, and the claim that
    went stale was one nobody re-read: a gate from an earlier phase named a
    scenario that had since been folded into another test, and the receipt went
    on saying it for as long as the only way to notice was to type the command
    by hand.
    """
    receipts = sorted(_gatelib.RECEIPTS.glob(_gatelib.RECEIPT_GLOB))
    if not receipts:
        print("parity_receipt: no receipts under %s" % _gatelib.RECEIPTS)
        return 2
    worst = 0
    for receipt in receipts:
        worst = max(worst, one(receipt, receipt.name.startswith(MUST_NAME)))
    print("PARITY_RECEIPTS: %s %d receipts" % ("PASS" if worst == 0 else "FAIL", len(receipts)))
    return worst


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    if argv[1] == "--self-test":
        return self_test()
    if argv[1] == "--all":
        return sweep()
    receipt = Path(argv[1])
    if not receipt.is_file():
        print("parity_receipt: no receipt at %s" % receipt)
        return 2
    return one(receipt, True)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
