"""Concept-set helpers that mirror the Capr ``cs()`` / ``descendants()`` builders.

``cs()`` returns a CircePy :class:`ConceptSet` directly, so concept sets can be
consumed by ``circe.cohortdefinition`` and the ``circe.execution`` layer without
a parallel spec type.
"""

from __future__ import annotations

from collections.abc import Iterable

from circe.vocabulary import Concept, ConceptSet, ConceptSetExpression, ConceptSetItem


def cs(
    direct: Iterable[int] = (),
    descendants: Iterable[int] = (),
    name: str = "",
    set_id: int = 0,
) -> ConceptSet:
    """Build a :class:`ConceptSet` (Capr ``cs()`` equivalent).

    ``direct`` -> items with ``include_descendants=False``; ``descendants`` ->
    items with ``include_descendants=True``. The ``set_id`` is a placeholder
    (re-assigned by :func:`resolve_family`); pass a stable id if you manage
    concept-set ids yourself.
    """
    items: list[ConceptSetItem] = []
    for concept_id in direct:
        items.append(
            ConceptSetItem(concept=Concept(concept_id=int(concept_id)), include_descendants=False)
        )
    for concept_id in descendants:
        items.append(
            ConceptSetItem(concept=Concept(concept_id=int(concept_id)), include_descendants=True)
        )
    return ConceptSet(
        id=int(set_id),
        name=name or None,
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


def resolve_concept_set_overlaps(
    cs_I: ConceptSet | None,
    cs_S: ConceptSet | None = None,
    cs_D: ConceptSet | None = None,
    cs_T: ConceptSet | None = None,
    cs_C: ConceptSet | None = None,
    cs_A: ConceptSet | None = None,
    warn_on_overlap: bool = True,
) -> dict[str, ConceptSet | None]:
    """Resolve overlapping concepts across category concept sets.

    Replicates the R precedence rules:

      1. ``I`` (disease of interest) wins over ``S``/``C``/``A``.
      2. ``A`` (alternative diagnosis) wins over ``S``/``C``.
      3. ``S`` and ``C`` are allowed to overlap (different time windows).

    Only condition/observation-domain sets (``I``, ``S``, ``C``, ``A``) are
    modified; ``D`` and ``T`` are passed through unchanged. Any set reduced to
    zero concepts becomes ``None``.
    """
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
