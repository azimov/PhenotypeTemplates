"""Concept-set analysis: resolved concepts and per-concept prevalence.

For every concept set in the family (I/S/D/T/C/A), resolve its concepts
(descendant expansion via ``concept_ancestor``), then compute the prevalence of
each resolved concept among the entry cohort within the category's domain +
window. Descendant counts are rolled up to parents, so an ancestor's prevalence
is the number of entry-cohort persons with the ancestor *or any descendant*.
Concepts with zero prevalence are retained (orphan detection).
"""

from __future__ import annotations

import ibis
import pandas as pd

PERSON_ID = "person_id"

_CATEGORY_ORDER = ("I", "S", "D", "T", "C", "A")

_CATEGORY_DOMAINS: dict[str, tuple[tuple[str, str, str], ...]] = {
    "S": (
        ("condition_occurrence", "condition_concept_id", "condition_start_date"),
        ("observation", "observation_concept_id", "observation_date"),
    ),
    "D": (
        ("measurement", "measurement_concept_id", "measurement_date"),
        ("procedure_occurrence", "procedure_concept_id", "procedure_date"),
        ("device_exposure", "device_concept_id", "device_exposure_start_date"),
    ),
    "T": (
        ("drug_exposure", "drug_concept_id", "drug_exposure_start_date"),
        ("procedure_occurrence", "procedure_concept_id", "procedure_date"),
        ("device_exposure", "device_concept_id", "device_exposure_start_date"),
    ),
    "C": (
        ("condition_occurrence", "condition_concept_id", "condition_start_date"),
        ("observation", "observation_concept_id", "observation_date"),
    ),
    "A": (
        ("condition_occurrence", "condition_concept_id", "condition_start_date"),
        ("observation", "observation_concept_id", "observation_date"),
    ),
}

_CATEGORY_WINDOW: dict[str, tuple[int, int]] = {
    "S": (-30, 0),
    "D": (-30, 0),
    "T": (0, 30),
    "C": (1, 365),
    "A": (-30, 30),
}


def _category_concept_set(resolved, label: str):
    codeset_id = resolved.codeset_ids.get(label)
    if codeset_id is None:
        return None
    for cs in resolved.concept_sets:
        if cs.id == codeset_id:
            return cs
    return None


def _items(resolved) -> dict[str, list[tuple[int, bool]]]:
    out: dict[str, list[tuple[int, bool]]] = {}
    for label in _CATEGORY_ORDER:
        cs = _category_concept_set(resolved, label)
        if cs is None or cs.expression is None or not cs.expression.items:
            continue
        out[label] = [
            (int(it.concept.concept_id), bool(it.include_descendants))
            for it in cs.expression.items
            if it is not None and it.concept is not None and it.concept.concept_id is not None
        ]
    return out


def _resolve_ids(
    items: dict[str, list[tuple[int, bool]]], expansion: dict[int, set[int]]
) -> dict[str, set[int]]:
    resolved: dict[str, set[int]] = {}
    for label, entries in items.items():
        ids: set[int] = set()
        for cid, include_desc in entries:
            ids.add(cid)
            if include_desc:
                ids |= expansion.get(cid, set())
        resolved[label] = ids
    return resolved


def _scan_domains(family, ctx, domains, window: tuple[int, int], ids: list[int]) -> pd.DataFrame:
    lo, hi = window
    ie = family.index_events.select(
        family.index_events[PERSON_ID].name(PERSON_ID),
        family.index_events.start_date.name("start_date"),
    ).distinct()

    parts = []
    for table, concept_col, start_col in domains:
        domain = ctx.table(table)
        joined = ie.join(domain, ie[PERSON_ID] == domain[PERSON_ID])
        cond = (
            domain[concept_col].isin(ids)
            & (domain[start_col] >= ie.start_date + ibis.interval(days=lo))
            & (domain[start_col] <= ie.start_date + ibis.interval(days=hi))
        )
        parts.append(
            joined.filter(cond).select(
                ie[PERSON_ID].name(PERSON_ID),
                domain[concept_col].cast("int64").name("concept_id"),
            )
        )

    if not parts:
        return pd.DataFrame(columns=[PERSON_ID, "concept_id"])

    unioned = parts[0]
    for part in parts[1:]:
        unioned = unioned.union(part, distinct=False)
    return unioned.distinct().execute()


