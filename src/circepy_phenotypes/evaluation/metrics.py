"""Pure, label-based evaluation metrics (sensitivity / specificity / PPV / NPV).

No CircePy or ibis dependency: everything operates on person-id sets so the
logic can be unit-tested independently of any backend.
"""

from __future__ import annotations

import math
import warnings
from dataclasses import dataclass


@dataclass(frozen=True)
class ConfusionMatrix:
    """Binary confusion matrix counts over a universe ``U``."""

    tp: int
    fp: int
    fn: int
    tn: int

    @property
    def total(self) -> int:
        return self.tp + self.fp + self.fn + self.tn

    @property
    def positive(self) -> int:
        return self.tp + self.fn

    @property
    def negative(self) -> int:
        return self.tn + self.fp


def confusion_matrix(
    universe: set[int] | frozenset[int],
    gold: set[int] | frozenset[int],
    candidate: set[int] | frozenset[int],
) -> ConfusionMatrix:
    """Compute the confusion matrix for a candidate against a gold standard.

    ``universe`` is the evaluation universe (e.g. the demographics-filtered
    sensitive population). Persons are compared by integer id.
    """
    u = set(universe)
    g = set(gold)
    c = set(candidate)

    tp = len(c & g)
    fp = len(c - g)
    fn = len(g - c)
    tn = len(u - (c | g))

    return ConfusionMatrix(tp=tp, fp=fp, fn=fn, tn=tn)


@dataclass(frozen=True)
class Metrics:
    """Derived label-based performance metrics."""

    sensitivity: float
    specificity: float
    ppv: float
    npv: float
    prevalence: float

    @property
    def youden(self) -> float:
        """Youden's J statistic = sensitivity + specificity - 1."""
        return self.sensitivity + self.specificity - 1.0

    @property
    def f1(self) -> float:
        """F1 score (harmonic mean of PPV and sensitivity)."""
        denom = self.ppv + self.sensitivity
        if denom == 0 or math.isnan(denom):
            return float("nan")
        return 2.0 * self.ppv * self.sensitivity / denom


def _ratio(numerator: int, denominator: int, label: str) -> float:
    if denominator == 0:
        warnings.warn(f"{label} denominator is zero; returning NaN", stacklevel=3)
        return float("nan")
    return numerator / denominator


def compute_metrics(cm: ConfusionMatrix) -> Metrics:
    """Derive sens/spec/PPV/NPV/prevalence from a confusion matrix.

    Empty denominators yield ``NaN`` (with a warning) rather than raising.
    """
    sensitivity = _ratio(cm.tp, cm.tp + cm.fn, "Sensitivity")
    specificity = _ratio(cm.tn, cm.tn + cm.fp, "Specificity")
    ppv = _ratio(cm.tp, cm.tp + cm.fp, "PPV")
    npv = _ratio(cm.tn, cm.tn + cm.fn, "NPV")
    prevalence = _ratio(cm.positive, cm.total, "Prevalence")
    return Metrics(
        sensitivity=sensitivity,
        specificity=specificity,
        ppv=ppv,
        npv=npv,
        prevalence=prevalence,
    )
