"""Shared data extraction for diagnostics (pandas-level).

All results here are aggregated person/count level. Patient-level rows are
never written to the local asset store.
"""

from __future__ import annotations

import pandas as pd

from ..cohorts.templates import POST_LABELS, PRE_LABELS, _effective_combo

PERSON_ID = "person_id"


def execute_index_events(family) -> pd.DataFrame:
    return family.index_events.execute()


def execute_person(ctx) -> pd.DataFrame:
    cols = [
        "person_id",
        "gender_concept_id",
        "race_concept_id",
        "ethnicity_concept_id",
        "year_of_birth",
    ]
    table = ctx.table("person")
    cols = [c for c in cols if c in table.columns]
    return table.select(*cols).execute()


def execute_concept(ctx) -> pd.DataFrame:
    table = ctx.vocabulary_table("concept")
    cols = [
        c
        for c in ("concept_id", "concept_name", "domain_id", "standard_concept", "vocabulary_id")
        if c in table.columns
    ]
    df = table.select(*cols).execute()
    if "concept_name" not in df.columns:
        df["concept_name"] = None
    return df


def execute_visit(ctx) -> pd.DataFrame:
    table = ctx.table("visit_occurrence")
    cols = [c for c in ("visit_occurrence_id", "visit_concept_id") if c in table.columns]
    return table.select(*cols).execute()


def category_person_sets(family) -> dict[str, set[int] | None]:
    """Distinct persons per evidence category (S/D/T/C/F/A), from the shared key sets."""
    out: dict[str, set[int] | None] = {}
    for label, keys in family.key_sets.items():
        if keys is None:
            out[label] = None
            continue
        df = keys.select(keys[PERSON_ID]).distinct().execute()
        out[label] = {int(x) for x in df[PERSON_ID].tolist()}
    return out


def base_persons(family) -> set[int]:
    df = family.index_events.select(family.index_events[PERSON_ID]).distinct().execute()
    return {int(x) for x in df[PERSON_ID].tolist()}


def combine_person_sets(
    category_persons: dict[str, set[int] | None], combo: tuple[str, ...], op: str
) -> set[int] | None:
    sets = [category_persons[l] for l in combo if category_persons.get(l) is not None]
    if not sets:
        return None
    if len(sets) == 1:
        return sets[0]
    if op == "any":
        return set.union(*sets)
    return set.intersection(*sets)


def template_person_sets(
    category_persons: dict[str, set[int] | None],
    base: set[int],
    specs,
) -> dict[str, set[int]]:
    """Per-template person sets (set algebra over category persons, fixed index)."""
    present = {l for l, v in category_persons.items() if v is not None}
    out: dict[str, set[int]] = {}
    for spec in specs:
        pre = combine_person_sets(
            category_persons, _effective_combo(spec.pre_combo, PRE_LABELS, present), spec.pre_op
        )
        post = combine_person_sets(
            category_persons, _effective_combo(spec.post_combo, POST_LABELS, present), spec.post_op
        )
        result = set(base)
        for constraint in (pre, post):
            if constraint is not None:
                result &= constraint
        if spec.exclude_a and category_persons.get("A") is not None:
            result &= category_persons["A"]
        out[spec.name] = result
    return out
