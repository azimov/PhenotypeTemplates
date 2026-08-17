# pheno_tpl

Efficient, Python-native generation of the **phevaluator-style phenotyping
template family** — a `base_case` cohort plus 22 specificity templates (as
originally defined in `r_template.R`) — built on **CircePy's Ibis execution
layer** (`circe.execution`, the `develop` branch of `OHDSI/CircePy`).

The key idea: instead of defining and executing 23 near-identical cohort
definitions (each re-running the same expensive OMOP domain scans), compute the
**index event cohort once**, compute each **inclusion population once**, and
derive all 23 templates as **trivial set algebra** over those shared results.
The decomposition is *exact*: every template's output is identical to running
the full per-template cohort, as enforced by parity tests.

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
`(S|D)`, `(T|C|F)^!A`, `(S^D)^(T^C^F)`, etc. (full list below).

**Inefficiency:** every template re-declares — and at execution time re-computes —
the identical index event and the identical `S/D/T/C/F/A` populations. On a real
CDM that means the same domain-table scans are repeated ~23×.

## The approach

1. **Index events once** — build the primary event relation (`person_id`,
   `event_id`, `start_date`, …) for the first-ever `I` diagnosis, via
   `circe.execution.engine.primary.build_primary_events`.
2. **Inclusion populations once** — evaluate each atomic criterion group
   (`S`, `D`, `T`, `C`, `F`, `A`) against the index events via
   `circe.execution.engine.groups._evaluate_group`. Each produces a
   `(person_id, event_id)` **key set** — the index events that match that
   population. A criteria-group evaluation is a pure function of the index
   events, so this is exact.
3. **Templates as set algebra** — combine key sets with union/intersection
   (`withAny` → union, `withAll` → intersection, `!A` → intersection with the
   "no-A" key set), join back to the index events, then apply the standard
   end-strategy / collapse pipeline (`apply_result_limit`,
   `apply_end_strategy`, `collapse_events`).
4. **One write** — project all 23 results to OHDSI cohort-table shape
   (`cohort_definition_id, subject_id, cohort_start_date, cohort_end_date`),
   union them, and write to a single cohort table with **one**
   `CREATE TABLE … OVERWRITE` (the efficient Databricks path).

With intermediate materialization, the shared artifacts are persisted to
scratch tables so each expensive scan runs exactly once regardless of the query
optimizer's common-subexpression handling.

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
├── pyproject.toml
├── pheno_tpl/
│   ├── __init__.py
│   ├── concept_sets.py           # Capr cs()/descendants() + overlap resolution
│   ├── criteria.py               # criterion builders -> CircePy models
│   ├── templates.py              # TemplateSpecs + full CohortExpression builder
│   ├── family.py                 # wires specs -> resolved family
│   ├── setops.py                 # set algebra over (person_id, event_id) keys
│   └── executor.py               # TemplateFamilyExecutor (the fast path)
├── examples/
│   └── afib_eunomia.py           # full AFib family on the Eunomia CDM
└── tests/
    ├── conftest.py               # deterministic in-memory DuckDB CDM fixture
    ├── test_parity.py            # fast path == per-template build_cohort
    ├── test_overlaps.py          # overlap-resolution rules
    ├── test_structure.py         # Capr->CircePy mapping assertions
    └── test_eunomia_parity.py    # opt-in, real-CDM parity (slow)
```

## Modules

| Module | Purpose |
|---|---|
| `concept_sets.py` | `cs()`/`descendants()` builder producing `ConceptSet` models, plus `resolve_concept_set_overlaps()` replicating the R precedence rules (`I` beats `S/C/A`, `A` beats `S/C`, `S↔C` overlap allowed, `D/T` untouched) |
| `criteria.py` | Builders for the index entry, multi-domain criterion groups, the `F` follow-up group, the `A` exclusion group, windows, end strategies and collapse settings — emitting CircePy models with 1:1 Capr semantics |
| `templates.py` | The 23 `TemplateSpec`s and `build_template_expression()` producing a full, standalone `CohortExpression` per template |
| `family.py` | `FamilySpec` (input concept sets) → `ResolvedFamily` (resolved concept sets, `codeset_ids`, atomic groups, per-template expressions, `cohort_ids`) |
| `setops.py` | `union_keys` / `intersect_keys` / `combine_key_sets` over key relations |
| `executor.py` | `TemplateFamilyExecutor` — shared execution, intermediate materialization, single cohort-table write |

## Install

Requires the `develop` branch of `OHDSI/CircePy` (which ships
`circe.execution`). The installed copy must be the pinned commit this package
was developed against, because the fast path imports a few internal executor
functions (see *Caveats*).

```bash
# CircePy (in its own checkout):
uv sync --extra ibis-duckdb --extra dev      # or: pip install -e ".[ibis-duckdb]"

