# circepy-phenotypes

Efficient, Python-native generation of the **phevaluator-style phenotyping
template family** — a `base_case` cohort plus 22 specificity templates (as
originally defined in `r_template.R`) — built on **CircePy's Ibis execution
layer** (`circe.execution`), plus a **label-based evaluation** layer that scores
each candidate cohort against a gold standard with proxy
sensitivity/specificity/PPV/NPV.

The key idea for generation: instead of defining and executing 23 near-identical
cohort definitions (each re-running the same expensive OMOP domain scans),
compute the **index event cohort once**, compute each **inclusion population
once**, and derive all 23 templates as **trivial set algebra** over those shared
results. The decomposition is *exact*: every template's output is identical to
running the full per-template cohort, as enforced by parity tests.

---

## Background: the problem being solved

`r_template.R` builds 23 Capr cohort definitions for a disease of interest:

| Cohort | Definition |
|---|---|
| `base_case` | First-ever diagnosis of the disease (index event `I`), no further restriction — the **sensitive** case |
| `tpl_1` … `tpl_22` | The base case restricted by different Boolean combinations of supporting clinical evidence |

Evidence is grouped into categories, each querying multiple OMOP domains:

| Category | Meaning | Time window | Domains |
|---|---|---|---|
| `I` | disease of interest (index event) | — | condition, observation |
| `S` | symptoms | −30 … 0 days | condition, observation |
| `D` | diagnostic tests | −30 … 0 days | measurement, procedure, device |
| `T` | treatments | 0 … +30 days | drug, procedure, device |
| `C` | complications | +1 … +365 days | condition, observation |
| `F` | follow-up care | second `I` code +1…+365, or ER/Inpatient visit overlapping index | condition, observation, visit |
| `A` | alternative diagnoses (**excluded**) | −30 … +30 days | condition, observation |

The 22 templates are just different combinations of these populations, e.g.
`(S|D)`, `(T|C|F)^!A`, `(S^D)^(T^C^F)`, etc.

**Inefficiency:** every template re-declares — and at execution time re-computes —
the identical index event and the identical `S/D/T/C/F/A` populations. On a real
CDM that means the same domain-table scans are repeated ~23×.

## The approach

1. **Index events once** — build the primary event relation (`person_id`,
   `event_id`, `start_date`, …) for the first-ever `I` diagnosis.
2. **Inclusion populations once** — evaluate each atomic criterion group
   (`S`, `D`, `T`, `C`, `F`, `A`) against the index events. Each produces a
   `(person_id, event_id)` **key set**. A criteria-group evaluation is a pure
   function of the index events, so this is exact.
3. **Templates as set algebra** — combine key sets with union/intersection
   (`withAny` → union, `withAll` → intersection, `!A` → intersection with the
   "no-A" key set), join back to the index events, then apply the standard
   end-strategy / collapse pipeline.
4. **One write** — project all 23 results to OHDSI cohort-table shape
   (`cohort_definition_id, subject_id, cohort_start_date, cohort_end_date`),
   union them, and write to a single cohort table with **one**
   `CREATE TABLE … OVERWRITE` (the efficient Databricks path).

## Evaluation

Beyond generation, the package scores each candidate cohort against a
gold-standard label set. All evaluation components are CircePy
`CohortExpression`s whose executed person sets are intersected with the same
non-temporal `DemographicCriteria` at metric time:

| Component | Meaning |
|---|---|
| Sensitive population `P` | persons with **any evidence** of the disease (may be widened across domains) |
| Sensitive entry cohort `U₀` | `base_case` (first-ever `I`) |
| Gold standard `G` | an expert "xSpec" definition |
| Candidate `C` | a template (or any cohort expression) |

Metrics (pure, label-based):

```
TP = |C' ∩ G'|    FP = |C' \ G'|    FN = |G' \ C'|    TN = |U' \ (C' ∪ G')|
Sensitivity = TP/(TP+FN)   Specificity = TN/(TN+FP)
PPV = TP/(TP+FP)           NPV = TN/(TN+FN)
```

The universe `U` defaults to `P'` (demographics-filtered sensitive population)
or `U₀'`. Candidates are ranked by Youden's J, F1, or any metric.

## The 22 scenario templates

