"""pheno_tpl: efficient phenotyping-template cohorts on CircePy's Ibis executor."""

from .concept_sets import (
    ConceptSetSpec,
    concept_ids,
    cs,
    make_concept_set,
    remove_ids,
    resolve_concept_set_overlaps,
)
from .criteria import (
    combine_criteria,
    event_ends_window,
    event_starts_window,
    make_collapse_settings,
    make_end_strategy,
    make_entry_criteria,
    make_exclusion_criterion,
    make_f_criterion,
    make_multi_domain_criterion,
)
from .executor import BuiltFamily, TemplateFamilyExecutor
from .family import FamilySpec, ResolvedFamily, resolve_family
from .setops import combine_key_sets, intersect_all, intersect_keys, union_keys
from .templates import TEMPLATE_SPECS, TemplateSpec, build_all_expressions, build_atomic_groups

__all__ = [
    "TEMPLATE_SPECS",
    "BuiltFamily",
    "ConceptSetSpec",
    "FamilySpec",
    "ResolvedFamily",
    "TemplateFamilyExecutor",
    "TemplateSpec",
    "build_all_expressions",
    "build_atomic_groups",
    "combine_criteria",
    "combine_key_sets",
    "concept_ids",
    "cs",
    "event_ends_window",
    "event_starts_window",
    "intersect_all",
    "intersect_keys",
    "make_collapse_settings",
    "make_concept_set",
    "make_end_strategy",
    "make_entry_criteria",
    "make_exclusion_criterion",
    "make_f_criterion",
    "make_multi_domain_criterion",
    "remove_ids",
    "resolve_concept_set_overlaps",
    "resolve_family",
    "union_keys",
]
