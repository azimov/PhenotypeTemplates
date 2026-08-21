"""Time-distribution statistics (observation before/after index)."""

from __future__ import annotations

import pandas as pd

_METRICS = ("obs_before_days", "obs_after_days")
_BINS = [float("-inf"), 0, 30, 90, 180, 365, float("inf")]
_BUCKET_LABELS = ["<0", "0-30", "30-90", "90-180", "180-365", "365+"]


def _summary_row(series: pd.Series, metric: str) -> dict:
    return {
        "metric": metric,
        "n": int(series.count()),
        "min": float(series.min()),
        "p10": float(series.quantile(0.10)),
        "p25": float(series.quantile(0.25)),
        "median": float(series.median()),
        "mean": float(series.mean()),
        "p75": float(series.quantile(0.75)),
        "p90": float(series.quantile(0.90)),
        "max": float(series.max()),
    }


def time_distribution(index_df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return ``(summary, histogram)`` DataFrames for obs-before/after index."""
    df = index_df.copy()
    df["obs_before_days"] = (df["start_date"] - df["op_start_date"]).dt.days
    df["obs_after_days"] = (df["op_end_date"] - df["start_date"]).dt.days

    summary = pd.DataFrame([_summary_row(df[m], m) for m in _METRICS])

    hist_rows = []
    for metric in _METRICS:
        buckets = pd.cut(df[metric], bins=_BINS, labels=_BUCKET_LABELS, right=False)
        counts = buckets.value_counts().sort_index()
        total = int(counts.sum())
        for bucket, n in counts.items():
            hist_rows.append(
                {
                    "metric": metric,
                    "bucket": str(bucket),
                    "n_persons": int(n),
                    "pct": (int(n) / total if total else 0.0),
                }
            )
    histogram = pd.DataFrame(hist_rows)
    return summary, histogram
