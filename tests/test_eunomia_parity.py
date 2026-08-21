"""Opt-in end-to-end parity on the real Eunomia CDM (DuckDB).

Gated behind ``PHENO_TPL_EUNOMIA=1`` because the reference path re-runs all 23
templates independently (~45s).
"""

from __future__ import annotations

import os
import shutil
import tempfile

import pytest

from circepy_phenotypes import FamilySpec, TemplateFamilyExecutor, resolve_family

EUNOMIA_DB = os.path.join(
    os.path.dirname(__file__), "..", "..", "Circepy", "eunomia_data", "GiBleed_5.3_1.4.duckdb"
)

pytestmark = pytest.mark.skipif(
    os.environ.get("PHENO_TPL_EUNOMIA", "0") != "1" or not os.path.exists(EUNOMIA_DB),
    reason="set PHENO_TPL_EUNOMIA=1 to run the slow Eunomia parity test",
)


def _make_spec() -> FamilySpec:
    return FamilySpec(
        cs_I=cs_direct(),
        cs_S=cs_desc(),
        cs_D=cs_desc(),
        cs_T=cs_desc(),
        cs_C=cs_desc(),
        cs_A=cs_desc(),
        phenotype_label="Eunomia parity",
    )


def cs_direct():
    from circepy_phenotypes import cs

    return cs((313217, 605092, 1340258), name="I")


def cs_desc():
    from circepy_phenotypes import cs

    return cs(descendants=(27674, 79908, 259153, 313217, 314665), name="S")


def test_eunomia_parity_all_templates():
    import ibis
    from circe.api import build_cohort

    tmp = os.path.join(tempfile.mkdtemp(), "eunomia.duckdb")
    shutil.copy(EUNOMIA_DB, tmp)
    backend = ibis.duckdb.connect(tmp, read_only=False)

    resolved = resolve_family(_make_spec())

    reference = {}
    for name, (_cid, expr) in resolved.expressions.items():
        df = build_cohort(expr, backend=backend, cdm_schema="main").execute()
        reference[name] = set(df["person_id"].tolist()) if len(df) else set()

    executor = TemplateFamilyExecutor(backend, cdm_schema="main")
    fast = {
        name: set(df["person_id"].tolist()) if len(df) else set()
        for name, df in {
            n: rel.execute() for n, rel in executor.run_resolved(resolved).items()
        }.items()
    }

    assert set(fast) == set(reference)
    for name, ref_persons in reference.items():
        assert fast[name] == ref_persons, name