```
 1: (S|D)                  9: (S|D) ^ (T|C|F)             15: (S^D) ^ (T^F)
 2: (T|C|F)               10: (S|D) ^ (T|C|F) ^ !A       16: (S^D) ^ (F^C)
 3: F                     11: (S^D) ^ (T|C|F)            17: (S^D) ^ (T^C)
 4: T                     12: (S^D) ^ (T|C|F) ^ !A       18: (S^D) ^ (T^F) ^ !A
 5: !A                    13: (S|D) ^ (T^C^F)            19: (S^D) ^ (F^C) ^ !A
 6: D                     14: (S|D) ^ (T^C^F) ^ !A       20: (S^D) ^ (T^C) ^ !A
 7: (S|D) ^ !A                                           21: (S^D) ^ (T^C^F)
 8: (T|C|F) ^ !A                                         22: (S^D) ^ (T^C^F) ^ !A
```

## Project layout

```
pheno_template/
├── r_template.R                  # original R/Capr reference (unchanged)
├── pyproject.toml                # name=circepy-phenotypes; src layout; console scripts
├── src/circepy_phenotypes/
│   ├── __init__.py
│   ├── config.py                 # pydantic config -> CircePy models
│   ├── backend.py                # connect_backend(): DuckDB / Databricks
│   ├── cli.py                    # `circepy-phenotypes` / `cpt`
│   ├── py.typed
│   ├── cohorts/
│   │   ├── concept_sets.py       # cs() -> ConceptSet + overlap resolution
│   │   ├── criteria.py           # criterion builders -> CircePy models
│   │   ├── templates.py          # 23-template matrix -> CohortExpression
│   │   ├── family.py             # FamilySpec -> ResolvedFamily
│   │   ├── setops.py             # set algebra over (person_id, event_id) keys
│   │   └── executor/
│   │       ├── __init__.py       # TemplateFamilyExecutor (fast path)
│   │       └── _engine.py        # THE ONLY place importing circe.execution internals
│   └── evaluation/
│       ├── population.py         # any-evidence sensitive-population expression
│       ├── demographics.py       # uniform DemographicCriteria (∩ T)
│       ├── cohorts.py            # gold-standard (xSpec) expression builder
│       ├── metrics.py            # label-based sens/spec/ppv/npv (pure)
│       ├── selection.py          # rank (Youden's J, F1, ...)
│       └── report.py             # tidy metrics table + optional plot
├── examples/
└── tests/
```

## Install

Requires the `develop` branch of `OHDSI/CircePy` (which ships
`circe.execution`). The installed copy must be the pinned commit this package
was developed against, because the fast path imports a few internal executor
functions (isolated behind `cohorts/executor/_engine.py`).

```bash
# CircePy (in its own checkout):
uv sync --extra ibis-duckdb --extra dev      # or: pip install -e ".[ibis-duckdb]"

# this package:
pip install -e .
pip install -e ".[databricks]"              # optional, for Databricks
pip install -e ".[report]"                  # optional, pandas + matplotlib
```

## Quick start: generation

```python
from circepy_phenotypes import FamilySpec, TemplateFamilyExecutor, connect_backend, cs, resolve_family

spec = FamilySpec(
    cs_I=cs((313217, 605092), name="Atrial fibrillation"),
    cs_S=cs(descendants=(27674, 79908, 259153), name="AFib symptoms"),
    cs_D=cs(descendants=(4759705, 759706), name="AFib diagnostics"),
    cs_T=cs(descendants=(902427, 914335), name="AFib treatments"),
    cs_C=cs(descendants=(135360, 197320), name="AFib complications"),
    cs_A=cs(descendants=(313217, 317302), name="Alternative diagnoses"),
    phenotype_label="Atrial Fibrillation",
    exit_strategy="chronic",       # "chronic" | "acute14d" | "acute365d"
)

resolved = resolve_family(spec)

conn = connect_backend("duckdb")            # or connect_backend("databricks")
executor = TemplateFamilyExecutor(
    conn.backend,
    cdm_schema=conn.cdm_schema,
    results_schema=conn.results_schema,
    vocabulary_schema=conn.vocabulary_schema,
)
relations = executor.run_resolved(resolved, materialize_intermediates=True)
# -> {name: ibis relation} for base_case, tpl_1, ..., tpl_22

executor.write_cohort_table(
    relations, cohort_ids=resolved.cohort_ids, cohort_table="phe_tpl_cohort"
)
```

## Quick start: evaluation

