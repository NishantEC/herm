"""Engine context + operations shared by the boot reconciler and the CLI."""
from __future__ import annotations

import dataclasses
import os
from pathlib import Path

from . import catalog, gateway, lockfile, reconcile


@dataclasses.dataclass
class Paths:
    catalog_dir: Path
    skills_dir: Path
    lockfile: Path

    @classmethod
    def from_env(cls) -> "Paths":
        # All herm-owned, on the persistent disk -- no root required. The CLI
        # pushes the engine + catalog here over SSH; cloud-init seeds the same
        # paths at boot. Overridable via env (used by tests and the boot script).
        hermes = Path(os.environ.get("SKILLPM_HERMES", str(Path.home() / ".hermes")))
        skills_dir = Path(os.environ.get("SKILLPM_HOME", str(hermes / "skills" / "herm")))
        catalog_dir = Path(os.environ.get("SKILLPM_CATALOG", str(hermes / "skill-catalog")))
        lock = Path(os.environ.get("SKILLPM_LOCK", str(hermes / "skill-lock.toml")))
        return cls(catalog_dir=catalog_dir, skills_dir=skills_dir, lockfile=lock)


def load_or_seed(paths: Paths) -> dict[str, lockfile.SkillEntry]:
    entries = lockfile.load(paths.lockfile)
    if entries:
        return entries
    # First run: seed from the catalog, then PRESERVE any skills already present
    # in the live dir that the catalog doesn't ship (user/private skills like a
    # pre-existing on-VM skill) by recording them as source=local so reconcile
    # keeps them instead of deleting them.
    entries = {n: lockfile.SkillEntry(name=n, source="catalog") for n in catalog.discover(paths.catalog_dir)}
    for n in reconcile.actual(paths.skills_dir):
        entries.setdefault(n, lockfile.SkillEntry(name=n, source="local"))
    lockfile.save(paths.lockfile, entries)
    return entries


def sync(paths: Paths, reload: bool = False) -> dict:
    summary = reconcile.reconcile(load_or_seed(paths), paths.catalog_dir, paths.skills_dir)
    if reload:
        summary["reload"] = gateway.reload()
    return summary


def list_rows(paths: Paths) -> list[tuple[str, str, bool, bool]]:
    entries = load_or_seed(paths)
    live = reconcile.actual(paths.skills_dir)
    return [(n, e.source, e.enabled, n in live) for n, e in sorted(entries.items())]


def toggle(paths: Paths, name: str, enabled: bool, reload: bool = False) -> bool:
    entries = load_or_seed(paths)
    if name not in entries:
        return False
    entries[name].enabled = enabled
    lockfile.save(paths.lockfile, entries)
    reconcile.reconcile(entries, paths.catalog_dir, paths.skills_dir)
    if reload:
        gateway.reload()
    return True
