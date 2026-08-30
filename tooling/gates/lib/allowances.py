#!/usr/bin/env python3
"""The vocabulary of an auditable exemption, shared by the gates that grant one.

Two gates let the policy waive a finding: the LOC gate names a function that may
exceed the parameter limit, and the magic-string gate names a literal that may
repeat. They are the same mechanism - a declaration in the policy file with a
written reason - and they were spelling its keys separately.

The rule both enforce: an exemption without a reason is refused. A list of
waived findings that does not say why is indistinguishable from a weaker gate,
and the point of an allowlist is that a reader can tell those apart.
"""
from __future__ import annotations

from typing import Any, Mapping, Sequence

from .gate_io import GateError

#: Where a rule applies, what it names, and why it is granted.
GLOB_KEY = "glob"
FUNCTION_KEY = "function"
REASON_KEY = "reason"

#: The literal a magic-string allowance waives.
LITERAL_KEY = "literal"

#: Every LOC exemption names all three. All or none: a partial rule would match
#: more than its author meant.
EXEMPTION_KEYS = (GLOB_KEY, FUNCTION_KEY, REASON_KEY)


def justified_reason(entry: Mapping[str, Any], label: str) -> str:
    """The entry's reason, or a GateError naming what is missing."""
    reason = entry.get(REASON_KEY)
    if not isinstance(reason, str) or not reason.strip():
        raise GateError(
            "%s needs a %r saying why it is allowed" % (label, REASON_KEY)
        )
    return reason


def allowed_literals(raw: Any, extra: Sequence[str]) -> tuple[str, ...]:
    """The literals a policy waives, each having recorded why.

    An entry may be a bare string - how the CLI passes a one-off override - or
    an object carrying the literal and its reason. Policy entries come through
    the same list, so an object that omits its reason is a configuration error
    rather than a silent allowance.
    """
    if raw is None:
        return tuple(extra)
    if not isinstance(raw, list):
        raise GateError("allow_literals must be a list")

    literals: list[str] = []
    for index, entry in enumerate(raw):
        if isinstance(entry, str):
            literals.append(entry)
            continue
        if not isinstance(entry, dict):
            raise GateError(
                "allow_literals[%d] must be a string or an object" % index
            )
        literal = entry.get(LITERAL_KEY)
        if not isinstance(literal, str) or not literal:
            raise GateError(
                "allow_literals[%d] needs a non-empty %r" % (index, LITERAL_KEY)
            )
        justified_reason(entry, "allow_literals[%d] (%r)" % (index, literal))
        literals.append(literal)
    return (*literals, *extra)
