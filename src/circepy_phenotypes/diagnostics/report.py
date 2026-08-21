"""Markdown report generation for diagnostics results."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING

import pandas as pd

if TYPE_CHECKING:
    from . import DiagnosticsResult


def _md_table(df: pd.DataFrame, max_rows: int | None = None) -> str:
    if df.empty:
        return "_no rows_\n"
    shown = df if max_rows is None else df.head(max_rows)
    header = "| " + " | ".join(str(c) for c in shown.columns) + " |"
    sep = "| " + " | ".join("---" for _ in shown.columns) + " |"
    lines = [header, sep]
    for _, row in shown.iterrows():
        cells = []
        for value in row:
            if value is None or (isinstance(value, float) and pd.isna(value)):
                cells.append("")
            elif isinstance(value, float):
                cells.append(f"{value:,.4f}")
            else:
                cells.append(str(value))
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def _cohort_sizes_table(result: DiagnosticsResult) -> pd.DataFrame:
    rows = [
        {"template": name, "n_persons": len(persons)}
        for name, persons in sorted(result.template_persons.items())
    ]
    return pd.DataFrame(rows)


def format_report(result: DiagnosticsResult) -> str:
    parts: list[str] = []
    parts.append(f"# Phenotype diagnostics — {result.phenotype_label}")
    parts.append("")
    parts.append(f"- **phenotype_id**: `{result.phenotype_id}`")
    parts.append(f"- **run_id**: {result.run_id}")
    parts.append(f"- **generated**: {datetime.now(timezone.utc).isoformat()}")
    parts.append(
        f"- **entry cohort**: {len(result.template_persons.get('base_case', set()))} persons"
    )
    parts.append("")

    if "index_event_breakdown" in result.tables:
        parts.append("## Index event breakdown")
        parts.append(_md_table(result.tables["index_event_breakdown"], max_rows=25))

    if "visit_context" in result.tables:
        parts.append("## Visit context")
        parts.append(_md_table(result.tables["visit_context"], max_rows=25))

    if "demographics" in result.tables:
        parts.append("## Demographic characterization")
        parts.append(_md_table(result.tables["demographics"]))

    if "time_distribution" in result.tables:
        parts.append("## Time distribution (observation around index)")
        parts.append(_md_table(result.tables["time_distribution"]))
        if "time_histogram" in result.tables:
            parts.append(_md_table(result.tables["time_histogram"]))

    if "coverage" in result.tables:
        parts.append("## Evidence category coverage")
        parts.append(_md_table(result.tables["coverage"]))

    if "attrition" in result.tables:
        parts.append("## Cohort rule attrition")
        parts.append(_md_table(result.tables["attrition"]))

    if "concept_prevalence" in result.tables:
        parts.append("## Concept-set prevalence (rolled up to parents)")
        prev = result.tables["concept_prevalence"]
        for category in sorted(prev["category"].unique()):
            parts.append(f"### {category}")
            parts.append(_md_table(prev[prev["category"] == category], max_rows=25))
        parts.append(
            "_Full concept list is in the DuckDB store (`concept_sets`, `concept_prevalence`)._"
        )

    if "template_overlap" in result.tables:
        parts.append("## Template overlap (Jaccard)")
        overlap = result.tables["template_overlap"].sort_values("jaccard", ascending=False)
        parts.append(_md_table(overlap, max_rows=40))
        parts.append("_Full pairwise triangle is in the DuckDB store (`template_overlap`)._")

    return "\n".join(parts) + "\n"


def write_report(result: DiagnosticsResult, output_dir: str | Path) -> Path:
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    safe_label = "".join(c if c.isalnum() else "_" for c in result.phenotype_label) or "phenotype"
    path = output_dir / f"{safe_label}_diagnostics_{result.run_id or 'run'}.md"
    path.write_text(format_report(result))
    return path
