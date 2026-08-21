"""Template family definitions mirroring ``r_template.R``.

Encodes the 23 evaluation templates (base_case + tpl_1..tpl_22) as declarative
specs and provides builders that:

  * emit a full :class:`CohortExpression` per template (Atlas/SQL/parity path), and
  * describe the atomic inclusion populations (``S``, ``D``, ``T``, ``C``, ``F``, ``A``)
    used by the fast shared-execution path.
"""

from __future__ import annotations

from dataclasses import dataclass

from circe.cohortdefinition import CohortExpression, InclusionRule
from circe.cohortdefinition.core import ResultLimit
from circe.vocabulary import ConceptSet

from .criteria import (
    combine_criteria,
    condition_occurrence,
    device_exposure,
    drug_exposure,
    event_starts_window,
    make_collapse_settings,
    make_end_strategy,
    make_entry_criteria,
    make_exclusion_criterion,
    make_f_criterion,
    make_multi_domain_criterion,
    measurement,
    observation,
    procedure,
)

# Category labels used across the family
PRE_LABELS = ("S", "D")
POST_LABELS = ("T", "C", "F")


@dataclass(frozen=True)
class TemplateSpec:
    """Declarative description of a scenario template.

    ``pre_combo``/``post_combo`` semantics match Capr: ``None`` means "use
    whichever of the categories is present" (default behaviour), ``()`` means
    "no constraint", otherwise a tuple of category labels.
    """

    name: str
    template_number: int | None = None
    pre_op: str = "any"
    pre_combo: tuple[str, ...] | None = None
    post_op: str = "any"
    post_combo: tuple[str, ...] | None = None
    exclude_a: bool = False


# 22 scenario templates (tpl_1 .. tpl_22); base_case is handled separately.
TEMPLATE_SPECS: tuple[TemplateSpec, ...] = (
    TemplateSpec("tpl_1", 1, pre_op="any", pre_combo=("S", "D"), post_combo=()),
    TemplateSpec("tpl_2", 2, pre_combo=(), post_op="any"),
    TemplateSpec("tpl_3", 3, pre_combo=(), post_combo=("F",)),
    TemplateSpec("tpl_4", 4, pre_combo=(), post_combo=("T",)),
    TemplateSpec("tpl_5", 5, pre_combo=(), post_combo=(), exclude_a=True),
    TemplateSpec("tpl_6", 6, pre_combo=("D",), post_combo=()),
    TemplateSpec("tpl_7", 7, pre_op="any", pre_combo=("S", "D"), post_combo=(), exclude_a=True),
    TemplateSpec("tpl_8", 8, pre_combo=(), post_op="any", exclude_a=True),
    TemplateSpec("tpl_9", 9, pre_op="any", post_op="any"),
    TemplateSpec("tpl_10", 10, pre_op="any", post_op="any", exclude_a=True),
    TemplateSpec("tpl_11", 11, pre_op="all", post_op="any"),
    TemplateSpec("tpl_12", 12, pre_op="all", post_op="any", exclude_a=True),
    TemplateSpec("tpl_13", 13, pre_op="any", post_op="all"),
    TemplateSpec("tpl_14", 14, pre_op="any", post_op="all", exclude_a=True),
    TemplateSpec("tpl_15", 15, pre_op="all", post_op="all", post_combo=("T", "F")),
    TemplateSpec("tpl_16", 16, pre_op="all", post_op="all", post_combo=("F", "C")),
    TemplateSpec("tpl_17", 17, pre_op="all", post_op="all", post_combo=("T", "C")),
    TemplateSpec("tpl_18", 18, pre_op="all", post_op="all", post_combo=("T", "F"), exclude_a=True),
    TemplateSpec("tpl_19", 19, pre_op="all", post_op="all", post_combo=("F", "C"), exclude_a=True),
    TemplateSpec("tpl_20", 20, pre_op="all", post_op="all", post_combo=("T", "C"), exclude_a=True),
    TemplateSpec("tpl_21", 21, pre_op="all", post_op="all", post_combo=("T", "C", "F")),
    TemplateSpec("tpl_22", 22, pre_op="all", post_op="all", post_combo=("T", "C", "F"), exclude_a=True),
)

# Fixed concept-set ids assigned to each category (stable across the family).
CONCEPT_SET_IDS = {
    "I": 1,
    "S": 2,
    "D": 3,
    "T": 4,
    "C": 5,
    "A": 6,
    "F_VISIT": 7,
}


