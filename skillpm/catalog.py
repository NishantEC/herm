"""Discover skills shipped in this repo's catalog (on the VM: /opt/herm/skills)."""
from __future__ import annotations

from pathlib import Path


def discover(catalog_dir: Path) -> list[str]:
    if not catalog_dir.is_dir():
        return []
    return sorted(p.parent.name for p in catalog_dir.glob("*/SKILL.md"))
