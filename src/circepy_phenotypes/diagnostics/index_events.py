"""Index-event breakdown and visit context (aggregated)."""

from __future__ import annotations

import pandas as pd

PERSON_ID = "person_id"


def _concept_lookup(concept_df: pd.DataFrame) -> pd.DataFrame:
    if "concept_name" not in concept_df.columns:
        return concept_df[["concept_id"]].drop_duplicates("concept_id")
    return concept_df[["concept_id", "concept_name"]].drop_duplicates("concept_id")


def index_event_breakdown(index_df: pd.DataFrame, concept_df: pd.DataFrame) -> pd.DataFrame:
    """Counts of entry events by domain / concept / source table."""
    df = index_df.copy()
    df["concept_id"] = df["concept_id"].fillna(0).astype("int64")
    grp = (
        df.groupby(["domain", "concept_id", "source_table"], as_index=False)
        .agg(n_persons=(PERSON_ID, "nunique"), n_events=(PERSON_ID, "size"))
        .sort_values("n_events", ascending=False)
    )
    return grp.merge(_concept_lookup(concept_df), on="concept_id", how="left")


def visit_context(
    index_df: pd.DataFrame, visit_df: pd.DataFrame, concept_df: pd.DataFrame
) -> pd.DataFrame:
    """Visit-type distribution at index (via visit_occurrence)."""
    ie = index_df[[PERSON_ID, "visit_occurrence_id"]].copy()
    ie = ie[ie["visit_occurrence_id"].notna()]
    if ie.empty:
        return pd.DataFrame(columns=["visit_concept_id", "visit_concept_name", "n_persons"])

    ie["visit_occurrence_id"] = ie["visit_occurrence_id"].astype("int64")
    visits = visit_df[["visit_occurrence_id", "visit_concept_id"]].drop_duplicates(
        "visit_occurrence_id"
    )
    merged = ie.merge(visits, on="visit_occurrence_id", how="inner")

    grp = (
        merged.groupby("visit_concept_id", as_index=False)
        .agg(n_persons=(PERSON_ID, "nunique"))
        .sort_values("n_persons", ascending=False)
    )
    return grp.merge(
        _concept_lookup(concept_df), left_on="visit_concept_id", right_on="concept_id", how="left"
    )
