"""Config-driven evaluation: pydantic models that load YAML/JSON and produce
CircePy models (``CohortExpression``, ``DemographicCriteria``, ``ConceptSet``).

Only types that CircePy does not already model are introduced here (the
template-family descriptor and the evaluation wiring); everything else reuses
CircePy base models.
"""

from __future__ import annotations

from pathlib import Path
from typing import Literal

import yaml
from circe.cohortdefinition import CohortExpression
from circe.vocabulary import ConceptSet
from pydantic import BaseModel, Field

from .cohorts import FamilySpec, cs
from .evaluation import evidence_expression, gold_standard_expression
from .evaluation.demographics import build_demographic_group
from .evaluation.population import domain_criteria

__all__ = [
    "ConceptSetConfig",
    "EvaluationConfig",
    "EvidenceEntry",
    "GoldStandardConfig",
    "TargetPopulationConfig",
    "UniverseConfig",
    "load_config",
]


class ConceptSetConfig(BaseModel):
    """Capr-style concept set: direct ids and/or descendant ids."""

    direct: list[int] = Field(default_factory=list)
    descendants: list[int] = Field(default_factory=list)
    name: str = ""

    def build(self) -> ConceptSet:
        return cs(direct=self.direct, descendants=self.descendants, name=self.name)


class TargetPopulationConfig(BaseModel):
    """Uniform non-temporal demographics (gender/race/ethnicity/age)."""

    gender: list[int] | None = None
    race: list[int] | None = None
    ethnicity: list[int] | None = None
    age: dict | None = None

    def build(self):
        return build_demographic_group(
            gender=self.gender,
            race=self.race,
            ethnicity=self.ethnicity,
            age=self.age,
        )


class EvidenceEntry(BaseModel):
    """One evidence source for the sensitive population."""

    codeset_id: int
    domains: list[str] = Field(default_factory=lambda: ["condition_occurrence", "observation"])


class UniverseConfig(BaseModel):
    """Evaluation universe (sensitive population or entry cohort)."""

    type: Literal["sensitive_population", "entry_cohort"] = "sensitive_population"
    evidence: list[EvidenceEntry] = Field(default_factory=lambda: [EvidenceEntry(codeset_id=1)])

    def build_population(self, concept_sets: list[ConceptSet]) -> CohortExpression:
        primary = []
        for entry in self.evidence:
            for domain in entry.domains:
                primary.append(domain_criteria(domain, entry.codeset_id))
        return evidence_expression(primary, concept_sets=concept_sets)


class GoldStandardConfig(BaseModel):
    """Gold-standard (xSpec) definition as a first/any-occurrence entry."""

    codeset_id: int
    domains: list[str] = Field(default_factory=lambda: ["condition_occurrence", "observation"])
    first: bool = True

    def build(self, concept_sets: list[ConceptSet]) -> CohortExpression:
        primary = []
        for domain in self.domains:
            criterion = domain_criteria(domain, self.codeset_id)
            if self.first:
                criterion = criterion.model_copy(update={"first": True})
            primary.append(criterion)
        return gold_standard_expression(primary, concept_sets=concept_sets, name="gold standard")


class EvaluationConfig(BaseModel):
    """Top-level evaluation configuration."""

    backend: str = "duckdb"
    duckdb_path: str | None = None

    phenotype_label: str = ""
    exit_strategy: str = "chronic"
    concept_sets: dict[str, ConceptSetConfig] = Field(default_factory=dict)

    target_population: TargetPopulationConfig = Field(default_factory=TargetPopulationConfig)
    universe: UniverseConfig = Field(default_factory=UniverseConfig)
    gold_standard: GoldStandardConfig | None = None

    def build_family_spec(self) -> FamilySpec:
        def get(key: str):
            cfg = self.concept_sets.get(key)
            return cfg.build() if cfg else None

        return FamilySpec(
            cs_I=get("cs_I"),
            cs_S=get("cs_S"),
            cs_D=get("cs_D"),
            cs_T=get("cs_T"),
            cs_C=get("cs_C"),
            cs_A=get("cs_A"),
            phenotype_label=self.phenotype_label,
            exit_strategy=self.exit_strategy,
        )


def load_config(path: str | Path) -> EvaluationConfig:
    """Load an evaluation config from a YAML or JSON file."""
    path = Path(path)
    text = path.read_text()
    if path.suffix.lower() == ".json":
        import json

        data = json.loads(text)
    else:
        data = yaml.safe_load(text)
    return EvaluationConfig.model_validate(data)
