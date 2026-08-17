"""Backend connections for running the pheno_tpl templating family.

Provides a uniform ``connect_backend(...)`` helper for DuckDB (local Eunomia
file) and Databricks (SQL warehouse via YAML config / environment variables), so
the same family-execution code runs on either backend.
"""

from __future__ import annotations

import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import ibis
import yaml

# Optional Databricks support — checked lazily at connect time.
try:
    import ibis.backends.databricks

    _HAS_IBIS_DATABRICKS = True
except ImportError:
    _HAS_IBIS_DATABRICKS = False

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = Path(
    os.environ.get("PHENO_TPL_DB_CONFIG", str(REPO_ROOT / "pheno_tpl_db_config.yaml"))
)
ENV_PATH = REPO_ROOT / ".env"

COHORT_TABLE = "phe_tpl_cohort"
INTERMEDIATE_PREFIX = "_phe_tpl_"


def _strip_wrapping_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def _load_env_file() -> None:
    """Load repo-local environment variables without overriding the shell."""
    if not ENV_PATH.exists():
        return

    for raw_line in ENV_PATH.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        if not key or key in os.environ:
            continue

        os.environ[key] = _strip_wrapping_quotes(value.strip())


_load_env_file()


def _expandvars(text: str) -> str:
    """Expand ``${ENV_VAR}`` patterns in *text*, falling back to an empty string."""
    return re.sub(r"\$\{(\w+)\}", lambda m: os.environ.get(m.group(1), ""), text)


