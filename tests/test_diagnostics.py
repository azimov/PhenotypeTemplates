"""Tests for the diagnostics layer (pure + DuckDB integration)."""

from __future__ import annotations

import duckdb
import pandas as pd
import pytest
from test_evaluation import _build_eval_backend

from circepy_phenotypes import BackendConnection, FamilySpec, cs, resolve_family
from circepy_phenotypes.cohorts.templates import TEMPLATE_SPECS, TemplateSpec
from circepy_phenotypes.diagnostics import diagnose, phenotype_id
from circepy_phenotypes.diagnostics.inclusion import attrition, coverage
from circepy_phenotypes.diagnostics.overlap import template_overlap
from circepy_phenotypes.diagnostics.report import _md_table
from circepy_phenotypes.diagnostics.time import time_distribution

# ---------------------------------------------------------------------------
# Pure unit tests
# ---------------------------------------------------------------------------


def test_phenotype_id_stable_and_sensitive():
    base = resolve_family(FamilySpec(cs_I=cs((111,), name="I"), cs_S=cs((211,), name="S")))
    changed_S = resolve_family(FamilySpec(cs_I=cs((111,), name="I"), cs_S=cs((222,), name="S")))
    changed_I = resolve_family(FamilySpec(cs_I=cs((999,), name="I"), cs_S=cs((211,), name="S")))

    assert phenotype_id(base) == phenotype_id(changed_S)
    assert phenotype_id(base) != phenotype_id(changed_I)
    assert len(phenotype_id(base)) == 16


def test_template_overlap_jaccard():
    persons = {"a": {1, 2, 3}, "b": {2, 3, 4}, "c": {5}}
    df = template_overlap(persons)

    ab = df[(df.template_a == "a") & (df.template_b == "b")].iloc[0]
    assert ab.n_intersection == 2
    assert ab.n_union == 4
    assert ab.jaccard == 0.5

    ac = df[(df.template_a == "a") & (df.template_b == "c")].iloc[0]
    assert ac.jaccard == 0.0


def test_coverage_and_attrition_arithmetic():
    category = {"S": {1, 2}, "D": {2, 3}, "T": {3, 4}, "C": set(), "F": set(), "A": {5}}
    base = {1, 2, 3, 4, 5}
    specs = (TemplateSpec("base_case", pre_combo=(), post_combo=()), *TEMPLATE_SPECS)

    cov = coverage(category, len(base))
    s_row = cov[cov.category == "S"].iloc[0]
    assert s_row.n_persons == 2
    assert s_row.pct_of_base == pytest.approx(0.4)

    att = attrition(category, base, specs)
    by_template = {name: dict(zip(g.stage, g.n_persons)) for name, g in att.groupby("template")}

    assert by_template["base_case"]["final"] == 5
    # tpl_1 = (S|D): entry 5 -> pre {1,2,3} -> final 3
    assert by_template["tpl_1"]["pre"] == 3
    assert by_template["tpl_1"]["final"] == 3
    # tpl_5 = !A: entry 5 -> not_a {5} -> final 1
    assert by_template["tpl_5"]["not_a"] == 1
    assert by_template["tpl_5"]["final"] == 1


def test_time_distribution_summary():
    df = pd.DataFrame(
        {
            "start_date": pd.to_datetime(["2020-06-01", "2020-06-01"]),
            "op_start_date": pd.to_datetime(["2019-01-01", "2019-06-01"]),
            "op_end_date": pd.to_datetime(["2021-12-31", "2021-06-01"]),
        }
    )
    summary, histogram = time_distribution(df)

    before = summary[summary.metric == "obs_before_days"].iloc[0]
    assert before["min"] == 366
    assert before["max"] == 517
    assert before["n"] == 2

    assert set(histogram.metric) == {"obs_before_days", "obs_after_days"}
    assert histogram.n_persons.sum() == 4  # 2 metrics x 2 persons


def test_markdown_table_formatter():
    df = pd.DataFrame({"a": [1, 2], "b": ["x", None]})
    out = _md_table(df)
    assert "| a | b |" in out
    assert "| --- | --- |" in out
    assert "| 1 | x |" in out


# ---------------------------------------------------------------------------
# Integration (DuckDB in-memory CDM)
# ---------------------------------------------------------------------------


def _diagnose(tmp_path, **family_kwargs):
    conn = _build_eval_backend()
    spec = FamilySpec(cs_I=cs((111,), name="I"), cs_S=cs((211, 999), name="S"), **family_kwargs)
    resolved = resolve_family(spec)
    bc = BackendConnection(
        backend=conn, cdm_schema="main", results_schema="main", vocabulary_schema="main"
    )
    return diagnose(bc, resolved, output_dir=tmp_path, phenotype_label="Test")


def test_diagnose_concept_prevalence_and_orphans(tmp_path):
    result = _diagnose(tmp_path)

    prev = result.tables["concept_prevalence"]
    s = prev[prev.category == "S"]
    orphan = s[s.concept_id == 999].iloc[0]
    assert orphan.n_persons == 0  # resolved but never observed
    used = s[s.concept_id == 211].iloc[0]
    assert used.n_persons == 1
    assert used.pct_of_base == pytest.approx(1 / 3)

    idx = result.tables["concept_prevalence"][result.tables["concept_prevalence"].category == "I"]
    assert idx.iloc[0].n_persons == 3  # all three entry persons have I


def test_diagnose_breakdown_coverage(tmp_path):
    result = _diagnose(tmp_path)

    breakdown = result.tables["index_event_breakdown"]
    assert breakdown[breakdown.concept_id == 111].iloc[0].n_persons == 3

    cov = result.tables["coverage"]
    assert cov[cov.category == "S"].iloc[0].n_persons == 1

    overlap = result.tables["template_overlap"]
    assert len(overlap) == 23 * 22 // 2


def test_store_is_aggregated_only(tmp_path):
    result = _diagnose(tmp_path)

    con = duckdb.connect(str(result.store_path))
    assert con.execute("SELECT COUNT(*) FROM runs").fetchone()[0] == 1

    patient_columns = {"person_id", "event_id", "subject_id"}
    tables = [
        r[0]
        for r in con.execute("SELECT table_name FROM information_schema.tables").fetchall()
        if r[0] != "runs"
    ]
    for table in tables:
        cols = {r[0] for r in con.execute(f"DESCRIBE {table}").fetchall()}
        assert patient_columns.isdisjoint(cols), f"{table} leaks patient-level columns"
    con.close()
