"""Pairwise template overlap (Jaccard) over fixed-index person sets."""

from __future__ import annotations

import pandas as pd


def template_overlap(template_persons: dict[str, set[int]]) -> pd.DataFrame:
    """Jaccard overlap for every pair of cohorts (base_case + templates)."""
    names = sorted(template_persons)
    rows = []
    for i, a in enumerate(names):
        set_a = template_persons[a]
        for b in names[i + 1 :]:
            set_b = template_persons[b]
            intersection = set_a & set_b
            union = set_a | set_b
            rows.append(
                {
                    "template_a": a,
                    "template_b": b,
                    "n_a": len(set_a),
                    "n_b": len(set_b),
                    "n_intersection": len(intersection),
                    "n_union": len(union),
                    "jaccard": (len(intersection) / len(union)) if union else 0.0,
                }
            )
    return pd.DataFrame(rows)
