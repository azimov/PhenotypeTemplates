"""Shared DuckDB test fixture: a small deterministic CDM exercising all categories."""

from __future__ import annotations

import pandas as pd
import pytest


def build_test_backend():
    """Build an in-memory DuckDB backend with the phenotyping test fixture.

    Four persons, each with a single index I event (concept 111):

      * person 1: has S, D, T, C and an ER/Inpatient visit at index (F) -- passes all templates
      * person 2: has S and D only -- pre-index templates only
      * person 3: has T and a second I (F) -- post-index templates only
      * person 4: has an A (alternative diagnosis) -- excluded from A templates
    """
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
            "person_id": [1, 2, 3, 4],
            "year_of_birth": [1980, 1980, 1980, 1980],
            "gender_concept_id": [8507, 8507, 8507, 8507],
        },
    )
    create(
        "observation_period",
        {
            "person_id": [1, 2, 3, 4],
            "observation_period_id": [10, 11, 12, 13],
            "observation_period_start_date": ["2019-01-01", "2019-01-01", "2019-01-01", "2019-01-01"],
            "observation_period_end_date": ["2021-12-31", "2021-12-31", "2021-12-31", "2021-12-31"],
        },
        date_cols=("observation_period_start_date", "observation_period_end_date"),
    )

    rows = [
        # (person, occurrence_id, concept, start, visit)
        (1, 100, 111, "2020-06-01", 900),   # index I
        (1, 101, 211, "2020-05-20", 900),   # S (condition) -12d
        (1, 102, 511, "2020-07-01", 900),   # C +30d
        (2, 200, 111, "2020-06-01", 901),   # index I
        (2, 201, 211, "2020-05-20", 901),   # S -12d
        (3, 300, 111, "2020-06-01", 902),   # index I
        (3, 301, 111, "2020-07-15", 902),   # second I +44d (F)
        (4, 400, 111, "2020-06-01", 903),   # index I
        (4, 401, 611, "2020-06-10", 903),   # A +10d
    ]
    create(
        "condition_occurrence",
        {
            "person_id": [r[0] for r in rows],
            "condition_occurrence_id": [r[1] for r in rows],
            "condition_concept_id": [r[2] for r in rows],
            "condition_start_date": [r[3] for r in rows],
            "condition_end_date": [r[3] for r in rows],
            "visit_occurrence_id": [r[4] for r in rows],
        },
        date_cols=("condition_start_date", "condition_end_date"),
    )
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
            "person_id": [1, 2],
            "measurement_id": [1001, 2001],
            "measurement_concept_id": [311, 311],
            "measurement_date": ["2020-05-25", "2020-05-25"],
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
        "drug_exposure",
        {
            "person_id": [1, 3],
            "drug_exposure_id": [1100, 1300],
            "drug_concept_id": [411, 411],
            "drug_exposure_start_date": ["2020-06-10", "2020-06-10"],
            "drug_exposure_end_date": ["2020-06-10", "2020-06-10"],
        },
        date_cols=("drug_exposure_start_date", "drug_exposure_end_date"),
    )
    create(
        "visit_occurrence",
        {
            "person_id": [1, 2, 3, 4],
            "visit_occurrence_id": [900, 901, 902, 903],
            "visit_concept_id": [9201, 9203, 580, 262],
            "visit_start_date": ["2020-06-01", "2020-06-01", "2020-06-01", "2020-06-01"],
            "visit_end_date": ["2020-06-01", "2020-06-01", "2020-06-01", "2020-06-01"],
        },
        date_cols=("visit_start_date", "visit_end_date"),
    )

    # Vocabulary (needed for F visit descendant expansion)
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
def conn():
    return build_test_backend()
