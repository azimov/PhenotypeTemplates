"""Console entry point: ``circepy-phenotypes`` (alias ``cpt``).

Subcommands:

  * ``run``        — generate the 23-template family into a single cohort table.
  * ``evaluate``   — evaluate candidate cohorts against a gold standard.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .backend import connect_backend
from .cohorts import TemplateFamilyExecutor, resolve_family
from .config import load_config
from .evaluation import evaluate
from .evaluation.report import format_report, metrics_table, plot_metrics


def _cmd_run(args: argparse.Namespace) -> int:
    if not args.config:
        raise SystemExit("run requires --config path/to/config.yaml")

    spec = load_config(args.config).build_family_spec()
    resolved = resolve_family(spec)

    conn = connect_backend(args.backend, duckdb_path=args.duckdb_path)
    executor = TemplateFamilyExecutor(
        conn.backend,
        cdm_schema=conn.cdm_schema,
        results_schema=conn.results_schema,
        vocabulary_schema=conn.vocabulary_schema,
        intermediate_prefix=conn.intermediate_prefix,
    )
    relations = executor.run_resolved(resolved, materialize_intermediates=not args.no_materialize)
    cohort_table = args.cohort_table or conn.cohort_table
    executor.write_cohort_table(relations, cohort_ids=resolved.cohort_ids, cohort_table=cohort_table)

    print(f"\n{'template':<12}{'cohort_id':<10}{'persons':<8}{'rows'}")
    for name, relation in relations.items():
        df = relation.execute()
        persons = df["person_id"].nunique() if len(df) else 0
        print(f"{name:<12}{resolved.cohort_ids[name]:<10}{persons:<8}{len(df)}")
    print(f"\nWrote {len(relations)} cohorts to {conn.results_schema}.{cohort_table}")
    return 0


def _cmd_evaluate(args: argparse.Namespace) -> int:
    if not args.config:
        raise SystemExit("evaluate requires --config path/to/config.yaml")

    config = load_config(args.config)
    spec = config.build_family_spec()
    resolved = resolve_family(spec)

    conn = connect_backend(config.backend, duckdb_path=config.duckdb_path)

    population = config.universe.build_population(resolved.concept_sets)
    gold_standard = (
        config.gold_standard.build(resolved.concept_sets)
        if config.gold_standard
        else resolved.expressions["base_case"][1]
    )
    demographic_group = config.target_population.build()

    result = evaluate(
        conn,
        family=resolved,
        population_expression=population,
        gold_standard=gold_standard,
        demographic_group=demographic_group,
        universe=config.universe.type,
    )

    print(f"Universe ({config.universe.type}): {len(result.universe_persons)} persons")
    print(f"Gold standard: {len(result.gold_persons)} persons")
    print()
    print(format_report(result))

    if args.plot:
        fig = plot_metrics(result, save_path=args.plot)
        print(f"\nWrote plot to {args.plot}")
        fig.clear()

    if args.csv:
        metrics_table(result).to_csv(args.csv, index=False)
        print(f"Wrote metrics to {args.csv}")

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="circepy-phenotypes",
        description="Efficient phenotyping template generation and proxy evaluation.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    run_p = sub.add_parser("run", help="generate the 23-template family")
    run_p.add_argument("--config", type=Path, required=True, help="YAML/JSON config path")
    run_p.add_argument("--backend", default="duckdb", choices=("duckdb", "databricks"))
    run_p.add_argument("--duckdb-path", type=Path, default=None)
    run_p.add_argument("--cohort-table", default=None)
    run_p.add_argument("--no-materialize", action="store_true")
    run_p.set_defaults(func=_cmd_run)

    eval_p = sub.add_parser("evaluate", help="evaluate candidate cohorts vs a gold standard")
    eval_p.add_argument("--config", type=Path, required=True, help="YAML/JSON config path")
    eval_p.add_argument("--csv", type=Path, default=None, help="write metrics to CSV")
    eval_p.add_argument("--plot", type=Path, default=None, help="write a sensitivity/specificity plot")
    eval_p.set_defaults(func=_cmd_evaluate)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
