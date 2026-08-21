"""Sensitive-population builder: any-evidence ``CohortExpression``.

The sensitive population ``P`` is the set of persons with **any evidence** of
the disease within a window (default: within available observation). Unlike the
sensitive *entry* cohort (first-ever ``I`` diagnosis), ``P`` is index-date
independent and may be widened across domains (e.g. a semaglutide drug exposure
counts as evidence of T2D even without a T2D diagnosis).
"""

from __future__ import annotations

from collections.abc import Iterable

from circe.cohortdefinition import CohortExpression, PrimaryCriteria
from circe.cohortdefinition.core import ObservationFilter, ResultLimit
from circe.vocabulary import ConceptSet

from ..cohorts.criteria import (
    condition_occurrence,
    device_exposure,
    drug_exposure,
    measurement,
    observation,
    procedure,
    visit,
)

# Domain name -> criterion builder (shared with ``criteria.py``).
_DOMAIN_BUILDERS = {
    "condition_occurrence": condition_occurrence,
    "observation": observation,
    "measurement": measurement,
    "procedure": procedure,
    "device_exposure": device_exposure,
    "drug_exposure": drug_exposure,
    "visit_occurrence": visit,
}


def domain_criteria(domain: str, codeset_id: int):
    """Build a single-domain criterion object for *domain* and *codeset_id*."""
    builder = _DOMAIN_BUILDERS.get(domain.lower())
    if builder is None:
        available = ", ".join(sorted(_DOMAIN_BUILDERS))
        raise ValueError(f"Unknown domain {domain!r}. Available: {available}")
    return builder(codeset_id)


def evidence_criteria(evidence: Iterable[tuple[str, int]]):
    """Build domain criterion objects from ``(domain, codeset_id)`` pairs.

    Also accepts pre-built criterion objects (a non-tuple entry) passed through
    unchanged.
    """
    out = []
    for entry in evidence:
        if isinstance(entry, tuple):
            domain, codeset_id = entry
            out.append(domain_criteria(domain, codeset_id))
        else:
            out.append(entry)
    return out


def evidence_expression(
    primary,
    *,
    concept_sets: Iterable[ConceptSet] | None = None,
    observation_window: ObservationFilter | None = None,
    primary_limit: str = "All",
    name: str = "sensitive population",
) -> CohortExpression:
    """Build the any-evidence sensitive-population expression.

    ``primary`` is a sequence of domain criterion objects (e.g.
    ``ConditionOccurrence(codeset_id=cs_I.id)``) or ``(domain, codeset_id)``
    pairs. Every criterion is treated as *any occurrence* (not first-ever), and
    the default observation window is "within available observation"
    (``ObservationFilter(prior_days=0, post_days=0)``).
    """
    criteria = evidence_criteria(primary)
    return CohortExpression(
        title=name,
        concept_sets=list(concept_sets) if concept_sets else [],
        primary_criteria=PrimaryCriteria(
            criteria_list=criteria,
            observation_window=observation_window or ObservationFilter(prior_days=0, post_days=0),
            primary_limit=ResultLimit(type=primary_limit),
        ),
        expression_limit=ResultLimit(type="First"),
        qualified_limit=ResultLimit(type="First"),
    )
