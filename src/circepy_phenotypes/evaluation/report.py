"""Tidy report generation for an :class:`~.EvaluationResult`."""

from __future__ import annotations

from . import EvaluationResult

_COLUMNS = (
    "cohort",
    "n_persons",
    "tp",
    "fp",
    "fn",
    "tn",
    "sensitivity",
    "specificity",
    "ppv",
    "npv",
    "prevalence",
    "youden",
    "f1",
)


def metrics_table(result: EvaluationResult, sort_by: str = "youden"):
    """Return a pandas DataFrame of per-candidate metrics (best first)."""
    import pandas as pd

    rows = []
    for name, metrics in result.metrics.items():
        cm = result.confusion_matrices[name]
        rows.append(
            {
                "cohort": name,
                "n_persons": len(result.candidate_persons[name]),
                "tp": cm.tp,
                "fp": cm.fp,
                "fn": cm.fn,
                "tn": cm.tn,
                "sensitivity": metrics.sensitivity,
                "specificity": metrics.specificity,
                "ppv": metrics.ppv,
                "npv": metrics.npv,
                "prevalence": metrics.prevalence,
                "youden": metrics.youden,
                "f1": metrics.f1,
            }
        )

    df = pd.DataFrame(rows, columns=list(_COLUMNS))
    if sort_by:
        df = df.sort_values(sort_by, ascending=False, na_position="last")
    return df


def format_report(result: EvaluationResult) -> str:
    """Render the metrics as a human-readable string table."""
    import pandas as pd

    df = metrics_table(result)
    with pd.option_context("display.float_format", "{:,.4f}".format, "display.max_columns", None):
        return df.to_string(index=False)


def plot_metrics(result: EvaluationResult, *, show: bool = False, save_path: str | None = None):
    """Plot sensitivity vs specificity per candidate (matplotlib, optional)."""
    import matplotlib.pyplot as plt

    sens = [m.sensitivity for m in result.metrics.values()]
    spec = [m.specificity for m in result.metrics.values()]
    names = list(result.metrics.keys())

    fig, ax = plt.subplots()
    ax.scatter(spec, sens)
    for i, name in enumerate(names):
        ax.annotate(name, (spec[i], sens[i]))
    ax.set_xlabel("Specificity")
    ax.set_ylabel("Sensitivity")
    ax.set_title("Candidate cohorts: sensitivity vs specificity")
    ax.set_xlim(-0.05, 1.05)
    ax.set_ylim(-0.05, 1.05)

    if save_path:
        fig.savefig(save_path)
    if show:
        plt.show()
    return fig
