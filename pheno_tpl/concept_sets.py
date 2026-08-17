"""Concept-set helpers that mirror the Capr `cs()` / `descendants()` builders.

The Python objects produced here are CircePy `ConceptSet` models that can be
consumed directly by `circe.cohortdefinition` and the `circe.execution` layer.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from circe.vocabulary import Concept, ConceptSet, ConceptSetExpression, ConceptSetItem


@dataclass(frozen=True)
class ConceptSetSpec:
    """A Capr-style concept set specification.

    Mirrors `cs(direct_ids, descendants_ids, name = ...)`:

      * ``direct`` -> items with ``include_descendants=False``
      * ``descendants`` -> items with ``include_descendants=True``

    Concept-set *details* (CONCEPT_NAME etc.) are intentionally not required:
    CircePy resolves descendants at execution time against the vocabulary
    tables on the backend.
    """

    direct: tuple[int, ...] = ()
    descendants: tuple[int, ...] = ()
    name: str = ""


def cs(
    direct: Iterable[int] = (),
    descendants: Iterable[int] = (),
    name: str = "",
) -> ConceptSetSpec:
    """Build a :class:`ConceptSetSpec` (Capr `cs()` equivalent)."""
    return ConceptSetSpec(tuple(int(x) for x in direct), tuple(int(x) for x in descendants), name)


def make_concept_set(set_id: int, spec: ConceptSetSpec) -> ConceptSet:
    """Convert a :class:`ConceptSetSpec` into a CircePy :class:`ConceptSet`."""
    items: list[ConceptSetItem] = []
    for concept_id in spec.direct:
        items.append(
            ConceptSetItem(concept=Concept(concept_id=int(concept_id)), include_descendants=False)
        )
    for concept_id in spec.descendants:
        items.append(
            ConceptSetItem(concept=Concept(concept_id=int(concept_id)), include_descendants=True)
        )
    return ConceptSet(
        id=int(set_id),
        name=spec.name or None,
        expression=ConceptSetExpression(items=items),
    )


def concept_ids(cs_obj: ConceptSet | None) -> tuple[int, ...]:
    """Return the *listed* concept IDs of a concept set (not expanded descendants)."""
    if cs_obj is None or cs_obj.expression is None or not cs_obj.expression.items:
        return ()
    ids: list[int] = []
    for item in cs_obj.expression.items:
        if item is not None and item.concept is not None and item.concept.concept_id is not None:
            ids.append(int(item.concept.concept_id))
    return tuple(ids)


def remove_ids(
    cs_obj: ConceptSet | None,
    ids_to_remove: Iterable[int],
    label: str,
    warn_on_overlap: bool = True,
) -> ConceptSet | None:
    """Remove concept IDs from a concept set (R `resolveConceptSetOverlaps` equivalent)."""
    remove = {int(x) for x in ids_to_remove}
    if cs_obj is None or not remove:
        return cs_obj

    current = concept_ids(cs_obj)
    overlap = [c for c in current if c in remove]
    if not overlap:
        return cs_obj

    if warn_on_overlap:
        print(
            f"resolve_concept_set_overlaps: removed {len(overlap)} concept(s) from {label} "
            f"due to precedence: {overlap}"
        )

    keep = [
        item
        for item in cs_obj.expression.items
        if item.concept is None or item.concept.concept_id is None or int(item.concept.concept_id) not in remove
    ]
    if not keep:
        if warn_on_overlap:
            print(f"  -> {label} is now empty (set to None)")
        return None

    return cs_obj.model_copy(update={"expression": ConceptSetExpression(items=keep)})


def _as_concept_set(cs_obj: ConceptSet | ConceptSetSpec | None, *, label: str = "cs") -> ConceptSet | None:
    """Normalize a ``ConceptSet`` or ``ConceptSetSpec`` input to a ``ConceptSet``."""
    if cs_obj is None:
        return None
    if isinstance(cs_obj, ConceptSetSpec):
        return make_concept_set(-1, cs_obj)
    return cs_obj


def resolve_concept_set_overlaps(
    cs_I: ConceptSet | ConceptSetSpec | None,
    cs_S: ConceptSet | ConceptSetSpec | None = None,
    cs_D: ConceptSet | ConceptSetSpec | None = None,
    cs_T: ConceptSet | ConceptSetSpec | None = None,
    cs_C: ConceptSet | ConceptSetSpec | None = None,
    cs_A: ConceptSet | ConceptSetSpec | None = None,
    warn_on_overlap: bool = True,
) -> dict[str, ConceptSet | None]:
    """Resolve overlapping concepts across category concept sets.

    Accepts either :class:`ConceptSet` models or :class:`ConceptSetSpec`
    (Capr ``cs()``) inputs.

    Replicates the R precedence rules:

      1. ``I`` (disease of interest) wins over ``S``/``C``/``A``.
      2. ``A`` (alternative diagnosis) wins over ``S``/``C``.
      3. ``S`` and ``C`` are allowed to overlap (different time windows).

    Only condition/observation-domain sets (``I``, ``S``, ``C``, ``A``) are
    modified; ``D`` and ``T`` are passed through unchanged. Any set reduced to
    zero concepts becomes ``None``.
    """
    cs_I = _as_concept_set(cs_I, label="cs_I")
    cs_S = _as_concept_set(cs_S, label="cs_S")
    cs_D = _as_concept_set(cs_D, label="cs_D")
    cs_T = _as_concept_set(cs_T, label="cs_T")
    cs_C = _as_concept_set(cs_C, label="cs_C")
    cs_A = _as_concept_set(cs_A, label="cs_A")
    if cs_I is None:
        raise ValueError("cs_I (disease of interest) is required")

    ids_I = concept_ids(cs_I)

    cs_S = remove_ids(cs_S, ids_I, "cs_S (symptoms)", warn_on_overlap)
    cs_C = remove_ids(cs_C, ids_I, "cs_C (complications)", warn_on_overlap)
    cs_A = remove_ids(cs_A, ids_I, "cs_A (alternative diagnoses)", warn_on_overlap)

    ids_A = concept_ids(cs_A)
    cs_S = remove_ids(cs_S, ids_A, "cs_S (symptoms, A-precedence)", warn_on_overlap)
    cs_C = remove_ids(cs_C, ids_A, "cs_C (complications, A-precedence)", warn_on_overlap)

    return {
        "cs_I": cs_I,
        "cs_S": cs_S,
        "cs_D": cs_D,
        "cs_T": cs_T,
        "cs_C": cs_C,
        "cs_A": cs_A,
    }
