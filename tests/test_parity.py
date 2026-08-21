"""Parity tests: decomposed executor == per-template ``build_cohort``."""

from __future__ import annotations

import pytest
from circe.api import build_cohort
from circe.execution.ibis.operations import read_table

from circepy_phenotypes import FamilySpec, TemplateFamilyExecutor, cs, resolve_family

EXPECTED_PERSONS = {
    "base_case": {1, 2, 3, 4},
    "tpl_1": {1, 2},          # (S|D)
    "tpl_2": {1, 2, 3, 4},    # (T|C|F) -- persons 2 & 4 have ER/Inpatient visits at index (F)
    "tpl_3": {1, 2, 3, 4},    # F
    "tpl_4": {1, 3},          # T
    "tpl_5": {1, 2, 3},       # !A
    "tpl_6": {1, 2},          # D
    "tpl_7": {1, 2},          # (S|D)^!A
    "tpl_8": {1, 2, 3},       # (T|C|F)^!A
    "tpl_9": {1, 2},          # (S|D)^(T|C|F)
    "tpl_10": {1, 2},
    "tpl_11": {1, 2},         # (S^D)^(T|C|F)
    "tpl_12": {1, 2},
    "tpl_13": {1},            # (S|D)^(T^C^F)
    "tpl_14": {1},
    "tpl_15": {1},            # (S^D)^(T^F)
    "tpl_16": {1},            # (S^D)^(F^C)
    "tpl_17": {1},            # (S^D)^(T^C)
    "tpl_18": {1},
    "tpl_19": {1},
    "tpl_20": {1},
    "tpl_21": {1},            # (S^D)^(T^C^F)
    "tpl_22": {1},
}


def _make_family(exit_strategy: str = "chronic") -> FamilySpec:
    return FamilySpec(
        cs_I=cs((111,), name="I"),
        cs_S=cs((211,), name="S"),
        cs_D=cs((311,), name="D"),
        cs_T=cs((411,), name="T"),
        cs_C=cs((511,), name="C"),
        cs_A=cs((611,), name="A"),
        phenotype_label="Test",
        exit_strategy=exit_strategy,
    )


def _persons(relation) -> set:
    df = relation.execute()
    return set(df["person_id"].tolist()) if len(df) else set()


def _reference_persons(conn, resolved) -> dict[str, set]:
    out = {}
    for name, (_cid, expression) in resolved.expressions.items():
        out[name] = _persons(build_cohort(expression, backend=conn, cdm_schema="main"))
    return out


@pytest.mark.parametrize("materialize", [False, True])
def test_decomposed_matches_reference(conn, materialize):
    resolved = resolve_family(_make_family())
    reference = _reference_persons(conn, resolved)

    executor = TemplateFamilyExecutor(conn, cdm_schema="main")
    fast = {
        name: _persons(rel)
        for name, rel in executor.run_resolved(resolved, materialize_intermediates=materialize).items()
    }

    assert set(fast) == set(reference) == set(EXPECTED_PERSONS)
    for name, expected in EXPECTED_PERSONS.items():
        assert fast[name] == expected, name
        assert reference[name] == expected, name
        assert fast[name] == reference[name], name


def test_acute14d_exit_parity(conn):
    resolved = resolve_family(_make_family(exit_strategy="acute14d"))
    reference = _reference_persons(conn, resolved)

    executor = TemplateFamilyExecutor(conn, cdm_schema="main")
    fast = {name: _persons(rel) for name, rel in executor.run_resolved(resolved).items()}

    assert fast == reference
    assert fast["base_case"] == {1, 2, 3, 4}


def test_write_single_cohort_table(conn):
    resolved = resolve_family(_make_family())
    executor = TemplateFamilyExecutor(conn, cdm_schema="main")
    relations = executor.run_resolved(resolved)

    cohort_table = "phe_tpl_test_cohort"
    executor.write_cohort_table(relations, cohort_ids=resolved.cohort_ids, cohort_table=cohort_table)

    tbl = read_table(executor.backend, table_name=cohort_table, schema=None)
    df = tbl.execute()
    assert set(df["cohort_definition_id"].tolist()) == set(resolved.cohort_ids.values())
    for name, persons in EXPECTED_PERSONS.items():
        cid = resolved.cohort_ids[name]
        sub = df[df["cohort_definition_id"] == cid]
        assert set(sub["subject_id"].tolist()) == persons, name
