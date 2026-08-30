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

__all__ = ["gate_io"]
