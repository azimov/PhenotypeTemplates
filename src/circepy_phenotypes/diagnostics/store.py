"""Local DuckDB asset store for diagnostics results.

Only **aggregated** tables are persisted here (counts, distributions,
prevalences) — never patient-level rows. Patient-level data remains on the CDM.

The store is append-only across runs and keyed by ``run_id`` and
``phenotype_id`` (a checksum of the base cohort entry criteria), so successive
runs of the same phenotype can be compared as the definition evolves.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import duckdb
import pandas as pd
from typing_extensions import Self

DB_FILENAME = "pheno_diagnostics.duckdb"

_RUNS_SCHEMA = """
CREATE TABLE IF NOT EXISTS runs (
    run_id INTEGER PRIMARY KEY,
    timestamp TIMESTAMP,
    phenotype_id VARCHAR,
    phenotype_label VARCHAR,
    config VARCHAR
)
"""


def phenotype_id(resolved) -> str:
    """Stable checksum of the base cohort entry criteria.

    Derived only from the index (``I``) concept set and the entry criteria, so
    it is invariant to template / demographic / evidence edits and changes only
    when the entry definition changes.
    """
    from ..cohorts.criteria import make_entry_criteria

    cs_I = next(cs for cs in resolved.concept_sets if cs.id == resolved.codeset_ids["I"])
    entry = make_entry_criteria(resolved.codeset_ids["I"], primary_limit=resolved.primary_limit)
    payload = {
        "concept_set_I": cs_I.model_dump(mode="json", exclude_none=True),
        "primary_criteria": entry.model_dump(mode="json", exclude_none=True),
        "expression_limit": resolved.expression_limit,
        "qualified_limit": "First",
    }
    canonical = json.dumps(payload, sort_keys=True, default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]


class DiagnosticsStore:
    """Append-only DuckDB store for aggregated diagnostics tables."""

    def __init__(self, output_dir: str | Path):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.path = self.output_dir / DB_FILENAME
        self._con = duckdb.connect(str(self.path))
        self._con.execute(_RUNS_SCHEMA)

    # -- run ledger ---------------------------------------------------------

    def record_run(
        self,
        *,
        phenotype_id_value: str,
        phenotype_label: str,
        config: dict[str, Any] | None = None,
    ) -> int:
        run_id = self._con.execute("SELECT COALESCE(MAX(run_id), 0) + 1 FROM runs").fetchone()[0]
        self._con.execute(
            "INSERT INTO runs (run_id, timestamp, phenotype_id, phenotype_label, config) "
            "VALUES (?, ?, ?, ?, ?)",
            [
                run_id,
                datetime.now(timezone.utc).isoformat(),
                phenotype_id_value,
                phenotype_label,
                json.dumps(config, sort_keys=True, default=str) if config is not None else None,
            ],
        )
        return int(run_id)

    # -- table writes -------------------------------------------------------

    def write_table(
        self,
        name: str,
        df: pd.DataFrame,
        *,
        run_id: int,
        phenotype_id_value: str,
    ) -> None:
        """Persist an aggregated table, tagged with run/phenotype ids."""
        data = df.copy()
        data["run_id"] = int(run_id)
        data["phenotype_id"] = phenotype_id_value
        self._con.register("_tmp", data)
        self._con.execute(f'CREATE TABLE IF NOT EXISTS "{name}" AS SELECT * FROM _tmp WHERE FALSE')
        self._con.execute(f'INSERT INTO "{name}" SELECT * FROM _tmp')
        self._con.unregister("_tmp")

    def table_names(self) -> list[str]:
        return [
            row[0]
            for row in self._con.execute(
                "SELECT table_name FROM information_schema.tables ORDER BY table_name"
            ).fetchall()
        ]

    def close(self) -> None:
        self._con.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc) -> None:
        self.close()