def build_atomic_groups(codeset_ids: dict[str, int]) -> dict[str, object]:
    """Build the atomic inclusion-population groups for each category.

    ``codeset_ids`` maps category labels (``I``, ``S``, ``D``, ``T``, ``C``,
    ``A``, ``F_VISIT``) to concept-set ids; a missing label means the category
    is not relevant and its group is ``None``.
    """
    cs = codeset_ids
    groups: dict[str, object] = {}

    if cs.get("S") is not None:
        groups["S"] = make_multi_domain_criterion(
            cs["S"], [condition_occurrence, observation], start_window=event_starts_window(-30, 0)
        )
    if cs.get("D") is not None:
        groups["D"] = make_multi_domain_criterion(
            cs["D"], [measurement, procedure, device_exposure], start_window=event_starts_window(-30, 0)
        )
    if cs.get("T") is not None:
        groups["T"] = make_multi_domain_criterion(
            cs["T"], [drug_exposure, procedure, device_exposure], start_window=event_starts_window(0, 30)
        )
    if cs.get("C") is not None:
        groups["C"] = make_multi_domain_criterion(
            cs["C"], [condition_occurrence, observation], start_window=event_starts_window(1, 365)
        )
    if cs.get("I") is not None and cs.get("F_VISIT") is not None:
        groups["F"] = make_f_criterion(cs["I"], cs["F_VISIT"])
    if cs.get("A") is not None:
        groups["A"] = make_exclusion_criterion(cs["A"])

    return groups


def _effective_combo(
    combo: tuple[str, ...] | None,
    default_labels: tuple[str, ...],
    present: set[str],
) -> tuple[str, ...]:
    if combo is None:
        return tuple(label for label in default_labels if label in present)
    return tuple(label for label in combo if label in present)


def build_template_expression(
    spec: TemplateSpec,
    *,
    concept_sets: list[ConceptSet],
    codeset_ids: dict[str, int],
    atomic: dict[str, object],
    exit_strategy: str = "chronic",
    expression_limit: str = "First",
    primary_limit: str = "First",
    era_days: int = 0,
) -> CohortExpression:
    """Build the full ``CohortExpression`` for a single template.

    This mirrors the Capr cohort produced by ``outcomePhenotypeTpl()`` and is
    used for Atlas export, SQL fallback, and parity testing against
    ``build_cohort()``.
    """
    if spec.name == "base_case":
        inclusion_rules: list[InclusionRule] = []
    else:
        present = {label for label, grp in atomic.items() if grp is not None}

        pre_combo = _effective_combo(spec.pre_combo, PRE_LABELS, present)
        post_combo = _effective_combo(spec.post_combo, POST_LABELS, present)

        rules: list[InclusionRule] = []
        if pre_combo:
            pre_group = combine_criteria([atomic[label] for label in pre_combo], spec.pre_op)
            if pre_group is not None:
                rules.append(
                    InclusionRule(
                        name="pre-index evidence (S/D within -30 to 0d)", expression=pre_group
                    )
                )
        if post_combo:
            post_group = combine_criteria([atomic[label] for label in post_combo], spec.post_op)
            if post_group is not None:
                rules.append(
                    InclusionRule(
                        name="post-index evidence (T/C/F within specified windows)",
                        expression=post_group,
                    )
                )
        if spec.exclude_a and "A" in atomic and atomic["A"] is not None:
            rules.append(
                InclusionRule(
                    name="no alternative diagnosis (A excluded -30 to +30d)",
                    expression=atomic["A"],
                )
            )
        inclusion_rules = rules

    return CohortExpression(
        title=f"[PheTpl] {spec.name}",
        concept_sets=concept_sets,
        primary_criteria=make_entry_criteria(codeset_ids["I"], primary_limit=primary_limit),
        expression_limit=ResultLimit(type=expression_limit),
        qualified_limit=ResultLimit(type="First"),
        inclusion_rules=inclusion_rules,
        end_strategy=make_end_strategy(exit_strategy),
        collapse_settings=make_collapse_settings(era_days),
    )


def build_all_expressions(
    *,
    concept_sets: list[ConceptSet],
    codeset_ids: dict[str, int],
    atomic: dict[str, object],
    exit_strategy: str = "chronic",
    expression_limit: str = "First",
    primary_limit: str = "First",
    era_days: int = 0,
    phenotype_label: str = "",
) -> dict[str, tuple[int, CohortExpression]]:
    """Build all 23 ``CohortExpression`` objects (base_case + tpl_1..22).

    Returns a dict mapping template name to ``(cohort_id, expression)`` where
    ``cohort_id`` is the ``cohort_definition_id`` used when writing results.
    """
    base = TemplateSpec(
        "base_case",
        template_number=None,
        pre_combo=(),
        post_combo=(),
        exclude_a=False,
    )
    specs: tuple[TemplateSpec, ...] = (base, *TEMPLATE_SPECS)

    out: dict[str, tuple[int, CohortExpression]] = {}
    for index, spec in enumerate(specs):
        expression = build_template_expression(
            spec,
            concept_sets=concept_sets,
            codeset_ids=codeset_ids,
            atomic=atomic,
            exit_strategy=exit_strategy,
            expression_limit=expression_limit,
            primary_limit=primary_limit,
            era_days=era_days,
        )
        expression.title = f"[PheTpl] {phenotype_label} tpl {spec.name}" if spec.name != "base_case" else (
            f"[PheTpl] {phenotype_label} tpl base_case"
        )
        out[spec.name] = (index, expression)
    return out
