"""What the reference says, against what this engine does - and a refusal to
pretend when the reference has not been asked.

The corpus under `test/parity/goldens/` is the only thing in this repository
allowed to be called parity, and a golden earns that by carrying outputs a real
Unreal Engine 5.7.4 produced. Until it does it says NOT_UE_VERIFIED and this
tool stops: a number authored from documentation is a reviewable claim, and
presenting one as parity is the failure the whole corpus exists to prevent.

Two things are checked, in this order:

    every golden has the fields the phase names, spelled the way it names them;
    every golden says which of the two evidence states it is in.

and then, only for goldens that are UE_VERIFIED, the engine's own outputs are
compared against them. Those outputs come from
`artifacts/parity/results/ue_scenarios.json`, written by the suite - this tool
runs no engine and invents no number.

Usage:

    python tooling/parity_diff.py [--goldens DIR] [--results FILE]

Exit codes:

    0  every golden is UE_VERIFIED and every comparison agreed
    1  a golden is malformed, a comparison disagreed, or the corpus is not
       verified - which is a stop, not a failure of the engine
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

REPO = pathlib.Path(__file__).resolve().parent.parent
GOLDENS = REPO / "test" / "parity" / "goldens"
RESULTS = REPO / "artifacts" / "parity" / "results" / "ue_scenarios.json"

UE_VERIFIED = "UE_VERIFIED"
NOT_UE_VERIFIED = "NOT_UE_VERIFIED"
STATES = (UE_VERIFIED, NOT_UE_VERIFIED)

# The fields the phase names, each of them because a golden missing it is a
# claim that cannot be checked in that dimension.
REQUIRED = (
    "scenario",
    "ue_version",
    "changelist",
    "evidence",
    "inputs",
    "outputs",
    "numeric_tolerance",
    "execution_order_observable",
    "execution_order",
)

STOP = "STOP: UE_REFERENCE_UNAVAILABLE\nPACKAGE: F6.5"


def load(path: pathlib.Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def faults_in(golden: dict[str, Any], named: str) -> list[str]:
    """Everything wrong with one golden's shape, rather than the first thing."""
    faults: list[str] = []
    for field in REQUIRED:
        if field not in golden:
            faults.append("%s: no `%s`" % (named, field))
    if golden.get("evidence") not in STATES:
        faults.append(
            "%s: evidence is %r, which is neither %s nor %s"
            % (named, golden.get("evidence"), UE_VERIFIED, NOT_UE_VERIFIED)
        )
    if golden.get("evidence") == UE_VERIFIED and golden.get("outputs") is None:
        faults.append(
            "%s: says %s and carries no outputs, which is a claim with nothing "
            "behind it" % (named, UE_VERIFIED)
        )
    if golden.get("execution_order_observable") and golden.get("evidence") == UE_VERIFIED:
        if not golden.get("execution_order"):
            faults.append(
                "%s: the order is observable and %s, and is not written down"
                % (named, UE_VERIFIED)
            )
    return faults


def compared(golden: dict[str, Any], produced: Any, named: str) -> list[str]:
    """Where the engine and the reference disagree, to the golden's tolerance."""
    if produced is None:
        return ["%s: verified, and the engine produced nothing to compare" % named]
    tolerance = float(golden.get("numeric_tolerance", 0.0))
    return _differences(golden["outputs"], produced, tolerance, named)


def _under(where: str, key: str) -> str:
    """Where inside a golden a difference is, said the way a reader would."""
    return where + "." + key


def _differences(want: Any, got: Any, tolerance: float, where: str) -> list[str]:
    if isinstance(want, dict):
        if not isinstance(got, dict):
            return ["%s: expected an object, got %r" % (where, type(got).__name__)]
        faults: list[str] = []
        for key, value in want.items():
            if key not in got:
                faults.append(_under(where, key) + ": missing")
                continue
            faults.extend(_differences(value, got[key], tolerance, _under(where, key)))
        return faults
    if isinstance(want, list):
        if not isinstance(got, list) or len(got) != len(want):
            return ["%s: expected %d entries, got %r" % (where, len(want), got)]
        faults = []
        for index, value in enumerate(want):
            faults.extend(
                _differences(value, got[index], tolerance, "%s[%d]" % (where, index))
            )
        return faults
    if isinstance(want, (int, float)) and isinstance(got, (int, float)):
        if abs(float(want) - float(got)) > tolerance:
            return ["%s: %s vs %s (tolerance %s)" % (where, want, got, tolerance)]
        return []
    if want != got:
        return ["%s: %r vs %r" % (where, want, got)]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goldens", default=str(GOLDENS))
    parser.add_argument("--results", default=str(RESULTS))
    args = parser.parse_args()

    folder = pathlib.Path(args.goldens)
    files = sorted(folder.glob("*.json"))
    if not files:
        print("PARITY_DIFF_FAIL: no goldens under %s" % folder)
        return 1

    produced: dict[str, Any] = {}
    results = pathlib.Path(args.results)
    if results.exists():
        produced = load(results)

    faults: list[str] = []
    unverified: list[str] = []
    verified = 0

    for path in files:
        golden = load(path)
        named = golden.get("scenario", path.stem)
        shape = faults_in(golden, named)
        faults.extend(shape)
        if shape:
            continue
        if golden["evidence"] != UE_VERIFIED:
            unverified.append(named)
            continue
        verified += 1
        faults.extend(compared(golden, produced.get(named), named))

    print("goldens: %d" % len(files))
    print("%s: %d" % (UE_VERIFIED, verified))
    print("%s: %d" % (NOT_UE_VERIFIED, len(unverified)))
    for fault in faults:
        print("  - " + fault)

    if faults:
        print("PARITY_DIFF_FAIL")
        return 1
    if unverified:
        print()
        print(STOP)
        print()
        print(
            "The corpus is not certified: %d scenario(s) have no outputs from a\n"
            "real Unreal Engine %s run. Nothing here is a failure of this engine -\n"
            "the comparison has not been made. See tools/ue_reference/README.md\n"
            "for how to produce them, and artifacts/parity/UE_REFERENCE_F6.md for\n"
            "what this blocks." % (len(unverified), files and load(files[0])["ue_version"])
        )
        for named in unverified:
            print("  - " + named)
        return 1

    print("PARITY_DIFF_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
