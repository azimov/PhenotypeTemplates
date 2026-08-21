"""Efficient template-family executor built on CircePy's Ibis execution layer.

The core idea (mirroring the plan):

  * compute the **index event cohort once** (primary events),
  * compute each **inclusion population once** (``S``, ``D``, ``T``, ``C``,
    ``F``, ``A`` -> ``(person_id, event_id)`` key sets),
  * then produce every template as **trivial set algebra** (union/intersection)
    over those key sets, followed by the standard end-strategy / collapse
    pipeline.

This avoids re-running the expensive OMOP domain scans once per template.

All CircePy execution internals are imported through :mod:`._engine` (the
adapter), so a future CircePy public API can be adopted without touching this
module.
"""

from __future__ import annotations

from circe.cohortdefinition import CohortExpression
from circe.cohortdefinition.core import ResultLimit
from circe.vocabulary import ConceptSet

from ..criteria import make_entry_criteria
from ..setops import combine_key_sets, intersect_all
from ..templates import POST_LABELS, PRE_LABELS, TemplateSpec, _effective_combo
from ._engine import (
    CohortPlan,
    PrimaryEventInput,
    _evaluate_group,
    apply_end_strategy,
    apply_result_limit,
    attach_observation_period,
    build_primary_events,
    collapse_events,
    create_table,
    lower_criterion,
    make_execution_context,
    maybe_apply_databricks_post_connect_workaround,
    normalize_cohort,
    normalize_criteria_group,
    normalize_end_strategy,
    project_to_ohdsi_cohort_table,
    read_table,
)

PERSON_ID = "person_id"
EVENT_ID = "event_id"


class BuiltFamily:
    """Shared execution artifacts: index events + per-category key sets."""

    def __init__(
        self,
        *,
        index_events,
        key_sets: dict[str, object],
        ctx,
        expression_limit: str,
    ):
        self.index_events = index_events
        self.key_sets = key_sets
        self.ctx = ctx
        self.expression_limit = expression_limit


