"""End-to-end example: build all 23 phenotyping templates on Eunomia (DuckDB).

Uses the same Atrial Fibrillation concept sets as ``r_template.R`` against the
GiBleed Eunomia CDM, runs the *shared-execution* fast path (index events +
inclusion populations computed once), and writes all 23 results into a single
OHDSI cohort table keyed by ``cohort_definition_id``.
"""

from __future__ import annotations

import os
import shutil
import sys
import tempfile

import ibis

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src"))

from circepy_phenotypes import FamilySpec, TemplateFamilyExecutor, cs, resolve_family

EUNOMIA_DB = os.path.join(
    os.path.dirname(__file__), "..", "..", "Circepy", "eunomia_data", "GiBleed_5.3_1.4.duckdb"
)


def afib_family_spec() -> FamilySpec:
    """The Atrial Fibrillation concept sets from ``r_template.R``."""
    cs_I = cs(
        (
            313217, 605092, 1340258, 4068155, 4117112, 4119601, 4119602, 4141360, 4154290,
            4199501, 4232691, 4232697, 37170582, 37171038, 37172212, 37172244, 37395821,
            42539346, 44782442, 45768480,
        ),
        name="Atrial fibrillation",
    )
    cs_S = cs(
        descendants=(
            27674, 79908, 259153, 313217, 314665, 315078, 317376, 376961, 436817, 441417,
            441542, 442555, 444070, 4034235, 4037885, 4041664, 4059005, 4090431, 4092743,
            4114624, 4116811, 4203638, 4223659, 4223938, 4229392, 4262562, 4272240, 4305080,
            4310235, 4329041, 36714126,
        ),
        name="AFib symptoms",
    )
    cs_D = cs(
        descendants=(
            4759705, 759706, 759707, 759708, 759709, 759710, 759711, 759712, 2001544, 2007079,
            2212089, 2313879, 2313880, 3000551, 3001019, 3004064, 3005162, 3005456, 3006906,
            3008486, 3015377, 3020059, 3024675, 3027495, 3032503, 3041230, 3047107, 4014134,
            4017355, 4062856, 4094598, 4098039, 4154490, 4163951, 4196969, 4219024, 4230911,
            4243005, 4245152, 4246879, 4248132, 42529233, 42739967, 43528023,
        ),
        name="AFib diagnostics",
    )
    cs_T = cs(
        descendants=(
            902427, 914335, 927084, 950370, 989878, 1105775, 1112807, 1183554, 1301025, 1307046,
            1307542, 1307863, 1309204, 1309944, 1310149, 1313200, 1314002, 1314577, 1322081,
            1322184, 1326303, 1328165, 1335606, 1337860, 1338005, 1346823, 1351461, 1353256,
            1353766, 1354860, 1360421, 1362979, 1367571, 1370109, 2001549, 2001551, 2008358,
            2008361, 2107050, 2107051, 2107065, 2107066, 2107068, 2313791, 2313792, 2313854,
            2726385, 2788044, 4049987, 4051938, 4098410, 4144100, 19015230, 19024063, 19026180,
            19063575, 19084670, 40163615, 40228152, 40241331, 42627933, 43013024, 45892847,
            46234437,
        ),
        name="AFib treatments",
    )
    cs_C = cs(
        descendants=(
            135360, 197320, 200451, 201965, 254061, 261600, 313217, 313226, 313780, 316139,
            317002, 319844, 320744, 321042, 321319, 372924, 373503, 374022, 374384, 375557,
            376713, 377845, 381316, 434056, 435642, 438791, 440424, 443454, 443551, 4068155,
            4110961, 4112024, 4121341, 4124706, 4138543, 4142895, 4159647, 4164092, 4185607,
            4188331, 4191650, 4213731, 4237062, 4238191, 4256228, 4274969, 4311124, 4322024,
            37309626, 42536547, 44782781,
        ),
        name="AFib complications",
    )
    cs_A = cs(
        descendants=(313217, 317302, 437892, 441872, 4007310, 4089462, 4091901, 4103295, 4171269, 4275423),
        name="Alternative diagnoses",
    )
    return FamilySpec(
        cs_I=cs_I,
        cs_S=cs_S,
        cs_D=cs_D,
        cs_T=cs_T,
        cs_C=cs_C,
        cs_A=cs_A,
        phenotype_label="Atrial Fibrillation",
        exit_strategy="chronic",
    )


def main() -> None:
    # Work on a writable copy so the shared Eunomia file is never mutated.
    tmp = os.path.join(tempfile.mkdtemp(), "eunomia.duckdb")
    shutil.copy(EUNOMIA_DB, tmp)
    backend = ibis.duckdb.connect(tmp, read_only=False)

    resolved = resolve_family(afib_family_spec())
    executor = TemplateFamilyExecutor(backend, cdm_schema="main")

    relations = executor.run_resolved(resolved, materialize_intermediates=True)

    print(f"{'template':<12}{'cohort_id':<10}{'persons':<8}{'rows'}")
    for name, relation in relations.items():
        df = relation.execute()
        cohort_id = resolved.cohort_ids[name]
        persons = df["person_id"].nunique() if len(df) else 0
        rows = len(df)
        print(f"{name:<12}{cohort_id:<10}{persons:<8}{rows}")

    cohort_table = "afib_phe_tpl_cohort"
    executor.write_cohort_table(
        relations,
        cohort_ids=resolved.cohort_ids,
        cohort_table=cohort_table,
    )
    print(f"\nWrote all 23 cohorts to table '{cohort_table}' "
          f"({len(resolved.cohort_ids)} cohort_definition_ids)")


if __name__ == "__main__":
    main()
