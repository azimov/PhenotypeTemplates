"""Tests for concept-set overlap resolution (R `resolveConceptSetOverlaps` parity)."""

from __future__ import annotations

from circepy_phenotypes import cs, resolve_concept_set_overlaps


def _ids(cs_obj):
    from circepy_phenotypes import concept_ids

    return set(concept_ids(cs_obj))


def test_overlap_resolution_matches_r_documented_example():
    """Mirrors the documented expected output in ``r_template.R``."""
    cs_I = cs((100, 101, 102), name="I")
    cs_S = cs((100, 200, 201, 202, 300), name="S")
    cs_D = cs((400, 401, 402), name="D")
    cs_T = cs((500, 501, 502), name="T")
    cs_C = cs((101, 201, 300, 600, 601), name="C")
    cs_A = cs((102, 300, 301, 302), name="A")

    resolved = resolve_concept_set_overlaps(
        cs_I, cs_S, cs_D, cs_T, cs_C, cs_A, warn_on_overlap=False
    )

    assert _ids(resolved["cs_I"]) == {100, 101, 102}
    assert _ids(resolved["cs_A"]) == {300, 301, 302}
    assert _ids(resolved["cs_S"]) == {200, 201, 202}
    assert _ids(resolved["cs_C"]) == {201, 600, 601}
    assert _ids(resolved["cs_D"]) == {400, 401, 402}
    assert _ids(resolved["cs_T"]) == {500, 501, 502}


def test_empty_set_becomes_none():
    cs_I = cs((100, 101), name="I")
    cs_S = cs((100, 101), name="S")

    resolved = resolve_concept_set_overlaps(cs_I, cs_S=cs_S, warn_on_overlap=False)
    assert resolved["cs_S"] is None


def test_requires_cs_I():
    import pytest

    with pytest.raises(ValueError, match="cs_I"):
        resolve_concept_set_overlaps(None)
