#!/usr/bin/env python3
"""Run one quality gate with its canonical invocation.

The canonical CLI is a contract Task 0 sealed, and it was being spelled twice:
once where each gate declares its options, and again in `tooling/verify.ps1`
where they are passed. Two spellings of one contract drift the first time either
side is touched, and nothing would report it - the runner would simply stop
passing an option nobody noticed had been renamed.

This is the single owner. `verify.ps1` names a gate and a receipt directory;
everything else - the flag names, the report paths, which findings block - comes
from here and from `lib.gate_io`, in Python, next to the gates themselves.

    python tooling/gates/run_gate.py loc artifacts/gates/T3

Exit code is the gate's own, propagated verbatim.
"""
from __future__ import annotations

import dataclasses
import subprocess
import sys
from pathlib import Path

GATE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(GATE_DIR))

from lib import gate_io  # noqa: E402

ROOT = GATE_DIR.parent.parent

#: The policy lives beside the gates rather than at the repository root. The
#: root is the public product, and a file there named for the private process
#: would state that the process exists even while its contents stayed out.
POLICY_PATH = GATE_DIR.parent / gate_io.CONFIG_FILENAME

#: duplication-gate reads no policy file, so its exclusion is passed on the
#: command line, using the flag name the gate itself declares.

#: Discovery normally asks git which files exist, and git does not list an
#: ignored one. `tooling/` is deliberately untracked - this repository is public
#: and is the addon, not the process that built it - so git-based discovery
#: dropped the gates out of their own scan: 99 files became 73 and every gate
#: still said PASS. Override 4 keeps the gates in scope of their own policy, so
#: the canonical invocation walks the filesystem instead, using the flag name
#: gate_io already declares rather than a second spelling of it.
VENDORED_GUT_GLOB = "addons/gut/**"


@dataclasses.dataclass(frozen=True, slots=True)
class Gate:
    """One gate: what to run, where its reports go, and what blocks."""

    name: str
    script: str
    report: str
    extra: tuple[str, ...] = ()
    #: Whether this gate reads the policy file. duplication-gate takes its
    #: exclusions on the command line and reads none, so offering it --config
    #: would be an unknown option rather than a configuration.
    reads_policy: bool = True


#: The canonical order of section 8, and the only place it is written down.
GATES: tuple[Gate, ...] = (
    Gate("loc", "loc-gate.py", "loc"),
    Gate("test-location", "test-location-gate.py", "test-location"),
    Gate(
        "magic-string",
        "magic-string-gate.py",
        "magic-strings",
        (gate_io.FAIL_ON_FLAG, "repeated,templates,colors"),
    ),
    Gate(
        "duplication",
        "duplication-gate.py",
        "duplication",
        (
            gate_io.INCLUDE_TESTS_FLAG,
            gate_io.FAIL_ON_FLAG,
            "structural,masked",
            # GUT is pinned byte-identical by step 11.6 and must not be edited,
            # so duplication findings inside it can never be actioned. The
            # magic-string policy excludes it for the same reason; this gate
            # reads no configuration file, so the exclusion is passed here.
            gate_io.PATH_EXCLUDE_FLAG,
            VENDORED_GUT_GLOB,
        ),
    ),
)

BY_NAME = {gate.name: gate for gate in GATES}


def invocation(gate: Gate, receipt_dir: Path) -> list[str]:
    """The exact argv for one gate."""
    base = receipt_dir / gate.report
    return [
        sys.executable,
        str(GATE_DIR / gate.script),
        gate_io.PROJECT_ROOT_FLAG,
        str(ROOT),
        gate_io.OUTPUT_FLAG,
        str(base.with_suffix(".md")),
        gate_io.JSON_OUTPUT_FLAG,
        str(base.with_suffix(".json")),
        gate_io.NO_GIT_FLAG,
        *((gate_io.CONFIG_FLAG, str(POLICY_PATH)) if gate.reads_policy else ()),
        *gate.extra,
    ]


def run(name: str, receipt_dir: Path) -> int:
    gate = BY_NAME.get(name)
    if gate is None:
        print(f"unknown gate: {name}; expected one of {', '.join(BY_NAME)}", file=sys.stderr)
        return 2
    receipt_dir.mkdir(parents=True, exist_ok=True)
    return subprocess.run(invocation(gate, receipt_dir), check=False).returncode


#: Asking for the roster rather than restating it. `verify.ps1` calls this, so
#: adding a gate means editing GATES above and nothing else.
LIST_FLAG = "--list"


def main(argv: list[str]) -> int:
    if len(argv) == 1 and argv[0] == LIST_FLAG:
        for gate in GATES:
            print(gate.name)
        return 0
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print(f"usage: run_gate.py <gate> <receipt-directory> | {LIST_FLAG}", file=sys.stderr)
        return 2
    return run(argv[0], Path(argv[1]))


if __name__ == "__main__":
    gate_io.configure_stdio()
    raise SystemExit(main(sys.argv[1:]))