def concept_set_analysis(
    resolved, family, ctx, *, base_n: int
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return ``(concept_sets, concept_prevalence)`` DataFrames."""
    items = _items(resolved)

    empty_sets = pd.DataFrame(
        columns=[
            "category",
            "concept_id",
            "concept_name",
            "domain_id",
            "standard_concept",
            "is_root",
        ]
    )
    empty_prev = pd.DataFrame(
        columns=["category", "concept_id", "concept_name", "n_persons", "pct_of_base"]
    )
    if not items:
        return empty_sets, empty_prev

    roots_with_desc = [cid for entries in items.values() for cid, inc in entries if inc]

    expansion: dict[int, set[int]] = {}
    if roots_with_desc:
        ca = ctx.vocabulary_table("concept_ancestor")
        exp = (
            ca.filter(ca.ancestor_concept_id.isin(roots_with_desc))
            .select(ca.ancestor_concept_id, ca.descendant_concept_id)
            .execute()
        )
        for ancestor, descendant in zip(exp["ancestor_concept_id"], exp["descendant_concept_id"]):
            expansion.setdefault(int(ancestor), set()).add(int(descendant))

    resolved_ids = _resolve_ids(items, expansion)
    all_resolved = sorted(set().union(*resolved_ids.values()))

    concept = ctx.vocabulary_table("concept")
    meta_cols = [
        c
        for c in ("concept_id", "concept_name", "domain_id", "standard_concept", "vocabulary_id")
        if c in concept.columns
    ]
    meta = concept.filter(concept.concept_id.isin(all_resolved)).select(*meta_cols).execute()

    edges_df = pd.DataFrame(columns=["ancestor_concept_id", "descendant_concept_id"])
    if all_resolved:
        ca = ctx.vocabulary_table("concept_ancestor")
        edges = (
            ca.filter(
                ca.ancestor_concept_id.isin(all_resolved)
                & ca.descendant_concept_id.isin(all_resolved)
            )
            .select(ca.ancestor_concept_id, ca.descendant_concept_id)
            .execute()
        )
        if not edges.empty:
            edges_df = edges.astype("int64")
    # Ensure self-mapping so direct concepts roll up to themselves.
    self_edges = pd.DataFrame(
        {"ancestor_concept_id": all_resolved, "descendant_concept_id": all_resolved}
    )
    edges_df = pd.concat([edges_df, self_edges], ignore_index=True).drop_duplicates()

    concept_sets_rows = []
    prevalence_rows = []
    for label in _CATEGORY_ORDER:
        if label not in resolved_ids:
            continue
        ids = sorted(resolved_ids[label])
        roots = {cid for cid, _inc in items[label]}

        sub_meta = meta[meta["concept_id"].isin(ids)]
        for cid in ids:
            row = sub_meta[sub_meta["concept_id"] == cid]
            concept_sets_rows.append(
                {
                    "category": label,
                    "concept_id": cid,
                    "concept_name": row.iloc[0].get("concept_name") if not row.empty else None,
                    "domain_id": row.iloc[0].get("domain_id") if not row.empty else None,
                    "standard_concept": row.iloc[0].get("standard_concept")
                    if not row.empty
                    else None,
                    "is_root": cid in roots,
                }
            )

        if label == "I":
            ie = family.index_events
            matched = (
                ie.filter(ie.concept_id.isin(ids))
                .select(
                    ie[PERSON_ID].name(PERSON_ID), ie.concept_id.cast("int64").name("concept_id")
                )
                .distinct()
                .execute()
            )
        else:
            matched = _scan_domains(
                family, ctx, _CATEGORY_DOMAINS[label], _CATEGORY_WINDOW[label], ids
            )

        if matched.empty:
            matched = pd.DataFrame(columns=[PERSON_ID, "concept_id"])

        rolled = matched.merge(
            edges_df, left_on="concept_id", right_on="descendant_concept_id", how="inner"
        )
        rolled = rolled[rolled["ancestor_concept_id"].isin(ids)]
        counts = rolled.groupby("ancestor_concept_id")[PERSON_ID].nunique()

        for cid in ids:
            n = int(counts.get(cid, 0))
            mrow = sub_meta[sub_meta["concept_id"] == cid]
            prevalence_rows.append(
                {
                    "category": label,
                    "concept_id": cid,
                    "concept_name": mrow.iloc[0].get("concept_name") if not mrow.empty else None,
                    "n_persons": n,
                    "pct_of_base": (n / base_n) if base_n else 0.0,
                }
            )

    concept_sets_df = pd.DataFrame(concept_sets_rows)
    prevalence_df = pd.DataFrame(prevalence_rows)
    if not prevalence_df.empty:
        prevalence_df = prevalence_df.sort_values(
            ["category", "pct_of_base"], ascending=[True, False]
        )
    return concept_sets_df, prevalence_df
