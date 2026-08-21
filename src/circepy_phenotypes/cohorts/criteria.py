"""Criterion builders that mirror the Capr helpers in ``r_template.R``.

Every builder emits CircePy cohort-definition models (``CriteriaGroup``,
``CorelatedCriteria``, ``PrimaryCriteria``, ...) with semantics that match the
Capr definitions 1:1 (window encoding, observation-period handling, occurrence
types).

Window semantics follow Capr exactly:

  * ``eventStarts(a, b)`` -> ``Window(start=bound(a), end=bound(b),
    use_event_end=False, use_index_end=False)``
  * ``eventEnds(a, b)`` -> ``Window(..., use_event_end=True, ...)``
  * ``bound(0)`` -> ``WindowBound(coeff=-1, days=0)``
  * ``bound(±Inf)`` -> ``WindowBound(coeff=∓1, days=None)``
"""

from __future__ import annotations

import math
from collections.abc import Sequence

from circe.cohortdefinition import (
    ConditionOccurrence,
    CorelatedCriteria,
    CriteriaGroup,
    DeviceExposure,
    DrugExposure,
    Measurement,
    Observation,
    Occurrence,
    PrimaryCriteria,
    ProcedureOccurrence,
    VisitOccurrence,
)
from circe.cohortdefinition.core import (
    CollapseSettings,
    CollapseType,
    DateOffsetStrategy,
    ObservationFilter,
    ResultLimit,
    Window,
    WindowBound,
)

# ---------------------------------------------------------------------------
# Domain criterion constructors (concept-set id -> domain criterion model)
# ---------------------------------------------------------------------------


def condition_occurrence(codeset_id: int) -> ConditionOccurrence:
    return ConditionOccurrence(codeset_id=codeset_id)


def observation(codeset_id: int) -> Observation:
    return Observation(codeset_id=codeset_id)


def measurement(codeset_id: int) -> Measurement:
    return Measurement(codeset_id=codeset_id)


def procedure(codeset_id: int) -> ProcedureOccurrence:
    return ProcedureOccurrence(codeset_id=codeset_id)


def device_exposure(codeset_id: int) -> DeviceExposure:
    return DeviceExposure(codeset_id=codeset_id)


def drug_exposure(codeset_id: int) -> DrugExposure:
    return DrugExposure(codeset_id=codeset_id)


def visit(codeset_id: int) -> VisitOccurrence:
    return VisitOccurrence(codeset_id=codeset_id)


# ---------------------------------------------------------------------------
# Windows
# ---------------------------------------------------------------------------


def _bound(x: float) -> WindowBound:
    if math.isinf(x):
        return WindowBound(coeff=-1 if x < 0 else 1, days=None)
    if x == 0:
        return WindowBound(coeff=-1, days=0)
    if x < 0:
        return WindowBound(coeff=-1, days=int(abs(x)))
    return WindowBound(coeff=1, days=int(x))


def event_starts_window(a: float, b: float) -> Window:
    """Capr ``eventStarts(a, b)``: constrain the *start* date of the event."""
    return Window(start=_bound(a), end=_bound(b), use_event_end=False, use_index_end=False)


def event_ends_window(a: float, b: float) -> Window:
    """Capr ``eventEnds(a, b)``: constrain the *end* date of the event."""
    return Window(start=_bound(a), end=_bound(b), use_event_end=True, use_index_end=False)


# ---------------------------------------------------------------------------
# CorelatedCriteria / group builders
# ---------------------------------------------------------------------------


def correlated_criterion(
    criterion,
    *,
    min_count: int = 1,
    occurrence_type: int | None = None,
    start_window: Window | None = None,
    end_window: Window | None = None,
    ignore_observation_period: bool = True,
    restrict_visit: bool = False,
) -> CorelatedCriteria:
    """Build a :class:`CorelatedCriteria`.

    ``occurrence_type`` is a Circe Occurrence constant (``_AT_LEAST``=2,
    ``_AT_MOST``=1, ``_EXACTLY``=0). If not given, defaults to ``AT_LEAST``
    with ``min_count``, matching Capr ``atLeast(n, ...)``. Pass
    ``occurrence_type=Occurrence._EXACTLY, min_count=0`` for Capr
    ``exactly(0, ...)``.
    """
    if occurrence_type is None:
        occurrence_type = Occurrence._EXACTLY if min_count == 0 else Occurrence._AT_LEAST
    return CorelatedCriteria(
        criteria=criterion,
        occurrence=Occurrence(type=int(occurrence_type), count=int(min_count)),
        start_window=start_window,
        end_window=end_window,
        ignore_observation_period=ignore_observation_period,
        restrict_visit=restrict_visit,
    )