class TemplateFamilyExecutor:
    """Execute a template family with shared index events and key sets."""

    def __init__(
        self,
        backend,
        cdm_schema: str,
        results_schema: str | None = None,
        vocabulary_schema: str | None = None,
        intermediate_prefix: str = "_phe_tpl_",
    ):
        maybe_apply_databricks_post_connect_workaround(backend)
        self.backend = backend
        self.cdm_schema = cdm_schema
        self.results_schema = results_schema
        self.vocabulary_schema = vocabulary_schema
        self.intermediate_prefix = intermediate_prefix

    # ------------------------------------------------------------------
    # Build shared artifacts
    # ------------------------------------------------------------------

    def build(
        self,
        *,
        concept_sets: list[ConceptSet],
        index_codeset_id: int,
        atomic: dict[str, object],
        end_strategy=None,
        collapse_settings=None,
        expression_limit: str = "First",
        primary_limit: str = "First",
        materialize_intermediates: bool = False,
    ) -> BuiltFamily:
        """Build the index events and per-category key sets once."""
        expression = CohortExpression(
            title="template-family (shared artifacts)",
            concept_sets=concept_sets,
            primary_criteria=make_entry_criteria(index_codeset_id, primary_limit=primary_limit),
            expression_limit=ResultLimit(type=expression_limit),
            qualified_limit=ResultLimit(type="First"),
            end_strategy=end_strategy,
            collapse_settings=collapse_settings,
        )
        normalized = normalize_cohort(expression)
        ctx = make_execution_context(
            backend=self.backend,
            cdm_schema=self.cdm_schema,
            results_schema=self.results_schema,
            vocabulary_schema=self.vocabulary_schema,
            concept_sets=normalized.concept_sets,
        )

        plan = CohortPlan(
            primary_event_plans=tuple(
                PrimaryEventInput(
                    event_plan=lower_criterion(criterion, criterion_index=index),
                    correlated_criteria=criterion.correlated_criteria,
                )
                for index, criterion in enumerate(normalized.primary.criteria)
            ),
            observation_window=normalized.primary.observation_window,
            primary_limit_type=normalized.primary.primary_limit_type,
            qualified_limit_type=normalized.result_limits.qualified_limit_type,
            expression_limit_type=normalized.result_limits.expression_limit_type,
        )

        index_events = build_primary_events(plan, ctx)
        index_with_obs = attach_observation_period(index_events, ctx)

        key_sets: dict[str, object] = {}
        for label, group in atomic.items():
            if group is None:
                key_sets[label] = None
                continue
            normalized_group = normalize_criteria_group(group)
            key_sets[label] = _evaluate_group(index_with_obs, normalized_group, ctx)

        if materialize_intermediates:
            index_events = self._materialize(index_events, "index")
            key_sets = {
                label: (self._materialize(keys, f"keys_{label}") if keys is not None else None)
                for label, keys in key_sets.items()
            }

        return BuiltFamily(
            index_events=index_events,
            key_sets=key_sets,
            ctx=ctx,
            expression_limit=expression_limit,
        )

    def _materialize(self, relation, name: str):
        table_name = f"{self.intermediate_prefix}{name}"
        create_table(
            self.backend,
            table_name=table_name,
            schema=self.results_schema,
            obj=relation,
            overwrite=True,
        )
        return read_table(self.backend, table_name=table_name, schema=self.results_schema)

    # ------------------------------------------------------------------
    # Per-template combination
    # ------------------------------------------------------------------

    def template_keys(self, family: BuiltFamily, spec: TemplateSpec):
        """Return the included ``(person_id, event_id)`` key set for a template.

        ``None`` means no inclusion constraint (the full index-event set).
        """
        present = {label for label, keys in family.key_sets.items() if keys is not None}
        pre_combo = _effective_combo(spec.pre_combo, PRE_LABELS, present)
        post_combo = _effective_combo(spec.post_combo, POST_LABELS, present)

        pre = combine_key_sets(family.key_sets, pre_combo, spec.pre_op)
        post = combine_key_sets(family.key_sets, post_combo, spec.post_op)

        constraints = [c for c in (pre, post) if c is not None]
        if spec.exclude_a and family.key_sets.get("A") is not None:
            constraints.append(family.key_sets["A"])

        return intersect_all(constraints)

    def template_relation(
        self,
        family: BuiltFamily,
        spec: TemplateSpec,
        *,
        end_strategy=None,
        collapse_settings=None,
    ):
        """Produce the final cohort rows (index events + end strategy + collapse)."""
        included = self.template_keys(family, spec)

        rows = family.index_events
        if included is not None:
            keys2 = included.select(
                included[PERSON_ID].name("_k_person_id"),
                included[EVENT_ID].name("_k_event_id"),
            )
            joined = rows.join(
                keys2,
                predicates=[
                    (rows[PERSON_ID] == keys2._k_person_id) & (rows[EVENT_ID] == keys2._k_event_id)
                ],
            )
            rows = joined.select(*[joined[c] for c in rows.columns])

        rows = apply_result_limit(rows, family.expression_limit)
        rows = apply_end_strategy(rows, end_strategy, family.ctx)
        return collapse_events(rows, collapse_settings, None)

    # ------------------------------------------------------------------
    # Full pipeline
    # ------------------------------------------------------------------

    def run(
        self,
        *,
        concept_sets: list[ConceptSet],
        index_codeset_id: int,
        atomic: dict[str, object],
        specs: tuple[TemplateSpec, ...],
        end_strategy=None,
        collapse_settings=None,
        expression_limit: str = "First",
        primary_limit: str = "First",
        materialize_intermediates: bool = False,
    ) -> dict[str, object]:
        """Run all templates and return ``{template_name: rows_relation}``."""
        family = self.build(
            concept_sets=concept_sets,
            index_codeset_id=index_codeset_id,
            atomic=atomic,
            end_strategy=end_strategy,
            collapse_settings=collapse_settings,
            expression_limit=expression_limit,
            primary_limit=primary_limit,
            materialize_intermediates=materialize_intermediates,
        )
        results: dict[str, object] = {}
        normalized_end_strategy = normalize_end_strategy(end_strategy)
        for spec in specs:
            results[spec.name] = self.template_relation(
                family,
                spec,
                end_strategy=normalized_end_strategy,
                collapse_settings=collapse_settings,
            )
        return results

    def build_resolved(self, resolved, *, materialize_intermediates: bool = False):
        """Build the shared artifacts for a :class:`ResolvedFamily`.

        Returns a :class:`BuiltFamily` (index events + per-category key sets)
        without producing the per-template cohort rows.
        """
        from ..criteria import make_collapse_settings, make_end_strategy

        return self.build(
            concept_sets=resolved.concept_sets,
            index_codeset_id=resolved.codeset_ids["I"],
            atomic=resolved.atomic,
            end_strategy=make_end_strategy(resolved.exit_strategy),
            collapse_settings=make_collapse_settings(resolved.era_days),
            expression_limit=resolved.expression_limit,
            primary_limit=resolved.primary_limit,
            materialize_intermediates=materialize_intermediates,
        )

    def run_resolved(self, resolved, *, materialize_intermediates: bool = False):
        """Run a :class:`~circepy_phenotypes.cohorts.family.ResolvedFamily` end to end.

        Returns ``{template_name: rows_relation}`` using the family's shared
        concept sets, atomic groups, end strategy, and collapse settings.
        """
        from ..criteria import make_collapse_settings, make_end_strategy

        family = self.build_resolved(resolved, materialize_intermediates=materialize_intermediates)
        normalized_end_strategy = normalize_end_strategy(make_end_strategy(resolved.exit_strategy))
        collapse_settings = make_collapse_settings(resolved.era_days)
        return {
            spec.name: self.template_relation(
                family,
                spec,
                end_strategy=normalized_end_strategy,
                collapse_settings=collapse_settings,
            )
            for spec in resolved.specs
        }

    # ------------------------------------------------------------------
    # Single OHDSI cohort table write
    # ------------------------------------------------------------------

    def write_cohort_table(
        self,
        relations: dict[str, object],
        *,
        cohort_ids: dict[str, int],
        cohort_table: str,
        if_exists: str = "replace",
    ) -> None:
        """Project each template to OHDSI cohort-table shape and write once.

        All templates are combined into a single lazy relation and written with
        one ``create_table`` (``overwrite``) call — the efficient path for
        Databricks (no transactional delete+insert replace).
        """
        combined = None
        for name, relation in relations.items():
            projected = project_to_ohdsi_cohort_table(relation, cohort_id=cohort_ids[name])
            if combined is None:
                combined = projected
            else:
                combined = combined.union(projected, distinct=False)

        create_table(
            self.backend,
            table_name=cohort_table,
            schema=self.results_schema,
            obj=combined,
            overwrite=(if_exists == "replace"),
        )
