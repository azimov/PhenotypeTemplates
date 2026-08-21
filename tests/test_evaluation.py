"""Integration tests for the evaluation layer (DuckDB in-memory CDM).

Covers the three plan requirements:

  * sensitive population is wider than the entry cohort (drug-only evidence),
  * non-temporal demographics applied uniformly to P/G/C/U,
  * full-run invariants (TP+FP+FN+TN == |U'|, ratios in [0, 1]).
"""

from __future__ import annotations

import math

import pandas as pd
import pytest

from circepy_phenotypes import (
    BackendConnection,
    FamilySpec,
    build_demographic_group,
    cs,
    domain_criteria,
    evaluate,
    evidence_expression,
    resolve_family,
)

MALE = 8507
FEMALE = 8532


def _build_eval_backend():
    ibis = pytest.importorskip("ibis")
    pytest.importorskip("duckdb")
    conn = ibis.duckdb.connect()

    def create(name, data, date_cols=()):
        df = pd.DataFrame(data)
        for col in date_cols:
            df[col] = pd.to_datetime(df[col])
        for col in df.columns:
            if df[col].dtype == object and df[col].isna().any():
                df[col] = df[col].astype("string")
        conn.create_table(name, obj=df, overwrite=True)

    create(
        "person",
        {
            "person_id": [1, 2, 3, 4, 5],
            "year_of_birth": [1980, 1980, 1980, 1980, 1980],
            "gender_concept_id": [MALE, MALE, FEMALE, MALE, FEMALE],
            "race_concept_id": [0, 0, 0, 0, 0],
            "ethnicity_concept_id": [0, 0, 0, 0, 0],
        },
    )
    create(
        "observation_period",
        {
            "person_id": [1, 2, 3, 4, 5],
            "observation_period_id": [10, 11, 12, 13, 14],
            "observation_period_start_date": ["2019-01-01"] * 5,
            "observation_period_end_date": ["2021-12-31"] * 5,
        },
        date_cols=("observation_period_start_date", "observation_period_end_date"),
    )

    # Disease I = 111; symptom S = 211.
    create(
        "condition_occurrence",
        {
            "person_id": [1, 2, 2, 3],
            "condition_occurrence_id": [100, 200, 201, 300],
            "condition_concept_id": [111, 111, 211, 111],
            "condition_start_date": ["2020-06-01", "2020-06-01", "2020-05-20", "2020-06-01"],
            "condition_end_date": ["2020-06-01", "2020-06-01", "2020-05-20", "2020-06-01"],
            "visit_occurrence_id": [900, 901, 901, 902],
        },
        date_cols=("condition_start_date", "condition_end_date"),
    )
    # Semaglutide-like drug = 777 (evidence only, persons 4 & 5 have no I dx).
    create(
        "drug_exposure",
        {
            "person_id": [4, 5],
            "drug_exposure_id": [400, 500],
            "drug_concept_id": [777, 777],
            "drug_exposure_start_date": ["2020-06-01", "2020-06-01"],
            "drug_exposure_end_date": ["2020-06-01", "2020-06-01"],
        },
        date_cols=("drug_exposure_start_date", "drug_exposure_end_date"),
    )

    # Empty-but-present domain tables (referenced by template groups).
    create(
        "observation",
        {
            "person_id": [999],
            "observation_id": [1],
            "observation_concept_id": [999999],
            "observation_date": ["2010-01-01"],
        },
        date_cols=("observation_date",),
    )
    create(
        "measurement",
        {
            "person_id": [999],
            "measurement_id": [1],
            "measurement_concept_id": [999999],
            "measurement_date": ["2010-01-01"],
        },
        date_cols=("measurement_date",),
    )
    create(
        "procedure_occurrence",
        {
            "person_id": [999],
            "procedure_occurrence_id": [1],
            "procedure_concept_id": [999999],
            "procedure_date": ["2010-01-01"],
        },
        date_cols=("procedure_date",),
    )
    create(
        "device_exposure",
        {
            "person_id": [999],
            "device_exposure_id": [1],
            "device_concept_id": [999999],
            "device_exposure_start_date": ["2010-01-01"],
        },
        date_cols=("device_exposure_start_date",),
    )
    create(
        "visit_occurrence",
        {
            "person_id": [999],
            "visit_occurrence_id": [1],
            "visit_concept_id": [999999],
            "visit_start_date": ["2010-01-01"],
            "visit_end_date": ["2010-01-01"],
        },
        date_cols=("visit_start_date", "visit_end_date"),
    )

    # Vocabulary for the hard-coded F visit concept set.
    create(
        "concept",
        {"concept_id": [9201, 9203, 262], "invalid_reason": [None, None, None]},
    )
    create(
        "concept_ancestor",
        {
            "ancestor_concept_id": [9201, 9203, 262],
            "descendant_concept_id": [9201, 9203, 262],
        },
    )
    create(
        "concept_relationship",
        {
            "concept_id_1": [999999],
            "concept_id_2": [999999],
            "relationship_id": ["Maps to"],
            "invalid_reason": [None],
        },
    )

    return conn