def make_multi_domain_criterion(
    codeset_id: int,
    domain_fns: Sequence,
    start_window: Window,
    end_window: Window | None = None,
    min_count: int = 1,
) -> CriteriaGroup:
    """Build ``withAny(domain1(cs, ...), domain2(cs, ...), ...)``.

    All domains share the same aperture (``ignoreObservationPeriod=TRUE``).
    """
    criteria = [
        correlated_criterion(
            fn(codeset_id),
            min_count=min_count,
            start_window=start_window,
            end_window=end_window,
        )
        for fn in domain_fns
    ]
    return CriteriaGroup(type="ANY", criteria_list=criteria)


def make_f_criterion(codeset_id_I: int, visit_codeset_id: int) -> CriteriaGroup:
    """Build the F (follow-up) criterion group.

    F = a second I code within +1..+365 days (condition OR observation)
        OR an ER/Inpatient visit overlapping the index date.
    """
    second_i = make_multi_domain_criterion(
        codeset_id_I,
        [condition_occurrence, observation],
        start_window=event_starts_window(1, 365),
    )
    visit_criterion = correlated_criterion(
        visit(visit_codeset_id),
        min_count=1,
        start_window=event_starts_window(float("-inf"), 0),
        end_window=event_ends_window(0, float("inf")),
    )
    return CriteriaGroup(type="ANY", criteria_list=[visit_criterion], groups=[second_i])


def make_exclusion_criterion(codeset_id_A: int) -> CriteriaGroup:
    """Build the A (alternative diagnosis) exclusion criterion.

    ``withAll(exactly(0, conditionOccurrence(cs_A)), exactly(0, observation(cs_A)))``
    within -30..+30 days around index.
    """
    aperture = event_starts_window(-30, 30)
    crit_cond = correlated_criterion(
        condition_occurrence(codeset_id_A),
        min_count=0,
        occurrence_type=Occurrence._EXACTLY,
        start_window=aperture,
    )
    crit_obs = correlated_criterion(
        observation(codeset_id_A),
        min_count=0,
        occurrence_type=Occurrence._EXACTLY,
        start_window=aperture,
    )
    return CriteriaGroup(type="ALL", criteria_list=[crit_cond, crit_obs])


def combine_criteria(criteria: Sequence[object | None], op: str) -> CriteriaGroup | None:
    """Combine criteria with ``withAny``/``withAll`` (Capr ``combineCriteria``).

    Filters ``None`` members; returns ``None`` if empty, the sole member if a
    single non-None remains, otherwise a ``CriteriaGroup``. ``CorelatedCriteria``
    members go into ``criteria_list``; ``CriteriaGroup`` members into ``groups``
    (matching Capr's ``withAny``/``withAll`` split).
    """
    parts = [c for c in criteria if c is not None]
    if not parts:
        return None
    if len(parts) == 1:
        return parts[0]
    criteria_list = [c for c in parts if isinstance(c, CorelatedCriteria)]
    groups = [c for c in parts if isinstance(c, CriteriaGroup)]
    return CriteriaGroup(type=op.upper(), criteria_list=criteria_list, groups=groups)


# ---------------------------------------------------------------------------
# Entry / exit / era
# ---------------------------------------------------------------------------


def make_entry_criteria(codeset_id_I: int, primary_limit: str = "First") -> PrimaryCriteria:
    """Build the index-event entry criteria.

    Mirrors Capr ``entry(conditionOccurrence(cs_I, firstOccurrence()),
    observation(cs_I, firstOccurrence()))`` with the default
    ``continuousObservation(0, 0)`` observation window.
    """
    return PrimaryCriteria(
        criteria_list=[
            ConditionOccurrence(codeset_id=codeset_id_I, first=True),
            Observation(codeset_id=codeset_id_I, first=True),
        ],
        observation_window=ObservationFilter(prior_days=0, post_days=0),
        primary_limit=ResultLimit(type=primary_limit),
    )


def _to_pascal_cap(x: str) -> str:
    """Capr ``toPascal``: 'endDate' -> 'EndDate'."""
    return x[0].upper() + x[1:]


def make_end_strategy(exit_strategy: str = "chronic") -> DateOffsetStrategy | None:
    """Map the R ``exit`` argument to a CircePy end strategy.

    ``"chronic"`` -> ``None`` (observation exit); ``"acute14d"``/``"acute365d"``
    -> ``DateOffsetStrategy(date_field="EndDate", offset=14|365)``.
    """
    if exit_strategy == "chronic":
        return None
    if exit_strategy == "acute14d":
        offset = 14
    elif exit_strategy == "acute365d":
        offset = 365
    else:
        raise ValueError(f"Unknown exit strategy: {exit_strategy!r}")
    return DateOffsetStrategy(date_field=_to_pascal_cap("endDate"), offset=offset)


def make_collapse_settings(era_days: int = 0) -> CollapseSettings:
    """Map Capr ``era(eraDays=n)`` to ``CollapseSettings``."""
    return CollapseSettings(era_pad=int(era_days), collapse_type=CollapseType.ERA)
