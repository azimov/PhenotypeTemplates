"""Candidate ranking/selection over label-based metrics.

Pure (no backend dependency): operates on :class:`~.metrics.Metrics` values.
"""

from __future__ import annotations

import math
from collections.abc import Mapping

from .metrics import Metrics

# Score functions keyed by a canonical criterion name.
_SCORERS: dict[str, object] = {
    "youden": lambda m: m.youden,
    "f1": lambda m: m.f1,
    "sensitivity": lambda m: m.sensitivity,
    "specificity": lambda m: m.specificity,
    "ppv": lambda m: m.ppv,
    "npv": lambda m: m.npv,
}


def score(metrics: Metrics, criterion: str = "youden") -> float:
    """Return the scalar score for *criterion*."""
    key = criterion.lower().replace("'", "").replace("-", "_").replace(" ", "_")
    scorer = _SCORERS.get(key)
    if scorer is None:
        available = ", ".join(sorted(_SCORERS))
        raise ValueError(f"Unknown selection criterion {criterion!r}. Available: {available}")
    return float(scorer(metrics))


def rank_candidates(
    candidates: Mapping[str, Metrics],
    criterion: str = "youden",
    *,
    na_last: bool = True,
) -> list[tuple[str, float]]:
    """Rank candidates by *criterion*, best first.

    Returns ``[(name, score), ...]`` sorted descending. ``NaN`` scores are
    pushed to the end (or the front if ``na_last=False``).
    """
    def sort_key(item: tuple[str, float]) -> tuple[int, int, float]:
        _name, value = item
        is_nan = math.isnan(value)
        # (nan_rank, sign * value) sorts finite values descending while
        # grouping NaN according to ``na_last``.
        nan_rank = 1 if is_nan else 0
        if not na_last:
            nan_rank = -nan_rank
        return (nan_rank, 0 if is_nan else 1, value if not is_nan else 0.0)

    scored = [(name, score(metrics, criterion)) for name, metrics in candidates.items()]
    scored.sort(key=sort_key, reverse=True)
    return scored
