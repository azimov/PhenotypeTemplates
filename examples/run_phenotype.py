#!/usr/bin/env python3
"""Run the circepy-phenotypes templating family on DuckDB or Databricks.

Uses the connection helpers in :mod:`circepy_phenotypes.backend`
(``connect_backend``) so the same execution code runs on either backend.

Usage::

    # DuckDB (stages a writable Eunomia copy if needed)
    python examples/run_phenotype.py

    # Databricks (set DATABRICKS_HOST, DATABRICKS_HTTP_PATH, DATABRICKS_TOKEN,
    #             DATABRICKS_CDM_SCHEMA, DATABRICKS_RESULTS_SCHEMA)
    python examples/run_phenotype.py --backend databricks

    # Custom concept sets (JSON: {cs_I, cs_S, cs_D, cs_T, cs_C, cs_A, phenotype_label})
    python examples/run_phenotype.py --concept-sets path/to/concept_sets.json
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "src"))

from circepy_phenotypes import FamilySpec, TemplateFamilyExecutor, cs, resolve_family
from circepy_phenotypes.backend import connect_backend

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
for logger_name in (
    "databricks",
    "databricks.sql",
    "databricks.sql.client",
    "databricks.sql.http",
    "urllib3",
):
    logging.getLogger(logger_name).setLevel(logging.WARNING)


def _default_afib_spec() -> FamilySpec:
    sys.path.insert(0, str(REPO_ROOT))
    from examples.afib_eunomia import afib_family_spec

    return afib_family_spec()


def _spec_from_json(path: Path) -> FamilySpec:
    data = json.loads(path.read_text())

    def category(key: str) -> Any:
        entry = data.get(key)
        if not entry:
            return None
        return cs(
            direct=entry.get("direct", ()),
            descendants=entry.get("descendants", ()),
            name=entry.get("name", key),
        )

    return FamilySpec(
        cs_I=category("cs_I"),
        cs_S=category("cs_S"),
        cs_D=category("cs_D"),
        cs_T=category("cs_T"),
        cs_C=category("cs_C"),
        cs_A=category("cs_A"),
        phenotype_label=data.get("phenotype_label", "Phenotype"),
        exit_strategy=data.get("exit_strategy", "chronic"),
    )


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run the circepy-phenotypes templating family")
    p.add_argument(
        "--backend",
        default="duckdb",
        choices=("duckdb", "databricks"),
        help="Target database backend (default: duckdb)",
    )
    p.add_argument(
        "--concept-sets",
        type=Path,
        default=None,
        help="JSON file with cs_I/cs_S/cs_D/cs_T/cs_C/cs_A concept-set specs (default: AFib)",
    )
    p.add_argument(
        "--exit-strategy",
        default=None,
        choices=("chronic", "acute14d", "acute365d"),
        help="Exit strategy (default: from concept-sets JSON / AFib chronic)",
    )
    p.add_argument(
        "--no-materialize",
        action="store_true",
        help="Do not materialize index events / key sets to scratch tables",
    )
    p.add_argument(
        "--cohort-table",
        default=None,
        help="Name of the single OHDSI cohort table to write (default: phe_tpl_cohort)",
    )
    p.add_argument(
        "--duckdb-path",
        type=Path,
        default=None,
        help="Explicit DuckDB file to use (default: staged Eunomia copy)",
    )
    return p.parse_args()


def main() -> None:
    args = _parse_args()

    spec = _spec_from_json(args.concept_sets) if args.concept_sets else _default_afib_spec()
    if args.exit_strategy:
        spec.exit_strategy = args.exit_strategy
    print(f"Phenotype : {spec.phenotype_label}")
    print(f"Exit      : {spec.exit_strategy}")
    print(f"Backend   : {args.backend}")

    resolved = resolve_family(spec)
    print(
        f"Templates : {len(resolved.expressions)} (base_case + {len(resolved.expressions) - 1} scenarios)"
    )

    conn = connect_backend(
        args.backend, duckdb_path=str(args.duckdb_path) if args.duckdb_path else None
    )
    print(f"Connected : {conn.backend.name}")

    executor = TemplateFamilyExecutor(
        conn.backend,
        cdm_schema=conn.cdm_schema,
        results_schema=conn.results_schema,
        vocabulary_schema=conn.vocabulary_schema,
        intermediate_prefix=conn.intermediate_prefix,
    )
    relations = executor.run_resolved(resolved, materialize_intermediates=not args.no_materialize)

    cohort_table = args.cohort_table or conn.cohort_table
    executor.write_cohort_table(
        relations,
        cohort_ids=resolved.cohort_ids,
        cohort_table=cohort_table,
    )

    print(f"\n{'template':<12}{'cohort_id':<10}{'persons':<8}{'rows'}")
    for name, relation in relations.items():
        df = relation.execute()
        cohort_id = resolved.cohort_ids[name]
        persons = df["person_id"].nunique() if len(df) else 0
        rows = len(df)
        print(f"{name:<12}{cohort_id:<10}{persons:<8}{rows}")

    print(f"\nWrote {len(relations)} cohorts to {conn.results_schema}.{cohort_table}")


if __name__ == "__main__":
    main()