def _expandvars_recursive(obj: Any) -> Any:
    """Expand environment variables throughout a nested dict/list."""
    if isinstance(obj, str):
        return _expandvars(obj)
    if isinstance(obj, dict):
        return {k: _expandvars_recursive(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_expandvars_recursive(v) for v in obj]
    return obj


def _require_config_value(
    cfg: dict[str, Any], path: tuple[str, ...], env_var: str | None = None
) -> str:
    """Return a non-empty configuration value or raise a helpful error."""
    current: Any = cfg
    for key in path:
        if not isinstance(current, dict):
            current = None
            break
        current = current.get(key)

    if isinstance(current, str) and current:
        return current

    dotted = ".".join(path)
    if env_var is not None:
        raise ValueError(
            f"Missing Databricks config value '{dotted}'. Set {env_var} or update {CONFIG_PATH}."
        )
    raise ValueError(f"Missing Databricks config value '{dotted}' in {CONFIG_PATH}.")


def _split_catalog_schema(qualified_schema: str | None) -> tuple[str | None, str | None]:
    """Split a qualified Databricks schema into catalog and schema parts."""
    if not qualified_schema:
        return None, None

    parts = [part for part in qualified_schema.split(".") if part]
    if len(parts) >= 2:
        return parts[0], parts[1]
    return None, parts[0] if parts else None


def _infer_databricks_namespace(cfg: dict[str, Any]) -> tuple[str | None, str | None]:
    """Infer a sensible catalog/schema for the initial Databricks connection."""
    conn_cfg = cfg.get("connection", {})
    if conn_cfg.get("catalog") or conn_cfg.get("schema"):
        return conn_cfg.get("catalog"), conn_cfg.get("schema")

    for key in ("results_schema", "cdm_schema", "vocabulary_schema"):
        catalog, schema = _split_catalog_schema(cfg.get(key))
        if catalog or schema:
            return catalog, schema

    return None, None


def _eunomia_sources() -> list[Path]:
    """Locate a GiBleed Eunomia DuckDB file to stage a writable working copy."""
    candidates: list[Path] = []
    env = os.environ.get("EUNOMIA_DB")
    if env:
        candidates.append(Path(env))
    candidates.append(Path.home() / "PycharmProjects/Circepy/eunomia_data/GiBleed_5.3_1.4.duckdb")
    return [p for p in candidates if p.exists()]


def stage_duckdb(path: Path | None = None) -> Path:
    """Return a writable DuckDB file, copying from a source if it does not exist."""
    target = path or (REPO_ROOT / "eunomia.duckdb")
    if target.exists():
        return target

    sources = _eunomia_sources()
    if not sources:
        raise FileNotFoundError(
            "No Eunomia DuckDB file found. Set EUNOMIA_DB to point at a GiBleed "
            "Eunomia .duckdb file (e.g. CircePy/eunomia_data/GiBleed_5.3_1.4.duckdb)."
        )

    target.parent.mkdir(parents=True, exist_ok=True)
    print(f"  Staging writable Eunomia copy -> {target}")
    shutil.copy(sources[0], target)
    return target


@dataclass
class BackendConnection:
    """Hold the configured connection and schema information for a run."""

    backend: ibis.BaseBackend
    cdm_schema: str
    results_schema: str
    vocabulary_schema: str
    cohort_table: str = COHORT_TABLE
    intermediate_prefix: str = INTERMEDIATE_PREFIX


def load_config(backend_name: str) -> dict[str, Any]:
    """Load the YAML configuration for *backend_name*.

    ``${ENV_VAR}`` placeholders are expanded from the process environment.
    """
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(f"Config not found: {CONFIG_PATH}")

    config = yaml.safe_load(CONFIG_PATH.read_text())
    section = config.get(backend_name)
    if section is None:
        available = [k for k in config if k != "eunomia"]
        raise ValueError(f"Unknown backend '{backend_name}'. Available: {', '.join(available)}")

    return _expandvars_recursive(section)


def connect_backend(backend_name: str, *, duckdb_path: str | None = None) -> BackendConnection:
    """Create and return a backend connection.

    ``duckdb`` points at a local (optionally staged) Eunomia DuckDB file.
    ``databricks`` reads ``pheno_tpl_db_config.yaml`` (copy the ``.example`` and
    fill in connection details / env vars).
    """
    if backend_name == "duckdb":
        path = stage_duckdb(Path(duckdb_path) if duckdb_path else None)
        backend = ibis.duckdb.connect(str(path))
        return BackendConnection(
            backend=backend,
            cdm_schema="main",
            results_schema="main",
            vocabulary_schema="main",
        )

    cfg = load_config(backend_name)
    driver = cfg.get("driver", backend_name)

    if driver == "databricks":
        if not _HAS_IBIS_DATABRICKS:
            raise ImportError(
                "ibis-framework[databricks] is required. Install with: "
                "pip install 'ibis-framework[databricks]'"
            )

        catalog, schema = _infer_databricks_namespace(cfg)
        db_cfg: dict[str, Any] = {
            "server_hostname": _require_config_value(
                cfg, ("connection", "server_hostname"), env_var="DATABRICKS_HOST"
            ),
            "http_path": _require_config_value(
                cfg, ("connection", "http_path"), env_var="DATABRICKS_HTTP_PATH"
            ),
        }
        token = _require_config_value(
            cfg, ("connection", "personal_access_token"), env_var="DATABRICKS_TOKEN"
        )
        if token:
            db_cfg["access_token"] = token
        if catalog:
            db_cfg["catalog"] = catalog
        if schema:
            db_cfg["schema"] = schema

        backend = ibis.databricks.connect(**db_cfg)
        return BackendConnection(
            backend=backend,
            cdm_schema=_require_config_value(cfg, ("cdm_schema",), env_var="DATABRICKS_CDM_SCHEMA"),
            results_schema=_require_config_value(
                cfg, ("results_schema",), env_var="DATABRICKS_RESULTS_SCHEMA"
            ),
            vocabulary_schema=cfg.get("vocabulary_schema")
            or _require_config_value(cfg, ("cdm_schema",), env_var="DATABRICKS_CDM_SCHEMA"),
        )

    raise ValueError(f"Unsupported driver: {driver}")