# this package:
pip install -e .
pip install -e ".[databricks]"              # optional, for Databricks
```

## Quick start

```python
import ibis
from pheno_tpl import FamilySpec, TemplateFamilyExecutor, cs, resolve_family

# 1. Concept sets (Capr-style; descendants expand against the backend vocabulary)
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

# 2. Resolve overlaps, build concept sets, atomic groups and expressions
resolved = resolve_family(spec)

# 3. Execute: index + populations computed once; 23 templates as set algebra
backend = ibis.duckdb.connect("eunomia.duckdb")   # or ibis.databricks.connect(...)
executor = TemplateFamilyExecutor(
    backend,
    cdm_schema="main",
    results_schema="results",       # scratch/intermediate + cohort table schema
    vocabulary_schema=None,         # defaults to cdm_schema
)
relations = executor.run_resolved(resolved, materialize_intermediates=True)
# -> {name: ibis relation} for base_case, tpl_1, ..., tpl_22

# 4. Write all 23 into a single OHDSI cohort table keyed by cohort_definition_id
executor.write_cohort_table(
    relations, cohort_ids=resolved.cohort_ids, cohort_table="phe_tpl_cohort"
)
```

### The per-template `CohortExpression` path (Atlas / SQL / fallback)

`ResolvedFamily.expressions` holds a full, standalone `CohortExpression` for
every template. Use these to:

- serialize to Atlas JSON (`expression.model_dump_json()`),
- generate SQL via `circe.api.build_cohort_query(expression, options)`,
- run independently via `circe.execution.build_cohort(expression, backend=…,
  cdm_schema=…)` — used by the parity tests as the reference implementation.

## Databricks notes

- `TemplateFamilyExecutor` applies the Databricks post-connect workaround
  (`circe.execution.databricks_compat`) automatically.
- `cdm_schema` / `results_schema` should be the values the Databricks ibis
  backend expects for `database=`/`catalog.schema` access; pass `None` to use
  the connection default.
- Databricks has **no transactional delete+insert replace**, so the executor
  deliberately writes the whole family with one `CREATE TABLE … OVERWRITE`
  rather than per-cohort read-modify-write.
- Intermediate materialization (`materialize_intermediates=True`, the
  recommended setting for Databricks) guarantees each population is computed
  once, and keeps the 23 template queries cheap joins over scratch tables.

## Example

```bash
python examples/afib_eunomia.py
```

Builds the Atrial Fibrillation family (the actual concept sets from
`r_template.R`) against the GiBleed Eunomia CDM, prints per-template counts, and
writes a single `afib_phe_tpl_cohort` table. A writable copy of the Eunomia DB
is used so the shared file is never mutated.

## Tests

```bash
python -m pytest tests/                        # parity + structure + overlaps
PHENO_TPL_EUNOMIA=1 python -m pytest tests/test_eunomia_parity.py
```

- `test_parity.py` — for all 23 templates, asserts the shared-execution path
  (lazy and materialized) returns the exact same rows/persons as the reference
  per-template `build_cohort()`, plus a single-cohort-table write test.
- `test_structure.py` — asserts the generated expressions match the Capr mapping
  (entry observation window 0/0, `First:true`, window bounds, occurrence types,
  end strategies).
- `test_overlaps.py` — asserts overlap resolution against the documented R
  example.
- `test_eunomia_parity.py` — opt-in (slow) parity on the real Eunomia CDM.

On the GiBleed Eunomia data, the reference path (23 × `build_cohort`) takes
~45 s while the materialized shared-execution path takes ~4 s for the same
result.

## Caveats & limitations

- **Internal CircePy API coupling.** The fast path imports non-public
  `circe.execution` functions (`build_primary_events`, `_evaluate_group`,
  `attach_observation_period`, `apply_end_strategy`, `collapse_events`,
  `apply_result_limit`, `project_to_ohdsi_cohort_table`). Pin the CircePy
  commit you develop against; ideally these would be promoted to a public
  facade upstream.
- **Vocabulary tables required.** Concept-set descendant expansion reads
  `concept`, `concept_ancestor`, and `concept_relationship` on the backend, so
  the CDM must include the OMOP vocabulary.
- **Branch note.** The `circe.execution` layer is on the `develop` branch of
  `OHDSI/CircePy`; the package pins to the exact commit it was built against.
- The 22-template matrix, windows, and exit strategies mirror `r_template.R`
  exactly; changing the template matrix is a one-line change in
  `pheno_tpl/templates.py`.