@pytest.fixture
def eval_conn():
    return _build_eval_backend()


def _family():
    return resolve_family(
        FamilySpec(cs_I=cs((111,), name="I"), cs_S=cs((211,), name="S"), phenotype_label="Test")
    )


def _population_expression(resolved):
    semaglutide = cs((777,), name="semaglutide", set_id=8)
    return evidence_expression(
        [("condition_occurrence", 1), ("observation", 1), ("drug_exposure", 8)],
        concept_sets=resolved.concept_sets + [semaglutide],
    )


def _backend_conn(conn):
    return BackendConnection(
        backend=conn, cdm_schema="main", results_schema="main", vocabulary_schema="main"
    )


def test_population_includes_drug_only_evidence(eval_conn):
    resolved = _family()
    gold = resolved.expressions["base_case"][1]

    result = evaluate(
        _backend_conn(eval_conn),
        family=resolved,
        population_expression=_population_expression(resolved),
        gold_standard=gold,
    )

    assert result.entry_persons == {1, 2, 3}
    assert result.population_persons == {1, 2, 3, 4, 5}
    # Persons 4 & 5 have drug evidence but no disease diagnosis.
    assert 4 in result.population_persons and 4 not in result.entry_persons
    assert 5 in result.population_persons and 5 not in result.entry_persons
    assert result.universe_persons == {1, 2, 3, 4, 5}


def test_demographics_applied_uniformly(eval_conn):
    resolved = _family()
    gold = resolved.expressions["base_case"][1]
    male = build_demographic_group(gender=[MALE])

    result = evaluate(
        _backend_conn(eval_conn),
        family=resolved,
        population_expression=_population_expression(resolved),
        gold_standard=gold,
        demographic_group=male,
    )

    # Females (3 & 5) excluded from every component uniformly.
    assert result.universe_persons == {1, 2, 4}
    assert result.population_persons == {1, 2, 4}
    assert result.entry_persons == {1, 2}
    assert result.gold_persons == {1, 2}
    # tpl_1 = (S|D): only person 2 has the symptom.
    assert result.candidate_persons["tpl_1"] == {2}
    assert result.metrics["tpl_1"].sensitivity == pytest.approx(0.5)
    assert result.metrics["tpl_1"].specificity == pytest.approx(1.0)


def test_male_candidate_sensitivity_one(eval_conn):
    resolved = _family()
    gold = resolved.expressions["base_case"][1]
    male = build_demographic_group(gender=[MALE])

    result = evaluate(
        _backend_conn(eval_conn),
        family=resolved,
        population_expression=_population_expression(resolved),
        gold_standard=gold,
        demographic_group=male,
        candidate_expressions={"base_case": gold},
    )

    assert result.metrics["base_case"].sensitivity == pytest.approx(1.0)
    assert result.metrics["base_case"].specificity == pytest.approx(1.0)


def test_full_run_invariants(eval_conn):
    resolved = _family()
    gold = resolved.expressions["base_case"][1]
    male = build_demographic_group(gender=[MALE])

    result = evaluate(
        _backend_conn(eval_conn),
        family=resolved,
        population_expression=_population_expression(resolved),
        gold_standard=gold,
        demographic_group=male,
    )

    assert result.metrics  # non-empty
    for name, cm in result.confusion_matrices.items():
        assert cm.total == len(result.universe_persons), name
        m = result.metrics[name]
        for value in (m.sensitivity, m.specificity, m.ppv, m.npv):
            assert (0.0 <= value <= 1.0) or math.isnan(value), (name, value)


def test_domain_criteria_unknown_domain_raises():
    with pytest.raises(ValueError, match="Unknown domain"):
        domain_criteria("nonsense", 1)
