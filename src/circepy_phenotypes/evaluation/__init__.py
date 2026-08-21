"""Label-based evaluation of phenotyping candidate cohorts.

Computes proxy sensitivity / specificity / PPV / NPV for each candidate cohort
against a gold-standard label set, over a shared evaluation universe (the
demographics-filtered sensitive population by default).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from circe.cohortdefinition import CohortExpression, CriteriaGroup

from ..backend import BackendConnection
from ..cohorts.executor._engine import build_included_events
from ..cohorts.family import ResolvedFamily
from .cohorts import distinct_persons, gold_standard_expression
from .demographics import apply_demographics, build_demographic_group
from .metrics import ConfusionMatrix, Metrics, compute_metrics, confusion_matrix
from .population import domain_criteria, evidence_expression
from .selection import rank_candidates, score

__all__ = [
    "ConfusionMatrix",
    "EvaluationResult",
    "Metrics",
    "apply_demographics",
    "build_demographic_group",
    "compute_metrics",
    "confusion_matrix",
    "distinct_persons",
    "domain_criteria",
    "evaluate",
    "evidence_expression",
    "gold_standard_expression",
    "rank_candidates",
    "score",
]


@dataclass
class EvaluationResult:
    """Outcome of a full evaluation run."""

    universe_persons: set[int]
    population_persons: set[int]
    entry_persons: set[int]
    gold_persons: set[int]
    candidate_persons: dict[str, set[int]] = field(default_factory=dict)
    confusion_matrices: dict[str, ConfusionMatrix] = field(default_factory=dict)
    metrics: dict[str, Metrics] = field(default_factory=dict)

    def ranked(self, criterion: str = "youden") -> list[tuple[str, float]]:
        return rank_candidates(self.metrics, criterion=criterion)


def evaluate(
    backend_conn: BackendConnection,
    *,
    family: ResolvedFamily,
    population_expression: CohortExpression,
    gold_standard: CohortExpression,
    demographic_group: CriteriaGroup | None = None,
    universe: str = "sensitive_population",
    candidate_expressions: dict[str, CohortExpression] | None = None,
) -> EvaluationResult:
    """Evaluate candidate cohorts against a gold standard.

    Every component is executed through the execution adapter and intersected
    with the same demographic filter (``∩ T``) so metrics are uniformly bounded.

    ``universe`` is ``"sensitive_population"`` (default) or ``"entry_cohort"``.
    ``candidate_expressions`` overrides the template candidates derived from
    ``family`` (default: every template except ``base_case``).
    """
    backend = backend_conn.backend
    cdm_schema = backend_conn.cdm_schema
    results_schema = backend_conn.results_schema
    vocabulary_schema = backend_conn.vocabulary_schema

    def person_set(expression: CohortExpression) -> set[int]:
        events, ctx = build_included_events(
            expression,
            backend=backend,
            cdm_schema=cdm_schema,
            results_schema=results_schema,
            vocabulary_schema=vocabulary_schema,
        )
        keys = apply_demographics(events, demographic_group, ctx)
        return distinct_persons(keys)

    entry_expression = family.expressions["base_case"][1]

    entry_persons = person_set(entry_expression)
    population_persons = person_set(population_expression)
    gold_persons = person_set(gold_standard)

    universe_persons = population_persons if universe == "sensitive_population" else entry_persons

    if candidate_expressions is None:
        candidate_expressions = {
            name: expression
            for name, (_cid, expression) in family.expressions.items()
            if name != "base_case"
        }

    candidate_persons = {name: person_set(expr) for name, expr in candidate_expressions.items()}

    confusion_matrices = {
        name: confusion_matrix(universe_persons, gold_persons, persons)
        for name, persons in candidate_persons.items()
    }
    metrics = {name: compute_metrics(cm) for name, cm in confusion_matrices.items()}

    return EvaluationResult(
        universe_persons=universe_persons,
        population_persons=population_persons,
        entry_persons=entry_persons,
        gold_persons=gold_persons,
        candidate_persons=candidate_persons,
        confusion_matrices=confusion_matrices,
        metrics=metrics,
    )