```python
from circepy_phenotypes import (
    connect_backend, evaluate, evidence_expression,
    build_demographic_group, resolve_family, cs, FamilySpec,
)

resolved = resolve_family(FamilySpec(cs_I=cs((313217,), name="AFib"), phenotype_label="AFib"))
conn = connect_backend("duckdb")

# Sensitive population: any evidence of the disease (condition/observation),
# optionally widened across domains.
population = evidence_expression(
    [("condition_occurrence", 1), ("observation", 1)],
    concept_sets=resolved.concept_sets,
)

# Gold standard = the sensitive entry cohort (base_case), or an xSpec expression.
gold = resolved.expressions["base_case"][1]

# Uniform non-temporal demographics, e.g. males only.
male = build_demographic_group(gender=[8507])

result = evaluate(
    conn,
    family=resolved,
    population_expression=population,
    gold_standard=gold,
    demographic_group=male,
    universe="sensitive_population",   # or "entry_cohort"
)

for name, metrics in result.metrics.items():
    print(name, metrics.sensitivity, metrics.specificity, metrics.ppv, metrics.npv)
```

## CLI

```bash
# Generate the 23-template family into a single cohort table
cpt run --config config.yaml

# Evaluate candidate cohorts against a gold standard
cpt evaluate --config config.yaml
cpt evaluate --config config.yaml --csv metrics.csv --plot sens_spec.png
```

A minimal `config.yaml`:

```yaml
backend: duckdb                       # or databricks
phenotype_label: "Atrial Fibrillation"
concept_sets:
  cs_I: { direct: [313217] }
  cs_S: { descendants: [27674] }
target_population:                    # uniform DemographicCriteria
  gender: [8507]
universe:
  type: sensitive_population          # or entry_cohort
  evidence:
    - codeset_id: 1
      domains: [condition_occurrence, observation]
gold_standard:
  codeset_id: 1
  domains: [condition_occurrence, observation]
  first: true
```

## Databricks notes

- `TemplateFamilyExecutor` applies the Databricks post-connect workaround
  (`circe.execution.databricks_compat`) automatically.
- `cdm_schema` / `results_schema` should be the values the Databricks ibis
  backend expects for `database=`/`catalog.schema` access; pass `None` to use
  the connection default.
- Databricks has **no transactional delete+insert replace**, so the executor
  deliberately writes the whole family with one `CREATE TABLE … OVERWRITE`
  rather than per-cohort read-modify-write.
- Intermediate materialization (`materialize_intermediates=True`, recommended
  for Databricks) guarantees each population is computed once, and keeps the 23
  template queries cheap joins over scratch tables.
- Databricks config reads `pheno_tpl_db_config.yaml` (copy the `.example`) or
  env vars: `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DATABRICKS_TOKEN`,
  `DATABRICKS_CDM_SCHEMA`, `DATABRICKS_RESULTS_SCHEMA`.

## Examples

```bash
python examples/afib_eunomia.py          # AFib family on Eunomia (DuckDB)
python examples/run_phenotype.py         # templating on DuckDB/Databricks
```

## Tests

```bash
python -m pytest tests/                  # parity + structure + overlaps + evaluation
PHENO_TPL_EUNOMIA=1 python -m pytest tests/test_eunomia_parity.py
```

- `test_parity.py` — decomposed executor == per-template `build_cohort()`.
- `test_structure.py` — Capr→CircePy mapping assertions.
- `test_overlaps.py` — overlap-resolution rules.
- `test_metrics.py` — pure confusion-matrix / metric / ranking tests.
- `test_evaluation.py` — integration: population, demographics, invariants.
- `test_eunomia_parity.py` — opt-in (slow) parity on the real Eunomia CDM.

On the GiBleed Eunomia data, the reference path (23 × `build_cohort`) takes
~45 s while the materialized shared-execution path takes ~4 s for the same
result.

## Caveats & limitations

- **Internal CircePy API coupling.** The fast path imports non-public
  `circe.execution` functions, isolated behind `cohorts/executor/_engine.py`.
  Pin the CircePy commit you develop against; when the public execution facade
  lands (CircePy > 0.3.0), reimplement `_engine.py` against it.
- **Vocabulary tables required.** Concept-set descendant expansion reads
  `concept`, `concept_ancestor`, and `concept_relationship` on the backend.
- **Branch note.** The `circe.execution` layer is on the `develop` branch of
  `OHDSI/CircePy`.
- The 22-template matrix, windows, and exit strategies mirror `r_template.R`
  exactly; changing the template matrix is a one-line change in
  `cohorts/templates.py`.
