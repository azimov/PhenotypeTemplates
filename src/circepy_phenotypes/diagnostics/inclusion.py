"""Coverage and attrition statistics from the cohort inclusion rules."""

from __future__ import annotations

import pandas as pd

from ..cohorts.templates import POST_LABELS, PRE_LABELS, _effective_combo
from ._data import combine_person_sets

_CATEGORIES = ("S", "D", "T", "C", "F", "A")


def coverage(category_persons: dict[str, set[int] | None], base_n: int) -> pd.DataFrame:
    """Persons captured by each evidence category, as a fraction of base_case."""
    rows = []
    for category in _CATEGORIES:
        if category not in category_persons or category_persons[category] is None:
            continue
        n = len(category_persons[category])
        rows.append(
            {
                "category": category,
                "n_persons": n,
                "pct_of_base": (n / base_n) if base_n else 0.0,
            }
        )
    return pd.DataFrame(rows)


def attrition(
    category_persons: dict[str, set[int] | None],
    base_persons: set[int],
    specs,
) -> pd.DataFrame:
    """Stepwise person counts as each template's rules are applied."""
    present = {l for l, v in category_persons.items() if v is not None}
    rows = []
    for spec in specs:
        current = set(base_persons)
        entry_n = len(current)
        stages: list[tuple[str, int]] = [("entry", entry_n)]

        pre = combine_person_sets(
            category_persons, _effective_combo(spec.pre_combo, PRE_LABELS, present), spec.pre_op
        )
        post = combine_person_sets(
            category_persons, _effective_combo(spec.post_combo, POST_LABELS, present), spec.post_op
        )

        if pre is not None:
            current &= pre
            stages.append(("pre", len(current)))
        if post is not None:
            current &= post
            stages.append(("post", len(current)))
        if spec.exclude_a and category_persons.get("A") is not None:
            current &= category_persons["A"]
            stages.append(("not_a", len(current)))

        stages.append(("final", len(current)))
        rows.extend(
            {
                "template": spec.name,
                "stage": stage,
                "n_persons": n,
                "pct_of_entry": (n / entry_n) if entry_n else 0.0,
            }
            for stage, n in stages
        )

    return pd.DataFrame(rows)
