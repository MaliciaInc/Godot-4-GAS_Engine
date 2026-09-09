"""Make the gates' shared library importable from the tools beside it.

`tooling/seal_policy.py` and `tooling/project_invariants.py` are not gates, but
they speak the same vocabulary: the same CLI flag, the same policy filename, the
same executable. Rather than each re-spelling that vocabulary, they import it -
and rather than each working out how to reach it, they import it from here.

This is the one place that names the gates directory. A bootstrap cannot use
the constant it bootstraps, which is why that literal lives here and is recorded
in the magic-string policy with exactly that reason.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "gates"))

from lib import gate_io  # noqa: E402,F401

## Where the parity and closure receipts live, and what they are.
##
## Two tools sweep this directory - the receipt checker and the traceability
## check - and a directory spelled twice is a directory one of them goes on
## reading after the other has been moved.
RECEIPTS = Path("artifacts/parity")
RECEIPT_GLOB = "*.md"

__all__ = ["gate_io", "RECEIPTS", "RECEIPT_GLOB"]
