"""Configuration loading. hermes.yaml and rubric.yaml are plain YAML; this module only locates them."""
from __future__ import annotations

import hashlib
import os
from functools import lru_cache
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]


def config_path() -> Path:
    return Path(os.environ.get("HRE_CONFIG", ROOT / "config" / "hermes.yaml"))


def rubric_path() -> Path:
    return Path(os.environ.get("HRE_RUBRIC", config_path().parent / "rubric.yaml"))


@lru_cache(maxsize=None)
def load(path: str | None = None) -> dict:
    return yaml.safe_load(Path(path or config_path()).read_text())


@lru_cache(maxsize=None)
def load_rubric(path: str | None = None) -> dict:
    return yaml.safe_load(Path(path or rubric_path()).read_text())


def config_hash() -> str:
    h = hashlib.sha256()
    for p in (config_path(), rubric_path()):
        h.update(p.read_bytes())
    return h.hexdigest()[:16]
