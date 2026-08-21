"""High-level wiring: concept sets -> resolved family -> executor inputs."""

from __future__ import annotations

from dataclasses import dataclass

from circe.cohortdefinition import CohortExpression
from circe.vocabulary import ConceptSet

from .concept_sets import cs, resolve_concept_set_overlaps
from .templates import (
    CONCEPT_SET_IDS,
    TEMPLATE_SPECS,
    TemplateSpec,
    build_all_expressions,
    build_atomic_groups,
)


@dataclass
class FamilySpec:
    """Input concept sets for a phenotype family (built via :func:`cs`)."""

    cs_I: ConceptSet
    cs_S: ConceptSet | None = None
    cs_D: ConceptSet | None = None
    cs_T: ConceptSet | None = None
    cs_C: ConceptSet | None = None
    cs_A: ConceptSet | None = None
    phenotype_label: str = ""
    exit_strategy: str = "chronic"
    expression_limit: str = "First"
    primary_limit: str = "First"
    era_days: int = 0
    warn_on_overlap: bool = True


@dataclass
class ResolvedFamily:
    """Resolved concept sets + atomic groups + per-template expressions."""

    concept_sets: list[ConceptSet]
    codeset_ids: dict[str, int]
    atomic: dict[str, object]
    specs: tuple[TemplateSpec, ...]
    expressions: dict[str, tuple[int, CohortExpression]]
    cohort_ids: dict[str, int]
    exit_strategy: str = "chronic"
    expression_limit: str = "First"
    primary_limit: str = "First"
    era_days: int = 0


def _assign_id(cs_obj: ConceptSet | None, label: str) -> ConceptSet | None:
    if cs_obj is None:
        return None
    return cs_obj.model_copy(update={"id": CONCEPT_SET_IDS[label]})


def resolve_family(spec: FamilySpec) -> ResolvedFamily:
    """Resolve concept-set overlaps and build the shared family artifacts."""
    cs_I = _assign_id(spec.cs_I, "I")
    cs_S = _assign_id(spec.cs_S, "S")
    cs_D = _assign_id(spec.cs_D, "D")
    cs_T = _assign_id(spec.cs_T, "T")
    cs_C = _assign_id(spec.cs_C, "C")
    cs_A = _assign_id(spec.cs_A, "A")

    resolved = resolve_concept_set_overlaps(
        cs_I,
        cs_S,
        cs_D,
        cs_T,
        cs_C,
        cs_A,
        warn_on_overlap=spec.warn_on_overlap,
    )

    # F (follow-up) uses the ER/Inpatient visit concept set, hard-coded like R.
    cs_F_visit = cs(
        descendants=(9201, 9203, 262),
        name="ER/Inpatient visit types (hard-coded)",
        set_id=CONCEPT_SET_IDS["F_VISIT"],
    )

    concept_sets = [
        c
        for c in (
            resolved["cs_I"],
            resolved["cs_S"],
            resolved["cs_D"],
            resolved["cs_T"],
            resolved["cs_C"],
            resolved["cs_A"],
            cs_F_visit,
        )
        if c is not None
    ]

    codeset_ids: dict[str, int] = {
        "I": CONCEPT_SET_IDS["I"],
        "S": CONCEPT_SET_IDS["S"] if resolved["cs_S"] is not None else None,
        "D": CONCEPT_SET_IDS["D"] if resolved["cs_D"] is not None else None,
        "T": CONCEPT_SET_IDS["T"] if resolved["cs_T"] is not None else None,
        "C": CONCEPT_SET_IDS["C"] if resolved["cs_C"] is not None else None,
        "A": CONCEPT_SET_IDS["A"] if resolved["cs_A"] is not None else None,
        "F_VISIT": CONCEPT_SET_IDS["F_VISIT"],
    }

    atomic = build_atomic_groups(codeset_ids)

    expressions = build_all_expressions(
        concept_sets=concept_sets,
        codeset_ids=codeset_ids,
        atomic=atomic,
        exit_strategy=spec.exit_strategy,
        expression_limit=spec.expression_limit,
        primary_limit=spec.primary_limit,
        era_days=spec.era_days,
        phenotype_label=spec.phenotype_label,
    )

    cohort_ids = {name: cid for name, (cid, _expr) in expressions.items()}
    base_spec = TemplateSpec("base_case", template_number=None, pre_combo=(), post_combo=())
    spec_objects = (base_spec, *TEMPLATE_SPECS)

    return ResolvedFamily(
        concept_sets=concept_sets,
        codeset_ids=codeset_ids,
        atomic=atomic,
        specs=spec_objects,
        expressions=expressions,
        cohort_ids=cohort_ids,
        exit_strategy=spec.exit_strategy,
        expression_limit=spec.expression_limit,
        primary_limit=spec.primary_limit,
        era_days=spec.era_days,
    )
