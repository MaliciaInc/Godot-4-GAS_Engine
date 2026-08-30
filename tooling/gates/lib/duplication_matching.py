#!/usr/bin/env python3
"""Pairwise comparison of the units the duplication gate extracted.

Three kinds of duplication are separated here, weakest evidence last:

    structural   identical token shape, corroborated by a shared vocabulary
    masked       near-identical shape after every name was erased
    behavioral   same control flow, operator and call profile, different shape

The vocabulary check is what keeps `structural` honest. Two functions can
share a shape without sharing a single domain name - a pair of small typed
data builders, for instance - and calling that duplication would train people
to ignore the gate. A pair rejected for that reason is still counted, as
`shape_only`, so the rejection is visible rather than silent.

This module owns no policy of its own: `MatchPolicy` arrives from the gate,
which builds it from the frozen configuration and the command line.
"""
from __future__ import annotations

import dataclasses
import enum
import itertools
from collections import defaultdict

from .duplication_units import Category, Unit, finding_category


class Kind(str, enum.Enum):
    STRUCTURAL = "structural"
    MASKED = "masked"
    BEHAVIORAL = "behavioral"


@dataclasses.dataclass(frozen=True, slots=True)
class MatchPolicy:
    """Every threshold the comparison honors, as one immutable value."""

    masked_threshold: float = 0.86
    behavioral_threshold: float = 0.78
    # A structural match counts as duplication only when the vocabulary
    # corroborates it: enough distinct identifiers, and enough overlap.
    structural_vocabulary: float = 0.55
    structural_min_vocabulary: int = 3
    max_pairs: int = 250
    max_feature_owners: int = 200
    cross_language: bool = False


@dataclasses.dataclass(frozen=True, slots=True)
class Finding:
    kind: Kind
    left: str
    right: str
    score: float
    category: Category


@dataclasses.dataclass(frozen=True, slots=True)
class Comparison:
    """Findings plus the two counts that would otherwise vanish silently.

    A blocking count that stops rising because it hit a cap reads as "this is
    all there was", so the cap and the rejections are reported alongside it.
    """

    findings: list[Finding]
    shape_only: int
    suppressed: dict[str, int]


def jaccard(left: frozenset[str], right: frozenset[str]) -> float:
    """Overlap of two sets. Two empty sets are treated as identical."""
    union = len(left | right)
    return len(left & right) / union if union else 1.0


def weighted(left: dict[str, int], right: dict[str, int]) -> float:
    """Overlap of two multisets, weighted by how often each feature occurs."""
    keys = set(left) | set(right)
    denominator = sum(max(left.get(key, 0), right.get(key, 0)) for key in keys)
    if not denominator:
        return 1.0
    return sum(min(left.get(key, 0), right.get(key, 0)) for key in keys) / denominator


def bucket_key(unit: Unit, policy: MatchPolicy) -> str:
    """Units only compare inside one language unless cross-language is on."""
    return "*" if policy.cross_language else unit.language


def pair_key(left: Unit, right: Unit) -> tuple[str, str]:
    """Order-independent identity of a pair of units."""
    ordered = sorted((left.ref, right.ref))
    return (ordered[0], ordered[1])


def candidate_pairs(units: list[Unit], policy: MatchPolicy) -> set[tuple[int, int]]:
    """Pairs sharing at least one token shingle, ignoring ubiquitous shingles.

    A shingle owned by more files than `max_feature_owners` is boilerplate,
    not evidence, and pairing every owner of it would be quadratic for nothing.
    """
    owners: dict[tuple[str, str], list[int]] = defaultdict(list)
    for index, unit in enumerate(units):
        for feature in unit.shingles:
            owners[(bucket_key(unit, policy), feature)].append(index)
    pairs: set[tuple[int, int]] = set()
    for indexes in owners.values():
        if len(indexes) > policy.max_feature_owners:
            continue
        pairs.update((min(a, b), max(a, b)) for a, b in itertools.combinations(indexes, 2))
    return pairs


def structural_findings(
    units: list[Unit], policy: MatchPolicy, suppressed: dict[str, int]
) -> tuple[list[Finding], set[tuple[str, str]], int]:
    """Group units by identical shape, then require the vocabulary to agree."""
    groups: dict[tuple[str, tuple[str, ...]], list[Unit]] = defaultdict(list)
    for unit in units:
        groups[(bucket_key(unit, policy), unit.normalized)].append(unit)
    findings: list[Finding] = []
    matched: set[tuple[str, str]] = set()
    shape_only = 0
    for group in groups.values():
        for left, right in itertools.combinations(group, 2):
            thin = min(len(left.identifiers), len(right.identifiers)) < policy.structural_min_vocabulary
            if thin or jaccard(left.identifiers, right.identifiers) < policy.structural_vocabulary:
                shape_only += 1
                continue
            matched.add(pair_key(left, right))
            if len(findings) >= policy.max_pairs:
                suppressed[Kind.STRUCTURAL.value] += 1
                continue
            findings.append(
                Finding(Kind.STRUCTURAL, left.ref, right.ref, 1.0, finding_category(left, right))
            )
    return findings, matched, shape_only


def similarity_findings(
    units: list[Unit], policy: MatchPolicy, matched: set[tuple[str, str]], suppressed: dict[str, int]
) -> list[Finding]:
    """Masked and behavioral duplication among pairs structure did not claim."""
    findings: list[Finding] = []
    masked_count = behavioral_count = 0
    for left_index, right_index in sorted(candidate_pairs(units, policy)):
        left, right = units[left_index], units[right_index]
        if pair_key(left, right) in matched:
            continue
        category = finding_category(left, right)
        masked_score = jaccard(left.shingles, right.shingles)
        if masked_score >= policy.masked_threshold:
            if masked_count < policy.max_pairs:
                findings.append(Finding(Kind.MASKED, left.ref, right.ref, masked_score, category))
                masked_count += 1
            else:
                suppressed[Kind.MASKED.value] += 1
            continue
        behavior_score = weighted(left.behavior, right.behavior)
        if behavior_score < policy.behavioral_threshold:
            continue
        if behavioral_count < policy.max_pairs:
            findings.append(Finding(Kind.BEHAVIORAL, left.ref, right.ref, behavior_score, category))
            behavioral_count += 1
        else:
            suppressed[Kind.BEHAVIORAL.value] += 1
    return findings


def compare(units: list[Unit], policy: MatchPolicy) -> Comparison:
    """Full comparison, ordered deterministically for a stable report."""
    suppressed = {kind.value: 0 for kind in Kind}
    findings, matched, shape_only = structural_findings(units, policy, suppressed)
    findings.extend(similarity_findings(units, policy, matched, suppressed))
    findings.sort(key=lambda item: (item.kind.value, -item.score, item.left, item.right))
    return Comparison(findings, shape_only, suppressed)


def blocking_findings(findings: list[Finding], fail_on: frozenset[Kind]) -> list[Finding]:
    """Only executable duplication of a configured kind can fail the build."""
    return [item for item in findings if item.kind in fail_on and item.category is Category.EXECUTABLE]
