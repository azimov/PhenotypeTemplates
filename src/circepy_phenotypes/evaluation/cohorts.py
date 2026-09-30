"""Gold-standard (xSpec) cohort builder and person-set helpers.

The gold standard ``G`` is a ``CohortExpression`` supplied by the researcher
(an expert-defined "xSpec" definition) or assembled here from CircePy primary
criteria + optional inclusion rules.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence

from circe.cohortdefinition import CohortExpression, InclusionRule, PrimaryCriteria
from circe.cohortdefinition.core import ObservationFilter, ResultLimit
from circe.vocabulary import ConceptSet


def gold_standard_expression(
    primary,
    *,
    concept_sets: Iterable[ConceptSet] | None = None,
    inclusion_rules: Sequence[InclusionRule] = (),
    observation_window: ObservationFilter | None = None,
    primary_limit: str = "First",
    name: str = "gold standard",
    end_strategy=None,
    collapse_settings=None,
) -> CohortExpression:
    """Build a gold-standard (xSpec) ``CohortExpression``.

    ``primary`` is a sequence of domain criterion objects (typically
    ``ConditionOccurrence(codeset_id=..., first=True)`` etc.). Defaults to a
    first-occurrence entry within observation (mirroring the base case).
    """
    return CohortExpression(
        title=name,
        concept_sets=list(concept_sets) if concept_sets else [],
        primary_criteria=PrimaryCriteria(
            criteria_list=list(primary),
            observation_window=observation_window or ObservationFilter(prior_days=0, post_days=0),
            primary_limit=ResultLimit(type=primary_limit),
        ),
        expression_limit=ResultLimit(type="First"),
        qualified_limit=ResultLimit(type="First"),
        inclusion_rules=list(inclusion_rules),
        end_strategy=end_strategy,
        collapse_settings=collapse_settings,
    )


def distinct_persons(relation) -> set[int]:
    """Return the distinct ``person_id`` values of a relation as a set."""
    df = relation.select(relation.person_id).distinct().execute()
    return {int(x) for x in df["person_id"].tolist()}
