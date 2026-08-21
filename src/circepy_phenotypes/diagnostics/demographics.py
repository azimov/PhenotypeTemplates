"""Per-template demographic characterization (aggregated counts)."""

from __future__ import annotations

import pandas as pd

PERSON_ID = "person_id"

_AGE_BANDS = (
    (-1, 10, "0-9"),
    (10, 20, "10-19"),
    (20, 30, "20-29"),
    (30, 40, "30-39"),
    (40, 50, "40-49"),
    (50, 60, "50-59"),
    (60, 70, "60-69"),
    (70, 80, "70-79"),
    (80, 200, "80+"),
)


def _age_group(age: float) -> str:
    if pd.isna(age):
        return "unknown"
    for lo, hi, label in _AGE_BANDS:
        if lo <= age < hi:
            return label
    return "unknown"


def _concept_lookup(concept_df: pd.DataFrame) -> pd.DataFrame:
    if "concept_name" not in concept_df.columns:
        return concept_df[["concept_id"]].drop_duplicates("concept_id")
    return concept_df[["concept_id", "concept_name"]].drop_duplicates("concept_id")


def demographic_characterization(
    index_df: pd.DataFrame,
    person_df: pd.DataFrame,
    template_persons: dict[str, set[int]],
    concept_df: pd.DataFrame,
) -> pd.DataFrame:
    """Counts of gender / age group / race / ethnicity per template."""
    idx = index_df[[PERSON_ID, "start_date"]].copy()
    person = person_df.copy()
    merged = idx.merge(person, on=PERSON_ID, how="inner")
    merged["age"] = merged["start_date"].dt.year - merged["year_of_birth"]

    lookup = _concept_lookup(concept_df)
    rows: list[pd.DataFrame] = []

    for name, persons in template_persons.items():
        sub = merged[merged[PERSON_ID].isin(persons)]
        if sub[PERSON_ID].nunique() == 0:
            continue

        for dim, col in (
            ("gender", "gender_concept_id"),
            ("race", "race_concept_id"),
            ("ethnicity", "ethnicity_concept_id"),
        ):
            if col not in sub.columns:
                continue
            g = (
                sub.groupby(col, dropna=False)
                .agg(n_persons=(PERSON_ID, "nunique"))
                .reset_index()
                .rename(columns={col: "concept_id"})
            )
            g["template"] = name
            g["dimension"] = dim
            g = g.merge(lookup, on="concept_id", how="left")
            g["category"] = g["concept_name"].fillna(g["concept_id"].astype(str))
            rows.append(g[["template", "dimension", "category", "concept_id", "n_persons"]])

        age = sub.copy()
        age["age_group"] = age["age"].apply(_age_group)
        g = age.groupby("age_group").agg(n_persons=(PERSON_ID, "nunique")).reset_index()
        g["template"] = name
        g["dimension"] = "age_group"
        g["category"] = g["age_group"]
        g["concept_id"] = None
        rows.append(g[["template", "dimension", "category", "concept_id", "n_persons"]])

    if not rows:
        return pd.DataFrame(
            columns=[
                "template",
                "dimension",
                "category",
                "concept_id",
                "n_persons",
                "pct_of_template",
            ]
        )

    out = pd.concat(rows, ignore_index=True)
    out["pct_of_template"] = out.groupby(["template", "dimension"])["n_persons"].transform(
        lambda s: s / s.sum()
    )
    return out
