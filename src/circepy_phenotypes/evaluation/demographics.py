"""Uniform demographic filtering (``∩ T``) for evaluation.

Demographics are applied *identically* to every component (population, gold
standard, candidates, entry cohort) at metric time, otherwise sensitivity is
incorrectly bounded (e.g. a ``MALES`` rule on the cohort but not the sensitive
population inflates ``FN`` with females).

The filter is a CircePy :class:`DemographicCriteria` evaluated against a
cohort's index events via the engine's ``demographic_match_keys`` primitive
(through the execution adapter).
"""

from __future__ import annotations

from collections.abc import Iterable

from circe.cohortdefinition import CriteriaGroup, DemographicCriteria, NumericRange
from circe.vocabulary import Concept

from ..cohorts.executor._engine import demographic_match_keys, normalize_criteria_group

PERSON_ID = "person_id"
EVENT_ID = "event_id"


def _concepts(ids: Iterable[int] | None) -> list[Concept] | None:
    if not ids:
        return None
    return [Concept(concept_id=int(i)) for i in ids]


def build_demographic_group(
    gender: Iterable[int] | None = None,
    race: Iterable[int] | None = None,
    ethnicity: Iterable[int] | None = None,
    age: NumericRange | dict | None = None,
) -> CriteriaGroup | None:
    """Build a CircePy ``CriteriaGroup`` carrying a single ``DemographicCriteria``.

    ``gender``/``race``/``ethnicity`` are lists of OMOP concept ids; ``age`` is
    a ``NumericRange`` (or a mapping of ``op``/``value``/``extent``). Returns
    ``None`` when no demographic is specified (identity filter).
    """
    gender_cs = _concepts(gender)
    race_cs = _concepts(race)
    ethnicity_cs = _concepts(ethnicity)
    age_range = NumericRange.model_validate(age) if isinstance(age, dict) else age

    if not any((gender_cs, race_cs, ethnicity_cs, age_range is not None)):
        return None

    return CriteriaGroup(
        demographic_criteria_list=[
            DemographicCriteria(
                gender=gender_cs,
                race=race_cs,
                ethnicity=ethnicity_cs,
                age=age_range,
            )
        ]
    )


def normalize_demographic(group: CriteriaGroup | None):
    """Normalize a demographic group, returning the first ``NormalizedDemographicCriteria``."""
    if group is None:
        return None
    normalized = normalize_criteria_group(group)
    if normalized is None or not normalized.demographics:
        return None
    return normalized.demographics[0]


def apply_demographics(included_events, group: CriteriaGroup | None, ctx):
    """Intersect *included_events* with the demographic filter.

    Returns a ``(person_id, event_id)`` key relation of the events whose person
    matches the demographics (identity when ``group`` is ``None``).
    """
    demographic = normalize_demographic(group)
    if demographic is None:
        return included_events.select(
            included_events[PERSON_ID].name(PERSON_ID),
            included_events[EVENT_ID].name(EVENT_ID),
        ).distinct()
    return demographic_match_keys(included_events, demographic, ctx)
