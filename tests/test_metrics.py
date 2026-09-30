"""Pure unit tests for label-based metrics and candidate selection."""

from __future__ import annotations

import math

import pytest

from circepy_phenotypes.evaluation import (
    Metrics,
    compute_metrics,
    confusion_matrix,
    rank_candidates,
    score,
)


def test_confusion_matrix_hand_computed():
    universe = {1, 2, 3, 4, 5}
    gold = {1, 2, 3}
    candidate = {2, 3}

    cm = confusion_matrix(universe, gold, candidate)
    assert cm.tp == 2  # {2, 3}
    assert cm.fp == 0  # nothing in candidate but not gold
    assert cm.fn == 1  # {1}
    assert cm.tn == 2  # {4, 5}
    assert cm.total == 5
    assert cm.positive == 3
    assert cm.negative == 2


def test_compute_metrics_ratios():
    cm = confusion_matrix({1, 2, 3, 4}, {1, 2}, {2, 4})
    # tp=1 ({2}), fp=1 ({4}), fn=1 ({1}), tn=1 ({3})
    m = compute_metrics(cm)
    assert m.sensitivity == pytest.approx(0.5)
    assert m.specificity == pytest.approx(0.5)
    assert m.ppv == pytest.approx(0.5)
    assert m.npv == pytest.approx(0.5)
    assert m.prevalence == pytest.approx(0.5)
    assert m.youden == pytest.approx(0.0)
    assert m.f1 == pytest.approx(0.5)


def test_empty_candidate_ppv_nan_warns():
    cm = confusion_matrix({1, 2, 3}, {1, 2}, set())
    with pytest.warns(UserWarning, match="PPV"):
        m = compute_metrics(cm)
    assert m.sensitivity == 0.0
    assert m.specificity == 1.0  # tn=1, fp=0
    assert math.isnan(m.ppv)
    assert math.isnan(m.f1)  # harmonic mean with NaN denom


def test_empty_universe_all_nan_warns():
    cm = confusion_matrix(set(), set(), set())
    with pytest.warns(UserWarning):
        m = compute_metrics(cm)
    assert math.isnan(m.sensitivity)
    assert math.isnan(m.specificity)


def test_youden_and_f1_properties():
    m = Metrics(sensitivity=1.0, specificity=0.0, ppv=0.5, npv=0.0, prevalence=0.5)
    assert m.youden == pytest.approx(0.0)
    assert m.f1 == pytest.approx(2 * 0.5 * 1.0 / 1.5)


def test_score_and_rank():
    metrics = {
        "perfect": Metrics(1.0, 1.0, 1.0, 1.0, 0.5),
        "sensitive_only": Metrics(1.0, 0.0, 0.5, 0.0, 0.5),
        "specific_only": Metrics(0.0, 1.0, 0.0, 0.5, 0.5),
    }
    ranked = rank_candidates(metrics, criterion="youden")
    assert ranked[0][0] == "perfect"
    assert ranked[0][1] == pytest.approx(1.0)

    assert score(metrics["perfect"], "youden") == pytest.approx(1.0)
    assert score(metrics["sensitive_only"], "sensitivity") == pytest.approx(1.0)
    with pytest.raises(ValueError, match="Unknown selection criterion"):
        score(metrics["perfect"], "bogus")
