"""Structural tests: the built cohort expressions match the Capr/R mapping.

These assert on the CircePy models directly (the mapping established from
Capr's source), standing in for an R round-trip since R is not available here.
"""

from __future__ import annotations

from circe.cohortdefinition import CriteriaGroup, Occurrence

from pheno_tpl import FamilySpec, cs, resolve_family


def _family():
    return resolve_family(
        FamilySpec(
            cs_I=cs((111,), name="I"),
            cs_S=cs((211,), name="S"),
            cs_D=cs((311,), name="D"),
            cs_T=cs((411,), name="T"),
            cs_C=cs((511,), name="C"),
            cs_A=cs((611,), name="A"),
            phenotype_label="Test",
        )
    )


def test_base_case_structure():
    _, expr = _family().expressions["base_case"]
    assert expr.inclusion_rules == []
    pc = expr.primary_criteria
    assert [c.codeset_id for c in pc.criteria_list] == [1, 1]
    assert [c.first for c in pc.criteria_list] == [True, True]
    assert pc.observation_window.prior_days == 0
    assert pc.observation_window.post_days == 0
    assert pc.primary_limit.type == "First"
    assert expr.expression_limit.type == "First"
    assert expr.qualified_limit.type == "First"
    assert expr.end_strategy is None  # chronic / observationExit
    assert expr.collapse_settings.collapse_type.value == "ERA"
    assert expr.collapse_settings.era_pad == 0


def test_tpl1_pre_group_structure():
    _, expr = _family().expressions["tpl_1"]
    assert len(expr.inclusion_rules) == 1
    rule = expr.inclusion_rules[0]
    assert rule.name == "pre-index evidence (S/D within -30 to 0d)"
    group = rule.expression
    assert isinstance(group, CriteriaGroup)
    assert group.type == "ANY"
    assert len(group.groups) == 2  # S group and D group

    s_group, d_group = group.groups
    assert s_group.type == "ANY"
    assert len(s_group.criteria_list) == 2  # condition + observation
    cc = s_group.criteria_list[0]
    assert cc.criteria.codeset_id == 2
    assert cc.occurrence.type == Occurrence._AT_LEAST and cc.occurrence.count == 1
    assert cc.start_window.start.coeff == -1 and cc.start_window.start.days == 30
    assert cc.start_window.end.coeff == -1 and cc.start_window.end.days == 0
    assert cc.ignore_observation_period is True

    d_group_criteria = d_group.criteria_list
    assert len(d_group_criteria) == 3  # measurement + procedure + device
    assert [c.criteria.codeset_id for c in d_group_criteria] == [3, 3, 3]


def test_tpl5_exclusion_group_structure():
    _, expr = _family().expressions["tpl_5"]
    assert len(expr.inclusion_rules) == 1
    rule = expr.inclusion_rules[0]
    assert rule.name == "no alternative diagnosis (A excluded -30 to +30d)"
    group = rule.expression
    assert isinstance(group, CriteriaGroup)
    assert group.type == "ALL"
    assert len(group.criteria_list) == 2  # exactly(0) condition + observation
    for cc in group.criteria_list:
        assert cc.occurrence.type == Occurrence._EXACTLY and cc.occurrence.count == 0
        assert cc.start_window.start.coeff == -1 and cc.start_window.start.days == 30
        assert cc.start_window.end.coeff == 1 and cc.start_window.end.days == 30
        assert cc.ignore_observation_period is True


def test_tpl3_f_criterion_structure():
    _, expr = _family().expressions["tpl_3"]
    assert len(expr.inclusion_rules) == 1
    rule = expr.inclusion_rules[0]
    group = rule.expression
    assert isinstance(group, CriteriaGroup)
    assert group.type == "ANY"
    assert len(group.criteria_list) == 1  # ER/Inpatient visit
    assert len(group.groups) == 1  # second I (cond|obs, +1..+365)

    visit_cc = group.criteria_list[0]
    assert visit_cc.criteria.codeset_id == 7
    # start window eventStarts(-Inf, 0): no lower bound, end at index
    assert visit_cc.start_window.start.days is None and visit_cc.start_window.start.coeff == -1
    assert visit_cc.start_window.end.coeff == -1 and visit_cc.start_window.end.days == 0
    # end window eventEnds(0, Inf): use_event_end, start at index, no upper bound
    assert visit_cc.end_window.use_event_end is True
    assert visit_cc.end_window.start.coeff == -1 and visit_cc.end_window.start.days == 0
    assert visit_cc.end_window.end.days is None and visit_cc.end_window.end.coeff == 1
    assert visit_cc.ignore_observation_period is True

    second_i_group = group.groups[0]
    assert second_i_group.type == "ANY"
    second_cc = second_i_group.criteria_list[0]
    assert second_cc.start_window.start.coeff == 1 and second_cc.start_window.start.days == 1
    assert second_cc.start_window.end.coeff == 1 and second_cc.start_window.end.days == 365


def test_exit_strategies_map_correctly():
    from pheno_tpl import make_end_strategy

    assert make_end_strategy("chronic") is None
    acute = make_end_strategy("acute14d")
    assert acute.date_field == "EndDate" and acute.offset == 14
    assert make_end_strategy("acute365d").offset == 365
