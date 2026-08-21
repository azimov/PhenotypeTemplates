"""Cohort-definition diagnostics (CohortDiagnostics-inspired, scoped).

Produces aggregated diagnostic tables (index-event breakdown, demographics,
visit context, time distributions, coverage/attrition, concept-set prevalence,
template overlap) and persists them to a local DuckDB asset store, plus a
markdown report. Only aggregated data is written locally; patient-level rows
stay on the CDM.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pandas as pd

from ..backend import BackendConnection
from ..cohorts import TemplateFamilyExecutor
from ..cohorts.family import ResolvedFamily
from ._data import (
    base_persons,
    category_person_sets,
    execute_concept,
    execute_index_events,
    execute_person,
    execute_visit,
    template_person_sets,
)
from .concepts import concept_set_analysis
from .demographics import demographic_characterization
from .inclusion import attrition, coverage
from .index_events import index_event_breakdown, visit_context
from .overlap import template_overlap
from .report import write_report
from .store import DiagnosticsStore, phenotype_id
from .time import time_distribution

__all__ = [
    "DiagnosticsResult",
    "DiagnosticsStore",
    "diagnose",
    "phenotype_id",
]

_DEFAULT_TOGGLES = {
    "index_events": True,
    "demographics": True,
    "visit_context": True,
    "time_distribution": True,
    "coverage": True,
    "attrition": True,
    "concept_prevalence": True,
    "overlap": True,
}


@dataclass
class DiagnosticsResult:
    """Aggregated outputs of a diagnostics run."""

    phenotype_id: str
    phenotype_label: str
    run_id: int | None
    template_persons: dict[str, set[int]] = field(default_factory=dict)
    tables: dict[str, pd.DataFrame] = field(default_factory=dict)
    report_path: Path | None = None
    store_path: Path | None = None

    def cohort_sizes(self) -> pd.DataFrame:
        return pd.DataFrame(
            [
                {"template": name, "n_persons": len(persons)}
                for name, persons in sorted(self.template_persons.items())
            ]
        )


def diagnose(
    backend_conn: BackendConnection,
    resolved: ResolvedFamily,
    *,
    output_dir: str | Path,
    executor: TemplateFamilyExecutor | None = None,
    config: dict[str, Any] | None = None,
    toggles: dict[str, bool] | None = None,
    phenotype_label: str = "",
) -> DiagnosticsResult:
    """Run all diagnostics and persist to ``output_dir`` (DuckDB + markdown)."""
    toggles = {**_DEFAULT_TOGGLES, **(toggles or {})}
    executor = executor or TemplateFamilyExecutor(
        backend_conn.backend,
        cdm_schema=backend_conn.cdm_schema,
        results_schema=backend_conn.results_schema,
        vocabulary_schema=backend_conn.vocabulary_schema,
        intermediate_prefix=backend_conn.intermediate_prefix,
    )

    family = executor.build_resolved(resolved)
    ctx = family.ctx

    index_df = execute_index_events(family)
    person_df = execute_person(ctx)
    concept_df = execute_concept(ctx)
    visit_df = execute_visit(ctx)

    category_persons = category_person_sets(family)
    base = base_persons(family)
    base_n = len(base)
    template_persons = template_person_sets(category_persons, base, resolved.specs)

    tables: dict[str, pd.DataFrame] = {}

    if toggles["index_events"]:
        tables["index_event_breakdown"] = index_event_breakdown(index_df, concept_df)
    if toggles["visit_context"]:
        tables["visit_context"] = visit_context(index_df, visit_df, concept_df)
    if toggles["demographics"]:
        tables["demographics"] = demographic_characterization(
            index_df, person_df, template_persons, concept_df
        )
    if toggles["time_distribution"]:
        summary, histogram = time_distribution(index_df)
        tables["time_distribution"] = summary
        tables["time_histogram"] = histogram
    if toggles["coverage"]:
        tables["coverage"] = coverage(category_persons, base_n)
    if toggles["attrition"]:
        tables["attrition"] = attrition(category_persons, base, resolved.specs)
    if toggles["concept_prevalence"]:
        concept_sets_df, prevalence_df = concept_set_analysis(resolved, family, ctx, base_n=base_n)
        tables["concept_sets"] = concept_sets_df
        tables["concept_prevalence"] = prevalence_df
    if toggles["overlap"]:
        tables["template_overlap"] = template_overlap(template_persons)

    result = DiagnosticsResult(
        phenotype_id=phenotype_id(resolved),
        phenotype_label=phenotype_label,
        run_id=None,
        template_persons=template_persons,
        tables=tables,
    )

    with DiagnosticsStore(output_dir) as store:
        run_id = store.record_run(
            phenotype_id_value=result.phenotype_id,
            phenotype_label=result.phenotype_label,
            config=config,
        )
        result.run_id = run_id
        result.store_path = store.path
        for name, df in tables.items():
            store.write_table(name, df, run_id=run_id, phenotype_id_value=result.phenotype_id)

    result.report_path = write_report(result, output_dir)
    return result
