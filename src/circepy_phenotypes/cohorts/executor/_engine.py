"""CircePy execution adapter.

This is the **only** module that imports from ``circe.execution.*`` internals.
When CircePy > 0.3.0 lands with a stable public execution facade, reimplement
the re-exported names below against that API and delete the private imports.
Everything else in the package depends on CircePy *models* plus this adapter.
"""

from __future__ import annotations

from circe.execution import build_cohort
from circe.execution.databricks_compat import maybe_apply_databricks_post_connect_workaround
from circe.execution.engine.censoring import apply_censoring
from circe.execution.engine.cohort import apply_additional_criteria
from circe.execution.engine.collapse import collapse_events
from circe.execution.engine.end_strategy import apply_end_strategy
from circe.execution.engine.group_windows import attach_observation_period
from circe.execution.engine.groups import _evaluate_group, demographic_match_keys
from circe.execution.engine.inclusion import apply_inclusion_rules
from circe.execution.engine.limits import apply_result_limit
from circe.execution.engine.primary import build_primary_events
from circe.execution.ibis.context import make_execution_context
from circe.execution.ibis.materialize import project_to_ohdsi_cohort_table
from circe.execution.ibis.operations import create_table, read_table
from circe.execution.lower.criteria import lower_criterion
from circe.execution.normalize.cohort import normalize_cohort
from circe.execution.normalize.end_strategy import normalize_end_strategy
from circe.execution.normalize.groups import normalize_criteria_group
from circe.execution.plan.cohort import CohortPlan, PrimaryEventInput

__all__ = [
    "CohortPlan",
    "PrimaryEventInput",
    "_evaluate_group",
    "apply_additional_criteria",
    "apply_censoring",
    "apply_end_strategy",
    "apply_inclusion_rules",
    "apply_result_limit",
    "attach_observation_period",
    "build_cohort",
    "build_included_events",
    "build_primary_events",
    "collapse_events",
    "create_table",
    "demographic_match_keys",
    "lower_criterion",
    "make_execution_context",
    "maybe_apply_databricks_post_connect_workaround",
    "normalize_cohort",
    "normalize_criteria_group",
    "normalize_end_strategy",
    "project_to_ohdsi_cohort_table",
    "read_table",
]


def build_included_events(
    expression,
    *,
    backend,
    cdm_schema: str,
    results_schema: str | None = None,
    vocabulary_schema: str | None = None,
):
    """Build a cohort expression's included events *before* collapse.

    Returns ``(events, ctx)`` where ``events`` carries ``person_id``,
    ``event_id``, ``start_date`` and ``end_date`` (one row per person after the
    expression's ``First`` limit) — the shape ``demographic_match_keys`` needs —
    and ``ctx`` is the execution context (person table access, codeset
    resolver) reused by the demographic intersection.
    """
    normalized = normalize_cohort(expression)
    ctx = make_execution_context(
        backend=backend,
        cdm_schema=cdm_schema,
        results_schema=results_schema,
        vocabulary_schema=vocabulary_schema,
        concept_sets=normalized.concept_sets,
    )

    plan = CohortPlan(
        primary_event_plans=tuple(
            PrimaryEventInput(
                event_plan=lower_criterion(criterion, criterion_index=index),
                correlated_criteria=criterion.correlated_criteria,
            )
            for index, criterion in enumerate(normalized.primary.criteria)
        ),
        observation_window=normalized.primary.observation_window,
        primary_limit_type=normalized.primary.primary_limit_type,
        qualified_limit_type=normalized.result_limits.qualified_limit_type,
        expression_limit_type=normalized.result_limits.expression_limit_type,
    )

    events = build_primary_events(plan, ctx)
    events = apply_additional_criteria(events, normalized.additional_criteria, ctx)
    if normalized.additional_criteria is not None and not normalized.additional_criteria.is_empty():
        events = apply_result_limit(events, plan.qualified_limit_type)
    events = apply_inclusion_rules(events, normalized.inclusion_rules, ctx)
    events = apply_result_limit(events, plan.expression_limit_type)
    events = apply_end_strategy(events, normalized.end_strategy, ctx)
    events = apply_censoring(events, normalized.censoring_criteria, normalized.censor_window, ctx)
    return events, ctx
