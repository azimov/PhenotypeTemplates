"""Set algebra over ``(person_id, event_id)`` key relations.

All key sets are subsets of the index-event keys, so combining templates is pure
set algebra (union / intersection). ``intersection`` is expressed as an inner
join on the two key columns; it is exact because keys are unique per
``(person_id, event_id)``.
"""

from __future__ import annotations

from collections.abc import Sequence

PERSON_ID = "person_id"
EVENT_ID = "event_id"


def union_keys(tables: Sequence[object]) -> object:
    """Union of key relations (distinct)."""
    if not tables:
        raise ValueError("union_keys requires at least one table")
    current = tables[0]
    for table in tables[1:]:
        current = current.union(table, distinct=False)
    return current.distinct()


def intersect_keys(a: object, b: object) -> object:
    """Intersection of two key relations via inner join on both key columns."""
    b2 = b.select(
        b[PERSON_ID].name("_b_person_id"),
        b[EVENT_ID].name("_b_event_id"),
    )
    joined = a.join(
        b2,
        predicates=[a[PERSON_ID] == b2._b_person_id, a[EVENT_ID] == b2._b_event_id],
    )
    return joined.select(
        joined[PERSON_ID].name(PERSON_ID),
        joined[EVENT_ID].name(EVENT_ID),
    ).distinct()


def intersect_all(tables: Sequence[object]) -> object | None:
    """Fold :func:`intersect_keys` over a sequence; ``None`` if empty."""
    if not tables:
        return None
    current = tables[0]
    for table in tables[1:]:
        current = intersect_keys(current, table)
    return current


def combine_key_sets(
    key_sets: dict[str, object],
    combo: Sequence[str],
    op: str,
) -> object | None:
    """Combine a named subset of key sets by ``"any"`` (union) or ``"all"`` (intersection)."""
    tables = [
        key_sets[label] for label in combo if label in key_sets and key_sets[label] is not None
    ]
    if not tables:
        return None
    if len(tables) == 1:
        return tables[0]
    if op == "any":
        return union_keys(tables)
    if op == "all":
        return intersect_all(tables)
    raise ValueError(f"Unsupported set operator: {op!r}")
