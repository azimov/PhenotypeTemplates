"""End-to-end example: build all 23 phenotyping templates on Databricks.

Uses the same Atrial Fibrillation concept sets as ``r_template.R`` and
``afib_eunomia.py``, runs the *shared-execution* fast path (index events +
inclusion populations computed once) against a Databricks workspace, and
writes all 23 results into a single OHDSI cohort table keyed by
``cohort_definition_id``.
"""

from __future__ import annotations

import logging
import os
import sys

import ibis
import yaml

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src"))

from circepy_phenotypes import FamilySpec, TemplateFamilyExecutor, cs, resolve_family

logger = logging.getLogger(__name__)


def _split_catalog_schema(qualified_schema: str | None) -> tuple[str | None, str | None]:
    """Split a qualified Databricks schema into catalog and schema parts."""
    if not qualified_schema:
        return None, None

    parts = [part for part in qualified_schema.split(".") if part]
    if len(parts) >= 2:
        return parts[0], parts[1]
    return None, parts[0] if parts else None


def load_databricks_config(config_path: str | None = None) -> dict:
    """Load Databricks connection configuration from YAML file.

    Args:
        config_path: Path to databricks_connection.yml. Defaults to
            ~/.config/ohdsi/databricks_connection.yml

    Returns:
        Dictionary with connection parameters suitable for ibis.databricks.connect().
    """
    if config_path is None:
        config_path = os.path.expanduser("~/.config/ohdsi/databricks_connection.yml")

    with open(config_path) as f:
        config = yaml.safe_load(f)

    db_config = config["databricks"]
    conn_cfg = db_config.get("connection", {})

    # Build connection parameters for ibis.databricks.connect()
    db_params = {
        "server_hostname": conn_cfg.get("server_hostname"),
        "http_path": conn_cfg.get("http_path"),
    }

    # Map personal_access_token from config to access_token for Ibis
    if conn_cfg.get("personal_access_token"):
        db_params["access_token"] = conn_cfg["personal_access_token"]

    # Infer catalog from qualified schema names if not explicitly provided
    catalog = conn_cfg.get("catalog")
    if not catalog:
        for schema_key in ("cdm_schema", "results_schema", "vocabulary_schema"):
            cat, _ = _split_catalog_schema(db_config.get(schema_key))
            if cat:
                catalog = cat
                break

    if catalog:
        db_params["catalog"] = catalog

    # Add optional schema if present in connection config
    if conn_cfg.get("schema"):
        db_params["schema"] = conn_cfg["schema"]

    return {
        "connection": db_params,
        "cdm_schema": db_config.get("cdm_schema"),
        "results_schema": db_config.get("results_schema"),
        "vocabulary_schema": db_config.get("vocabulary_schema", db_config.get("cdm_schema")),
    }


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
            4188331, 4191650, 4213731, 4237062, 4238191, 4256228, 4269969, 4311124, 4322024,
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
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    
    # Suppress verbose Databricks/HTTP logging
    logging.getLogger("databricks").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("ibis").setLevel(logging.WARNING)

    logger.info("Starting Atrial Fibrillation phenotyping on Databricks")

    # Load Databricks configuration
    logger.info("Loading Databricks configuration...")
    config = load_databricks_config()
    connection_params = config["connection"]
    cdm_schema = config["cdm_schema"]
    results_schema = config["results_schema"]
    logger.info(f"Connected to catalog, CDM schema: {cdm_schema}, results schema: {results_schema}")

    # Connect to Databricks
    logger.info("Connecting to Databricks...")
    backend = ibis.databricks.connect(**connection_params)
    logger.info("Successfully connected to Databricks")

    logger.info("Resolving family specification...")
    resolved = resolve_family(afib_family_spec())
    logger.info(f"Resolved {len(resolved.cohort_ids)} templates")

    logger.info("Creating executor and running templates...")
    executor = TemplateFamilyExecutor(
        backend, 
        cdm_schema=cdm_schema,
        results_schema=results_schema,
    )
    relations = executor.run_resolved(resolved, materialize_intermediates=True)

    logger.info("Processing results...")
    print(f"{'template':<12}{'cohort_id':<10}{'persons':<8}{'rows'}")
    for i, (name, relation) in enumerate(relations.items(), 1):
        logger.info(f"Processing template {i}/{len(relations)}: {name}")
        df = relation.execute()
        cohort_id = resolved.cohort_ids[name]
        persons = df["person_id"].nunique() if len(df) else 0
        rows = len(df)
        print(f"{name:<12}{cohort_id:<10}{persons:<8}{rows}")
        logger.info(f"  {name}: {persons} persons, {rows} rows")

    cohort_table = "afib_phe_tpl_cohort"
    logger.info(f"Writing cohort table to {results_schema}.{cohort_table}...")
    executor.write_cohort_table(
        relations,
        cohort_ids=resolved.cohort_ids,
        cohort_table=cohort_table,
    )
    logger.info(f"Successfully wrote all 23 cohorts to table '{results_schema}.{cohort_table}' "
                f"({len(resolved.cohort_ids)} cohort_definition_ids)")
    print(f"\nWrote all 23 cohorts to table '{results_schema}.{cohort_table}' "
          f"({len(resolved.cohort_ids)} cohort_definition_ids)")


if __name__ == "__main__":
    main()
