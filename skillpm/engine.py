"""Engine context + operations shared by the boot reconciler and the CLI."""
from __future__ import annotations

import dataclasses
import os
from pathlib import Path

from . import catalog, lockfile, reconcile


@dataclasses.dataclass
class Paths:
    catalog_dir: Path
    skills_dir: Path
    lockfile: Path

    @classmethod
    def from_env(cls) -> "Paths":
        skills_dir = Path(
            os.environ.get("SKILLPM_HOME", str(Path.home() / ".hermes" / "skills" / "herm"))
        )
        catalog_dir = Path(os.environ.get("SKILLPM_CATALOG", "/opt/herm/skills"))
        return cls(catalog_dir=catalog_dir, skills_dir=skills_dir, lockfile=skills_dir / "skills.toml")


def load_or_seed(paths: Paths) -> dict[str, lockfile.SkillEntry]:
    entries = lockfile.load(paths.lockfile)
    if not entries:
        # Back-compat: no lockfile -> seed all catalog skills enabled (prior behavior).
        entries = {n: lockfile.SkillEntry(name=n) for n in catalog.discover(paths.catalog_dir)}
        lockfile.save(paths.lockfile, entries)
    return entries


def sync(paths: Paths) -> dict:
    return reconcile.reconcile(load_or_seed(paths), paths.catalog_dir, paths.skills_dir)


def list_rows(paths: Paths) -> list[tuple[str, str, bool, bool]]:
    entries = load_or_seed(paths)
    live = reconcile.actual(paths.skills_dir)
    return [(n, e.source, e.enabled, n in live) for n, e in sorted(entries.items())]


def toggle(paths: Paths, name: str, enabled: bool) -> bool:
    entries = load_or_seed(paths)
    if name not in entries:
        return False
    entries[name].enabled = enabled
    lockfile.save(paths.lockfile, entries)
    reconcile.reconcile(entries, paths.catalog_dir, paths.skills_dir)
    return True
